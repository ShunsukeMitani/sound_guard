package com.example.sound_guard

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.soundguard/volume"
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            methodChannel = MethodChannel(messenger, CHANNEL)
        }

        // Flutterからのサービス制御要求を受け取る
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    // Flutterから現在の機器ごとの基準dBマップを受け取ってサービスに渡す
                    val baselineMap = call.argument<Map<String, Double>>("baselineMap") ?: emptyMap()
                    SoundMonitorService.updateBaselineMap(baselineMap)
                    
                    val intent = Intent(this, SoundMonitorService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopService(Intent(this, SoundMonitorService::class.java))
                    result.success(true)
                }
                "updateBaseline" -> {
                    val deviceId = call.argument<String>("deviceId") ?: ""
                    val db = call.argument<Double>("baselineDb") ?: 75.0
                    SoundMonitorService.addBaseline(deviceId, db)
                    result.success(true)
                }
                "clearServiceData" -> {
                    SoundMonitorService.clearStats()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // インスタンスをサービス側に共有（リアルタイム通知用）
        SoundMonitorService.setMainActivity(this)

        // 必須権限の一括リクエスト（マイク、通知、Bluetooth）
        requestRequiredPermissions()
    }

    private fun requestRequiredPermissions() {
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            permissions.add(Manifest.permission.BLUETOOTH)
        }

        val missingPermissions = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), 100)
        }
    }

    // サービスからFlutterへ最新ステータスを送る
    fun sendStatusToFlutter(status: Map<String, Any>) {
        runOnUiThread {
            methodChannel?.invokeMethod("onStatusChanged", status)
        }
    }

    // サービスからFlutterへキャリブレーション中の一瞬のdBデータを送る
    fun sendCalibrationProgress(db: Double) {
        runOnUiThread {
            methodChannel?.invokeMethod("onCalibrationProgress", db)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        SoundMonitorService.setMainActivity(null)
    }
}