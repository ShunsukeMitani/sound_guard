import 'dart:math';

class SafeListeningCalculator {
  // WHO基準: 80dBにおける最大許容時間（時間）
  static const double baseDb = 80.0;
  static const double baseHours = 40.0;
  // 3dB交換率
  static const double exchangeRate = 3.0;

  /// 1. 現在の音圧(dB)から、7日間の最大許容時間を計算する
  static double calculateAllowedHours(double currentDb) {
    if (currentDb < 70) {
      // 70dB未満は実質的にダメージなし（無限）として扱う
      return double.infinity;
    }
    // 計算式: T = 40 / (2 ^ ((L - 80) / 3))
    double exponent = (currentDb - baseDb) / exchangeRate;
    return baseHours / pow(2, exponent);
  }

  /// 2. 特定の音圧(dB)を特定の時間(秒)聴いた際の、耳の体力消費量(%)を計算する
  static double calculateConsumedDose(double dbLevel, int durationSeconds) {
    double allowedHours = calculateAllowedHours(dbLevel);
    if (allowedHours == double.infinity) return 0.0;

    // 許容時間を秒に変換
    double allowedSeconds = allowedHours * 3600;
    // 消費した割合(%)を返す
    return (durationSeconds / allowedSeconds) * 100;
  }

  /// 3. 複数のセッションデータから、正確な平均音圧(等価騒音レベル: Leq)を計算する
  /// セッションリストの要素はMap形式: {'db': 音圧, 'seconds': 聴取秒数}
  static double calculateLeq(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return 0.0;

    double totalSeconds = 0;
    double energySum = 0;

    for (var session in sessions) {
      double db = session['db'] as double;
      int seconds = session['seconds'] as int;

      totalSeconds += seconds;
      // 音圧をエネルギーに変換して時間に掛ける: t * 10^(L/10)
      energySum += seconds * pow(10, db / 10);
    }

    if (totalSeconds == 0) return 0.0;

    // エネルギーの平均をdBに戻す: 10 * log10(平均エネルギー)
    return 10 * (log(energySum / totalSeconds) / ln10);
  }
}