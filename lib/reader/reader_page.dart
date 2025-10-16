
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../services/prefs.dart';
import '../services/cache_store.dart';

enum PageCounterMode { chapter, volume, global }

class SutraReaderPage extends StatefulWidget {
  const SutraReaderPage({
    super.key,
    required this.dao,
    required this.fullChapters,
    required this.chapterIndex,
  });

  final SutraDao dao;
  final List<({String chapId, String title})> fullChapters;
  final int chapterIndex;

  @override
  State<SutraReaderPage> createState() => _SutraReaderPageState();
}

class _SutraReaderPageState extends State<SutraReaderPage> {
  final ScrollController _sc = ScrollController();
  bool _loading = true;
  List<String> _paragraphs = const [];

  double _fontSize = 20;
  double _lineHeight = 1.6;
  String _fontFamily = '';
  bool _isDark = false;

  late final String _cacheScrollKey;
  static const _kFontSizeKey = 'reader.fontSize';
  static const _kLineHeightKey = 'reader.lineHeight';
  static const _kFontFamilyKey = 'reader.fontFamily';
  static const _kDarkKey = 'reader.dark';

  ({String chapId, String title}) get _current => widget.fullChapters[widget.chapterIndex];

  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _cacheScrollKey = 'reader:scroll@chap:${_current.chapId}';
    _restorePrefs().then((_) { _loadTextFor(_current.chapId); });
    _sc.addListener(_onScroll);
  }

  void _onScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final offset = _sc.hasClients ? _sc.offset : 0.0;
      await CacheStore.setString(_cacheScrollKey, offset.toStringAsFixed(1));
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _sc.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final fs = await CacheStore.getString(_kFontSizeKey);
    final lh = await CacheStore.getString(_kLineHeightKey);
    final ff = await CacheStore.getString(_kFontFamilyKey);
    final dk = await CacheStore.getString(_kDarkKey);
    setState(() {
      _fontSize = double.tryParse(fs ?? '') ?? 20;
      _lineHeight = double.tryParse(lh ?? '') ?? 1.6;
      _fontFamily = ff ?? '';
      _isDark = (dk == '1');
    });
  }

  Future<void> _persistPrefs() async {
    await CacheStore.setString(_kFontSizeKey, _fontSize.toStringAsFixed(1));
    await CacheStore.setString(_kLineHeightKey, _lineHeight.toStringAsFixed(2));
    await CacheStore.setString(_kFontFamilyKey, _fontFamily);
    await CacheStore.setString(_kDarkKey, _isDark ? '1' : '0');
  }

  Future<void> _loadTextFor(String chapId) async {
    try {
      final text = await widget.dao.loadChapterText(chapId);
      if (!mounted) return;
      final raw = (text ?? '').trim();
      final ps = _splitToParagraphs(raw);
      setState(() { _paragraphs = ps; _loading = false; });

      final so = await CacheStore.getString(_cacheScrollKey);
      final offset = double.tryParse(so ?? '0') ?? 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients && offset > 0) { _sc.jumpTo(offset); }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _paragraphs = const []; _loading = false; });
    }
  }

  List<String> _splitToParagraphs(String raw) {
    if (raw.isEmpty) return const [];
    final parts = raw.split(RegExp(r'\n{2,}')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length > 1) return parts;
    final fallback = raw.split(RegExp(r'(?<=[。！？；\n])')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return fallback.isEmpty ? <String>[raw] : fallback;
  }

  TextStyle _paragraphStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 18);
    return base.copyWith(
      fontSize: _fontSize,
      height: _lineHeight,
      fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
    );
  }

  ThemeData _theme(BuildContext context) {
    final seed = Theme.of(context).colorScheme.primary;
    final light = ThemeData(colorSchemeSeed: seed, brightness: Brightness.light, useMaterial3: true);
    final dark  = ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark,  useMaterial3: true);
    return _isDark ? dark : light;
  }

  @override
  Widget build(BuildContext context) {
    final title = _current.title.isNotEmpty ? _current.title : '章節閱讀';
    return Theme(
      data: _theme(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(tooltip: '字小', icon: const Icon(Icons.text_decrease), onPressed: () async { setState(() => _fontSize = (_fontSize - 1).clamp(12, 48)); await _persistPrefs(); }),
            IconButton(tooltip: '字大', icon: const Icon(Icons.text_increase), onPressed: () async { setState(() => _fontSize = (_fontSize + 1).clamp(12, 48)); await _persistPrefs(); }),
            IconButton(tooltip: '字距/行距', icon: const Icon(Icons.format_line_spacing), onPressed: () async { setState(() => _lineHeight = (_lineHeight >= 2.2) ? 1.2 : (_lineHeight + 0.2)); await _persistPrefs(); }),
            IconButton(tooltip: '字型', icon: const Icon(Icons.font_download_outlined), onPressed: () async { setState(() { _fontFamily = _fontFamily.isEmpty ? 'NotoSerifTC' : ''; }); await _persistPrefs(); }),
            IconButton(tooltip: _isDark ? '日間模式' : '夜間模式', icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode), onPressed: () async { setState(() => _isDark = !_isDark); await _persistPrefs(); }),
          ],
        ),
        body: _loading
            ? const Center(child: _DotSpinner())
            : _paragraphs.isEmpty
                ? _EmptyState(onRetry: () => _loadTextFor(_current.chapId))
                : ListView.separated(
                    controller: _sc,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    itemBuilder: (context, i) => Text(_paragraphs[i], style: _paragraphStyle(context), textAlign: TextAlign.start),
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemCount: _paragraphs.length,
                  ),
        bottomNavigationBar: _loading || _paragraphs.isEmpty ? null : SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 10), child: Align(alignment: Alignment.centerRight, child: Text('段落 ${_paragraphs.length}', style: Theme.of(context).textTheme.labelMedium)))),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final FutureOr<void> Function() onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.menu_book_outlined, size: 36),
      const SizedBox(height: 12),
      const Text('找不到此章節的內文'),
      const SizedBox(height: 8),
      ElevatedButton.icon(onPressed: () => onRetry(), icon: const Icon(Icons.refresh), label: const Text('重新載入'))
    ]));
  }
}

class _DotSpinner extends StatefulWidget { const _DotSpinner({Key? key}) : super(key: key); @override State<_DotSpinner> createState() => _DotSpinnerState(); }
class _DotSpinnerState extends State<_DotSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override void initState() { super.initState(); _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(); }
  @override void dispose() { _ac.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ac, builder: (_, __) {
      final t = _ac.value; final size = 8.0 + 6.0 * (t < 0.5 ? t * 2 : (1 - t) * 2);
      return Container(width: size, height: size, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2)));
    });
  }
}
