// ============================================================
// dashboard_service.dart
// Servicio para gestión del dashboard personalizable
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_widget.dart';

class DashboardService extends ChangeNotifier {
  static final DashboardService instance = DashboardService._internal();
  
  static const String _widgetsKey = 'dashboard_widgets';
  static const String _layoutKey = 'dashboard_layout';
  
  List<DashboardWidget> _widgets = [];
  Map<String, int> _widgetPositions = {};
  
  DashboardService._internal();
  
  List<DashboardWidget> get widgets => _widgets;
  List<DashboardWidget> get enabledWidgets => _widgets.where((w) => w.isEnabled).toList();
  
  Future<void> initialize() async {
    await _loadConfiguration();
  }
  
  Future<void> _loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    
    final widgetsJson = prefs.getString(_widgetsKey);
    if (widgetsJson != null) {
      try {
        final widgetsList = jsonDecode(widgetsJson) as List;
        _widgets = widgetsList
            .map((json) => DashboardWidget.fromJson(json as Map<String, dynamic>))
            .toList();
      } catch (e) {
        _widgets = DashboardWidget.getDefaultWidgets();
      }
    } else {
      _widgets = DashboardWidget.getDefaultWidgets();
    }
    
    final layoutJson = prefs.getString(_layoutKey);
    if (layoutJson != null) {
      try {
        _widgetPositions = Map<String, int>.from(jsonDecode(layoutJson));
      } catch (e) {
        _widgetPositions = {};
      }
    }
    
    notifyListeners();
  }
  
  Future<void> _saveConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    
    final widgetsJson = jsonEncode(_widgets.map((w) => w.toJson()).toList());
    await prefs.setString(_widgetsKey, widgetsJson);
    
    final layoutJson = jsonEncode(_widgetPositions);
    await prefs.setString(_layoutKey, layoutJson);
  }
  
  Future<void> addWidget(DashboardWidget widget) async {
    _widgets.add(widget);
    await _saveConfiguration();
    notifyListeners();
  }
  
  Future<void> removeWidget(String widgetId) async {
    _widgets.removeWhere((w) => w.id == widgetId);
    await _saveConfiguration();
    notifyListeners();
  }
  
  Future<void> updateWidget(DashboardWidget widget) async {
    final index = _widgets.indexWhere((w) => w.id == widget.id);
    if (index != -1) {
      _widgets[index] = widget;
      await _saveConfiguration();
      notifyListeners();
    }
  }
  
  Future<void> reorderWidgets(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    final widget = _widgets.removeAt(oldIndex);
    _widgets.insert(newIndex, widget);
    
    // Actualizar posiciones
    for (int i = 0; i < _widgets.length; i++) {
      _widgets[i] = _widgets[i].copyWith(position: i);
    }
    
    await _saveConfiguration();
    notifyListeners();
  }
  
  Future<void> toggleWidget(String widgetId) async {
    final index = _widgets.indexWhere((w) => w.id == widgetId);
    if (index != -1) {
      _widgets[index] = _widgets[index].copyWith(
        isEnabled: !_widgets[index].isEnabled,
      );
      await _saveConfiguration();
      notifyListeners();
    }
  }
  
  Future<void> setWidgetSize(String widgetId, int rowSpan, int colSpan) async {
    final index = _widgets.indexWhere((w) => w.id == widgetId);
    if (index != -1) {
      _widgets[index] = _widgets[index].copyWith(
        rowSpan: rowSpan,
        colSpan: colSpan,
      );
      await _saveConfiguration();
      notifyListeners();
    }
  }
  
  Future<void> resetToDefaults() async {
    _widgets = DashboardWidget.getDefaultWidgets();
    _widgetPositions = {};
    await _saveConfiguration();
    notifyListeners();
  }
  
  DashboardWidget? getWidgetById(String widgetId) {
    try {
      return _widgets.firstWhere((w) => w.id == widgetId);
    } catch (e) {
      return null;
    }
  }
  
  List<DashboardWidget> getWidgetsByType(DashboardWidgetType type) {
    return _widgets.where((w) => w.type == type).toList();
  }
}
