package com.pdg.galaxymicrolaunchpad

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.RemoteViews

class UsageWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        UsageWidgetUpdater.render(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        UsageWidgetUpdater.render(context, appWidgetManager, intArrayOf(appWidgetId))
    }
}

internal data class UsageWidgetValues(
    val weeklyRemaining: Int?,
    val fiveHourRemaining: Int?
)

internal object UsageWidgetUpdater {
    private const val PREFERENCES_NAME = "usage_widget_state"
    private const val KEY_WEEKLY_REMAINING = "weekly_remaining"
    private const val KEY_FIVE_HOUR_REMAINING = "five_hour_remaining"

    fun onUsageChanged(context: Context, weeklyRemaining: Int?, fiveHourRemaining: Int?) {
        val appContext = context.applicationContext
        if (!saveUsage(appContext, weeklyRemaining, fiveHourRemaining)) return

        val manager = AppWidgetManager.getInstance(appContext)
        val component = ComponentName(appContext, UsageWidgetProvider::class.java)
        render(appContext, manager, manager.getAppWidgetIds(component))
    }

    fun render(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        if (appWidgetIds.isEmpty()) return

        val appContext = context.applicationContext
        val values = readUsage(appContext)
        val weeklyText = percentText(appContext, values.weeklyRemaining)
        val fiveHourText = percentText(appContext, values.fiveHourRemaining)
        val views = RemoteViews(appContext.packageName, R.layout.widget_usage).apply {
            setTextViewText(R.id.widget_weekly_value, weeklyText)
            setTextViewText(R.id.widget_five_hour_value, fiveHourText)
            setProgressBar(R.id.widget_weekly_progress, 100, values.weeklyRemaining ?: 0, false)
            setProgressBar(R.id.widget_five_hour_progress, 100, values.fiveHourRemaining ?: 0, false)
            setContentDescription(
                R.id.widget_root,
                appContext.getString(
                    R.string.usage_widget_content_description,
                    appContext.getString(R.string.usage_widget_weekly),
                    weeklyText,
                    appContext.getString(R.string.usage_widget_five_hour),
                    fiveHourText
                )
            )
            setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent(appContext))
        }
        appWidgetIds.forEach { widgetId -> manager.updateAppWidget(widgetId, views) }
    }

    private fun saveUsage(context: Context, weeklyRemaining: Int?, fiveHourRemaining: Int?): Boolean {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val weekly = weeklyRemaining?.coerceIn(0, 100)
        val fiveHour = fiveHourRemaining?.coerceIn(0, 100)
        val weeklyChanged = weekly != null &&
            preferences.getInt(KEY_WEEKLY_REMAINING, -1) != weekly
        val fiveHourChanged = fiveHour != null &&
            preferences.getInt(KEY_FIVE_HOUR_REMAINING, -1) != fiveHour
        if (!weeklyChanged && !fiveHourChanged) return false

        preferences.edit().apply {
            if (weekly != null) putInt(KEY_WEEKLY_REMAINING, weekly)
            if (fiveHour != null) putInt(KEY_FIVE_HOUR_REMAINING, fiveHour)
        }.apply()
        return true
    }

    private fun readUsage(context: Context): UsageWidgetValues {
        val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        return UsageWidgetValues(
            weeklyRemaining = preferences.getInt(KEY_WEEKLY_REMAINING, -1).takeIf { it in 0..100 },
            fiveHourRemaining = preferences.getInt(KEY_FIVE_HOUR_REMAINING, -1).takeIf { it in 0..100 }
        )
    }

    private fun percentText(context: Context, value: Int?): String {
        return value?.let { context.getString(R.string.usage_widget_percent, it) }
            ?: context.getString(R.string.usage_widget_unknown)
    }

    private fun openAppPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
