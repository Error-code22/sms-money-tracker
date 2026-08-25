package com.droner.sms_money_tracker

import java.util.regex.Pattern
import kotlin.math.abs

data class Txn(
    val smsId: Long,
    val sender: String,
    val body: String,
    val amount: Double,
    val currency: String,
    val type: String,
    val counterparty: String,
    val ts: Long,
    val category: String? = null,
    val interest: Double? = null,
    val isConfident: Boolean = false
)

object SmsParser {

    // ---------------------------------------------------------------
    // M-Pesa gate: sender MPESA + "XXXX1234AB Confirmed." prefix.
    // Anything from MPESA without this is a promo/OTP/balance notice.
    // ---------------------------------------------------------------
    private const val MPESA_SENDER = "MPESA"
    private val mpesaGate = Regex("^[A-Z0-9]{10}\\s+Confirmed\\.")

    // Dedicated M-Pesa templates (one per transaction type).
    private val sendPattern = Regex(
        "Ksh([\\d,]+\\.?\\d*) sent to ([A-Za-z ]+?)\\s+(\\d{10,12})\\s+on\\b", RegexOption.IGNORE_CASE
    )
    private val receivePattern = Regex(
        "received Ksh([\\d,]+\\.?\\d*) from ([A-Za-z ]+?)\\s+(\\d{10,12})", RegexOption.IGNORE_CASE
    )
    private val paybillPattern = Regex(
        "Ksh([\\d,]+\\.?\\d*) paid to ([A-Za-z0-9 ]+?)\\.?\\s*for account\\s+(\\S+)", RegexOption.IGNORE_CASE
    )
    private val tillPattern = Regex(
        "Ksh([\\d,]+\\.?\\d*) paid to ([A-Za-z0-9 ]+?)\\.?\\s*on\\b", RegexOption.IGNORE_CASE
    )
    private val withdrawPattern = Regex(
        "Ksh([\\d,]+\\.?\\d*) withdrawn from (.+?)\\s+on\\b", RegexOption.IGNORE_CASE
    )
    private val airtimePattern = Regex(
        "bought Ksh([\\d,]+\\.?\\d*) of airtime", RegexOption.IGNORE_CASE
    )
    private val fulizaUsedPattern = Regex(
        "(?:used|covered) Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE
    )
    private val fulizaInterestPattern = Regex(
        "(?:interest (?:of |is )?|charged )Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE
    )
    private val reversalPatternA = Regex(
        "reversal of Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE
    )
    private val reversalPatternB = Regex(
        "Ksh([\\d,]+\\.?\\d*)\\s+reversal", RegexOption.IGNORE_CASE
    )

    // Generic fallback: currency whitelist only, never bare words.
    private val currencyToken = "(KES|KSH|UGX|TZS|RWF|NGN|GHS|ETB|ZMW|MWK|ZAR|USD|EUR|GBP|R|[$€£₦])"
    private val moneyPattern = Regex(
        "(?<![A-Za-z])$currencyToken\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)(?![0-9])",
        RegexOption.IGNORE_CASE
    )

    private val debitKeywords = listOf(
        "sent to", "paid to", "debited", "withdraw", "withdrawal",
        "purchased", "bought", "payment of", "paid for", "spent",
        "charged", "transfer to", "payment made", "you paid", "has been sent"
    )

    private val creditKeywords = listOf(
        "received", "credited", "deposit", "paid you", "you have received",
        "sent you", "payment received", "refund", "cash in", "deposited",
        "received from", "money received"
    )

    private val skipKeywords = listOf(
        "otp", "verification code", "security code", "one time password"
    )

    private val counterpartyPattern = Pattern.compile(
        "(?:from|to|paid to|sent to|received from|credited to|debited from|payment from|payment to)\\s+([A-Za-z0-9][A-Za-z0-9 ._&'-]{1,40})",
        Pattern.CASE_INSENSITIVE
    )

    private data class MoneyMatch(val token: String, val amount: String, val start: Int)

    // ---------------------------------------------------------------
    // Entry point
    // ---------------------------------------------------------------
    fun parse(sms: SmsMessage): Txn? {
        val body = sms.body.trim()
        if (body.length < 8 || body.length > 800) return null
        val lower = body.lowercase()
        if (skipKeywords.any { lower.contains(it) }) return null

        val isMpesaSender = sms.sender.equals(MPESA_SENDER, ignoreCase = true)
        if (!isMpesaSender) return parseGeneric(sms, body)

        // From MPESA but no transaction header: promo/OTP/balance notice. Skip.
        if (!mpesaGate.containsMatchIn(body)) return null

        return parseMpesaTemplates(sms, body) ?: parseGeneric(sms, body)
    }

    // ---------------------------------------------------------------
    // M-Pesa dedicated templates
    // ---------------------------------------------------------------
    private fun parseMpesaTemplates(sms: SmsMessage, body: String): Txn? {
        val core = anchoredPrefix(body, listOf("New M-PESA balance", "Transaction cost,"))

        if (body.contains("Fuliza M-PESA", ignoreCase = true)) return parseFuliza(sms, body)
        if (body.contains("reversal", ignoreCase = true)) return parseReversal(sms, body, core)

        sendPattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
                m.groupValues[2].trim(), sms.date, isConfident = true)
        }

        receivePattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            return Txn(sms.id, sms.sender, body, amount, "KES", "credit",
                m.groupValues[2].trim(), sms.date, isConfident = true)
        }

        // Paybill must be tried before till: till messages never have "for account".
        paybillPattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            val merchant = m.groupValues[2].trim().trimEnd('.')
            val account = m.groupValues[3].trim()
            return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
                "$merchant · $account", sms.date, isConfident = true)
        }

        tillPattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
                m.groupValues[2].trim().trimEnd('.'), sms.date, isConfident = true)
        }

        withdrawPattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
                m.groupValues[2].trim().trimEnd('.'), sms.date, isConfident = true)
        }

        airtimePattern.find(core)?.let { m ->
            val amount = parseAmount(m.groupValues[1]) ?: return null
            return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
                "Airtime", sms.date, isConfident = true)
        }

        return null
    }

    private fun parseFuliza(sms: SmsMessage, body: String): Txn? {
        val core = anchoredPrefix(
            body,
            listOf("New Fuliza", "Fuliza M-PESA limit", "Fuliza M-PESA balance", "Transaction cost,")
        )
        var amount = fulizaUsedPattern.find(core)
            ?.let { parseAmount(it.groupValues[1]) }
        if (amount == null) {
            amount = moneyPattern.find(core)?.let { parseAmount(it.groupValues[2]) }
        }
        if (amount == null) return null

        val interest = fulizaInterestPattern.find(body)
            ?.let { parseAmount(it.groupValues[1]) }

        return Txn(sms.id, sms.sender, body, amount, "KES", "debit",
            "Fuliza M-PESA", sms.date, category = "Fuliza", interest = interest, isConfident = true)
    }

    private fun parseReversal(sms: SmsMessage, body: String, core: String): Txn? {
        val m = reversalPatternA.find(core) ?: reversalPatternB.find(core) ?: return null
        val amount = parseAmount(m.groupValues[1]) ?: return null
        return Txn(sms.id, sms.sender, body, amount, "KES", "credit",
            "M-PESA reversal", sms.date, category = "Reversal", isConfident = true)
    }

    // ---------------------------------------------------------------
    // Generic fallback for anything that is not a gated M-Pesa message
    // (banks, Airtel Money, or untemplated M-Pesa variants).
    // ---------------------------------------------------------------
    private fun parseGeneric(sms: SmsMessage, body: String): Txn? {
        val lower = body.lowercase()
        val matches = moneyPattern.findAll(body)
            .map { MoneyMatch(it.groupValues[1], it.groupValues[2], it.range.first) }
            .toList()
        if (matches.isEmpty()) return null

        val type = when {
            debitKeywords.any { lower.contains(it) } -> "debit"
            creditKeywords.any { lower.contains(it) } -> "credit"
            else -> return null
        }

        val picked = pickAmount(body, matches, type)
        val rawAmount = picked.amount
        val digits = rawAmount.replace(",", "").replace(".", "")
        if (digits.length <= 4 && !rawAmount.contains(",") && !rawAmount.contains(".")) return null
        if (digits.length >= 7 && !rawAmount.contains(",") && !rawAmount.contains(".")) return null

        val amount = rawAmount.replace(",", "").toDoubleOrNull() ?: return null
        if (amount <= 0.0 || amount > 1_000_000_000.0) return null

        return Txn(
            smsId = sms.id,
            sender = sms.sender,
            body = body,
            amount = amount,
            currency = normalizeCurrency(picked.token),
            type = type,
            counterparty = extractCounterparty(body),
            ts = sms.date,
            isConfident = false
        )
    }

    /**
     * Symmetric: pick the currency+amount match nearest the direction keyword,
     * on either side of it, never just "the next Ksh in the string".
     */
    private fun pickAmount(body: String, matches: List<MoneyMatch>, type: String): MoneyMatch {
        val lower = body.lowercase()
        val keywords = if (type == "debit") debitKeywords else creditKeywords
        var keywordIdx = -1
        for (kw in keywords) {
            val idx = lower.indexOf(kw)
            if (idx >= 0 && (keywordIdx == -1 || idx < keywordIdx)) keywordIdx = idx
        }
        if (keywordIdx < 0) return matches.first()
        return matches.minByOrNull { abs(it.start - keywordIdx) } ?: matches.first()
    }

    /**
     * Drop everything from the first occurrence of any delimiter (the amount
     * of the transaction always appears before balance/cost labels).
     */
    private fun anchoredPrefix(body: String, delimiters: List<String>): String {
        val lower = body.lowercase()
        var cut = body.length
        for (d in delimiters) {
            val idx = lower.indexOf(d.lowercase())
            if (idx > 0 && idx < cut) cut = idx
        }
        return body.substring(0, cut)
    }

    private fun parseAmount(raw: String?): Double? {
        if (raw == null) return null
        val amount = raw.replace(",", "").toDoubleOrNull() ?: return null
        if (amount <= 0.0 || amount > 1_000_000_000.0) return null
        return amount
    }

    private fun normalizeCurrency(token: String): String {
        return when (token.uppercase()) {
            "R" -> "ZAR"
            "$" -> "USD"
            "€" -> "EUR"
            "£" -> "GBP"
            "₦" -> "NGN"
            "KSH" -> "KES"
            else -> token.uppercase()
        }
    }

    private fun extractCounterparty(body: String): String {
        val matcher = counterpartyPattern.matcher(body)
        if (!matcher.find()) return ""
        var name = matcher.group(1)?.trim() ?: return ""
        val phone = Regex("\\d{7,}").find(name)
        if (phone != null) name = name.substring(0, phone.range.first)
        val cutAt = listOf(" on ", " at ", " ref ", " new ", " acc ", " for ", " your ", " has ", " is ")
            .map { name.lowercase().indexOf(it) }
            .filter { it > 0 }
            .minOrNull()
        if (cutAt != null) name = name.substring(0, cutAt)
        return name.trim().trimEnd('.', ',', ';').take(40)
    }

    // ---------------------------------------------------------------
    // Message shape for the review/learning layer
    // ---------------------------------------------------------------
    fun shapeOf(body: String): String =
        body.lowercase()
            .replace(Regex("\\d+"), "#")
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(120)
}
