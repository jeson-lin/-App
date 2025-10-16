
import 'package:flutter/material.dart';
import '../services/dao.dart';
import '../services/cache_store.dart';

/// Compatible with your original data model:
/// - constructor: SutraDao dao, List<({String chapId, String title})> fullChapters, int chapterIndex
/// - loads text via dao.loadChapterText(chapId)
/// - keeps features: vertical paging, edge-swipe chapter switch, catalog, last-read, stats, settings
class SutraReaderPage extends StatefulWidget {
  const SutraReaderPage({
    super.key,
    required this.dao,
    required this.fullChapters, // List<({String chapId, String title})>
    required this.chapterIndex,
  });

  final SutraDao dao;
  final List<({String chapId, String title})> fullChapters;
  final int chapterIndex;

  @override
  State<SutraReaderPage> createState() => _SutraReaderPageState();
}

class _SutraReaderPageState extends State<SutraReaderPage> with WidgetsBindingObserver {
  late int _idx;
  late PageController _pc;
  String _text = '';
  List<TextRange> _pages = <TextRange>[];
  int _pageIndex = 0;

  // prefs
  double _fontSize = 18;
  int _themeMode = 0;
  Color _bgColor = const Color(0xFFFAF6EF);

  // stats
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

  // ===== Prefs =====
  static const _kPrefs = 'reader_prefs_v1';
  Future<void> _loadPrefs() async {
    final m = await CacheStore.readJson(_kPrefs) ?? <String, dynamic>{};
    if (!mounted) return;
    setState(() {
      _fontSize = (m['fontSize'] is num) ? (m['fontSize'] as num).toDouble() : _fontSize;
      _themeMode = (m['themeMode'] is num) ? (m['themeMode'] as num).toInt() : _themeMode;
      if (m['bgColor'] is int) _bgColor = Color(m['bgColor'] as int);
    });
  }
  Future<void> _savePrefs() async {
    await CacheStore.writeJson(_kPrefs, {'fontSize': _fontSize, 'themeMode': _themeMode, 'bgColor': _bgColor.value});
  }

  // ===== Stats =====
  static const _kStats = 'reader_stats_v1';
  Future<void> _startSession() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastOpenTs = now;
    final m = await CacheStore.readJson(_kStats) ?? <String, dynamic>{'totalSeconds': 0};
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStats, m);
  }
  Future<void> _accumulateStats() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastOpenTs == null) return;
    int addSec = ((now - _lastOpenTs!) / 1000).round();
    final m = await CacheStore.readJson(_kStats) ?? <String, dynamic>{'totalSeconds': 0};
    m['totalSeconds'] = (m['totalSeconds'] ?? 0) + addSec;
    m['lastOpenTs'] = now;
    await CacheStore.writeJson(_kStats, m);
    _lastOpenTs = now;
  }
  Future<int> _getTotalSeconds() async {
    final m = await CacheStore.readJson(_kStats) ?? <String, dynamic>{'totalSeconds': 0};
    return (m['totalSeconds'] ?? 0) as int;
  }

  // ===== Last-read =====
  String _lastPosKeyFor(String chapId) => 'last_pos_v1|chap=$chapId';
  Future<int?> _loadLastPageFor(String chapId) async {
    final m = await CacheStore.readJson(_lastPosKeyFor(chapId));
    final p = m?['pageIndex'];
    if (p is int) return p;
    if (p is num) return p.toInt();
    return null;
  }
  Future<void> _saveLastPageFor(String chapId, int pageIndex) async {
    await CacheStore.writeJson(_lastPosKeyFor(chapId), {'pageIndex': pageIndex});
  }

  // ===== Load & paginate =====
  Future<void> _loadTextFor(int index) async {
    final chap = widget.fullChapters[index];
    String t = '';
    try {
      t = await widget.dao.loadChapterText(chap.chapId);
    } catch (_) {}
    int initialPage = 0;
    try {
      final last = await _loadLastPageFor(chap.chapId);
      if (last != null) initialPage = last;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _text = t;
      _paginate();
      _pageIndex = (_pages.isNotEmpty && initialPage >= 0 && initialPage < _pages.length) ? initialPage : 0;
      _pc = PageController(initialPage: _pageIndex);
    });
  }

  void _paginate() {
    _pages.clear();
    if (_text.trim().isEmpty) return;
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

  // ===== Chapter switching =====
  Future<void> _openChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    final cur = widget.fullChapters[_idx];
    await _saveLastPageFor(cur.chapId, _pageIndex);
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
    if (v > threshold) { if (atLastPage && hasNext) await _openChapter(_idx + 1); }
    else if (v < -threshold) { if (atFirstPage && hasPrev) await _openChapter(_idx - 1); }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('章節 ${_idx + 1}（${_pageIndex + 1}/${_pages.isEmpty ? 1 : _pages.length}）'),
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
            ? _buildEmpty()
            : GestureDetector(
                onHorizontalDragEnd: _onHorizontalSwipe,
                child: PageView.builder(
                  key: ValueKey<int>(_idx),
                  controller: _pc,
                  scrollDirection: Axis.vertical,
                  onPageChanged: (i) => setState(() {
                    _pageIndex = i;
                    _saveLastPageFor(widget.fullChapters[_idx].chapId, _pageIndex);
                    _accumulateStats();
                  }),
                  itemCount: _pages.length,
                  itemBuilder: (c, i) {
                    final r = _pages[i];
                    final pageText = _text.substring(r.start, r.end);
                    return _ReaderPage(text: pageText, fontSize: _fontSize, bgColor: _bgColor);
                  },
                ),
              ),
      ),
      bottomNavigationBar: _pages.isEmpty ? null : _buildBottomBar(),
    );
  }

  Widget _buildEmpty() {
    final chap = widget.fullChapters[_idx];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 48),
            const SizedBox(height: 8),
            Text('沒有內容（章: ${chap.title} / ${chap.chapId}）'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _loadTextFor(_idx),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新嘗試'),
                ),
                OutlinedButton.icon(
                  onPressed: _showCatalog,
                  icon: const Icon(Icons.list),
                  label: const Text('開啟目錄'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
              return ListTile(
                leading: Text('${i + 1}'),
                title: Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          value: localFont, min: 12, max: 28, divisions: 16,
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
                      ChoiceChip(label: const Text('跟隨系統'), selected: localMode == 0, onSelected: (_)=>setSheet(()=>localMode=0)),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('日間'), selected: localMode == 1, onSelected: (_)=>setSheet(()=>localMode=1)),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('夜間'), selected: localMode == 2, onSelected: (_)=>setSheet(()=>localMode=2)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('背景色'),
                      const SizedBox(width: 12),
                      for (final c0 in <Color>[const Color(0xFFFAF6EF), Colors.white, const Color(0xFF121212), const Color(0xFFFFF8E1)])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setSheet(() => localBg = c0),
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(color: c0, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                              child: localBg.value == c0.value ? const Icon(Icons.check, size: 18) : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(c).pop();
                          setState(() {
                            _fontSize = localFont;
                            _themeMode = localMode;
                            _bgColor = localBg;
                            _paginate();
                            final cur = _pageIndex.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
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
                    ? () => _pc.previousPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut)
                    : null,
              ),
              Expanded(
                child: total <= 1 ? const SizedBox.shrink() : Slider(
                  value: (_pageIndex + 1).toDouble(),
                  min: 1, max: total.toDouble(),
                  label: '${_pageIndex + 1}/$total',
                  onChanged: (v) {
                    final target = v.round() - 1;
                    if (target != _pageIndex) {
                      _pc.jumpToPage(target);
                      setState(() => _pageIndex = target);
                      _saveLastPageFor(widget.fullChapters[_idx].chapId, target);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _pageIndex < total - 1
                    ? () => _pc.nextPage(duration: const Duration(milliseconds: 180), curve: Curves.easeOut)
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
    final textColor = Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87;
    return SelectionArea(
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        alignment: Alignment.topLeft,
        child: Text(
          text.isEmpty ? '（本章無內容）' : text,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6, fontSize: fontSize, color: textColor),
        ),
      ),
    );
  }
}
