// lib/services/dao_extensions.dart
import 'package:sqflite/sqflite.dart';
import 'dao.dart';

extension SutraDaoVolumes on SutraDao {
  Database _db() {
    final d = (this as dynamic);
    try { return d.db as Database; } catch (_) {}
    try { return d.database as Database; } catch (_) {}
    throw StateError('SutraDao 無法取得 Database，請確認 dao.dart 欄位名為 db 或 database');
  }

  Future<List<({String volId, String title, int ord})>> listVolumes() async {
    final rows = await _db().rawQuery('''
      SELECT vol_id AS volId, title, ord
      FROM volumes
      ORDER BY ord
    ''');
    return rows.map((r) => (
      volId: (r['volId'] ?? '').toString(),
      title: (r['title'] ?? '').toString(),
      ord: (r['ord'] as int?) ?? 0,
    )).toList();
  }

  Future<List<({String chapId, String title, String volId, int ord})>> listChaptersByVolume(String volId) async {
    final rows = await _db().rawQuery('''
      SELECT chap_id AS chapId, title, vol_id AS volId, ord
      FROM chapters
      WHERE vol_id = ?
      ORDER BY ord
    ''', [volId]);
    return rows.map((r) => (
      chapId: (r['chapId'] ?? '').toString(),
      title: (r['title'] ?? '').toString(),
      volId: (r['volId'] ?? '').toString(),
      ord: (r['ord'] as int?) ?? 0,
    )).toList();
  }

  /// 專為你上傳的 DB：paragraphs(para_id, chap_id, ord, text)
  Future<String> loadChapterText(String chapId) async {
    final rows = await _db().rawQuery('''
      SELECT text AS t
      FROM paragraphs
      WHERE chap_id = ?
      ORDER BY ord
    ''', [chapId]);
    final buf = StringBuffer();
    for (final r in rows) {
      final s = (r['t'] ?? '').toString();
      if (s.isEmpty) continue;
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(s);
    }
    return buf.toString();
  }
}
