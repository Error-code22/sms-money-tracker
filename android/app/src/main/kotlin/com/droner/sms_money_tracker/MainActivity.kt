package com.droner.sms_money_tracker

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity (not FlutterActivity) so the local_auth plugin's
// BiometricPrompt has a FragmentActivity host.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "sms_money_tracker/channel"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Blank the recents/overview preview and block screenshots of
        // financial data (banking-app behaviour).
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun onResume() {
        super.onResume()
        AppForegroundState.isForeground = true
    }

    override fun onPause() {
        super.onPause()
        AppForegroundState.isForeground = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        syncExecutor.execute {
                            var added = -1
                            try {
                                added = SmsSync.sync(applicationContext)
                            } catch (e: Exception) {
                                DebugLog.exception(applicationContext, "MainActivity", e)
                            }
                            val finalAdded = added
                            runOnUiThread { result.success(finalAdded) }
                        }
                    }
                    "getTransactions" -> {
                        val filter = call.argument<String>("filter") ?: "all"
                        val query = call.argument<String>("query") ?: ""
                        try {
                            result.success(SmsDb.getTransactions(applicationContext, filter, query))
                        } catch (e: Exception) {
                            result.error("query_failed", e.message, null)
                        }
                    }
                    "getSummary" -> {
                        try {
                            result.success(SmsDb.getSummary(applicationContext))
                        } catch (e: Exception) {
                            result.error("query_failed", e.message, null)
                        }
                    }
                    "getMonthlyTotals" -> {
                        val months = call.argument<Int>("months") ?: 6
                        try {
                            result.success(SmsDb.getMonthlyTotals(applicationContext, months))
                        } catch (e: Exception) {
                            result.error("query_failed", e.message, null)
                        }
                    }
                    "getTopCounterparties" -> {
                        val months = call.argument<Int>("months") ?: 1
                        try {
                            result.success(SmsDb.getTopCounterparties(applicationContext, months))
                        } catch (e: Exception) {
                            result.error("query_failed", e.message, null)
                        }
                    }
                    "getCounterpartyTransactions" -> {
                        val counterparty = call.argument<String>("counterparty") ?: ""
                        val months = call.argument<Int>("months") ?: 1
                        try {
                            result.success(
                                SmsDb.getCounterpartyTransactions(applicationContext, counterparty, months)
                            )
                        } catch (e: Exception) {
                            result.error("query_failed", e.message, null)
                        }
                    }
                    "confirmTransaction" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        try {
                            result.success(SmsDb.confirmTransaction(applicationContext, id))
                        } catch (e: Exception) {
                            result.error("confirm_failed", e.message, null)
                        }
                    }
                    "markNotMoney" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        try {
                            result.success(SmsDb.markNotMoney(applicationContext, id))
                        } catch (e: Exception) {
                            result.error("mark_failed", e.message, null)
                        }
                    }
                    "setNote" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        val note = call.argument<String>("note")
                        try {
                            result.success(SmsDb.setNote(applicationContext, id, note))
                        } catch (e: Exception) {
                            result.error("set_note_failed", e.message, null)
                        }
                    }
                    "resetSyncState" -> {
                        syncExecutor.execute {
                            var added = -1
                            try {
                                SmsSync.resetSyncState(applicationContext)
                                added = SmsSync.sync(applicationContext)
                            } catch (e: Exception) {
                                DebugLog.exception(applicationContext, "MainActivity", e)
                            }
                            val finalAdded = added
                            runOnUiThread { result.success(finalAdded) }
                        }
                    }
                    "insertManual" -> {
                        val type = call.argument<String>("type") ?: "debit"
                        val amount = call.argument<Number>("amount")?.toDouble() ?: 0.0
                        val currency = call.argument<String>("currency") ?: "KES"
                        val category = call.argument<String>("category")?.takeIf { it.isNotBlank() }
                        val counterparty = call.argument<String>("counterparty") ?: ""
                        val ts = (call.argument<Number>("ts") ?: 0).toLong()
                        val note = call.argument<String>("note") ?: ""
                        try {
                            result.success(
                                SmsDb.insertManual(
                                    applicationContext, type, amount, currency,
                                    category, counterparty, ts, note
                                )
                            )
                        } catch (e: Exception) {
                            result.error("insert_failed", e.message, null)
                        }
                    }
                    "updateTransaction" -> {
                        val id = (call.argument<Number>("id") ?: 0).toLong()
                        val type = call.argument<String>("type") ?: "debit"
                        val amount = call.argument<Number>("amount")?.toDouble() ?: 0.0
                        val currency = call.argument<String>("currency") ?: "KES"
                        val category = call.argument<String>("category")?.takeIf { it.isNotBlank() }
                        val counterparty = call.argument<String>("counterparty") ?: ""
                        val ts = (call.argument<Number>("ts") ?: 0).toLong()
                        val note = call.argument<String>("note")
                        try {
                            result.success(
                                SmsDb.updateTransaction(
                                    applicationContext, id, type, amount, currency,
                                    category, counterparty, ts, note
                                )
                            )
                        } catch (e: Exception) {
                            result.error("update_failed", e.message, null)
                        }
                    }
                    "exportCsv" -> {
                        try {
                            result.success(SmsDb.exportCsv(applicationContext))
                        } catch (e: Exception) {
                            result.error("export_failed", e.message, null)
                        }
                    }
                    "isBatteryExempt" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestBatteryExemption" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        if (pm.isIgnoringBatteryOptimizations(packageName)) {
                            result.success(true)
                        } else {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                intent.data = Uri.parse("package:$packageName")
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                try {
                                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                    result.success(true)
                                } catch (e2: Exception) {
                                    result.success(false)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
