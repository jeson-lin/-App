// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import '../services/db_init.dart';
import '../services/dao.dart';
import '../services/dao_extensions.dart';
import '../reader/reader_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  SutraDao? _dao;
  List<({String volId, String title, int ord})> _vols = [];
  final Map<String, List<({String chapId, String title, String volId, int ord})>> _chapMap = {};

  // 全書章節索引（跨卷）
  List<({String chapId, String title})> _fullChapters = [];
  final Map<String, int> _chapGlobalIndex = {}; // chapId -> index

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final dbPath = await DbInit.ensureDatabase();
    final dao = await DbInit.openDao(dbPath);
    final vols = await dao.listVolumes();

    // 依卷順序，建立全書章節索引
    final full = <({String chapId, String title})>[];
    for (final v in vols) {
      final chs = await dao.listChaptersByVolume(v.volId);
      _chapMap[v.volId] = chs; // 也順帶快取，進入卷時不用再撈
      for (final ch in chs) {
        full.add((chapId: ch.chapId, title: ch.title));
      }
    }
    final idxMap = <String, int>{};
    for (int i = 0; i < full.length; i++) {
      idxMap[full[i].chapId] = i;
    }

    setState(() {
      _dao = dao;
      _vols = vols;
      _fullChapters = full;
      _chapGlobalIndex
        ..clear()
        ..addAll(idxMap);
    });
  }

  Future<void> _ensureChaps(String volId) async {
    final dao = _dao;
    if (dao == null || _chapMap.containsKey(volId)) return;
    final chs = await dao.listChaptersByVolume(volId);
    setState(() => _chapMap[volId] = chs);
  }

  void _openChapter(String volId, int chapIndexInVol) {
    final dao = _dao;
    if (dao == null) return;
    final chs = _chapMap[volId] ?? const [];
    if (chapIndexInVol < 0 || chapIndexInVol >= chs.length) return;
    final ch = chs[chapIndexInVol];

    final globalIndex = _chapGlobalIndex[ch.chapId] ?? 0;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SutraReaderPage(
        dao: dao,
        fullChapters: _fullChapters,
        chapterIndex: globalIndex,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_dao == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('地藏經 · 目錄')),
      body: ListView.builder(
        itemCount: _vols.length,
        itemBuilder: (c, i) {
          final vol = _vols[i];
          final chapters = _chapMap[vol.volId];
          return ExpansionTile(
            title: Text(vol.title),
            initiallyExpanded: i == 0,
            onExpansionChanged: (exp) { if (exp) _ensureChaps(vol.volId); },
            children: [
              if (chapters == null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: const SizedBox(height: 4, child: LinearProgressIndicator()),
                )
              else ...[
                for (int idx = 0; idx < chapters.length; idx++)
                  ListTile(
                    dense: true,
                    title: Text(chapters[idx].title),
                    onTap: () => _openChapter(vol.volId, idx),
                  )
              ]
            ],
          );
        },
      ),
    );
  }
}
