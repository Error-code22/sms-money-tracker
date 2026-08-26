package com.droner.sms_money_tracker

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

/**
 * Logging that is a no-op in release builds. Nothing in this app ever logs
 * SMS content; stack traces are debug-only so release builds stay silent.
 */
object DebugLog {
    fun exception(context: Context, tag: String, throwable: Throwable) {
        val flags = context.applicationContext.applicationInfo.flags
        val debuggable = (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) {
            Log.e(tag, "error", throwable)
        }
    }
}
