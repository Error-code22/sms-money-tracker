package com.droner.sms_money_tracker

import android.content.ContentResolver
import android.content.Context
import android.database.Cursor
import android.net.Uri

data class SmsMessage(val id: Long, val sender: String, val body: String, val date: Long)

object SmsSync {
    private const val PREFS = "sms_money_tracker_prefs"
    private const val KEY_LAST_SYNC = "last_sync_ms"
    private const val OVERLAP_MS = 5 * 60 * 1000L
    private const val FIRST_BACKFILL_DAYS = 90L

    fun sync(context: Context): Int {
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
            val txn = SmsParser.parse(sms)
            if (txn != null && SmsDb.insert(context, txn)) added++
        }
        prefs.edit().putLong(KEY_LAST_SYNC, now).apply()
        return added
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
            e.printStackTrace()
        } finally {
            cursor?.close()
        }
        return list
    }
}
