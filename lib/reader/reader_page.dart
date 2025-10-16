
import 'package:flutter/material.dart';
import '../services/cache_store.dart';
import 'horizontal_typesetter.dart';
import 'horizontal_page_painter.dart';

/// Reader page integrated with HorizontalTypesetter + HorizontalPagePainter
/// - True pagination using grid_layout (cols x rows) based on page size & text style
/// - Horizontal page turning; edge-swipe switches chapter
/// - Catalog, last-read per chapter, reading stats, appearance settings
class SutraReaderPage extends StatefulWidget {
  final dynamic dao;
  /// Chapters are records like: ({String chapId, String title})
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

class _SutraReaderPageState extends State<SutraReaderPage> with WidgetsBindingObserver {
  // chapter index
  late int _idx;

  // paging
  late PageController _pc;
  int _pageIndex = 0;
  List<TextRange> _pageRanges = <TextRange>[]; // computed by typesetter
  String _text = '';

  // layout
  Size _lastPageSize = Size.zero;
  EdgeInsets _pagePadding = const EdgeInsets.fromLTRB(20, 28, 20, 32);

  // preferences
  double _fontSize = 18;
  double _lineHeight = 1.6;
  int _themeMode = 0; // 0 system, 1 light, 2 dark
  Color _bgColor = const Color(0xFFFAF6EF);

  // stats
  int? _lastOpenTs;

  // caches
  final Map<String, List<TextRange>> _paginationCache = {}; // key: chapId|font|size|padding

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idx = widget.chapterIndex;
    _pc = PageController();
    _loadPrefs();
    _startSession();
    // Load current chapter immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChapter(_idx);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accumulateStats();
    _pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _accumulateStats();
    }
  }

  // ===== Preferences =====
  static const String _kPrefsKey = 'reader_prefs_v1';
  Future<void> _loadPrefs() async {
    final m = await CacheStore.readJson(_kPrefsKey) ?? <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _fontSize = (m['fontSize'] is num) ? (m['fontSize'] as num).toDouble() : _fontSize;
      _themeMode = (m['themeMode'] is num) ? (m['themeMode'] as num).toInt() : _themeMode;
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

  // ===== Stats =====
  static const String _kStatsKey = 'reader_stats_v1';
  Future<void> _startSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastOpenTs = now;
    final m = await CacheStore.readJson(_kStatsKey) ?? <String, dynamic>{'totalSeconds': 0};
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStatsKey, m);
  }

  Future<void> _accumulateStats() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastOpenTs == null) return;
    int addSec = ((now - _lastOpenTs!) / 1000).round();
    if (addSec < 0) addSec = 0;
    final m = await CacheStore.readJson(_kStatsKey) ?? <String, dynamic>{'totalSeconds': 0};
    m['totalSeconds'] = (m['totalSeconds'] ?? 0) + addSec;
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStatsKey, m);
    _lastOpenTs = now;
  }

  Future<int> _getTotalSeconds() async {
    final m = await CacheStore.readJson(_kStatsKey) ?? <String, dynamic>{'totalSeconds': 0};
    return (m['totalSeconds'] ?? 0) as int;
  }

  // ===== Last-read per chapter =====
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

  // ===== Data helpers =====
  String _chapIdOf(dynamic rec) {
    try { return (rec as dynamic).chapId as String; } catch (_) {}
    if (rec is Map && rec['chapId'] is String) return rec['chapId'] as String;
    return rec.toString();
  }
  String _titleOf(dynamic rec, int index) {
    try { final t = (rec as dynamic).title as String; if (t.isNotEmpty) return t; } catch (_) {}
    if (rec is Map && rec['title'] is String) return rec['title'] as String;
    return '第 ${index + 1} 章';
  }

  // ===== Chapter + pagination =====
  Future<void> _loadChapter(int index, {bool keepPage = false}) async {
    final chap = widget.fullChapters[index];
    final chapId = _chapIdOf(chap);

    String t = '';
    try {
      if (widget.dao != null && (widget.dao as dynamic).loadChapterText != null) {
        final fn = (widget.dao as dynamic).loadChapterText;
        t = await fn(chapId);
      }
    } catch (_) {}

    final int initial = keepPage ? _pageIndex : (await _loadLastPageFor(chapId)) ?? 0;

    if (!mounted) return;
    setState(() {
      _text = t;
      _pageRanges = <TextRange>[];
      _pageIndex = 0;
      _pc = PageController(initialPage: 0);
    });

    // After first layout we can paginate with concrete page size
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePaginationAndJump(initial);
    });
  }

  Future<void> _ensurePaginationAndJump(int initialPage) async {
    if (!mounted) return;
    final size = _lastPageSize;
    if (size == Size.zero) return; // Will try again on next build/layout

    final chap = widget.fullChapters[_idx];
    final chapId = _chapIdOf(chap);
    final cacheKey = '$chapId|${_fontSize.toStringAsFixed(1)}|${_lineHeight.toStringAsFixed(2)}|${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}|${_pagePadding.toString()}';

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
        final pages = ts.paginate(size); // List<HPageRange>
        ranges = pages.map((e) => TextRange(start: e.start, end: e.end)).toList();
      } catch (_) {
        // fallback: chunk by count so user still can read
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
    // save current position
    final curChapId = _chapIdOf(widget.fullChapters[_idx]);
    await _saveLastPageFor(curChapId, _pageIndex);
    setState(() => _idx = newIndex);
    await _loadChapter(_idx);
  }

  // ===== UI =====
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

            final bool noContent = _text.trim().isEmpty;
            if (noContent) {
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
    const threshold = 600; // px/s
    final bool atLastPage = _pageIndex >= _pageRanges.length - 1;
    final bool atFirstPage = _pageIndex <= 0;
    final bool hasPrev = _idx > 0;
    final bool hasNext = _idx < widget.fullChapters.length - 1;

    if (v < -threshold) {
      // right-to-left (next page) -> at last page, go next chapter
      if (atLastPage && hasNext) {
        await _openChapter(_idx + 1);
      }
    } else if (v > threshold) {
      // left-to-right (prev page) -> at first page, go prev chapter
      if (atFirstPage && hasPrev) {
        await _openChapter(_idx - 1);
      }
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

  // ===== Catalog =====
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

  // ===== Settings =====
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
                          final needRepaginate = localFont != _fontSize || localLine != _lineHeight;
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
