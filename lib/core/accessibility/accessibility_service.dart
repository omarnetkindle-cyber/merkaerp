// ============================================================
// accessibility_service.dart
// Servicio de configuración de accesibilidad
// ============================================================

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccessibilityService extends ChangeNotifier {
  static final AccessibilityService instance = AccessibilityService._internal();
  
  static const String _fontSizeKey = 'accessibility_font_size';
  static const String _highContrastKey = 'accessibility_high_contrast';
  static const String _reducedMotionKey = 'accessibility_reduced_motion';
  static const String _screenReaderKey = 'accessibility_screen_reader';
  
  double _fontSize = 1.0;
  bool _highContrast = false;
  bool _reducedMotion = false;
  bool _screenReader = false;
  
  AccessibilityService._internal();
  
  double get fontSize => _fontSize;
  bool get highContrast => _highContrast;
  bool get reducedMotion => _reducedMotion;
  bool get screenReader => _screenReader;
  
  Future<void> initialize() async {
    await _loadPreferences();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    _fontSize = prefs.getDouble(_fontSizeKey) ?? 1.0;
    _highContrast = prefs.getBool(_highContrastKey) ?? false;
    _reducedMotion = prefs.getBool(_reducedMotionKey) ?? false;
    _screenReader = prefs.getBool(_screenReaderKey) ?? false;
    
    notifyListeners();
  }
  
  Future<void> setFontSize(double size) async {
    _fontSize = size.clamp(0.8, 1.5);
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, _fontSize);
  }
  
  Future<void> setHighContrast(bool enabled) async {
    _highContrast = enabled;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_highContrastKey, _highContrast);
  }
  
  Future<void> setReducedMotion(bool enabled) async {
    _reducedMotion = enabled;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedMotionKey, _reducedMotion);
  }
  
  Future<void> setScreenReader(bool enabled) async {
    _screenReader = enabled;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenReaderKey, _screenReader);
  }
  
  void increaseFontSize() {
    setFontSize(_fontSize + 0.1);
  }
  
  void decreaseFontSize() {
    setFontSize(_fontSize - 0.1);
  }
  
  void resetToDefaults() {
    setFontSize(1.0);
    setHighContrast(false);
    setReducedMotion(false);
    setScreenReader(false);
  }
  
  /// Aplica el tamaño de fuente a un texto
  TextStyle applyFontSize(TextStyle style) {
    return style.copyWith(
      fontSize: (style.fontSize ?? 14) * _fontSize,
    );
  }
  
  /// Obtiene colores de alto contraste si está habilitado
  Color getHighContrastColor(Color originalColor) {
    if (!_highContrast) return originalColor;
    
    // Convertir a alto contraste
    final luminance = originalColor.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
  
  /// Verifica si se debe usar animaciones reducidas
  bool shouldReduceAnimations() {
    return _reducedMotion;
  }
  
  /// Obtiene duración de animación ajustada
  Duration getAnimationDuration(Duration original) {
    if (_reducedMotion) {
      return Duration.zero;
    }
    return original;
  }
}
