import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../Models/punch_in_model.dart';

class DBHelper {
  static final DBHelper instance = DBHelper._init();
  DBHelper._init();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('punch.db');
    return _database!;
  }

  Future<Database> _initDB(String file) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, file);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
        CREATE TABLE punches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp INTEGER,          -- stored as epoch milliseconds
          latitude REAL,
          longitude REAL,
          address TEXT
        )
        ''');
      },
    );
  }

  // ---------------------------------------------------------
  // INSERT PUNCH
  // ---------------------------------------------------------
  Future<int> insertPunch(Punch punch) async {
    final db = await database;
    return await db.insert('punches', punch.toMap());
  }

  // ---------------------------------------------------------
  // GET LAST PUNCH (for preventing quick re-punch)
  // ---------------------------------------------------------
  Future<Punch?> getLastPunch() async {
    final db = await database;

    final result = await db.query(
      'punches',
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return Punch.fromMap(result.first);
  }

  // ---------------------------------------------------------
  // GET PUNCHES SINCE A DATE (generic use)
  // ---------------------------------------------------------
  Future<List<Punch>> getPunchesSince(DateTime fromDate) async {
    final db = await database;

    final results = await db.query(
      'punches',
      where: 'timestamp >= ?',
      whereArgs: [fromDate.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
    );

    return results.map((r) => Punch.fromMap(r)).toList();
  }

  // ---------------------------------------------------------
  // GET PUNCHES FOR LAST 5 DAYS
  // ---------------------------------------------------------
  Future<List<Punch>> getPunchesForLast5Days() async {
    final db = await database;

    final fromDate = DateTime.now().subtract(const Duration(days: 5));

    final results = await db.query(
      'punches',
      where: 'timestamp >= ?',
      whereArgs: [fromDate.millisecondsSinceEpoch],
      orderBy: 'timestamp DESC',
    );

    return results.map((r) => Punch.fromMap(r)).toList();
  }

  // ---------------------------------------------------------
  // GET PUNCHES BY SPECIFIC DATE
  // ---------------------------------------------------------
  Future<List<Punch>> getPunchesByDate(DateTime date) async {
    final db = await database;

    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch;
    final end = DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;

    final results = await db.query(
      'punches',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'timestamp ASC',
    );

    return results.map((r) => Punch.fromMap(r)).toList();
  }

  // OPTIONAL: delete old data
  Future<int> deleteOldPunches(int days) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .millisecondsSinceEpoch;

    return await db.delete(
      'punches',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}
