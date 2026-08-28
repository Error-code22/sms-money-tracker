package com.droner.sms_money_tracker

/**
 * Tracks whether the app's activity is in the foreground, so the SMS
 * receiver can decide between a notification (app closed) and letting
 * the Flutter UI prompt for notes (app open).
 */
object AppForegroundState {
    @Volatile
    var isForeground: Boolean = false
}
