import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../services/cache_store.dart';
import 'horizontal_typesetter.dart';
import 'horizontal_page_painter.dart';

/// 橫版閱讀頁（整合：HorizontalTypesetter + HorizontalPagePainter）
/// 文字來源：SQLite `paragraphs`（chap_id, ord, text）→ 依 ord 串接成章文
class SutraReaderPage extends StatefulWidget {
  /// dao 可選：若沒有 .db，會自動嘗試開啟 assets 的 load.db
  final dynamic dao;
  /// 章清單：record 或 map，至少要有 chapId, title
  final List<dynamic> fullChapters;
  final int chapterIndex;

  const SutraReaderPage({
    Key? key,
    required this.dao,
    required this.fullChapters,
    required this.chapterIndex,
  }) : super(key: key);

  @override
  State<SutraReaderPage> createState() => _SutraReaderPageState();
}

class _SutraReaderPageState extends State<SutraReaderPage>
    with WidgetsBindingObserver {
  // 章索引
  late int _idx;

  // 分頁
  late PageController _pc;
  int _pageIndex = 0;
  List<TextRange> _pageRanges = <TextRange>[];
  String _text = '';

  // 版面 & 外觀
  Size _lastPageSize = Size.zero;
  EdgeInsets _pagePadding = const EdgeInsets.fromLTRB(20, 28, 20, 32);
  double _fontSize = 18;
  double _lineHeight = 1.6;
  int _themeMode = 0;
  Color _bgColor = const Color(0xFFFAF6EF);

  // 統計
  int? _lastOpenTs;

  // 分頁快取
  final Map<String, List<TextRange>> _paginationCache = {};

  // DB（若 dao 未提供時使用）
  Database? _db;

  // === 診斷工具 ===
  bool _debugPlainText = false; // 直接用 Text 呈現當頁內容（繞過 painter）
  String _debugPeek = '';       // SnackBar 顯示的檢查訊息

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idx = widget.chapterIndex;
    _pc = PageController();
    _loadPrefs();
    _startSession();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureDatabase(); // 先確保能開到 DB
      _loadChapter(_idx);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accumulateStats();
    _pc.dispose();
    _db?.close();
    super.dispose();
  }

  // ===== DB 開啟（若 dao 沒有 db，就從 assets 複製 load.db 再開啟） =====
  Future<Database> _getDatabase() async {
    try {
      final d = (widget.dao as dynamic).db;
      if (d is Database) return d;
    } catch (_) {}
    if (_db != null) return _db!;
    return await _ensureDatabase();
  }

  Future<Database> _ensureDatabase() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'load.db');
    if (!await File(dbPath).exists()) {
      // 嘗試從多個常見的資源路徑拷貝
      final candidates = <String>[
        'assets/db/load.db',
        'assets/load.db',
        'assets/database/load.db',
        'load.db',
      ];
      ByteData? data;
      for (final asset in candidates) {
        try {
          data = await rootBundle.load(asset);
          debugPrint('[reader] copied asset from $asset');
          break;
        } catch (_) {}
      }
      if (data == null) {
        debugPrint('[reader] load.db asset not found in candidates, creating empty file');
        await File(dbPath).create(recursive: true);
      } else {
        final bytes = data.buffer.asUint8List();
        await File(dbPath).writeAsBytes(bytes, flush: true);
      }
    }
    _db = await openDatabase(dbPath, readOnly: true);
    return _db!;
  }

  // ========= 偏好 =========
  static const String _kPrefsKey = 'reader_prefs_v1';

  Future<void> _loadPrefs() async {
    final m = await CacheStore.readJson(_kPrefsKey) ?? <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _fontSize =
          (m['fontSize'] is num) ? (m['fontSize'] as num).toDouble() : _fontSize;
      _themeMode =
          (m['themeMode'] is num) ? (m['themeMode'] as num).toInt() : _themeMode;
      if (m['bgColor'] is int) _bgColor = Color(m['bgColor'] as int);
    });
  }

  Future<void> _savePrefs() async {
    await CacheStore.writeJson(_kPrefsKey, {
      'fontSize': _fontSize,
      'themeMode': _themeMode,
      'bgColor': _bgColor.value,
    });
  }

  // ========= 統計 =========
  static const String _kStatsKey = 'reader_stats_v1';

  Future<void> _startSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastOpenTs = now;
    final m = await CacheStore.readJson(_kStatsKey) ??
        <String, dynamic>{'totalSeconds': 0};
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStatsKey, m);
  }

  Future<void> _accumulateStats() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastOpenTs == null) return;
    int addSec = ((now - _lastOpenTs!) / 1000).round();
    if (addSec < 0) addSec = 0;
    final m = await CacheStore.readJson(_kStatsKey) ??
        <String, dynamic>{'totalSeconds': 0};
    m['totalSeconds'] = (m['totalSeconds'] ?? 0) + addSec;
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStatsKey, m);
    _lastOpenTs = now;
  }

  Future<int> _getTotalSeconds() async {
    final m = await CacheStore.readJson(_kStatsKey) ??
        <String, dynamic>{'totalSeconds': 0};
    return (m['totalSeconds'] ?? 0) as int;
  }

  // ========= 續讀 =========
  String _lastPosKeyFor(String chapId) => 'last_pos_v1|chap=$chapId';

  Future<int?> _loadLastPageFor(String chapId) async {
    final m = await CacheStore.readJson(_lastPosKeyFor(chapId));
    if (m == null) return null;
    final p = m['pageIndex'];
    if (p is int) return p;
    if (p is num) return p.toInt();
    return null;
  }

  Future<void> _saveLastPageFor(String chapId, int pageIndex) async {
    await CacheStore.writeJson(_lastPosKeyFor(chapId), {'pageIndex': pageIndex});
  }

  // ========= 輔助 =========
  String _chapIdOf(dynamic rec) {
    try {
      return (rec as dynamic).chapId as String;
    } catch (_) {}
    if (rec is Map && rec['chapId'] is String) return rec['chapId'] as String;
    return rec.toString();
  }

  String _titleOf(dynamic rec, int index) {
    try {
      final t = (rec as dynamic).title as String;
      if (t.isNotEmpty) return t;
    } catch (_) {}
    if (rec is Map && rec['title'] is String) return rec['title'] as String;
    return '第 ${index + 1} 章';
  }

  /// 直接從 paragraphs 組章文（精準對你 DB）
  Future<String> _readParagraphsText(String chapId) async {
    try {
      final db = await _getDatabase();
      final rows = await db.rawQuery(
        'SELECT text FROM paragraphs WHERE chap_id = ? ORDER BY ord ASC',
        [chapId],
      );
      if (rows.isEmpty) return '';
      final buf = StringBuffer();
      for (final r in rows) {
        final line = (r['text'] ?? '').toString();
        if (line.isNotEmpty) buf.writeln(line);
      }
      return buf.toString().trimRight();
    } catch (e) {
      debugPrint('[reader] read paragraphs error: $e');
      return '';
    }
  }

  // ========= 章載入 + 分頁 =========
  Future<void> _loadChapter(int index, {bool keepPage = false}) async {
    final chap = widget.fullChapters[index];
    final String chapId = _chapIdOf(chap);

    // 先用 paragraphs 正規路徑
    String text = await _readParagraphsText(chapId);

    // 備援（如未來換資料源）：呼叫 dao.loadChapterText / getChapterText
    if (text.isEmpty) {
      try {
        final f = (widget.dao as dynamic).loadChapterText;
        if (f is Function) {
          text = await f(chapId);
        }
      } catch (_) {}
      if (text.isEmpty) {
        try {
          final f = (widget.dao as dynamic).getChapterText;
          if (f is Function) {
            final r = await f(chapId);
            if (r is String) text = r;
          }
        } catch (_) {}
      }
    }

    final int initial =
        keepPage ? _pageIndex : (await _loadLastPageFor(chapId)) ?? 0;

    if (!mounted) return;
    setState(() {
      _text = text;
      _pageRanges = <TextRange>[];
      _pageIndex = 0;
      _pc = PageController(initialPage: 0);
    });

    if (_text.trim().isEmpty && mounted) {
      final t = _titleOf(chap, index);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('讀不到內文：$t（$chapId）。請確認 load.db 是否放在 assets。')),
      );
    }

    // 有實際尺寸後做真實排版
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePaginationAndJump(initial);
    });
  }

  Future<void> _ensurePaginationAndJump(int initialPage) async {
    if (!mounted) return;
    final size = _lastPageSize;
    if (size == Size.zero) return;

    final chap = widget.fullChapters[_idx];
    final chapId = _chapIdOf(chap);
    final cacheKey =
        '$chapId|${_fontSize.toStringAsFixed(1)}|${_lineHeight.toStringAsFixed(2)}|'
        '${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}|${_pagePadding.toString()}';

    if (_paginationCache.containsKey(cacheKey)) {
      setState(() {
        _pageRanges = _paginationCache[cacheKey]!;
        _pageIndex = initialPage.clamp(0, _pageRanges.isEmpty ? 0 : _pageRanges.length - 1);
        _pc = PageController(initialPage: _pageIndex);
      });
      return;
    }

    List<TextRange> ranges = <TextRange>[];
    if (_text.trim().isNotEmpty) {
      try {
        final ts = HorizontalTypesetter(
          text: _text,
          style: TextStyle(fontSize: _fontSize, height: _lineHeight),
          padding: _pagePadding,
        );
        final pages = ts.paginate(size);
        ranges = pages.map((e) => TextRange(start: e.start, end: e.end)).toList();
      } catch (e) {
        ranges = _fallbackPaginate(_text, _fontSize);
      }
    }

    if (!mounted) return;
    setState(() {
      _pageRanges = ranges;
      _paginationCache[cacheKey] = ranges;
      _pageIndex = initialPage.clamp(0, _pageRanges.isEmpty ? 0 : _pageRanges.length - 1);
      _pc = PageController(initialPage: _pageIndex);
    });
  }

  List<TextRange> _fallbackPaginate(String text, double fontSize) {
    final List<TextRange> pages = [];
    if (text.isEmpty) return pages;
    final int base = 1000;
    final double scale = 18.0 / (fontSize <= 0 ? 18.0 : fontSize);
    final int chunk = (base * scale).clamp(400, 1600).toInt();
    int i = 0;
    while (i < text.length) {
      final end = (i + chunk < text.length) ? i + chunk : text.length;
      pages.add(TextRange(start: i, end: end));
      i = end;
    }
    return pages;
  }

  Future<void> _openChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    final curChapId = _chapIdOf(widget.fullChapters[_idx]);
    await _saveLastPageFor(curChapId, _pageIndex);
    setState(() => _idx = newIndex);
    await _loadChapter(_idx);
  }

  // ========= UI =========
  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme(context);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text('章節 ${_idx + 1}（${_pageIndex + 1}/${_pageRanges.isEmpty ? 1 : _pageRanges.length}）'),
          actions: [
            IconButton(
              tooltip: '目錄',
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: _showCatalog,
            ),
            IconButton(
              tooltip: '閱讀統計',
              icon: const Icon(Icons.timer_outlined),
              onPressed: () async {
                await _accumulateStats();
                final sec = await _getTotalSeconds();
                if (!mounted) return;
                final h = sec ~/ 3600;
                final m = (sec % 3600) ~/ 60;
                final s = sec % 60;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('累計閱讀：${h}h ${m}m ${s}s')),
                );
              },
            ),
            IconButton(
              tooltip: '外觀設定',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _showSettingsSheet,
            ),
            // === 診斷：切換純文字顯示 ===
            IconButton(
              tooltip: _debugPlainText ? '關閉文字檢視（回到排版器）' : '開啟文字檢視（繞過排版器）',
              icon: const Icon(Icons.text_fields),
              onPressed: () {
                setState(() => _debugPlainText = !_debugPlainText);
              },
            ),
            // === 診斷：顯示內容資訊 ===
            IconButton(
              tooltip: '檢查目前章節內容',
              icon: const Icon(Icons.search),
              onPressed: () async {
                final chapId = _chapIdOf(widget.fullChapters[_idx]);
                try {
                  final db = await _getDatabase();
                  final rows = await db.rawQuery(
                    'SELECT COUNT(*) AS c FROM paragraphs WHERE chap_id = ?',
                    [chapId],
                  );
                  int c = 0;
                  final raw = rows.first['c'];
                  if (raw is int) c = raw;
                  if (raw is num) c = raw.toInt();
                  final peek = _text.length > 50 ? _text.substring(0, 50) : _text;
                  _debugPeek = '章:$chapId 段落:$c 文字長度:${_text.length} 前50: $peek';
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_debugPeek)),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('檢查失敗：$e')),
                  );
                }
              },
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            if (size != _lastPageSize) {
              _lastPageSize = size;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _ensurePaginationAndJump(_pageIndex);
              });
            }

            if (_text.trim().isEmpty) {
              return _buildEmptyContent();
            }
            if (_pageRanges.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return GestureDetector(
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: PageView.builder(
                key: ValueKey<int>(_idx),
                controller: _pc,
                scrollDirection: Axis.horizontal,
                onPageChanged: (i) {
                  setState(() => _pageIndex = i);
                  final chapId = _chapIdOf(widget.fullChapters[_idx]);
                  _saveLastPageFor(chapId, i);
                  _accumulateStats();
                },
                itemCount: _pageRanges.length,
                itemBuilder: (c, i) {
                  final r = _pageRanges[i];

                  // 診斷：改用普通 Text 呈現當頁內容（繞過 painter）
                  if (_debugPlainText) {
                    final pageText = _text.substring(r.start, r.end);
                    return Container(
                      color: _bgColor,
                      padding: _pagePadding,
                      alignment: Alignment.topLeft,
                      child: SingleChildScrollView(
                        child: Text(
                          pageText,
                          style: TextStyle(fontSize: _fontSize, height: _lineHeight),
                        ),
                      ),
                    );
                  }

                  // 正常：用你的 painter 繪製
                  return CustomPaint(
                    painter: HorizontalPagePainter(
                      text: _text,
                      range: r,
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                      ),
                      padding: _pagePadding,
                      columnGap: 0,
                      textColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black87,
                    ),
                    child: Container(color: _bgColor),
                  );
                },
              ),
            );
          },
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  void _onHorizontalDragEnd(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    const threshold = 600;
    final bool atLastPage = _pageIndex >= _pageRanges.length - 1;
    final bool atFirstPage = _pageIndex <= 0;
    final bool hasPrev = _idx > 0;
    final bool hasNext = _idx < widget.fullChapters.length - 1;

    if (v < -threshold) {
      if (atLastPage && hasNext) await _openChapter(_idx + 1);
    } else if (v > threshold) {
      if (atFirstPage && hasPrev) await _openChapter(_idx - 1);
    }
  }

  Widget _buildEmptyContent() {
    final t = _titleOf(widget.fullChapters[_idx], _idx);
    final id = _chapIdOf(widget.fullChapters[_idx]);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 48),
            const SizedBox(height: 12),
            Text('本章沒有可顯示的內容', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('章：$t（$id）', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新載入'),
                  onPressed: () => _loadChapter(_idx, keepPage: true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.menu_open),
                  label: const Text('開啟目錄'),
                  onPressed: _showCatalog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _resolveTheme(BuildContext context) {
    switch (_themeMode) {
      case 1: return Theme.of(context).copyWith(brightness: Brightness.light);
      case 2: return Theme.of(context).copyWith(brightness: Brightness.dark);
      default: return Theme.of(context);
    }
  }

  void _showCatalog() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: ListView.separated(
            itemCount: widget.fullChapters.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final ch = widget.fullChapters[i];
              final title = _titleOf(ch, i);
              return ListTile(
                leading: Text('${i + 1}'),
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: i == _idx ? const Icon(Icons.check) : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openChapter(i);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        double localFont = _fontSize;
        int localMode = _themeMode;
        Color localBg = _bgColor;
        double localLine = _lineHeight;
        return StatefulBuilder(
          builder: (c, setSheet) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外觀設定', style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('字體大小'),
                      Expanded(
                        child: Slider(
                          value: localFont,
                          min: 12,
                          max: 28,
                          divisions: 16,
                          label: '${localFont.toStringAsFixed(0)}',
                          onChanged: (v) => setSheet(() => localFont = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('行高'),
                      Expanded(
                        child: Slider(
                          value: localLine,
                          min: 1.2,
                          max: 2.0,
                          divisions: 8,
                          label: localLine.toStringAsFixed(1),
                          onChanged: (v) => setSheet(() => localLine = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('主題'),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('跟隨系統'),
                        selected: localMode == 0,
                        onSelected: (_) => setSheet(() => localMode = 0),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('日間'),
                        selected: localMode == 1,
                        onSelected: (_) => setSheet(() => localMode = 1),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('夜間'),
                        selected: localMode == 2,
                        onSelected: (_) => setSheet(() => localMode = 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('背景色'),
                      const SizedBox(width: 12),
                      for (final c0 in <Color>[
                        const Color(0xFFFAF6EF),
                        Colors.white,
                        const Color(0xFF121212),
                        const Color(0xFFFFF8E1),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setSheet(() => localBg = c0),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: c0,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black12),
                              ),
                              child: localBg.value == c0.value
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(c).pop(),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(c).pop();
                          final needRepaginate = localFont != _fontSize ||
                              localLine != _lineHeight;
                          setState(() {
                            _fontSize = localFont;
                            _themeMode = localMode;
                            _bgColor = localBg;
                            _lineHeight = localLine;
                          });
                          _savePrefs();
                          if (needRepaginate) {
                            _paginationCache.clear();
                            _ensurePaginationAndJump(_pageIndex);
                          }
                        },
                        child: const Text('套用'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final total = _pageRanges.isEmpty ? 1 : _pageRanges.length;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _pageIndex > 0
                    ? () => _pc.previousPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
              Expanded(
                child: total <= 1
                    ? const SizedBox.shrink()
                    : Slider(
                        value: (_pageIndex + 1).toDouble(),
                        min: 1,
                        max: total.toDouble(),
                        label: '${_pageIndex + 1}/$total',
                        onChanged: (v) {
                          final target = v.round() - 1;
                          if (target != _pageIndex) {
                            _pc.jumpToPage(target);
                            setState(() => _pageIndex = target);
                            final chapId = _chapIdOf(widget.fullChapters[_idx]);
                            _saveLastPageFor(chapId, target);
                          }
                        },
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _pageIndex < total - 1
                    ? () => _pc.nextPage(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                        )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
