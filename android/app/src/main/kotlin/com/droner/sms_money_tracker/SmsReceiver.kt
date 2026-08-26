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
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                SmsSync.sync(context)
            } catch (e: Exception) {
                DebugLog.exception(context, "SmsReceiver", e)
            } finally {
                pendingResult.finish()
            }
        }, 3000)
    }
}
