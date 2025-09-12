import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dizangjing_app/reader/reader_page.dart';
import 'package:dizangjing_app/services/dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeSutraDao extends SutraDao {
  FakeSutraDao() : super(databaseFactoryFfi.openDatabase(inMemoryDatabasePath) as dynamic);
  @override
  Future<String> loadChapterText(String chapId) async {
    return '[$chapId] 測試經文 ' * 300;
  }
}

void main() {
  // 初始化 FFI 的 sqflite
  sqfliteFfiInit();

  testWidgets('Reader renders + vertical paging + horizontal chapter switch', (tester) async {
    final dao = FakeSutraDao();

    final chapters = <({String chapId, String title})>[
      (chapId: 'C1', title: '第一章'),
      (chapId: 'C2', title: '第二章'),
    ];

    await tester.pumpWidget(MaterialApp(
      home: SutraReaderPage(dao: dao, fullChapters: chapters, chapterIndex: 0),
    ));

    await tester.pumpAndSettle();

    // 標題可見（AutoSizeText 已替換）
    expect(find.text('第一章'), findsOneWidget);

    // 垂直翻兩次
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1000);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1000);
    await tester.pumpAndSettle();

    // 水平切下一章（左→右）
    await tester.fling(find.byType(PageView), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('第二章'), findsOneWidget);
  });
}
