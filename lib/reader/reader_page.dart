import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../services/prefs.dart';
import 'horizontal_typesetter.dart';
import 'horizontal_page_painter.dart';

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

class _SutraReaderPageState extends State<SutraReaderPage> {
  // 章索引
  late int _idx;

  // 章文字 & 分頁
  String _text = '';
  late PageController _pc;
  late List<dynamic> _pages; // 需有 .start/.end

  // 外觀設定
  double _fontSize = 18;
  int _bgColor = 0xFFFAF6EF;
  int _themeMode = 0; // 0: 跟隨系統, 1: 日間, 2: 夜間

  // 版面與安全區
  final EdgeInsets _basePadding = const EdgeInsets.fromLTRB(16, 16, 16, 16);
  static const double _bottomUIReserve = 0.0; // 只保留安全區
  Size? _lastSize;
  EdgeInsets? _lastEffectivePadding;

  bool get _isDarkEffective {
    final b = MediaQuery.maybeOf(context)?.platformBrightness;
    final bool sysDark = b == Brightness.dark;
    return _themeMode == 2 || (_themeMode == 0 && sysDark);
  }

  Color _bestTextColor(Color bg) {
    final lum = bg.computeLuminance(); // 0=黑、1=白
    return lum < 0.5 ? Colors.white70 : Colors.black87;
  }

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    _pages = const [];
    _idx = widget.chapterIndex;
    _pc = PageController();
    _pages = const [];

    // 載入記憶設定
    Prefs.loadFontSize().then((v) { if (mounted && v != null) setState(() => _fontSize = v); });
    Prefs.loadBgColor().then((v) { if (mounted && v != null) setState(() => _bgColor = v); });
    Prefs.loadThemeMode().then((v){ if (mounted && v != null) setState(() => _themeMode = v); });

    _loadTextFor(_idx);
  }

  Future<void> _loadTextFor(int index) async {
    final chap = widget.fullChapters[index];
    final t = await widget.dao.loadChapterText(chap.chapId);
    if (!mounted) return;
    setState(() => _text = t);
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: true);
    }
  }

  EdgeInsets _computeEffectivePadding(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottom = _basePadding.bottom + media.padding.bottom + _bottomUIReserve;
    return EdgeInsets.fromLTRB(
      _basePadding.left,
      _basePadding.top,
      _basePadding.right,
      bottom,
    );
  }

  void _reflow(Size size, EdgeInsets effectivePadding, {bool resetToFirstPage = false}) {
    final style = TextStyle(fontSize: _fontSize, height: 1.4);
    final ts = HorizontalTypesetter(text: _text, style: style, padding: effectivePadding);
    final pages = ts.paginate(size);
    setState(() {
      _pages = pages;
      _lastSize = size;
      _lastEffectivePadding = effectivePadding;
    });
    if (resetToFirstPage && _pc.hasClients) {
      _pc.jumpToPage(0);
    }
  }

  void _changeFont(double delta) {
    final next = (_fontSize + delta).clamp(14.0, 36.0);
    setState(() => _fontSize = next);
    Prefs.saveFontSize(next);
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: false);
    }
  }

  // 左右換章（沿用你原本的體感：以速度判斷）
  
void _onHorizontalSwipe(DragEndDetails d) async {
  final v = d.primaryVelocity ?? 0;
  const threshold = 600;
  final bool isLastPageInChapter = _pageIndex >= _pages.length - 1;
  final bool isFirstPageInChapter = _pageIndex <= 0;
  final bool isLastChapterInVolume = _idx >= widget.fullChapters.length - 1;
  final bool isFirstChapterInVolume = _idx == 0;

  if (v > threshold) {
    // 往後
    if (isLastChapterInVolume && isLastPageInChapter) {
      await _openAdjacentVolume(next: true);
    } else if (!isLastChapterInVolume && isLastPageInChapter) {
      _openChapter(_idx + 1);
    }
  } else if (v < -threshold) {
    // 往前
    if (isFirstChapterInVolume && isFirstPageInChapter) {
      await _openAdjacentVolume(next: false);
    } else if (!isFirstChapterInVolume && isFirstPageInChapter) {
      _openChapter(_idx - 1);
    }
  }
} else if (v < -threshold) {
      _openChapter(_idx - 1); // 左滑 → 上一章
    }
  
Future<void> _showCatalog() async {
  final vols = await widget.dao.listVolumes();
  if (!mounted) return;
  String? currentVolId = await _currentVolumeId();
  int volIndex = currentVolId == null ? 0 : vols.indexWhere((v) => v.volId == currentVolId);
  if (volIndex < 0) volIndex = 0;
  var chapters = await widget.dao.listChaptersByVolume(vols[volIndex].volId);

  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            return Row(
              children: [
                SizedBox(
                  width: 160,
                  child: ListView.separated(
                    itemCount: vols.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final v = vols[i];
                      final selected = i == volIndex;
                      return ListTile(
                        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        selected: selected,
                        onTap: () async {
                          volIndex = i;
                          chapters = await widget.dao.listChaptersByVolume(v.volId);
                          setSheet((){});
                        },
                      );
                    },
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: chapters.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = chapters[i];
                      return ListTile(
                        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openSpecificVolume(vols[volIndex].volId, i);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _openSpecificVolume(String volId, int chapterIndex) async {
  final chs = await widget.dao.listChaptersByVolume(volId);
  if (chs.isEmpty || !mounted) return;
  final list = chs.map((e) => (chapId: e.chapId, title: e.title)).toList();
  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) {
    return SutraReaderPage(dao: widget.dao, fullChapters: list, chapterIndex: chapterIndex);
  }));
}

Future<String?> _currentVolumeId() async {
  final chap = widget.fullChapters[_idx];
  final rows = await widget.dao.db.rawQuery('SELECT vol_id AS volId FROM chapters WHERE chap_id = ? LIMIT 1', [chap.chapId]);
  if (rows.isEmpty) return null;
  return (rows.first['volId'] ?? '').toString();
}

Future<void> _openAdjacentVolume({required bool next}) async {
  final curVol = await _currentVolumeId();
  if (curVol == null) return;
  final vols = await widget.dao.listVolumes();
  final i = vols.indexWhere((v) => v.volId == curVol);
  if (i < 0) return;
  final t = next ? i + 1 : i - 1;
  if (t < 0 || t >= vols.length) return;
  final targetVolId = vols[t].volId;
  final targetChaps = await widget.dao.listChaptersByVolume(targetVolId);
  if (!mounted || targetChaps.isEmpty) return;
  final list = targetChaps.map((e) => (chapId: e.chapId, title: e.title)).toList();
  final startIndex = next ? 0 : (list.length - 1);
  Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) {
    return SutraReaderPage(dao: widget.dao, fullChapters: list, chapterIndex: startIndex);
  }));
}


@override
void dispose() {
  _pc.dispose();
  super.dispose();
}
}



  void _openChapter(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    setState(() => _idx = newIndex);
    _loadTextFor(_idx);
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) {
        double local = _fontSize;
        int localMode = _themeMode;
        final presets = <int>[0xFFFFFFFF, 0xFFFAF6EF, 0xFFF5F5F5, 0xFF1E1E1E, 0xFF000000];

        return StatefulBuilder(builder: (c, setS) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主題模式', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('跟隨系統'), icon: Icon(Icons.auto_mode)),
                      ButtonSegment(value: 1, label: Text('日間模式'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: 2, label: Text('夜間模式'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {localMode},
                    onSelectionChanged: (s) {
                      final v = s.first;
                      setS(()=>localMode = v);
                      setState(()=>_themeMode = v);
                      Prefs.saveThemeMode(v);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('背景顏色', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: presets.map((c) => GestureDetector(
                      onTap: () { setState(()=>_bgColor=c); Prefs.saveBgColor(c); },
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('字體大小'),
                  Slider(
                    min: 14, max: 36, value: local,
                    onChanged: (v) {
                      setS(()=>local=v); setState(()=>_fontSize=v); Prefs.saveFontSize(v);
                      if (_lastSize != null && _lastEffectivePadding != null) {
                        _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color(_bgColor);
    final effectivePadding = _computeEffectivePadding(context);
    final title = widget.fullChapters[_idx].title;

    return Scaffold(
      backgroundColor: bg,
      
appBar: AppBar(
    leading: IconButton(icon: const Icon(Icons.menu_book), tooltip: '目錄', onPressed: _showCatalog),
    title: InkWell(onTap: _showCatalog, child: AutoSizeText(title, maxLines: 1, minFontSize: 12, overflow: TextOverflow.ellipsis)),
    actions: [
      GestureDetector(
        onTap: () {
          setState(() {
            _counterMode = _counterMode == PageCounterMode.chapter
              ? PageCounterMode.volume
              : _counterMode == PageCounterMode.volume
                ? PageCounterMode.global
                : PageCounterMode.chapter;
          });
        },
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Center(
            child: Builder(
              builder: (context) {
                String label = '';
                switch (_counterMode) {
                  case PageCounterMode.chapter:
                    label = '${_pageIndex + 1}/${_pages.length}';
                    break;
                  case PageCounterMode.volume:
                    label = (_volTotalPages > 0) ? '${_volPageIndex + 1}/${_volTotalPages}' : '…/…';
                    break;
                  case PageCounterMode.global:
                    label = (_globalTotalPages > 0) ? '${_globalPageIndex + 1}/${_globalTotalPages}' : '…/…';
                    break;
                }
                return Text(label, style: Theme.of(context).textTheme.labelLarge);
              },
            ),
          ),
        ),
      ),
      IconButton(icon: const Icon(Icons.palette), onPressed: _showSettingsSheet, tooltip: '外觀設定'),
    ],
  ),
      body: LayoutBuilder(
        builder: (c, bc) {
          final size = Size(bc.maxWidth, bc.maxHeight);

          final padChanged = _lastEffectivePadding == null || _lastEffectivePadding != effectivePadding;
          final sizeChanged = _lastSize == null || _lastSize != size;
          if (sizeChanged || padChanged) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _reflow(size, effectivePadding, resetToFirstPage: false),
            );
          }

          if (_text.isEmpty || _pages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final textColor = _isDarkEffective ? Colors.white70 : _bestTextColor(bg);
          final style = TextStyle(fontSize: _fontSize, height: 1.4, color: textColor);

          return GestureDetector(
            onHorizontalDragEnd: _onHorizontalSwipe, // 左右換章
            child: PageView.builder(
              key: ValueKey<int>(_idx,
              onPageChanged: (i) => setState(() => _pageIndex = i)),
              controller: _pc,
              scrollDirection: Axis.vertical, // 章內上下翻頁
              itemCount: _pages.length,
              itemBuilder: (c, i) {
                final pr = _pages[i] as dynamic;
                return CustomPaint(
                  painter: HorizontalPagePainter(
                    text: _text,
                    range: TextRange(start: pr.start, end: pr.end),
                    style: style,
                    padding: effectivePadding,
                  ),
                  child: Container(),
                );
              },
            ),
          );
        },
      ),
    );
  }

}
