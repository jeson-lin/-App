// lib/services/prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

class Prefs {
  static const _kThemeMode = 'theme_mode'; // 0: system, 1: light, 2: dark
  static const _kFontSize = 'font_size';
  static const _kBgColor = 'bg_color';

  static Future<void> saveFontSize(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFontSize, v);
  }

  static Future<double?> loadFontSize() async {
    final p = await SharedPreferences.getInstance();
    return p.getDouble(_kFontSize);
  }

  static Future<void> saveBgColor(int rgba) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBgColor, rgba);
  }

  static Future<int?> loadBgColor() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kBgColor);
  }
  static Future<void> saveThemeMode(int mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kThemeMode, mode);
  }

  static Future<int?> loadThemeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_kThemeMode);
  }

}
