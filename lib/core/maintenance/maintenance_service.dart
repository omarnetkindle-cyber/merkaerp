// ============================================================
// maintenance_service.dart
// Servicio de modo mantenimiento
// ============================================================

import 'package:shared_preferences/shared_preferences.dart';

class MaintenanceService {
  static final MaintenanceService instance = MaintenanceService._internal();
  
  static const String _maintenanceKey = 'maintenance_mode';
  static const String _maintenanceMessageKey = 'maintenance_message';
  static const String _maintenanceStartTimeKey = 'maintenance_start_time';
  static const String _scheduledMaintenanceKey = 'scheduled_maintenance';
  
  MaintenanceService._internal();
  
  /// Verifica si el modo mantenimiento está activo
  Future<bool> isMaintenanceMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_maintenanceKey) ?? false;
  }
  
  /// Activa el modo mantenimiento
  Future<void> enableMaintenanceMode({String? message}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_maintenanceKey, true);
    await prefs.setString(_maintenanceMessageKey, message ?? 'Sistema en mantenimiento. Por favor intente más tarde.');
    await prefs.setString(_maintenanceStartTimeKey, DateTime.now().toIso8601String());
  }
  
  /// Desactiva el modo mantenimiento
  Future<void> disableMaintenanceMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_maintenanceKey, false);
    await prefs.remove(_maintenanceMessageKey);
    await prefs.remove(_maintenanceStartTimeKey);
  }
  
  /// Obtiene el mensaje de mantenimiento
  Future<String> getMaintenanceMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_maintenanceMessageKey) ?? 'Sistema en mantenimiento.';
  }
  
  /// Obtiene la hora de inicio del mantenimiento
  Future<DateTime?> getMaintenanceStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final startTime = prefs.getString(_maintenanceStartTimeKey);
    if (startTime == null) return null;
    return DateTime.parse(startTime);
  }
  
  /// Programa un mantenimiento futuro
  Future<void> scheduleMaintenance(DateTime scheduledTime, {String? message}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduledMaintenanceKey, scheduledTime.toIso8601String());
    if (message != null) {
      await prefs.setString('${_scheduledMaintenanceKey}_message', message);
    }
  }
  
  /// Obtiene el mantenimiento programado
  Future<DateTime?> getScheduledMaintenance() async {
    final prefs = await SharedPreferences.getInstance();
    final scheduledTime = prefs.getString(_scheduledMaintenanceKey);
    if (scheduledTime == null) return null;
    return DateTime.parse(scheduledTime);
  }
  
  /// Obtiene el mensaje del mantenimiento programado
  Future<String?> getScheduledMaintenanceMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_scheduledMaintenanceKey}_message');
  }
  
  /// Cancela el mantenimiento programado
  Future<void> cancelScheduledMaintenance() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scheduledMaintenanceKey);
    await prefs.remove('${_scheduledMaintenanceKey}_message');
  }
  
  /// Verifica si hay un mantenimiento programado que debería activarse
  Future<bool> shouldActivateMaintenance() async {
    final scheduled = await getScheduledMaintenance();
    if (scheduled == null) return false;
    
    return DateTime.now().isAfter(scheduled);
  }
  
  /// Activa automáticamente el mantenimiento si está programado
  Future<bool> autoActivateMaintenance() async {
    if (await shouldActivateMaintenance()) {
      final message = await getScheduledMaintenanceMessage();
      await enableMaintenanceMode(message: message);
      await cancelScheduledMaintenance();
      return true;
    }
    return false;
  }
  
  /// Obtiene información del estado de mantenimiento
  Future<Map<String, dynamic>> getMaintenanceStatus() async {
    final isActive = await isMaintenanceMode();
    final startTime = await getMaintenanceStartTime();
    final scheduled = await getScheduledMaintenance();
    final scheduledMessage = await getScheduledMaintenanceMessage();
    
    return {
      'is_active': isActive,
      'message': isActive ? await getMaintenanceMessage() : null,
      'start_time': startTime?.toIso8601String(),
      'scheduled_time': scheduled?.toIso8601String(),
      'scheduled_message': scheduledMessage,
      'duration': startTime != null ? DateTime.now().difference(startTime).inMinutes : 0,
    };
  }
  
  /// Lista blanca de usuarios que pueden acceder durante mantenimiento
  Future<void> addWhitelistedUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final whitelist = prefs.getStringList('maintenance_whitelist') ?? [];
    if (!whitelist.contains(userId)) {
      whitelist.add(userId);
      await prefs.setStringList('maintenance_whitelist', whitelist);
    }
  }
  
  /// Remueve usuario de lista blanca
  Future<void> removeWhitelistedUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final whitelist = prefs.getStringList('maintenance_whitelist') ?? [];
    whitelist.remove(userId);
    await prefs.setStringList('maintenance_whitelist', whitelist);
  }
  
  /// Verifica si un usuario está en lista blanca
  Future<bool> isUserWhitelisted(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final whitelist = prefs.getStringList('maintenance_whitelist') ?? [];
    return whitelist.contains(userId);
  }
  
  /// Obtiene todos los usuarios en lista blanca
  Future<List<String>> getWhitelistedUsers() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('maintenance_whitelist') ?? [];
  }
  
  /// Limpia la lista blanca
  Future<void> clearWhitelist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('maintenance_whitelist');
  }
}
