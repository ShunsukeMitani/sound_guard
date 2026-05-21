package com.example.sound_guard

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import java.util.Timer
import java.util.TimerTask
import kotlin.concurrent.thread
import kotlin.math.log10

class SoundMonitorService : Service() {

    private val NOTIFICATION_ID = 888
    private val CHANNEL_ID = "soundguard_monitor_channel"
    
    private var audioManager: AudioManager? = null
    private var volumeReceiver: BroadcastReceiver? = null
    private var monitorTimer: Timer? = null

    companion object {
        private var mainActivity: MainActivity? = null
        private var baselineDbMap = HashMap<String, Double>()
        
        private var accumulatedSeconds = 0
        private var accumulatedDbSum = 0.0 // 追加：平均を出すための合計値
        private var peakDb = 0.0

        fun setMainActivity(activity: MainActivity?) {
            mainActivity = activity
        }

        fun updateBaselineMap(map: Map<String, Double>) {
            baselineDbMap.clear()
            for ((k, v) in map) {
                baselineDbMap[k] = v
            }
        }

        fun addBaseline(deviceId: String, db: Double) {
            baselineDbMap[deviceId] = db
        }

        fun clearStats() {
            accumulatedSeconds = 0
            accumulatedDbSum = 0.0
            peakDb = 0.0
        }
    }

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
        
        startForeground(NOTIFICATION_ID, buildNotification("SoundGuard 稼働中", "耳の健康を守るため音量を監視しています。"))

        val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
        volumeReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                thread { analyzeAndExecute() }
            }
        }
        registerReceiver(volumeReceiver, filter)

        monitorTimer = Timer()
        monitorTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                analyzeAndExecute()
            }
        }, 0, 1000)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY 
    }

    private fun analyzeAndExecute() {
        val audioManager = audioManager ?: return
        
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val volumeRatio = if (maxVolume > 0) currentVolume.toDouble() / maxVolume.toDouble() else 0.0
        val isMusicActive = audioManager.isMusicActive

        val deviceInfo = getConnectedHeadsetInfo()
        val isHeadset = deviceInfo.isHeadset
        val deviceId = deviceInfo.deviceId
        val deviceName = deviceInfo.deviceName

        var calculatedDb = 0.0
        if (isHeadset && isMusicActive && volumeRatio > 0.01) {
            val base = baselineDbMap[deviceId] ?: 75.0
            calculatedDb = base + 20 * log10(volumeRatio / 0.5)
            if (calculatedDb < 30.0) calculatedDb = 30.0
            if (calculatedDb > 120.0) calculatedDb = 120.0

            accumulatedSeconds++
            accumulatedDbSum += calculatedDb // 合計を加算
            if (calculatedDb > peakDb) peakDb = calculatedDb
        }

        // 平均値の計算
        val avgDb = if (accumulatedSeconds > 0) accumulatedDbSum / accumulatedSeconds else 0.0

        val text = if (calculatedDb > 0) {
            "現在の推定音圧: ${calculatedDb.toInt()} dB [ $deviceName ]"
        } else if (isHeadset && !isMusicActive) {
            "スタンバイ中: 音楽は停止しています [ $deviceName ]"
        } else {
            "イヤホン/ヘッドホンが接続されていません"
        }
        updateNotification(text)

        // 追加：平均値もウィジェットに送る
        sendUpdateToWidget(calculatedDb, deviceName, avgDb)

        mainActivity?.sendStatusToFlutter(mapOf(
            "volumeRatio" to volumeRatio,
            "isMusicActive" to isMusicActive,
            "isHeadset" to isHeadset,
            "deviceId" to deviceId,
            "deviceName" to deviceName,
            "calculatedDb" to calculatedDb
        ))
    }

    private fun getConnectedHeadsetInfo(): DeviceInfo {
        val am = audioManager ?: return DeviceInfo(false, "", "")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val outputs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in outputs) {
                if (device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET || device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES) {
                    return DeviceInfo(true, "Wired_Headset", "有線イヤホン")
                }
                
                if (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) {
                    val name = device.productName?.toString() ?: "Bluetooth機器"
                    
                    val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                    val adapter = bm?.adapter
                    if (adapter != null && ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                        val bondedDevices = adapter.bondedDevices
                        for (bd in bondedDevices) {
                            if (bd.name == name) {
                                val btClass = bd.bluetoothClass
                                if (btClass != null) {
                                    val deviceClass = btClass.deviceClass
                                    if (deviceClass == BluetoothClass.Device.AUDIO_VIDEO_LOUDSPEAKER || 
                                        deviceClass == BluetoothClass.Device.AUDIO_VIDEO_HIFI_AUDIO ||
                                        deviceClass == BluetoothClass.Device.AUDIO_VIDEO_SET_TOP_BOX) {
                                        return DeviceInfo(false, "", "") 
                                    }
                                }
                            }
                        }
                    }
                    return DeviceInfo(true, name, name) 
                }
            }
        } else {
            if (am.isWiredHeadsetOn) return DeviceInfo(true, "Wired_Headset", "有線イヤホン")
            if (am.isBluetoothA2dpOn) return DeviceInfo(true, "Bluetooth_Device", "Bluetoothイヤホン")
        }
        return DeviceInfo(false, "", "")
    }

    data class DeviceInfo(val isHeadset: Boolean, val deviceId: String, val deviceName: String)

    private fun sendUpdateToWidget(db: Double, deviceName: String, avgDb: Double) {
        val intent = Intent("com.example.soundguard.WIDGET_UPDATE")
        intent.setPackage(packageName)
        intent.putExtra("db", db)
        intent.putExtra("deviceName", deviceName)
        intent.putExtra("totalTime", accumulatedSeconds)
        intent.putExtra("avgDb", avgDb) // 追加
        sendBroadcast(intent)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(CHANNEL_ID, "SoundGuard Monitor", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(serviceChannel)
        }
    }

    private fun buildNotification(title: String, content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_menu_compass) 
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(content: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification("SoundGuard 耳の健康を監視中", content))
    }

    override fun onDestroy() {
        super.onDestroy()
        monitorTimer?.cancel()
        monitorTimer = null
        volumeReceiver?.let { unregisterReceiver(it) }
        stopForeground(true)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}