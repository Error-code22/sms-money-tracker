package com.droner.sms_money_tracker

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log

object DebugLog {
    fun exception(context: Context, tag: String, throwable: Throwable) {
        val flags = context.applicationContext.applicationInfo.flags
        val debuggable = (flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (debuggable) {
            Log.e(tag, "error", throwable)
        }
    }
}
