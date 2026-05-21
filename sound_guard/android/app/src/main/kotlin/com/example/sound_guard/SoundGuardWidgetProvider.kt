package com.example.sound_guard

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews

class SoundGuardWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateWidgetView(context, appWidgetManager, appWidgetId, 0.0, "未接続", 0, 0.0)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.example.soundguard.WIDGET_UPDATE") {
            val db = intent.getDoubleExtra("db", 0.0)
            val deviceName = intent.getStringExtra("deviceName") ?: "未接続"
            val totalTime = intent.getIntExtra("totalTime", 0)
            val avgDb = intent.getDoubleExtra("avgDb", 0.0)
            
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, SoundGuardWidgetProvider::class.java)
            val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            
            for (widgetId in allWidgetIds) {
                updateWidgetView(context, appWidgetManager, widgetId, db, deviceName, totalTime, avgDb)
            }
        }
    }

    private fun updateWidgetView(context: Context, appWidgetManager: AppWidgetManager, widgetId: Int, db: Double, deviceName: String, totalTime: Int, avgDb: Double) {
        val views = RemoteViews(context.packageName, R.layout.soundguard_widget)
        
        val h = totalTime / 3600
        val m = (totalTime % 3600) / 60
        views.setTextViewText(R.id.widget_time_text, "${h}h ${m}m")
        
        if (avgDb > 0) views.setTextViewText(R.id.widget_avg_text, "${avgDb.toInt()} dB")
        else views.setTextViewText(R.id.widget_avg_text, "-- dB")

        if (db > 0) {
            val color = if (db < 80) Color.parseColor("#00E5FF") 
                        else if (db <= 90) Color.parseColor("#FFC107") 
                        else Color.parseColor("#FF5252")

            val statusText = if (db < 80) "SAFE" else if (db <= 90) "WARNING" else "DANGER"

            views.setTextViewText(R.id.widget_db_text, "${db.toInt()} dB")
            views.setTextColor(R.id.widget_db_text, color)
            views.setTextViewText(R.id.widget_status_text, statusText)
            views.setTextColor(R.id.widget_status_text, color)
            
            // 円の枠線の色を変更する命令
            views.setInt(R.id.widget_circle_bg, "setColorFilter", color)
            views.setTextViewText(R.id.widget_device_text, deviceName)
        } else {
            views.setTextViewText(R.id.widget_db_text, "-- dB")
            views.setTextColor(R.id.widget_db_text, Color.parseColor("#FFFFFF"))
            views.setTextViewText(R.id.widget_status_text, "STANDBY")
            views.setTextColor(R.id.widget_status_text, Color.parseColor("#00E5FF"))
            
            // 待機中は円の色をグレーに
            views.setInt(R.id.widget_circle_bg, "setColorFilter", Color.parseColor("#333333"))
            views.setTextViewText(R.id.widget_device_text, if (deviceName.isNotEmpty() && deviceName != "未接続") deviceName else "イヤホン未接続")
        }

        appWidgetManager.updateAppWidget(widgetId, views)
    }
}