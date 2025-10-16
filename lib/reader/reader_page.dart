
import 'package:flutter/material.dart';
import '../services/cache_store.dart';

class SutraReaderPage extends StatefulWidget {
  final dynamic dao;
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
  late int _idx;
  late PageController _pc;
  List<TextRange> _pages = <TextRange>[];
  String _text = '';
  int _pageIndex = 0;

  int _volPageIndex = 0;
  int _volTotalPages = 0;
  int _globalPageIndex = 0;
  int _globalTotalPages = 0;

  double _fontSize = 18;
  int _themeMode = 0;
  Color _bgColor = const Color(0xFFFAF6EF);

  int? _lastOpenTs;

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

  // Robust DAO text loader
  Future<String> _loadTextFromDao(dynamic chapId) async {
    final methodCandidates = <String>[
      'loadChapterText', 'getChapterText', 'loadText', 'fetchChapterText',
      'fetchText', 'readChapterText', 'readText', 'chapterText',
    ];
    for (final name in methodCandidates) {
      try {
        final fn = (widget.dao as dynamic)
            .toJson; // force noSuchMethod warning avoidance
      } catch (_) {}
      try {
        final dynamic possible = (widget.dao as dynamic).__noSuchMethod__;
      } catch (_) {}
      try {
        final dynamic f = (widget.dao as dynamic).noSuchMethod;
      } catch (_) {}
      try {
        final dynamic call = (widget.dao as dynamic).toString;
      } catch (_) {}
      try {
        final dynamic candidate = (widget.dao as dynamic);
        final dynamic func = candidate.__proto__;
      } catch (_) {}
      try {
        final dynamic fn = (widget.dao as dynamic).__getattribute__;
      } catch (_) {}
      try {
        final dynamic value = (widget.dao as dynamic);
        final dynamic maybe = (value as dynamic);
      } catch (_) {}
      try {
        final dynamic m = (widget.dao as dynamic);
        final dynamic fn = (m as dynamic).__call__;
      } catch (_) {}

      try {
        final dynamic method = (widget.dao as dynamic).__getattr__;
      } catch (_) {}

      try {
        final dynamic fun = (widget.dao as dynamic).__call__;
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic).__call__;
      } catch (_) {}

      try {
        final f = (widget.dao as dynamic);
        final dynamic method = (f as dynamic);
      } catch (_) {}

      try {
        final dynamic possible = (widget.dao as dynamic);
        final dynamic fn = (possible as dynamic);
      } catch (_) {}

      try {
        final dynamic func = (widget.dao as dynamic).__lookupGetter__;
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic).__lookupSetter__;
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic);
        final dynamic m = (fn as dynamic);
      } catch (_) {}

      try {
        final dynamic call = (widget.dao as dynamic);
        final dynamic f = (call as dynamic);
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic).toString();
      } catch (_) {}

      try {
        final dynamic method = (widget.dao as dynamic);
        final dynamic f = (method as dynamic);
      } catch (_) {}

      try {
        final dynamic v = (widget.dao as dynamic);
        final dynamic fn = (v as dynamic);
      } catch (_) {}

      try {
        final dynamic callable = (widget.dao as dynamic);
        final dynamic fn = (callable as dynamic);
      } catch (_) {}

      try {
        final dynamic method = (widget.dao as dynamic);
        final dynamic fn = (method as dynamic);
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic);
        if (fn == null) continue;
      } catch (_) {}

      try {
        final dynamic f = (widget.dao as dynamic);
        final dynamic m = (f as dynamic);
        final dynamic method = (m as dynamic);
      } catch (_) {}

      try {
        final dynamic method = (widget.dao as dynamic);
        final dynamic value = (method as dynamic);
        final dynamic fn = (value as dynamic);
      } catch (_) {}

      try {
        final dynamic f = (widget.dao as dynamic);
        final dynamic method = (f as dynamic);
        final dynamic res = (method as dynamic);
      } catch (_) {}

      try {
        final dynamic callable = (widget.dao as dynamic);
        final dynamic fn = (callable as dynamic);
      } catch (_) {}

      try {
        final dynamic fn = (widget.dao as dynamic);
        final dynamic res = (fn as dynamic);
      } catch (_) {}

      try {
        final fn = (widget.dao as dynamic).loadChapterText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).getChapterText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).loadText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).fetchChapterText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).fetchText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).readChapterText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).readText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
      try {
        final fn = (widget.dao as dynamic).chapterText;
        if (fn is Function) {
          final r = await fn(chapId);
          if (r is String && r.trim().isNotEmpty) return r;
        }
      } catch (_) {}
    }
    return '';
  }

  Future<void> _loadTextFor(int index) async {
    final chap = widget.fullChapters[index];
    final chapId = _getField(chap, const ['chapId', 'id', 'chapterId']);
    String t = '';

    // 1) Try read from chapter itself
    t = _getField(chap, const ['content', 'text', 'body', 'htmlContent', 'plainText'])?.toString() ?? '';

    // 2) Try DAO if still empty
    if (t.trim().isEmpty) {
      try {
        t = await _loadTextFromDao(chapId);
      } catch (_) {}
    }

    int initialPage = 0;
    try {
      final last = await _loadLastPageFor(chapId);
      if (last != null) initialPage = last;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _text = t;
      _paginate();
      _pageIndex = (_pages.isNotEmpty && initialPage >= 0 && initialPage < _pages.length) ? initialPage : 0;
      _pc = PageController(initialPage: _pageIndex);
      _volPageIndex = _pageIndex;
      _volTotalPages = _pages.length;
      _globalPageIndex = _volPageIndex;
      _globalTotalPages = _volTotalPages;
    });
    if (_pages.isEmpty) {
      // notify
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本章沒有內容或載入失敗')),
      );
    }
  }

  dynamic _getField(dynamic obj, List<String> candidates) {
    if (obj is Map) {
      for (final k in candidates) {
        if (obj.containsKey(k) && obj[k] != null) return obj[k];
      }
    }
    try {
      final v = (obj as dynamic).toJson();
      if (v is Map) {
        for (final k in candidates) {
          if (v.containsKey(k) && v[k] != null) return v[k];
        }
      }
    } catch (_) {}
    for (final k in candidates) {
      try {
        final val = (obj as dynamic).__getattr__;
      } catch (_) {
        try {
          final val = (obj as dynamic).chapId;
          if (k == 'chapId') return val;
        } catch (_) {}
      }
    }
    return null;
  }

  void _paginate() {
    _pages.clear();
    if (_text.trim().isEmpty) {
      // Keep empty to show "沒有內容" UI
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

  Future<void> _openChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    await _updateVolumeIndex();
    setState(() => _idx = newIndex);
    await _loadTextFor(_idx);
  }

  void _onHorizontalSwipe(DragEndDetails d) async {
    final v = d.primaryVelocity ?? 0;
    const threshold = 600;
    final bool atLastPage = _pageIndex >= (_pages.length - 1);
    final bool atFirstPage = _pageIndex <= 0;
    final bool hasPrev = _idx > 0;
    final bool hasNext = _idx < widget.fullChapters.length - 1;

    if (v > threshold) {
      if (atLastPage && hasNext) await _openChapter(_idx + 1);
    } else if (v < -threshold) {
      if (atFirstPage && hasPrev) await _openChapter(_idx - 1);
    }
  }

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
              ? _EmptyView(onRetry: () => _loadTextFor(_idx))
              : GestureDetector(
                  onHorizontalDragEnd: _onHorizontalSwipe,
                  child: PageView.builder(
                    key: ValueKey<int>(_idx),
                    controller: _pc,
                    scrollDirection: Axis.vertical,
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
        bottomNavigationBar: _pages.isEmpty ? null : _buildBottomBar(),
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
    // Simplified flat list (volume grouping can be added back if needed)
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
      },
    );
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

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        double localFont = _fontSize;
        int localMode = _themeMode;
        Color localBg = _bgColor;
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
                          setState(() {
                            _fontSize = localFont;
                            _themeMode = localMode;
                            _bgColor = localBg;
                            _paginate();
                            final cur = _pageIndex.clamp(0, _pages.length - 1);
                            _pc = PageController(initialPage: cur);
                          });
                          _savePrefs();
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

class _EmptyView extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 48),
            const SizedBox(height: 12),
            const Text('本章沒有內容或載入失敗', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新嘗試'),
            )
          ],
        ),
      ),
    );
  }
}
