package com.droner.sms_money_tracker

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

object Notifier {
    private const val CHANNEL_ID = "new_transactions"
    private const val CHANNEL_NAME = "New transactions"
    private const val NOTIFICATION_ID = 1

    fun notifyNewTransactions(context: Context, count: Int) {
        if (notificationsBlocked(context)) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }

        val pending = launchPendingIntent(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (count > 1) "New transactions" else "New transaction")
            .setContentText("Tap to add a note while it's fresh")
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setDefaults(Notification.DEFAULT_VIBRATE)
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }

    private const val DIGEST_CHANNEL_ID = "weekly_digest"
    private const val DIGEST_CHANNEL_NAME = "Weekly recap"
    private const val DIGEST_NOTIFICATION_ID = 2

    fun notifyDigest(context: Context, text: String) {
        if (notificationsBlocked(context)) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                DIGEST_CHANNEL_ID, DIGEST_CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT
            )
            manager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, DIGEST_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Weekly money recap")
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentText(text)
            .setContentIntent(launchPendingIntent(context))
            .setAutoCancel(true)
            .build()

        manager.notify(DIGEST_NOTIFICATION_ID, notification)
    }

    private const val BUDGET_CHANNEL_ID = "budget_alerts"
    private const val BUDGET_CHANNEL_NAME = "Budget alerts"
    private const val BUDGET_NOTIFICATION_ID = 3

    fun notifyBudget(context: Context, title: String, text: String) {
        if (notificationsBlocked(context)) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                BUDGET_CHANNEL_ID, BUDGET_CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, BUDGET_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(launchPendingIntent(context))
            .setAutoCancel(true)
            .setDefaults(Notification.DEFAULT_VIBRATE)
            .build()

        manager.notify(BUDGET_NOTIFICATION_ID, notification)
    }

    private fun notificationsBlocked(context: Context): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
    }

    private fun launchPendingIntent(context: Context): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        return PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
