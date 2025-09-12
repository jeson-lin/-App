// lib/services/dao.dart
import 'package:sqflite/sqflite.dart';

/// HomePage 需要的章節型別 (chapId, title, volId, ord)
typedef ChapterTuple = (String chapId, String title, String volId, int ord);

/// Android/iOS 使用 sqflite，切記不要用 sqflite_common_ffi
class SutraDao {
  final Database db;
  SutraDao(this.db);

  // -------------------- 章節清單 --------------------

  /// 優先嘗試既有 chapters 表；若沒有，就用 paragraphs 推回章節
  Future<List<ChapterTuple>> listChapters() async {
    try {
      final rows = await db.rawQuery('''
        SELECT id AS chapId, title, COALESCE(volume_id,'') AS volId, COALESCE(ord,0) AS ord
        FROM chapters
        ORDER BY volId, ord, title
      ''');
      if (rows.isNotEmpty) {
        return rows.map(_rowToChapter).toList();
      }
    } catch (_) {
      // 沒有 chapters 表或欄位不符 → 走 smart
    }
    return listChaptersSmart();
  }

  /// 直接從 paragraphs 推回章節清單（最貼近你的 DB）
  ///
  /// - 章節 id：chap_id
  /// - 章節標題：取該章節的第一行 text 當作標題（或 MIN(ord) 的那行）
  /// - 卷別：暫無，給空字串
  /// - ord：MIN(ord)
  Future<List<ChapterTuple>> listChaptersSmart() async {
    final rows = await db.rawQuery('''
      SELECT
        p1.chap_id AS chapId,
        (
          SELECT p2.text
          FROM paragraphs p2
          WHERE p2.chap_id = p1.chap_id
          ORDER BY COALESCE(p2.ord, 0), p2.para_id
          LIMIT 1
        ) AS title,
        '' AS volId,
        MIN(COALESCE(p1.ord, 0)) AS ord
      FROM paragraphs p1
      GROUP BY p1.chap_id
      ORDER BY MIN(COALESCE(p1.ord, 0)), p1.chap_id
    ''');

    return rows.map((r) => (
      (r['chapId'] ?? '').toString(),
      (r['title'] ?? '').toString(),
      (r['volId'] ?? '').toString(),
      (r['ord'] as int?) ?? 0,
    )).toList();
  }

  // -------------------- 段落（經文內容）--------------------

  /// 依章節 id 載入經文段落（你 DB 的正確表與欄位）
  Future<List<String>> loadParagraphs(String chapId) async {
    final rows = await db.rawQuery('''
      SELECT text
      FROM paragraphs
      WHERE chap_id = ?
      ORDER BY COALESCE(ord, 0), para_id
    ''', [chapId]);

    return rows.map((r) => (r['text'] ?? '').toString()).toList();
  }

  /// 後備：同上（給 reader_page 既有呼叫）
  Future<List<String>> loadParagraphsSmart(String chapId) async {
    return loadParagraphs(chapId);
  }

  /// 模糊：同上（給 reader_page 既有呼叫）
  Future<List<String>> loadParagraphsFuzzy({
    required String chapId,
    required String title,
  }) async {
    return loadParagraphs(chapId);
  }

  // -------------------- 小工具 --------------------

  ChapterTuple _rowToChapter(Map<String, Object?> r) => (
    (r['chapId'] ?? '').toString(),
    (r['title'] ?? '').toString(),
    (r['volId'] ?? '').toString(),
    (r['ord'] as int?) ?? 0,
  );

  /// 偵錯用：列出所有資料表與建表語法
  Future<void> debugPrintTables() async {
    final rows = await db.rawQuery(
      'SELECT name, sql FROM sqlite_master WHERE type="table" AND name NOT LIKE "sqlite_%"'
    );
    // ignore: avoid_print
    print('TABLES: $rows');
  }
}
