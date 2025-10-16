// lib/services/cache_store.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class CacheStore {
  static Future<Directory> _dir() async {
    final dir = await getApplicationDocumentsDirectory();
    final cache = Directory('${dir.path}/cache');
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache;
  }

  static String _safe(String key) {
    return key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static Future<Map<String, dynamic>?> readJson(String key) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/${_safe(key)}.json');
      if (!await file.exists()) return null;
      final s = await file.readAsString();
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJson(String key, Map<String, dynamic> data) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/${_safe(key)}.json');
      await file.writeAsString(jsonEncode(data));
    } catch (_) {
      // ignore
    }
  }
}
