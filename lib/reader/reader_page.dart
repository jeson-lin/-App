
import 'package:flutter/material.dart';
import '../services/cache_store.dart';

/// Enhanced reader page:
/// - Loads chapter text using dao.loadChapterText(chapId) if available
/// - Simple pagination (by characters) with font-size control
/// - Persists user settings (fontSize, themeMode, bgColor) via CacheStore
/// - Tracks reading stats (totalSeconds) and last-read page per chapter
class SutraReaderPage extends StatefulWidget {
  final dynamic dao;                 // DAO is dynamic to avoid compilation issues
  final List<dynamic> fullChapters;  // Each item should expose chapId (field/property or toJson key)
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
  // Chapter index within fullChapters
  late int _idx;

  // Page state
  late PageController _pc;
  List<TextRange> _pages = <TextRange>[];
  String _text = '';
  int _pageIndex = 0;

  // Counters (can be expanded later)
  int _volPageIndex = 0;
  int _volTotalPages = 0;
  int _globalPageIndex = 0;
  int _globalTotalPages = 0;

  // Preferences
  double _fontSize = 18;
  // themeMode: 0 follow system, 1 light, 2 dark
  int _themeMode = 0;
  Color _bgColor = const Color(0xFFFAF6EF);

  // Stats session
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

  // ===== Preferences via CacheStore =====
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

  // ===== Reading stats via CacheStore =====
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

  // ===== Last-read position per chapter via CacheStore =====
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

  // ===== Chapter text loading & pagination =====
  Future<void> _loadTextFor(int index) async {
    final chap = widget.fullChapters[index];
    final chapId = _tryRead(chap, 'chapId');
    String t = '';
    try {
      if (widget.dao != null && widget.dao.loadChapterText != null) {
        t = await widget.dao.loadChapterText(chapId);
      }
    } catch (_) {
      // ignore
    }
    int initialPage = 0;
    try {
      final last = await _loadLastPageFor(chapId);
      if (last != null) initialPage = last;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _text = t;
      _paginate();             // rebuild page ranges
      _pageIndex = (initialPage >= 0 && initialPage < _pages.length) ? initialPage : 0;
      _pc = PageController(initialPage: _pageIndex);
      _volPageIndex = _pageIndex;
      _volTotalPages = _pages.length;
      _globalPageIndex = _volPageIndex;
      _globalTotalPages = _volTotalPages;
    });
  }

  dynamic _tryRead(dynamic obj, String field) {
    // Supports map or object with toJson(); otherwise tries direct getter
    try {
      if (obj is Map<String, dynamic>) return obj[field];
    } catch (_) {}
    try {
      final json = (obj as dynamic).toJson();
      if (json is Map && json.containsKey(field)) return json[field];
    } catch (_) {}
    try {
      // direct property getter
      return (obj as dynamic).chapId;
    } catch (_) {}
    return null;
  }

  void _paginate() {
    _pages.clear();
    if (_text.isEmpty) {
      _pages.add(const TextRange(start: 0, end: 0));
      return;
    }
    // Simple pagination size scales inversely with font size for a rough effect.
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
    // Persist last page for current chapter
    final chapId = _tryRead(widget.fullChapters[_idx], 'chapId');
    await _saveLastPageFor(chapId, _pageIndex);
  }

  Future<void> _updateGlobalIndex() async {
    _globalPageIndex = _volPageIndex;
    _globalTotalPages = _volTotalPages;
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
              : PageView.builder(
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
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  ThemeData _resolveTheme(BuildContext context) {
    switch (_themeMode) {
      case 1: // light
        return Theme.of(context).copyWith(brightness: Brightness.light);
      case 2: // dark
        return Theme.of(context).copyWith(brightness: Brightness.dark);
      default:
        return Theme.of(context);
    }
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
                        const Color(0xFFFAF6EF), // parchment
                        Colors.white,
                        const Color(0xFF121212), // dark
                        const Color(0xFFFFF8E1), // light cream
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
                            // 重建 controller 保持目前頁面附近
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
