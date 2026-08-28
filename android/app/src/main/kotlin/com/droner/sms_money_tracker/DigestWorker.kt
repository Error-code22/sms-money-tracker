package com.droner.sms_money_tracker

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

/**
 * Periodic worker that posts a weekly money recap notification
 * (rolling ~7 days) while the user has the digest enabled.
 */
class DigestWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val ctx = applicationContext
        try {
            val dartPrefs = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val enabled = dartPrefs.getBoolean("flutter.digest_enabled", true)
            if (!enabled) return Result.success()

            val prefs = ctx.getSharedPreferences("sms_money_tracker_prefs", Context.MODE_PRIVATE)
            val last = prefs.getLong("digest_last_sent", 0L)
            val now = System.currentTimeMillis()
            if (now - last < 6L * 24 * 3600 * 1000) return Result.success()

            val text = SmsDb.getDigest(ctx)
            if (text.isNotEmpty()) {
                Notifier.notifyDigest(ctx, text)
                prefs.edit().putLong("digest_last_sent", now).apply()
            }
        } catch (e: Exception) {
            DebugLog.exception(ctx, "DigestWorker", e)
        }
        return Result.success()
    }
}
