import 'dart:async';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';

import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../services/prefs.dart';
import '../services/cache_store.dart';
import 'horizontal_typesetter.dart';
import 'horizontal_page_painter.dart';

/// 頁碼顯示模式
enum PageCounterMode { chapter, volume, global }

/// 舊版相容：維持同樣的 Widget 名稱與必要參數
class SutraReaderPage extends StatefulWidget {
  const SutraReaderPage({
    super.key,
    required this.dao,
    required this.chap,
    this.title,
    this.counterMode = PageCounterMode.chapter,
  });

  final SutraDao dao;
  final ChapterRow chap;
  final String? title;
  final PageCounterMode counterMode;

  @override
  State<SutraReaderPage> createState() => _SutraReaderPageState();
}

class _SutraReaderPageState extends State<SutraReaderPage> {
  final PageController _pageController = PageController();
  bool _loading = true;
  List<String> _pages = const [];
  int _pageIndex = 0;
  late final String _cacheKey;

  @override
  void initState() {
    super.initState();
    _cacheKey = 'reader:last@chap:${widget.chap.chapId}';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 先讀快取的頁碼
    final cached = await CacheStore.getInt(_cacheKey);
    if (cached != null) _pageIndex = cached;
    // 載入章節文字
    await _loadTextFor(widget.chap);
  }

  Future<void> _loadTextFor(ChapterRow chap) async {
    try {
      final text = await widget.dao.loadChapterText(chap.chapId);
      if (!mounted) return;
      // 將章節文字切成「段落頁」：這邊以換行兩次為一段，
      // 若你的 DB 已經提供段落分行，可直接使用。
      final raw = (text ?? '').trim();
      final pages = _splitToParagraphPages(raw);
      setState(() {
        _pages = pages;
        _loading = false;
      });
      // 回到快取頁
      if (_pageIndex > 0 && _pageIndex < _pages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_pageIndex);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pages = const [];
        _loading = false;
      });
    }
  }

  List<String> _splitToParagraphPages(String raw) {
    if (raw.isEmpty) return const [];
    // 優先用空行分段；若沒有空行，依句號/頓號等標點做粗略切分
    final List<String> parts = raw.split(RegExp(r'\n{2,}')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length > 1) return parts;
    final fallback = raw.split(RegExp(r'(?<=[。！？；\n])')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return fallback.isEmpty ? <String>[raw] : fallback;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? '章節閱讀';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '章節資訊',
            onPressed: () => _showInfoBottomSheet(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: _DotSpinner())
          : _pages.isEmpty
              ? _EmptyState(onRetry: () => _loadTextFor(widget.chap))
              : PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) {
                    _pageIndex = i;
                    CacheStore.setInt(_cacheKey, i);
                  },
                  itemCount: _pages.length,
                  itemBuilder: (context, index) {
                    final text = _pages[index];
                    return _ReaderCard(
                      text: text,
                      index: index + 1,
                      total: _pages.length,
                    );
                  },
                ),
    );
  }

  void _showInfoBottomSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('章節資訊', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('卷：${widget.chap.volId} 章：${widget.chap.chapId}'),
                const SizedBox(height: 8),
                Text('頁數：${_pages.length}'),
                const SizedBox(height: 8),
                Text('目前頁：${_pageIndex + 1}/${_pages.isEmpty ? 1 : _pages.length}'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ReaderCard extends StatelessWidget {
  const _ReaderCard({required this.text, required this.index, required this.total});

  final String text;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          boxShadow: kElevationToShadow[1],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: AutoSizeText(
                    text,
                    minFontSize: 14,
                    maxLines: 1000,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text('$index / $total', style: theme.textTheme.labelMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final FutureOr<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 36),
          const SizedBox(height: 12),
          const Text('找不到此章節的內文'),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh),
            label: const Text('重新載入'),
          )
        ],
      ),
    );
  }
}

class _DotSpinner extends StatefulWidget {
  const _DotSpinner({Key? key}) : super(key: key);

  @override
  State<_DotSpinner> createState() => _DotSpinnerState();
}

class _DotSpinnerState extends State<_DotSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        final size = 8.0 + 6.0 * (t < 0.5 ? t * 2 : (1 - t) * 2);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}
