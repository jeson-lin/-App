// lib/reader/reader_page.dart
import 'package:flutter/material.dart';
import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../services/prefs.dart';
import 'vertical_typesetter.dart';
import 'vertical_page_painter.dart';

class SutraReaderPage extends StatefulWidget {
  const SutraReaderPage({
    super.key,
    required this.dao,
    required this.chapterId,
    required this.chapterTitle,
  });
  final SutraDao dao;
  final String chapterId;
  final String chapterTitle;

  @override
  State<SutraReaderPage> createState() => _SutraReaderPageState();
}

class _SutraReaderPageState extends State<SutraReaderPage> {
  String _text = '';
  late PageController _pc;
  List<PageRange> _pages = [];

  double _fontSize = 28;
  int _bgColor = 0xFFFAF6EF;
  final EdgeInsets _basePadding = const EdgeInsets.fromLTRB(24, 20, 24, 24);
  final double _columnGap = 12;

  Size? _lastSize;
  EdgeInsets? _lastEffectivePadding;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
    _loadPrefs();
    _loadText();
  }

  Future<void> _loadPrefs() async {
    final fs = await Prefs.loadFontSize();
    final bg = await Prefs.loadBgColor();
    setState(() { if (fs != null) _fontSize = fs; if (bg != null) _bgColor = bg; });
  }

  Future<void> _loadText() async {
    final t = await widget.dao.loadChapterText(widget.chapterId);
    setState(() { _text = t; });
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!);
    }
  }

  EdgeInsets _computeEffectivePadding(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Safe areas from system UI (gesture bar / 3-button nav)
    final bottomSafe = mq.padding.bottom > 0 ? mq.padding.bottom : mq.viewPadding.bottom;
    final gesture = mq.systemGestureInsets.bottom;
    final extraBottom = bottomSafe > gesture ? bottomSafe : gesture;
    return _basePadding.copyWith(bottom: _basePadding.bottom + extraBottom);
  }

  void _reflow(Size size, EdgeInsets effectivePadding) {
    final style = TextStyle(fontSize: _fontSize, height: 1.2);
    final ts = VerticalTypesetter(
      text: _text,
      style: style,
      padding: effectivePadding,
      columnGap: _columnGap,
    );
    final pages = ts.paginate(size);
    setState(() {
      _pages = pages;
      _lastSize = size;
      _lastEffectivePadding = effectivePadding;
    });
  }

  void _changeFont(double delta) {
    setState(() => _fontSize = (_fontSize + delta).clamp(16.0, 48.0));
    Prefs.saveFontSize(_fontSize);
    if (_lastSize != null && _lastEffectivePadding != null) {
      _reflow(_lastSize!, _lastEffectivePadding!);
    }
  }

  void _showFontSheet() {
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
                const Text('字體大小'),
                Slider(
                  min: 16, max: 48, value: local,
                  onChanged: (v) {
                    setS(() => local = v);
                    setState(() => _fontSize = v);
                    Prefs.saveFontSize(v);
                    if (_lastSize != null && _lastEffectivePadding != null) {
                      _reflow(_lastSize!, _lastEffectivePadding!);
                    }
                  },
                ),
              ],
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
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        actions: [
          IconButton(icon: const Icon(Icons.text_decrease), onPressed: () => _changeFont(-2)),
          IconButton(icon: const Icon(Icons.text_increase), onPressed: () => _changeFont(2)),
          IconButton(icon: const Icon(Icons.format_size), onPressed: _showFontSheet),
        ],
      ),
      body: LayoutBuilder(
        builder: (c, bc) {
          final size = Size(bc.maxWidth, bc.maxHeight);
          final padChanged = _lastEffectivePadding == null || _lastEffectivePadding != effectivePadding;
          final sizeChanged = _lastSize == null || _lastSize != size;
          if (sizeChanged || padChanged) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _reflow(size, effectivePadding));
          }
          if (_text.isEmpty || _pages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          final style = TextStyle(fontSize: _fontSize, height: 1.2, color: Colors.black87);
          return SafeArea(
            top: false, left: false, right: false, bottom: true,
            child: PageView.builder(
              controller: _pc,
              itemCount: _pages.length,
              reverse: true,
              itemBuilder: (c, i) {
                final pr = _pages[i];
                return CustomPaint(
                  painter: VerticalPagePainter(
                    text: _text,
                    range: TextRange(start: pr.start, end: pr.end),
                    style: style,
                    padding: effectivePadding,
                    columnGap: _columnGap,
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
