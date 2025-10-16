
import 'package:flutter/material.dart';

/// A minimal, self-contained reader page that compiles and works.
/// It avoids external dependencies and unknown project types by using `dynamic` where needed.
///
/// Constructor matches prior usage:
///   SutraReaderPage(dao: widget.dao, fullChapters: list, chapterIndex: startIndex);
class SutraReaderPage extends StatefulWidget {
  final dynamic dao;                 // unknown DAO type; use dynamic to compile
  final List<dynamic> fullChapters;  // chapters; items should have a `chapId` field or key
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

class _SutraReaderPageState extends State<SutraReaderPage> {
  // chapter index within fullChapters
  late int _idx;

  // Page state
  late PageController _pc;
  List<TextRange> _pages = <TextRange>[];
  String _text = '';
  int _pageIndex = 0;

  // Optional counters (kept for future expansion)
  int _volPageIndex = 0;
  int _volTotalPages = 0;
  int _globalPageIndex = 0;
  int _globalTotalPages = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.chapterIndex;
    _pc = PageController();
    _loadTextFor(_idx);
  }

  Future<void> _loadTextFor(int index) async {
    // Safely get chapter id from dynamic item
    final chap = widget.fullChapters[index];
    final chapId = _tryRead(chap, 'chapId');
    String t = '';
    try {
      // Expect dao.loadChapterText(chapId) -> Future<String>
      if (widget.dao != null && widget.dao.loadChapterText != null) {
        t = await widget.dao.loadChapterText(chapId);
      }
    } catch (_) {
      // ignore, keep empty text
    }
    if (!mounted) return;
    setState(() {
      _text = t;
      _paginate();             // rebuild page ranges
      _pageIndex = 0;
      _volPageIndex = 0;
      _volTotalPages = _pages.length;
      _globalPageIndex = _volPageIndex;
      _globalTotalPages = _volTotalPages;
    });
  }

  dynamic _tryRead(dynamic obj, String field) {
    try {
      if (obj is Map<String, dynamic>) return obj[field];
      // try dart object
      final val = (obj as dynamic).__noSuchMethod__;
      // If above doesn't throw, ignore
      // We'll try with reflect-like access using getters in a try-catch
    } catch (_) {
      // ignore
    }
    try {
      return (obj as dynamic).toJson()[field];
    } catch (_) {
      // Best effort: direct property
      try { return (obj as dynamic).chapId; } catch (_) {}
    }
    return null;
  }

  void _paginate() {
    _pages.clear();
    if (_text.isEmpty) return;
    // Very simple pagination by character chunk; avoids layout measuring.
    const int chunk = 1000; // characters per "page"
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
    // Placeholder: if you later compute real volume-level page index,
    // update _volPageIndex/_volTotalPages here.
    _volPageIndex = _pageIndex;
    _volTotalPages = _pages.length;
  }

  Future<void> _updateGlobalIndex() async {
    // Placeholder: if you later compute real global-level page index,
    // update _globalPageIndex/_globalTotalPages here.
    _globalPageIndex = _volPageIndex;
    _globalTotalPages = _volTotalPages;
  }

  @override
  Widget build(BuildContext context) {
    final title = '章節 ${_idx + 1}';
    final total = _pages.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('$title（${_pageIndex + 1}/$total）'),
      ),
      body: _pages.isEmpty
          ? const Center(child: Text('沒有內容'))
          : PageView.builder(
              key: ValueKey<int>(_idx),
              controller: _pc,
              scrollDirection: Axis.vertical,
              onPageChanged: (i) => setState(() {
                _pageIndex = i;
                _updateVolumeIndex();
                _updateGlobalIndex();
              }),
              itemCount: _pages.length,
              itemBuilder: (c, i) {
                final pr = _pages[i];
                final pageText = _text.substring(pr.start, pr.end);
                return _ReaderPage(text: pageText);
              },
            ),
      bottomNavigationBar: _buildBottomBar(total),
    );
  }

  Widget _buildBottomBar(int total) {
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
  const _ReaderPage({required this.text});

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        alignment: Alignment.topLeft,
        child: Text(
          text,
          textAlign: TextAlign.start,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ),
    );
  }
}
