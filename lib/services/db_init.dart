// lib/services/db_init.dart
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'dao.dart';

class DbInit {
  static const String assetDbPath = 'assets/db/load.db';
  static const String runtimeDbName = 'load.db';

  static Future<String> ensureDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, runtimeDbName);

    if (!await File(dbPath).exists()) {
      await Directory(p.dirname(dbPath)).create(recursive: true);
      final data = await rootBundle.load(assetDbPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    }
    return dbPath;
  }

  static Future<SutraDao> openDao(String dbPath) async {
    final db = await openDatabase(dbPath); // ← sqflite
    return SutraDao(db);                   // ← 具體類別可直接建構
  }
}
