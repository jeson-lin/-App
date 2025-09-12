import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'pages/home_page.dart';
import 'db_helper.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '地藏經',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.brown),
      home: FutureBuilder<Database>(
        future: initDb(), // 初始化 load.db
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('地藏經')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '資料庫初始化失敗：\n${snap.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // ✅ DB 準備完成，進入首頁
          return const HomePage();
        },
      ),
    );
  }
}