package com.example.sound_guard

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

class SoundGuardMinWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateMinWidget(context, appWidgetManager, appWidgetId, 0.0)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.example.soundguard.WIDGET_UPDATE") {
            val db = intent.getDoubleExtra("db", 0.0)
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, SoundGuardMinWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            
            for (widgetId in allWidgetIds) {
                updateMinWidget(context, appWidgetManager, widgetId, db)
            }
        }
    }

    private fun updateMinWidget(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, db: Double) {
        val views = RemoteViews(context.packageName, R.layout.soundguard_widget_min)
        
        if (db > 0) {
            val color = if (db < 80) Color.parseColor("#00E5FF") 
                        else if (db <= 90) Color.parseColor("#FFC107") 
                        else Color.parseColor("#FF5252")

            views.setTextViewText(R.id.widget_min_db_text, "${db.toInt()}dB")
            views.setTextColor(R.id.widget_min_db_text, color)
        } else {
            views.setTextViewText(R.id.widget_min_db_text, "--dB")
            views.setTextColor(R.id.widget_min_db_text, Color.parseColor("#888888"))
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}