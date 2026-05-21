import UIKit
import Flutter
import HealthKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    
    // HealthKitの司令塔
    let healthStore = HKHealthStore()
    // Flutterと通信するための橋（チャンネル）
    var methodChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
        // Flutter側で設定したのと同じチャンネル名
        methodChannel = FlutterMethodChannel(name: "com.example.soundguard/volume",
                                              binaryMessenger: controller.binaryMessenger)
        
        methodChannel?.setMethodCallHandler({
            (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            
            if call.method == "startForegroundService" {
                // HealthKitの許可をリクエストして計測を開始
                self.requestHealthKitAuthorization(result: result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        })
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // HealthKitの許可画面を出す処理
    private func requestHealthKitAuthorization(result: @escaping FlutterResult) {
        // デバイスがHealthKitに対応しているかチェック（iPadなどは非対応）
        guard HKHealthStore.isHealthDataAvailable() else {
            result(FlutterError(code: "UNAVAILABLE",
                                message: "HealthKit is not available on this device",
                                details: nil))
            return
        }

        // 取得したいデータ（ヘッドホン音量）の型を指定
        guard let headphoneAudioExposureType = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) else {
            result(FlutterError(code: "TYPE_ERROR",
                                message: "Headphone Audio Exposure type is not available",
                                details: nil))
            return
        }

        let typesToRead: Set<HKObjectType> = [headphoneAudioExposureType]

        // ユーザーに許可を求める
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { (success, error) in
            if success {
                // 許可が下りたら、データの監視（リアルタイム取得）を開始
                self.startObservingHeadphoneAudio()
                result(true)
            } else {
                let errorMessage = error?.localizedDescription ?? "Unknown error"
                result(FlutterError(code: "AUTH_DENIED",
                                    message: "HealthKit authorization failed: \(errorMessage)",
                                    details: nil))
            }
        }
    }

    // データの変更を監視する処理
    private func startObservingHeadphoneAudio() {
        guard let sampleType = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) else { return }

        // データが追加されたことを検知するオブザーバー
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { (query, completionHandler, error) in
            if error == nil {
                // 新しいデータが検知されたら、最新の数値を読み込みに行く
                self.fetchLatestHeadphoneAudioData()
            }
            completionHandler()
        }
        
        healthStore.execute(query)
        // アプリがバックグラウンドにいても監視を続ける設定
        healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { (success, error) in
            if !success {
                print("Failed to enable background delivery: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }

    // 最新の音量データを取得してFlutterに送る処理
    private func fetchLatestHeadphoneAudioData() {
        guard let sampleType = HKObjectType.quantityType(forIdentifier: .headphoneAudioExposure) else { return }
        
        // 最新の1件だけを取得する設定
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: sampleType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { (query, samples, error) in
            
            if let result = samples?.first as? HKQuantitySample {
                // 取得したデータをデシベル(dBASPL)に変換
                let dbValue = result.quantity.doubleValue(for: HKUnit.decibelAWeightedSoundPressureLevel())
                
                // メインスレッド（画面描画用のスレッド）でFlutterにデータを送信
                DispatchQueue.main.async {
                    let data: [String: Any] = [
                        "calculatedDb": dbValue,
                        "volumeRatio": 1.0, // HealthKitからは直接取れないため仮値
                        "isMusicActive": dbValue > 30.0, // 音量が30dB以上なら再生中と判定
                        "isHeadset": true,
                        "deviceId": "Apple_HealthKit",
                        "deviceName": "HealthKit Audio"
                    ]
                    // Android版と同じ "onStatusChanged" という名前でFlutterに送る
                    self.methodChannel?.invokeMethod("onStatusChanged", arguments: data)
                }
            }
        }
        healthStore.execute(query)
    }
}