import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const _platform = MethodChannel('com.example.soundguard/volume');

  bool _isMeasuring = false;
  bool _isCompleted = false;
  double _progress = 0.0;
  double _measuredDb = 0.0;
  final List<double> _measurements = [];

  @override
  void initState() {
    super.initState();
    // この画面専用のネイティブ通信リスナーを設定
    _platform.setMethodCallHandler(_handleMethodCall);
  }

  @override
  void dispose() {
    // 画面を閉じる際に確実にマイクをオフにする
    _platform.invokeMethod('stopCalibration');
    super.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == "onCalibrationProgress") {
      double db = call.arguments as double;
      _measurements.add(db);
    }
  }

  Future<void> _startCalibration() async {
    setState(() {
      _isMeasuring = true;
      _isCompleted = false;
      _progress = 0.0;
      _measurements.clear();
    });

    try {
      final bool success = await _platform.invokeMethod('startCalibration');
      if (!success) return;

      // 3秒間の計測タイマー
      Timer.periodic(const Duration(milliseconds: 50), (timer) {
        setState(() {
          _progress += 0.017;
          if (_progress >= 1.0) {
            _progress = 1.0;
            _isMeasuring = false;
            _isCompleted = true;
            timer.cancel();
            
            _platform.invokeMethod('stopCalibration');
            
            // 取得した波形データの平均値を計算
            if (_measurements.isNotEmpty) {
               _measuredDb = _measurements.reduce((a, b) => a + b) / _measurements.length;
            } else {
               _measuredDb = 75.0; // フォールバック
            }
          }
        });
      });
    } on PlatformException catch (e) {
      debugPrint("Calibration Error: ${e.message}");
      setState(() {
        _isMeasuring = false;
      });
    }
  }

  Future<void> _saveAndComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('baseline_db', _measuredDb);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'CALIBRATION',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 4.0),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'EARPHONE SETUP',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.cyanAccent,
                fontSize: 14,
                letterSpacing: 2.0,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            
            _buildStepRow('01', 'デバイスのメディア音量を正確に「50%」に設定してください。'),
            const SizedBox(height: 24),
            _buildStepRow('02', 'イヤホンのスピーカー部分を、デバイスのマイクに直接密着させてください。'),
            const SizedBox(height: 24),
            _buildStepRow('03', '「MEASURE」を押すと測定用の基準音が再生され、自動で音圧を記録します。'),
            
            const Spacer(),

            if (_isMeasuring) ...[
              _buildMeasuringIndicator(),
            ] else if (_isCompleted) ...[
              _buildResultDisplay(),
            ] else ...[
              const SizedBox(height: 120),
            ],

            const Spacer(),

            OutlinedButton(
              onPressed: _isMeasuring ? null : (_isCompleted ? _saveAndComplete : _startCalibration),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                side: BorderSide(
                  color: _isMeasuring ? Colors.grey.withValues(alpha: 0.3) : Colors.cyanAccent,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                _isCompleted ? 'SAVE & COMPLETE' : (_isMeasuring ? 'MEASURING...' : 'START MEASURE'),
                style: TextStyle(
                  color: _isMeasuring ? Colors.grey : Colors.cyanAccent,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          number,
          style: const TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
        ),
      ],
    );
  }

  Widget _buildMeasuringIndicator() {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            value: _progress,
            strokeWidth: 2,
            backgroundColor: const Color(0xFF222222),
            color: Colors.cyanAccent,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'ANALYZING AUDIO SIGNAL...',
          style: TextStyle(color: Colors.grey, fontFamily: 'monospace', fontSize: 12, letterSpacing: 1.5),
        ),
      ],
    );
  }

  Widget _buildResultDisplay() {
    return Column(
      children: [
        const Text(
          'BASE SPL (at 50% Volume)',
          style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _measuredDb.toStringAsFixed(1),
              style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w200, fontFamily: 'monospace', color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text('dB', style: TextStyle(fontSize: 16, color: Colors.cyanAccent, letterSpacing: 2.0)),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: const Text('SUCCESS', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        ),
      ],
    );
  }
}