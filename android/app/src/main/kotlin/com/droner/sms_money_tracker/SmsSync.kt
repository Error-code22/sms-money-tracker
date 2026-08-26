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
}
