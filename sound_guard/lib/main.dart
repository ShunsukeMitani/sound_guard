import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'calculator.dart';
import 'database_helper.dart';
import 'analytics_screen.dart';
import 'calibration_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const SafeListeningApp());
}

class SafeListeningApp extends StatelessWidget {
  const SafeListeningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SoundGuard',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'sans-serif',
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          surface: Color(0xFF161616),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      home: const MainDashboardScreen(),
    );
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  double _currentDb = 0.0;     
  double _consumedDose = 0.0;
  int _totalSeconds = 0;
  double _peakDb = 0.0;
  double _currentLeq = 0.0;
  bool _isLoading = true;

  double _currentVolumeRatio = 0.0;
  bool _isMusicActive = false;
  bool _isHeadset = false;
  String _currentDeviceId = "Wired_Headset";
  String _currentDeviceName = "有線イヤホン";
  double _baselineDb = 75.0; 

  static const _platform = MethodChannel('com.example.soundguard/volume');

  // --- 通知用システム ---
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  DateTime? _lastWarningTime; // スパム防止用の最終警告時間

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _initNativeAndStartService();
  }

  // 通知システムの初期化と権限リクエスト
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Android 13以上のための通知権限リクエスト
    _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // 危険音量検知時のプッシュ通知発動
  Future<void> _triggerWarningNotification(double db) async {
    final now = DateTime.now();
    // 前回の警告から10分経過していなければ通知しない（スパム防止）
    if (_lastWarningTime != null && now.difference(_lastWarningTime!).inMinutes < 10) {
      return;
    }
    _lastWarningTime = now;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'danger_alert_channel',
      '危険音量アラート',
      channelDescription: '耳にダメージを与える音量を検知した際の警告',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.redAccent,
      enableVibration: true,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    
    await _flutterLocalNotificationsPlugin.show(
      888, // 通知ID
      '⚠️ 警告：危険な音量レベルです',
      '現在の音量（${db.toInt()}dB）は聴覚に深刻なダメージを与える可能性があります。直ちに音量を下げてください。',
      platformDetails,
    );
  }

  Future<void> _initNativeAndStartService() async {
    await _loadDataFromDatabase();
    try {
      await _platform.invokeMethod('startForegroundService', {
        'baselineMap': {_currentDeviceId: _baselineDb}
      });
    } catch (e) {
      debugPrint("Service start error: $e");
    }
    _initNativeVolumeListener();
  }

  void _initNativeVolumeListener() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == "onStatusChanged") {
        final args = Map<dynamic, dynamic>.from(call.arguments);
        final double volumeRatio = args['volumeRatio'] as double;
        final bool isMusicActive = args['isMusicActive'] as bool;
        final bool isHeadset = args['isHeadset'] as bool;
        final String deviceId = args['deviceId'] as String? ?? "Wired_Headset";
        final String deviceName = args['deviceName'] as String? ?? "有線イヤホン";
        final double calculatedDb = args['calculatedDb'] as double? ?? 0.0;

        if (isHeadset && deviceId != _currentDeviceId) {
          final savedBaseline = await DatabaseHelper.instance.getCalibration(deviceId);
          if (savedBaseline != null) {
            _baselineDb = savedBaseline;
            await _platform.invokeMethod('updateBaseline', {
              'deviceId': deviceId,
              'baselineDb': _baselineDb,
            });
          } else {
            _baselineDb = 75.0; 
          }
        }

        if (isHeadset && isMusicActive && calculatedDb > 0) {
          _totalSeconds++;
          if (calculatedDb > _peakDb) _peakDb = calculatedDb;
          
          double hours = SafeListeningCalculator.calculateAllowedHours(calculatedDb);
          double doseTick = 0.0;
          if (hours > 0 && hours != double.infinity) {
            doseTick = 100.0 / (hours * 3600.0);
            _consumedDose += doseTick;
          }
          
          if (_totalSeconds == 1) {
            _currentLeq = calculatedDb;
          } else {
            _currentLeq = ((_currentLeq * (_totalSeconds - 1)) + calculatedDb) / _totalSeconds;
          }

          // --- 【追加】90dBを超えたらアラートを発動 ---
          if (calculatedDb >= 90.0) {
            _triggerWarningNotification(calculatedDb);
          }

          try {
            final nowStr = DateTime.now().toIso8601String();
            final oneSecAgoStr = DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String();
            DatabaseHelper.instance.insertSession({
              'db_level': calculatedDb,
              'start_time': oneSecAgoStr,
              'end_time': nowStr,
              'consumed_dose': doseTick,
            });
          } catch (e) {
            debugPrint("DB Insert Error: $e");
          }
        }

        if (mounted) {
          setState(() {
            _currentDb = calculatedDb;
            _currentVolumeRatio = volumeRatio;
            _isMusicActive = isMusicActive;
            _isHeadset = isHeadset;
            _currentDeviceId = deviceId;
            _currentDeviceName = deviceName;
          });
        }
      }
    });
  }

  Future<void> _loadDataFromDatabase() async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.deleteOldSessions();

    final pastSessions = await dbHelper.getPastSevenDaysSessions();
    double totalDose = 0.0;
    for (var session in pastSessions) {
      totalDose += (session['consumed_dose'] as num).toDouble();
    }
    if (totalDose > 100.0) totalDose = 100.0;

    final todaySessions = await dbHelper.getTodaySessions();
    int totalSec = 0;
    double maxDb = 0.0;
    List<Map<String, dynamic>> leqInput = [];

    for (var session in todaySessions) {
      double db = (session['db_level'] as num).toDouble();
      DateTime start = DateTime.parse(session['start_time'] as String);
      DateTime end = DateTime.parse(session['end_time'] as String);
      
      int duration = end.difference(start).inSeconds;
      if (duration <= 0) duration = 1; 

      totalSec += duration;
      if (db > maxDb) maxDb = db;
      leqInput.add({'db': db, 'seconds': duration});
    }

    double leq = SafeListeningCalculator.calculateLeq(leqInput);

    if (mounted) {
      setState(() {
        _consumedDose = totalDose;
        _totalSeconds = totalSec;
        _peakDb = maxDb;
        _currentLeq = leq;
        _isLoading = false;
      });
    }
  }

  Future<void> _showResetDialog() async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text('データの完全初期化', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        content: const Text('これまでのすべての耳の負担データ履歴、およびイヤホンの個別設定が完全に消去されます。よろしいですか？', style: TextStyle(fontSize: 13, color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              final messenger = ScaffoldMessenger.of(context);

              await DatabaseHelper.instance.clearAllData();
              await _platform.invokeMethod('clearServiceData');
              await _loadDataFromDatabase();
              
              if (mounted) {
                setState(() {
                  _currentDb = 0.0;
                  _baselineDb = 75.0;
                });
              }
              
              nav.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('すべてのデータを正常にリセットしました。'), backgroundColor: Colors.cyanAccent),
              );
            },
            child: const Text('初期化する', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showSpecificationInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
        ),
        title: const Row(
          children: [
            Icon(Icons.gpp_good_outlined, color: Colors.cyanAccent, size: 22),
            SizedBox(width: 8),
            Text('WHO安全基準 と アプリの仕様', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '【WHO（世界保健機関）安全基準】',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'WHO及び国際電気標準会議（IEC）は、耳への永続的なダメージ（騒音性難聴）を防ぐため、1週間あたりの安全なリスニング上限（Dose 100%）を以下のように定めています。',
                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F0F),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF222222)),
                  ),
                  child: Table(
                    border: const TableBorder(
                      horizontalInside: BorderSide(color: Color(0xFF222222), width: 1.0),
                    ),
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(1.2),
                    },
                    children: [
                      _buildTableRow('音圧レベル (dB)', '1週間の許容時間', isHeader: true),
                      _buildTableRow('80 dB', '週 40 時間 まで'),
                      _buildTableRow('85 dB', '週 12.5 時間 まで'),
                      _buildTableRow('90 dB', '週 4 時間 まで'),
                      _buildTableRow('95 dB', '週 1.25 時間 まで'),
                      _buildTableRow('100 dB', '週 24 分 まで(極めて危険)'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF222222)),
                const SizedBox(height: 8),
                const Text(
                  '【本アプリの測定仕様について】',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  '本アプリが表示する騒音レベル（dB）は、AndroidOSのセキュリティ制限に準拠するため、マイクによる常時実測ではなく「システム音量設定」と「音楽の再生状態」から対数エネルギー変換を用いてリアルタイムに算出した【論理推定値】です。\n\nキャリブレーションで実測したイヤホン固有の基準音圧をベースに、聴覚保護の観点から最も安全（高め）に見積もったマージンで計算されています。',
                  style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  TableRow _buildTableRow(String col1, String col2, {bool isHeader = false}) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
          child: Text(
            col1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.grey : Colors.white,
              fontFamily: isHeader ? 'sans-serif' : 'monospace',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10.0),
          child: Text(
            col2,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              color: isHeader ? Colors.grey : (col2.contains('分') ? Colors.redAccent : Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedRemainingTime() {
    if (_currentDb == 0.0) {
      return const Text(
        '音楽は再生されていません。耳は安全です。',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey, height: 1.6, fontSize: 13, letterSpacing: 0.5),
      );
    }
    double hours = SafeListeningCalculator.calculateAllowedHours(_currentDb);
    String text = hours == double.infinity 
        ? '安全な音量レベルです。' 
        : '現在の音量レベルを維持した場合、\nあと ${hours.floor()}時間${((hours - hours.floor()) * 60).round()}分 で限界に達します。';

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: _currentDb, end: _currentDb),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        return Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, height: 1.6, fontSize: 13, letterSpacing: 0.5));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double remainingHealth = 100.0 - _consumedDose;
    if (remainingHealth < 0) remainingHealth = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, 
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            onPressed: _showResetDialog,
          ),
          IconButton(
            icon: const Icon(Icons.headphones_outlined, color: Colors.cyanAccent),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CalibrationScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, color: Colors.grey),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const AnalyticsScreen()));
            },
          ),
          const SizedBox(width: 8), 
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),
                    AnimatedSoundMeter(currentDb: _currentDb),
                    const SizedBox(height: 32),
                    _buildHealthGauge(remainingHealth),
                    const SizedBox(height: 16),
                    _buildAnimatedRemainingTime(),
                    const Spacer(),
                    _buildStatusGrid(),
                    const SizedBox(height: 16),
                    _buildNativeStatusPanel(),
                    const SizedBox(height: 8), 
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHealthGauge(double remainingHealth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('EAR HEALTH', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.5)),
            Text('${remainingHealth.toStringAsFixed(1)}%', style: TextStyle(fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: remainingHealth > 20 ? Colors.cyanAccent : Colors.redAccent)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: remainingHealth / 100, backgroundColor: const Color(0xFF222222), color: remainingHealth > 20 ? Colors.cyanAccent : Colors.redAccent, minHeight: 8, borderRadius: BorderRadius.circular(4)),
      ],
    );
  }

  Widget _buildStatusGrid() {
    int h = _totalSeconds ~/ 3600;
    int m = (_totalSeconds % 3600) ~/ 60;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStatusCard('TOTAL TIME', '${h}h ${m}m', Icons.schedule),
        _buildStatusCard('AVERAGE', '${_currentLeq.toInt()} dB', Icons.bar_chart),
        _buildStatusCard('PEAK LEVEL', '${_peakDb.toInt()} dB', Icons.warning_amber_rounded),
      ],
    );
  }

  Widget _buildStatusCard(String title, String value, IconData icon) {
    return Expanded(
      child: Card(
        color: const Color(0xFF161616),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF2A2A2A))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
          child: Column(
            children: [
              Icon(icon, color: Colors.grey.shade600, size: 20),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNativeStatusPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SYSTEM AUDIO STATUS', style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.0)),
              GestureDetector(
                onTap: _showSpecificationInfo,
                child: const Icon(Icons.help_outline_rounded, color: Colors.grey, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusIndicator('VOLUME', '${(_currentVolumeRatio * 100).toInt()}%', Colors.white),
              _buildStatusIndicator('DEVICE', _isHeadset ? _currentDeviceName : '本体スピーカー（除外）', _isHeadset ? Colors.cyanAccent : Colors.grey),
              _buildStatusIndicator('MUSIC', _isMusicActive ? 'PLAYING' : 'STOPPED', _isMusicActive ? Colors.cyanAccent : Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace')),
      ],
    );
  }
}

class AnimatedSoundMeter extends StatelessWidget {
  final double currentDb;
  const AnimatedSoundMeter({super.key, required this.currentDb});

  Color _getMeterColor(double db) {
    if (db == 0) return Colors.grey.shade800;
    if (db < 80) return Colors.cyanAccent;
    if (db <= 90) return Colors.amber;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: currentDb, end: currentDb),
      duration: const Duration(milliseconds: 300),
      builder: (context, value, child) {
        Color meterColor = _getMeterColor(value);
        String statusText = value == 0 ? 'STANDBY' : (value < 80 ? 'SAFE' : (value <= 90 ? 'WARNING' : 'DANGER'));

        return Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: meterColor.withValues(alpha: value == 0 ? 0.1 : 0.3), width: 2),
            boxShadow: [BoxShadow(color: meterColor.withValues(alpha: value == 0 ? 0 : 0.1), blurRadius: 50, spreadRadius: 5)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value == 0 ? '--' : value.toInt().toString(),
                style: TextStyle(fontSize: 88, fontWeight: FontWeight.w200, fontFamily: 'monospace', color: value == 0 ? Colors.grey.shade700 : Colors.white),
              ),
              Text('dB', style: TextStyle(fontSize: 20, color: Colors.grey.shade700, letterSpacing: 2.0)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: meterColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: meterColor.withValues(alpha: value == 0 ? 0.2 : 0.5))),
                child: Text(statusText, style: TextStyle(color: meterColor, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ],
          ),
        );
      },
    );
  }
}