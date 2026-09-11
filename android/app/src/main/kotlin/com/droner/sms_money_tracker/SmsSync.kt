package com.droner.sms_money_tracker

import android.Manifest
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

data class SmsMessage(val id: Long, val sender: String, val body: String, val date: Long)

/**
 * Single background thread shared by the MethodChannel handlers and the SMS
 * receiver, so syncs are serialized and never run on the platform/UI thread.
 */
val syncExecutor: ExecutorService = Executors.newSingleThreadExecutor()

object SmsSync {
    private const val PREFS = "sms_money_tracker_prefs"
    private const val KEY_LAST_SYNC = "last_sync_ms"
    private const val OVERLAP_MS = 5 * 60 * 1000L
    private const val FIRST_BACKFILL_DAYS = 90L

    fun sync(context: Context): Int {
        // Never advance the sync window without SMS access: pre-permission
        // syncs must not stamp lastSync and collapse the future backfill.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            context.checkSelfPermission(Manifest.permission.READ_SMS) != PackageManager.PERMISSION_GRANTED
        ) {
            return 0
        }

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val lastSync = prefs.getLong(KEY_LAST_SYNC, 0L)
        val now = System.currentTimeMillis()
        val since = if (lastSync == 0L) {
            now - FIRST_BACKFILL_DAYS * 24 * 3600 * 1000
        } else {
            (lastSync - OVERLAP_MS).coerceAtLeast(0L)
        }
        var added = 0
        for (sms in readSmsSince(context, since)) {
            try {
                val txn = SmsParser.parse(sms)
                if (txn != null && SmsDb.insert(context, txn)) added++
            } catch (e: Exception) {
                DebugLog.exception(context, "SmsSync", e)
            }
        }
        prefs.edit().putLong(KEY_LAST_SYNC, now).apply()
        return added
    }

    fun resetSyncState(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_LAST_SYNC, 0L).apply()
    }

    private fun readSmsSince(context: Context, since: Long): List<SmsMessage> {
        val list = mutableListOf<SmsMessage>()
        val resolver: ContentResolver = context.contentResolver
        val uri = Uri.parse("content://sms/inbox")
        var cursor: Cursor? = null
        try {
            cursor = resolver.query(
                uri,
                arrayOf("_id", "address", "body", "date"),
                "date > ?",
                arrayOf(since.toString()),
                "date ASC"
            )
            cursor?.use { c ->
                val idIdx = c.getColumnIndexOrThrow("_id")
                val addrIdx = c.getColumnIndexOrThrow("address")
                val bodyIdx = c.getColumnIndexOrThrow("body")
                val dateIdx = c.getColumnIndexOrThrow("date")
                while (c.moveToNext()) {
                    list.add(
                        SmsMessage(
                            id = c.getLong(idIdx),
                            sender = c.getString(addrIdx) ?: "",
                            body = c.getString(bodyIdx) ?: "",
                            date = c.getLong(dateIdx)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            DebugLog.exception(context, "SmsSync", e)
        } finally {
            cursor?.close()
        }
        return list
    }

    fun getLatestBalance(context: Context): Double? {
        val cr: ContentResolver = context.contentResolver
        val uri = Uri.parse("content://sms/inbox")
        val matchers = arrayOf(
            "address LIKE '%MPESA%'",
            "address LIKE '%M-PESA%'"
        )
        val pattern = Regex("balance\\s+is\\s+Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE)
        for (where in matchers) {
            val cursor = cr.query(uri, arrayOf("body"), where, null, "date DESC LIMIT 40")
            cursor?.use {
                while (it.moveToNext()) {
                    val body = it.getString(0) ?: continue
                    val match = pattern.find(body) ?: continue
                    return match.groupValues[1].replace(",", "").toDoubleOrNull()
                }
            }
        }
        return null
    }

    fun getSummaryFromSms(context: Context): String? {
        val cr: ContentResolver = context.contentResolver
        val uri = Uri.parse("content://sms/inbox")
        val cal = java.util.Calendar.getInstance()
        cal.set(java.util.Calendar.DAY_OF_MONTH, 1)
        cal.set(java.util.Calendar.HOUR_OF_DAY, 0)
        cal.set(java.util.Calendar.MINUTE, 0)
        cal.set(java.util.Calendar.SECOND, 0)
        cal.set(java.util.Calendar.MILLISECOND, 0)
        val monthStart = cal.timeInMillis

        var spent = 0.0
        var received = 0.0
        var balance: Double? = null

        // Read all MPESA SMS
        val cursor = cr.query(uri, arrayOf("body", "date"), "address = 'MPESA'", null, "date DESC")
        cursor?.use {
            val bodyIdx = it.getColumnIndex("body")
            while (it.moveToNext()) {
                val body = it.getString(bodyIdx) ?: continue
                // Skip non-transaction messages
                if (!body.contains("Confirmed", ignoreCase = true)) continue

                // Extract amount
                val amtMatch = Regex("Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE)
                    .find(body) ?: continue
                val amount = amtMatch.groupValues[1].replace(",", "").toDoubleOrNull() ?: continue

                // Determine type
                val isCredit = body.contains("received", ignoreCase = true)
                val isDebit = body.contains("sent to", ignoreCase = true) ||
                    body.contains("paid to", ignoreCase = true) ||
                    body.contains("withdrawn", ignoreCase = true) ||
                    body.contains("bought", ignoreCase = true) ||
                    body.contains("used", ignoreCase = true)

                if (isCredit) received += amount
                else if (isDebit) spent += amount

                // Extract balance (first one is latest)
                if (balance == null) {
                    val balMatch = Regex("balance\\s+is\\s+Ksh([\\d,]+\\.?\\d*)", RegexOption.IGNORE_CASE)
                        .find(body)
                    if (balMatch != null) {
                        balance = balMatch.groupValues[1].replace(",", "").toDoubleOrNull()
                    }
                }
            }
        }

        return org.json.JSONObject().apply {
            put("spentThisMonth", spent)
            put("receivedThisMonth", received)
            put("balance", balance)
        }.toString()
    }
}
