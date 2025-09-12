import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

Future<Database> initDb() async {
  // 1. 裝置上的資料庫路徑
  final databasesPath = await getDatabasesPath();
  final dbPath = p.join(databasesPath, 'load.db');

  // 2. 如果裝置上沒有，從 assets 複製一份
  final exists = await File(dbPath).exists();
  if (!exists) {
    print('資料庫不存在，從 assets 複製...');
    try {
      await Directory(p.dirname(dbPath)).create(recursive: true);
      final data = await rootBundle.load('assets/db/load.db');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(dbPath).writeAsBytes(bytes, flush: true);
    } catch (e) {
      print('複製 load.db 發生錯誤: $e');
      rethrow;
    }
  }

  // 3. 開啟並回傳 Database
  return openDatabase(dbPath);
}