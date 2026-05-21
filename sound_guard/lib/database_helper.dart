import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('soundguard.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 日々のリスニングデータを記録するテーブル（device_idを除外した安定版スキーマ）
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        db_level REAL NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT NOT NULL,
        consumed_dose REAL NOT NULL
      )
    ''');

    // デバイスごとのキャリブレーション（基準値）を記憶するテーブル
    await db.execute('''
      CREATE TABLE calibrations (
        device_id TEXT PRIMARY KEY,
        baseline_db REAL NOT NULL
      )
    ''');
  }

  // ==========================================
  // セッションデータ（リスニング履歴）の操作
  // ==========================================

  // 1秒ごとのデータを保存
  Future<int> insertSession(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('sessions', row);
  }

  // 今日のデータを取得（メイン画面の計算用）
  Future<List<Map<String, dynamic>>> getTodaySessions() async {
    final db = await instance.database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    
    return await db.query(
      'sessions',
      where: 'start_time >= ?',
      whereArgs: [startOfDay],
    );
  }

  // 過去7日間のデータを取得（アナリティクス画面のグラフ用）
  Future<List<Map<String, dynamic>>> getPastSevenDaysSessions() async {
    final db = await instance.database;
    final now = DateTime.now();
    // 6日前の0時0分0秒を起点とする
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).toIso8601String();

    return await db.query(
      'sessions',
      where: 'start_time >= ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  // 7日より前の古いデータを自動削除して容量を節約
  Future<int> deleteOldSessions() async {
    final db = await instance.database;
    final now = DateTime.now();
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)).toIso8601String();

    return await db.delete(
      'sessions',
      where: 'start_time < ?',
      whereArgs: [sevenDaysAgo],
    );
  }

  // ==========================================
  // キャリブレーションデータ（デバイス設定）の操作
  // ==========================================

  // 測定した基準値を保存（すでに存在する場合は上書き）
  Future<int> saveCalibration(String deviceId, double baselineDb) async {
    final db = await instance.database;
    return await db.insert(
      'calibrations',
      {'device_id': deviceId, 'baseline_db': baselineDb},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // デバイス接続時に基準値を読み込む
  Future<double?> getCalibration(String deviceId) async {
    final db = await instance.database;
    final maps = await db.query(
      'calibrations',
      columns: ['baseline_db'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );

    if (maps.isNotEmpty) {
      return maps.first['baseline_db'] as double;
    } else {
      return null; // 未設定の場合はnullを返す
    }
  }

  // ==========================================
  // システム操作
  // ==========================================

  // すべてのデータを完全に初期化（リセットボタン用）
  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('sessions');
    await db.delete('calibrations');
  }
}