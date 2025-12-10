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
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, file);

      return await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE punches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER,
              latitude REAL,
              longitude REAL,
              address TEXT
            )
          ''');
        },
      );
    } catch (e) {
      print("DB initialization error: $e");
      rethrow;
    }
  }

  Future<int> insertPunch(Punch punch) async {
    try {
      final db = await database;
      return await db.insert('punches', punch.toMap());
    } catch (e) {
      print("Insert punch error: $e");
      return -1;
    }
  }

  Future<Punch?> getLastPunch() async {
    try {
      final db = await database;
      final result = await db.query(
        'punches',
        orderBy: 'timestamp DESC',
        limit: 1,
      );
      if (result.isEmpty) return null;
      return Punch.fromMap(result.first);
    } catch (e) {
      print("Get last punch error: $e");
      return null;
    }
  }

  Future<List<Punch>> getPunchesSince(DateTime fromDate) async {
    try {
      final db = await database;
      final results = await db.query(
        'punches',
        where: 'timestamp >= ?',
        whereArgs: [fromDate.millisecondsSinceEpoch],
        orderBy: 'timestamp DESC',
      );
      return results.map((r) => Punch.fromMap(r)).toList();
    } catch (e) {
      print("Get punches since error: $e");
      return [];
    }
  }

  Future<List<Punch>> getPunchesForLast5Days() async {
    final fromDate = DateTime.now().subtract(const Duration(days: 5));
    return await getPunchesSince(fromDate);
  }

  Future<List<Punch>> getPunchesByDate(DateTime date) async {
    try {
      final db = await database;
      final start =
          DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
      final end = DateTime(date.year, date.month, date.day, 23, 59, 59)
          .millisecondsSinceEpoch;

      final results = await db.query(
        'punches',
        where: 'timestamp BETWEEN ? AND ?',
        whereArgs: [start, end],
        orderBy: 'timestamp ASC',
      );

      return results.map((r) => Punch.fromMap(r)).toList();
    } catch (e) {
      print("Get punches by date error: $e");
      return [];
    }
  }

  Future<int> deleteOldPunches(int days) async {
    try {
      final db = await database;
      final cutoff =
          DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
      return await db.delete(
        'punches',
        where: 'timestamp < ?',
        whereArgs: [cutoff],
      );
    } catch (e) {
      print("Delete old punches error: $e");
      return -1;
    }
  }
}
