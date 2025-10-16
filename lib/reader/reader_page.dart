
import 'package:flutter/material.dart';
import '../services/cache_store.dart';

/// Reader with:
/// - vertical paging within a chapter
/// - horizontal edge swipe to switch chapter (L->R next, R->L prev)
/// - catalog (目錄) to jump to any chapter (and grouped by volume if info exists)
/// - preferences (font size, theme, bg)
/// - last-read page per chapter
/// - reading time accumulation
class SutraReaderPage extends StatefulWidget {
  final dynamic dao;
  final List<dynamic> fullChapters;  // may be across volumes already
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
  List<TextRange> _pages = <TextRange>[];
  String _text = '';
  int _pageIndex = 0;

  // counters
  int _volPageIndex = 0;
  int _volTotalPages = 0;
  int _globalPageIndex = 0;
  int _globalTotalPages = 0;

  // preferences
  double _fontSize = 18;
  int _themeMode = 0; // 0 system, 1 light, 2 dark
  Color _bgColor = const Color(0xFFFAF6EF);

  // stats
  int? _lastOpenTs; // ms

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idx = widget.chapterIndex;
    _pc = PageController();
    _loadPrefs();
    _startSession();
    _loadTextFor(_idx);
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
  String _lastPosKeyFor(dynamic chapId) => 'last_pos_v1|chap=$chapId';

  Future<int?> _loadLastPageFor(dynamic chapId) async {
    final m = await CacheStore.readJson(_lastPosKeyFor(chapId));
    if (m == null) return null;
    final p = m['pageIndex'];
    if (p is int) return p;
    if (p is num) return p.toInt();
    return null;
  }

  Future<void> _saveLastPageFor(dynamic chapId, int pageIndex) async {
    await CacheStore.writeJson(_lastPosKeyFor(chapId), {'pageIndex': pageIndex});
  }

  // ===== Chapter load & paginate =====
  Future<void> _loadTextFor(int index) async {
    final chap = widget.fullChapters[index];
    final chapId = _getField(chap, const ['chapId', 'id', 'chapterId']);
    String t = '';
    try {
      if (widget.dao != null && widget.dao.loadChapterText != null) {
        t = await widget.dao.loadChapterText(chapId);
      }
    } catch (_) {}
    int initialPage = 0;
    try {
      final last = await _loadLastPageFor(chapId);
      if (last != null) initialPage = last;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _text = t;
      _paginate();
      _pageIndex = (initialPage >= 0 && initialPage < _pages.length) ? initialPage : 0;
      _pc = PageController(initialPage: _pageIndex);
      _volPageIndex = _pageIndex;
      _volTotalPages = _pages.length;
      _globalPageIndex = _volPageIndex;
      _globalTotalPages = _volTotalPages;
    });
  }

  dynamic _getField(dynamic obj, List<String> candidates) {
    // Map
    if (obj is Map) {
      for (final k in candidates) {
        if (obj.containsKey(k)) return obj[k];
      }
    }
    // toJson
    try {
      final v = (obj as dynamic).toJson();
      if (v is Map) {
        for (final k in candidates) {
          if (v.containsKey(k)) return v[k];
        }
      }
    } catch (_) {}
    // direct common getter
    try { return (obj as dynamic).chapId; } catch (_) {}
    return null;
  }

  String _chapterTitle(dynamic chap, int idx) {
    for (final name in const ['title', 'chapterTitle', 'name']) {
      try {
        if (chap is Map && chap[name] is String) return chap[name] as String;
        final v = (chap as dynamic).toJson();
        if (v is Map && v[name] is String) return v[name] as String;
      } catch (_) {
        try {
          final v2 = (chap as dynamic).title as String;
          if (v2.isNotEmpty) return v2;
        } catch (_) {}
      }
    }
    return '第 ${idx + 1} 章';
  }

  String? _volumeId(dynamic chap) {
    for (final name in const ['volId', 'volumeId', 'vol_id']) {
      try {
        if (chap is Map && chap[name] != null) return chap[name].toString();
        final v = (chap as dynamic).toJson();
        if (v is Map && v[name] != null) return v[name].toString();
      } catch (_) {
        try {
          final v2 = (chap as dynamic).volId;
          if (v2 != null) return v2.toString();
        } catch (_) {}
      }
    }
    return null;
  }

  void _paginate() {
    _pages.clear();
    if (_text.isEmpty) {
      _pages.add(const TextRange(start: 0, end: 0));
      return;
    }
    final int baseChunk = 1000;
    final double scale = 18.0 / (_fontSize <= 0 ? 18.0 : _fontSize);
    final int chunk = (baseChunk * scale).clamp(400, 1600).toInt();

    int i = 0;
    while (i < _text.length) {
      final end = (i + chunk < _text.length) ? i + chunk : _text.length;
      _pages.add(TextRange(start: i, end: end));
      i = end;
    }
    if (_pages.isEmpty) {
      _pages.add(const TextRange(start: 0, end: 0));
    }
  }

  Future<void> _updateVolumeIndex() async {
    _volPageIndex = _pageIndex;
    _volTotalPages = _pages.length;
    final chapId = _getField(widget.fullChapters[_idx], const ['chapId', 'id', 'chapterId']);
    await _saveLastPageFor(chapId, _pageIndex);
  }

  Future<void> _updateGlobalIndex() async {
    _globalPageIndex = _volPageIndex;
    _globalTotalPages = _volTotalPages;
  }

  // ===== Chapter switching =====
  Future<void> _openChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    await _updateVolumeIndex(); // persist current before switching
    setState(() => _idx = newIndex);
    await _loadTextFor(_idx);
  }

  void _onHorizontalSwipe(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    const threshold = 600; // px/s
    final bool atLastPage = _pageIndex >= _pages.length - 1;
    final bool atFirstPage = _pageIndex <= 0;
    final bool hasPrev = _idx > 0;
    final bool hasNext = _idx < widget.fullChapters.length - 1;

    if (v > threshold) {
      // Left -> Right (下一章)
      if (atLastPage && hasNext) {
        await _openChapter(_idx + 1);
      }
    } else if (v < -threshold) {
      // Right -> Left (上一章)
      if (atFirstPage && hasPrev) {
        await _openChapter(_idx - 1);
      }
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme(context);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text('章節 ${_idx + 1}（${_pageIndex + 1}/${_pages.length}）'),
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
        body: Container(
          color: _bgColor,
          child: _pages.isEmpty
              ? const Center(child: Text('沒有內容'))
              : GestureDetector(
                  onHorizontalDragEnd: _onHorizontalSwipe, // 左右章切換
                  child: PageView.builder(
                    key: ValueKey<int>(_idx),
                    controller: _pc,
                    scrollDirection: Axis.vertical, // 章內上下翻頁
                    onPageChanged: (i) => setState(() {
                      _pageIndex = i;
                      _updateVolumeIndex();
                      _updateGlobalIndex();
                      _accumulateStats();
                    }),
                    itemCount: _pages.length,
                    itemBuilder: (c, i) {
                      final pr = _pages[i];
                      final pageText = _text.substring(pr.start, pr.end);
                      return _ReaderPage(text: pageText, fontSize: _fontSize, bgColor: _bgColor);
                    },
                  ),
                ),
        ),
        bottomNavigationBar: _buildBottomBar(),
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

  // ===== Catalog (目錄) =====
  void _showCatalog() {
    final Map<String, List<int>> groups = <String, List<int>>{};
    for (int i = 0; i < widget.fullChapters.length; i++) {
      final chap = widget.fullChapters[i];
      final vol = _volumeId(chap) ?? '未分卷';
      groups.putIfAbsent(vol, () => <int>[]).add(i);
    }
    final bool hasVolumes = groups.keys.length > 1 || (groups.keys.length == 1 && groups.keys.first != '未分卷');

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        if (!hasVolumes) {
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: ListView.separated(
              itemCount: widget.fullChapters.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final chap = widget.fullChapters[i];
                final title = _chapterTitle(chap, i);
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
        } else {
          final vols = groups.keys.toList();
          int volIndex = 0;
          final curVol = _volumeId(widget.fullChapters[_idx]);
          if (curVol != null) {
            volIndex = vols.indexOf(curVol);
            if (volIndex < 0) volIndex = 0;
          }
          return StatefulBuilder(
            builder: (ctx, setSheet) {
              final chapIdxList = groups[vols[volIndex]] ?? <int>[];
              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: ListView.separated(
                        itemCount: vols.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final v = vols[i];
                          return ListTile(
                            title: Text(v),
                            selected: i == volIndex,
                            onTap: () => setSheet(() => volIndex = i),
                          );
                        },
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: chapIdxList.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, k) {
                          final i = chapIdxList[k];
                          final chap = widget.fullChapters[i];
                          final title = _chapterTitle(chap, i);
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
                    ),
                  ],
                ),
              );
            },
          );
        }
      },
    );
  }

  Widget _buildBottomBar() {
    final total = _pages.length;
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
                child: Slider(
                  value: (_pageIndex + 1).toDouble(),
                  min: 1,
                  max: total == 0 ? 1 : total.toDouble(),
                  label: '${_pageIndex + 1}/$total',
                  onChanged: (v) {
                    final target = v.round() - 1;
                    if (target != _pageIndex) {
                      _pc.jumpToPage(target);
                      setState(() {
                        _pageIndex = target;
                        _updateVolumeIndex();
                        _updateGlobalIndex();
                        _accumulateStats();
                      });
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
class _ReaderPage extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color bgColor;
  const _ReaderPage({required this.text, required this.fontSize, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Colors.black87;
    return SelectionArea(
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        alignment: Alignment.topLeft,
        child: Text(
          text,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                fontSize: fontSize,
                color: textColor,
              ),
        ),
      ),
    );
  }
}
