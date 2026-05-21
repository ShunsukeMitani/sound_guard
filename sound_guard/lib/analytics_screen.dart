import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';
import 'calculator.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isLoading = true;
  
  List<double> _dailyDose = List.filled(7, 0.0);
  List<double> _dailyPeakDb = List.filled(7, 0.0);
  final List<String> _dayLabels = List.filled(7, '');

  double _weeklyTotalDose = 0.0;
  int _weeklyTotalSeconds = 0;
  double _weeklyAvgDb = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    final dbHelper = DatabaseHelper.instance;
    final pastSessions = await dbHelper.getPastSevenDaysSessions();

    final now = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final d = now.subtract(Duration(days: 6 - i));
      _dayLabels[i] = DateFormat('M/d').format(d);
    }

    double totalDose = 0.0;
    int totalSec = 0;
    List<Map<String, dynamic>> allLeqInput = [];

    List<double> dailyDoseTemp = List.filled(7, 0.0);
    List<double> dailyPeakTemp = List.filled(7, 0.0);

    for (var session in pastSessions) {
      double db = (session['db_level'] as num).toDouble();
      double dose = (session['consumed_dose'] as num).toDouble();
      DateTime start = DateTime.parse(session['start_time'] as String);
      DateTime end = DateTime.parse(session['end_time'] as String);
      
      int duration = end.difference(start).inSeconds;
      if (duration <= 0) duration = 1; 

      totalDose += dose;
      totalSec += duration;
      allLeqInput.add({'db': db, 'seconds': duration});

      final sessionDate = DateTime(start.year, start.month, start.day);
      final todayDate = DateTime(now.year, now.month, now.day);
      final differenceDays = todayDate.difference(sessionDate).inDays;

      if (differenceDays >= 0 && differenceDays <= 6) {
        int index = 6 - differenceDays;
        dailyDoseTemp[index] += dose;
        if (db > dailyPeakTemp[index]) {
          dailyPeakTemp[index] = db;
        }
      }
    }

    double avgLeq = SafeListeningCalculator.calculateLeq(allLeqInput);

    if (mounted) {
      setState(() {
        _dailyDose = dailyDoseTemp;
        _dailyPeakDb = dailyPeakTemp;
        
        _weeklyTotalDose = totalDose;
        _weeklyTotalSeconds = totalSec;
        _weeklyAvgDb = avgLeq;
        
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('ANALYTICS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2.0)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryCards(),
                    const SizedBox(height: 32),
                    const Text('WEEKLY EAR DAMAGE (Dose %)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0)),
                    const SizedBox(height: 16),
                    _buildDoseChart(),
                    const SizedBox(height: 40),
                    const Text('DAILY PEAK LEVEL (dB)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0)),
                    const SizedBox(height: 16),
                    _buildPeakDbChart(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCards() {
    int h = _weeklyTotalSeconds ~/ 3600;
    int m = (_weeklyTotalSeconds % 3600) ~/ 60;
    
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF161616), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2A2A2A))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL DOSE', style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 1.0)),
                const SizedBox(height: 8),
                Text('${_weeklyTotalDose.toStringAsFixed(1)}%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _weeklyTotalDose > 100 ? Colors.redAccent : Colors.cyanAccent, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('Past 7 days', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _buildMiniCard('AVG LEVEL', '${_weeklyAvgDb.toInt()} dB', Icons.bar_chart),
              const SizedBox(height: 12),
              _buildMiniCard('TOTAL TIME', '${h}h ${m}m', Icons.schedule),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniCard(String title, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFF161616), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2A2A2A))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 9, color: Colors.grey, letterSpacing: 1.0)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'monospace')),
            ],
          ),
          Icon(icon, color: Colors.grey.shade700, size: 20),
        ],
      ),
    );
  }

  Widget _buildDoseChart() {
    return AspectRatio(
      aspectRatio: 1.7,
      child: Container(
        padding: const EdgeInsets.only(top: 24, right: 16, left: 0, bottom: 12),
        decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF222222))),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: _weeklyTotalDose > 100 ? _weeklyTotalDose + 20 : 100,
            
            // --- 純正のタッチ判定機能をオン（高い位置に％を表示） ---
            barTouchData: BarTouchData(
              enabled: true, 
              touchTooltipData: BarTouchTooltipData(
                tooltipBgColor: const Color(0xFF2A2A2A),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                tooltipMargin: 40, // 指に隠れないよう大きく上にシフト
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    '${rod.toY.toStringAsFixed(1)}%',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                  );
                },
              ),
            ),
            
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    if (value < 0 || value >= _dayLabels.length) return const SizedBox.shrink();
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8.0,
                      child: Text(_dayLabels[value.toInt()], style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: 50,
                  getTitlesWidget: (value, meta) {
                    if (value == 0 || value == 50 || value == 100) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text('${value.toInt()}%', style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 50,
              getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF222222), strokeWidth: 1),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: 100,
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  strokeWidth: 1.5,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 5, bottom: 5),
                    style: const TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                    labelResolver: (line) => 'LIMIT',
                  ),
                ),
              ],
            ),
            borderData: FlBorderData(show: false),
            barGroups: _dailyDose.asMap().entries.map((e) {
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value,
                    color: e.value > 100 ? Colors.redAccent : Colors.cyanAccent,
                    width: 16,
                    borderRadius: BorderRadius.circular(4),
                    backDrawRodData: BackgroundBarChartRodData(show: true, toY: 100, color: const Color(0xFF1A1A1A)),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPeakDbChart() {
    List<FlSpot> spots = [];
    for (int i = 0; i < 7; i++) {
      spots.add(FlSpot(i.toDouble(), _dailyPeakDb[i] > 0 ? _dailyPeakDb[i] : 30));
    }

    final peakLineBarData = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: Colors.amber,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: true, color: Colors.amber.withValues(alpha: 0.1)),
    );

    return AspectRatio(
      aspectRatio: 1.7,
      child: Container(
        padding: const EdgeInsets.only(top: 24, right: 16, left: 0, bottom: 12),
        decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF222222))),
        child: LineChart(
          LineChartData(
            minX: 0, 
            maxX: 6, 
            minY: 30,
            maxY: 120,
            
            // --- 純正のタッチ判定機能をオン（高い位置にdBを表示） ---
            lineTouchData: LineTouchData(
              enabled: true,
              touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: const Color(0xFF2A2A2A),
                tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                tooltipMargin: 40, // 指に隠れないよう大きく上にシフト
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((LineBarSpot touchedSpot) {
                    return LineTooltipItem(
                      '${touchedSpot.y.toInt()} dB',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                    );
                  }).toList();
                },
              ),
            ),
            
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42, 
                  interval: 1,
                  getTitlesWidget: (value, meta) {
                    if (value < 0 || value >= _dayLabels.length) return const SizedBox.shrink();
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 8.0,
                      child: Text(_dayLabels[value.toInt()], style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: 30,
                  getTitlesWidget: (value, meta) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text('${value.toInt()}dB', style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 30,
              getDrawingHorizontalLine: (value) => const FlLine(color: Color(0xFF222222), strokeWidth: 1),
            ),
            extraLinesData: ExtraLinesData(
              horizontalLines: [
                HorizontalLine(
                  y: 90,
                  color: Colors.amber.withValues(alpha: 0.5),
                  strokeWidth: 1.5,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(right: 5, bottom: 5),
                    style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 9, fontWeight: FontWeight.bold),
                    labelResolver: (line) => 'WARNING',
                  ),
                ),
              ],
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [peakLineBarData],
          ),
        ),
      ),
    );
  }
}