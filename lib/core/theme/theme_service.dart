// ============================================================
// theme_service.dart
// Servicio para gestión de temas con persistencia
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ui/enterprise_design_system.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();

  static const String _themeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;

  ThemeService._internal();

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isLightMode => _themeMode == ThemeMode.light;
  bool get isSystemMode => _themeMode == ThemeMode.system;

  Future<void> initialize() async {
    await _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);

    if (savedTheme != null) {
      switch (savedTheme.toLowerCase()) {
        case 'light':
          _themeMode = ThemeMode.light;
          break;
        case 'dark':
          _themeMode = ThemeMode.dark;
          break;
        case 'system':
        default:
          _themeMode = ThemeMode.system;
          break;
      }
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    String modeString;

    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
        modeString = 'system';
        break;
    }

    await prefs.setString(_themeKey, modeString);
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else if (_themeMode == ThemeMode.dark) {
      setThemeMode(ThemeMode.system);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }

  void setLightMode() => setThemeMode(ThemeMode.light);
  void setDarkMode() => setThemeMode(ThemeMode.dark);
  void setSystemMode() => setThemeMode(ThemeMode.system);

  ThemeData getTheme(BuildContext context) {
    switch (_themeMode) {
      case ThemeMode.light:
        return EnterpriseThemeEngine.theme();
      case ThemeMode.dark:
        return EnterpriseThemeEngine.theme(brightness: Brightness.dark);
      case ThemeMode.system:
        final brightness = MediaQuery.of(context).platformBrightness;
        return EnterpriseThemeEngine.theme(brightness: brightness);
    }
  }
}
