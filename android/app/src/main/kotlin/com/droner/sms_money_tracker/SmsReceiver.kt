package com.droner.sms_money_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val pendingResult = goAsync()
        syncExecutor.execute {
            try {
                // Small delay so the SMS is committed to the content provider
                // before we query it. Runs off the main thread.
                Thread.sleep(3000)
                val added = SmsSync.sync(context)
                if (added > 0 && !AppForegroundState.isForeground) {
                    Notifier.notifyNewTransactions(context, added)
                }
            } catch (e: Exception) {
                DebugLog.exception(context, "SmsReceiver", e)
            } finally {
                Handler(Looper.getMainLooper()).post { pendingResult.finish() }
            }
        }
    }
}
