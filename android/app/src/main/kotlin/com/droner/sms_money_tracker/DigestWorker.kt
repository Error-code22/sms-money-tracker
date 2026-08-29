package com.droner.sms_money_tracker

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Periodic worker that posts a weekly money recap notification
 * (rolling ~7 days) and daily budget alerts while enabled.
 */
class DigestWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val ctx = applicationContext
        try {
            val dartPrefs = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val digestEnabled = dartPrefs.getBoolean("flutter.digest_enabled", true)
            val prefs = ctx.getSharedPreferences("sms_money_tracker_prefs", Context.MODE_PRIVATE)

            // Budget alerts: at 80%+ of a cap, notify once per day.
            val budgetsJson = dartPrefs.getString("flutter.budgets", null)
            var worstLine: String? = null
            var worstRatio = 0.0
            if (budgetsJson != null && budgetsJson.isNotEmpty()) {
                try {
                    val arr = JSONArray(budgetsJson)
                    for (i in 0 until arr.length()) {
                        val b = arr.getJSONObject(i)
                        val target = b.optString("target")
                        val label = b.optString("label", target)
                        val limit = b.optDouble("limit", 0.0)
                        if (target.isEmpty() || limit <= 0.0) continue
                        val spend = SmsDb.getBudgetSpend(ctx, target, 1)
                        val ratio = spend / limit
                        if (ratio >= 0.8 && ratio > worstRatio) {
                            worstRatio = ratio
                            worstLine =
                                "$label at ${(ratio * 100).toInt()}% " +
                                "(${"%,.0f".format(spend)} / ${"%,.0f".format(limit)})"
                        }
                    }
                } catch (_: Exception) {}
            }
            if (worstLine != null) {
                val today = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date())
                if (prefs.getString("budget_alert_day", "") != today) {
                    Notifier.notifyBudget(ctx, "Budget alert", worstLine!!)
                    prefs.edit().putString("budget_alert_day", today).apply()
                }
            }

            if (!digestEnabled) return Result.success()

            val last = prefs.getLong("digest_last_sent", 0L)
            val now = System.currentTimeMillis()
            if (now - last < 6L * 24 * 3600 * 1000) return Result.success()

            var text = SmsDb.getDigest(ctx)
            if (text.isNotEmpty()) {
                if (worstLine != null) text += " · Budget: $worstLine"
                Notifier.notifyDigest(ctx, text)
                prefs.edit().putLong("digest_last_sent", now).apply()
            }
        } catch (e: Exception) {
            DebugLog.exception(ctx, "DigestWorker", e)
        }
        return Result.success()
    }
}
