package com.droner.sms_money_tracker

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import org.json.JSONObject

class MoneyWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) refresh(context, appWidgetManager, id)
    }

    companion object {
        fun refreshAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(ComponentName(context, MoneyWidget::class.java))
                for (id in ids) refresh(context, manager, id)
            } catch (e: Exception) {
                DebugLog.exception(context, "MoneyWidget", e)
            }
        }

        private fun refresh(context: Context, manager: AppWidgetManager, id: Int) {
            try {
                val stats = JSONObject(SmsDb.getWidgetStats(context))
                val currency = stats.optString("currency", "")
                val spent = stats.optDouble("spent", 0.0)
                val received = stats.optDouble("received", 0.0)
                val views = RemoteViews(context.packageName, R.layout.widget_money)
                views.setTextViewText(R.id.widget_spent, "Spent: $currency ${"%,.0f".format(spent)}")
                views.setTextViewText(R.id.widget_received, "In: $currency ${"%,.0f".format(received)}")
                manager.updateAppWidget(id, views)
            } catch (e: Exception) {
                DebugLog.exception(context, "MoneyWidget", e)
            }
        }
    }
}
