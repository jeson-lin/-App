
// lib/reader/reader_page.dart (chapter reset patch)
import 'package:flutter/material.dart';
import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../services/prefs.dart';
import 'horizontal_typesetter.dart';
import 'horizontal_page_painter.dart';
import 'package:auto_size_text/auto_size_text.dart';

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
  String _text = '';
  late PageController _pc;
  List<HPageRange> _pages = [];

  double _fontSize = 18;
  int _bgColor = 0xFFFAF6EF;
  final EdgeInsets _basePadding = const EdgeInsets.fromLTRB(16, 16, 16, 16);

  Size? _lastSize;
  EdgeInsets? _lastEffectivePadding;
  int _idx = 0;

  int _themeMode = 0; // 0 system, 1 light, 2 dark

  
  bool get _isDarkEffective {
    final b = MediaQuery.maybeOf(context)?.platformBrightness;
    final bool sysDark = b == Brightness.dark;
    return _themeMode == 2 || (_themeMode == 0 && sysDark);
  }

  Color _bestTextColor(Color bg) {
    final r = bg.red / 255.0, g = bg.green / 255.0, b = bg.blue / 255.0;
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return lum < 0.5 ? Colors.white70 : Colors.black87;
  }
@override
  void initState() {
    super.initState();
    _pc = PageController(initialPage: 0);
    _idx = widget.chapterIndex;
    _loadPrefs();
    _loadTextFor(_idx);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final fs = await Prefs.loadFontSize();
    final bg = await Prefs.loadBgColor();
    if (!mounted) return;
    setState(() { if (fs != null) _fontSize = fs; if (bg != null) _bgColor = bg; });
  }

  Future<void> _loadTextFor(int index) async {
    final info = widget.fullChapters[index];
    final t = await widget.dao.loadChapterText(info.chapId);
    if (!mounted) return;
    setState(() { _text = t; });
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: true);
    }
  }

  EdgeInsets _computeEffectivePadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    final extraBottom = mq.viewPadding.bottom;
    return _basePadding.copyWith(bottom: _basePadding.bottom + extraBottom);
  }

  void _reflow(Size size, EdgeInsets effectivePadding, {bool resetToFirstPage = false}) {
    final style = TextStyle(fontSize: _fontSize, height: 1.4);
    final ts = HorizontalTypesetter(
      text: _text,
      style: style,
      padding: effectivePadding,
                    textColor: _isDarkEffective ? Colors.white70 : _bestTextColor(bg),
    );
    final pages = ts.paginate(size);
    setState(() {
      _pages = pages;
      _lastSize = size;
      _lastEffectivePadding = effectivePadding;
    });
    if (resetToFirstPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pc.hasClients) _pc.jumpToPage(0);
      });
    }
  }

  void _changeFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(14.0, 36.0));
    Prefs.saveFontSize(_fontSize);
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: false);
    }
  }

  Future<void> _openChapter(int newIndex) async {
    if (newIndex < 0 || newIndex >= widget.fullChapters.length) return;
    setState(() { _text = ''; _pages = []; _idx = newIndex; });
    final old = _pc;
    _pc = PageController(initialPage: 0);
    old.dispose();
    await _loadTextFor(newIndex);
  }

  void _onHorizontalSwipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    const threshold = 300;
    if (v > threshold) {
      _openChapter(_idx + 1);
    } else if (v < -threshold) {
      _openChapter(_idx - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Color(_bgColor);
    final effectivePadding = _computeEffectivePadding(context);
    final title = widget.fullChapters[_idx].title;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: AutoSizeText(title, maxLines: 1, minFontSize: 12, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.text_decrease), onPressed: () => _changeFont(-2)),
          IconButton(icon: const Icon(Icons.text_increase), onPressed: () => _changeFont(2)),
          IconButton(icon: const Icon(Icons.format_size), onPressed: () {
            showModalBottomSheet(
              context: context,
              builder: (c) {
                double local = _fontSize;
                return StatefulBuilder(builder: (c, setS) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('主題模式', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        RadioListTile<int>(value: 0, groupValue: _themeMode, title: Text('跟隨系統'), secondary: Icon(Icons.auto_mode), onChanged: (v){ if(v==null) return; setState(()=>_themeMode=v); Prefs.saveThemeMode(v); }),
                        RadioListTile<int>(value: 1, groupValue: _themeMode, title: Text('日間模式'), secondary: Icon(Icons.light_mode), onChanged: (v){ if(v==null) return; setState(()=>_themeMode=v); Prefs.saveThemeMode(v); }),
                        RadioListTile<int>(value: 2, groupValue: _themeMode, title: Text('夜間模式'), secondary: Icon(Icons.dark_mode), onChanged: (v){ if(v==null) return; setState(()=>_themeMode=v); Prefs.saveThemeMode(v); }),
                        SizedBox(height: 12),
                        const Text('背景顏色', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [0xFFFFFFFF,0xFFFAF6EF,0xFFF5F5F5,0xFF1E1E1E,0xFF000000].map((c)=>GestureDetector(
                            onTap: (){ setState(()=>_bgColor=c); Prefs.saveBgColor(c); },
                            child: Container(width: 36, height: 36, decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Colors.black12))),
                          )).toList(),
                        ),
                        SizedBox(height: 16),
                        const Text('字體大小'),
                        Slider(
                          min: 14, max: 36, value: local,
                          onChanged: (v) {
                            setS(() => local = v);
                            setState(() => _fontSize = v);
                            Prefs.saveFontSize(v);
                            if (_lastSize != null && _lastEffectivePadding != null) {
                              _reflow(_lastSize!, _lastEffectivePadding!, resetToFirstPage: false);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                });
              },
            );
          }),
        ],
      ),
      body: LayoutBuilder(
        builder: (c, bc) {
          final size = Size(bc.maxWidth, bc.maxHeight);
          final padChanged = _lastEffectivePadding == null || _lastEffectivePadding != effectivePadding;
          final sizeChanged = _lastSize == null || _lastSize != size;
          if (sizeChanged || padChanged) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _reflow(size, effectivePadding, resetToFirstPage: false));
          }
          if (_text.isEmpty || _pages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final style = TextStyle(fontSize: _fontSize, height: 1.4, color: Colors.black87);
          return GestureDetector(
            onHorizontalDragEnd: _onHorizontalSwipe,
            child: PageView.builder(
              key: ValueKey<int>(_idx),  // reset PageView state on chapter change
              controller: _pc,
              scrollDirection: Axis.vertical,
              itemCount: _pages.length,
              itemBuilder: (c, i) {
                final pr = _pages[i];
                return CustomPaint(
                  painter: HorizontalPagePainter(
                    text: _text,
                    range: TextRange(start: pr.start, end: pr.end),
                    style: style,
                    padding: effectivePadding,
                    textColor: _isDarkEffective ? Colors.white70 : _bestTextColor(bg),
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
