package com.droner.sms_money_tracker

import java.util.regex.Pattern

data class Txn(
    val smsId: Long,
    val sender: String,
    val body: String,
    val amount: Double,
    val currency: String,
    val type: String,
    val counterparty: String,
    val ts: Long
)

object SmsParser {
    private data class Match(val token: String, val amount: String, val start: Int)

    private val moneyPattern = Pattern.compile(
        "([A-Za-z]{2,4}|R|[$€£₦])\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
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

    fun parse(sms: SmsMessage): Txn? {
        val body = sms.body.trim()
        if (body.length < 8 || body.length > 800) return null
        val lower = body.lowercase()
        if (skipKeywords.any { lower.contains(it) }) return null

        val matcher = moneyPattern.matcher(body)
        val matches = mutableListOf<Match>()
        while (matcher.find()) {
            matches.add(Match(matcher.group(1) ?: "", matcher.group(2) ?: "", matcher.start()))
        }
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

        val currency = normalizeCurrency(picked.token)
        val counterparty = extractCounterparty(body)

        return Txn(
            smsId = sms.id,
            sender = sms.sender,
            body = body,
            amount = amount,
            currency = currency,
            type = type,
            counterparty = counterparty,
            ts = sms.date
        )
    }

    private fun pickAmount(body: String, matches: List<Match>, type: String): Match {
        val lower = body.lowercase()
        val keywords = if (type == "debit") debitKeywords else creditKeywords
        var keywordStart = -1
        for (kw in keywords) {
            val idx = lower.indexOf(kw)
            if (idx >= 0 && (keywordStart == -1 || idx < keywordStart)) keywordStart = idx
        }
        if (keywordStart >= 0) {
            val prefix = body.substring(0, keywordStart)
            val inPrefix = matches.filter { it.start < keywordStart }
            if (inPrefix.isNotEmpty()) return inPrefix.last()
        }
        return matches.first()
    }

    private fun normalizeCurrency(token: String): String {
        return when (token) {
            "$" -> "USD"
            "€" -> "EUR"
            "£" -> "GBP"
            "₦" -> "NGN"
            "R" -> "ZAR"
            "ksh", "kshs" -> "KES"
            "r" -> "ZAR"
            "ush", "ugx" -> token.uppercase()
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
}
