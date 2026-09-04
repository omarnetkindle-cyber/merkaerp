// ============================================================
// cache_manager.dart
// Servicio de gestión de caché con Hive y SharedPreferences
// ============================================================

import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cache_entry.dart';

class CacheManager {
  static final CacheManager instance = CacheManager._internal();
  
  static const String _hiveBoxName = 'merka_cache';
  static const String _preferencesPrefix = 'cache_pref_';
  
  late Box<CacheEntry> _cacheBox;
  late SharedPreferences _preferences;
  
  // TTL por defecto por tipo de dato (en minutos)
  static const Map<String, int> _defaultTTL = {
    'products': 30,
    'customers': 60,
    'suppliers': 60,
    'company_config': 120,
    'user_preferences': 1440, // 24 horas
    'exchange_rates': 60,
    'reports': 15,
    'dashboard_data': 5,
  };

  CacheManager._internal();

  Future<void> initialize() async {
    await Hive.initFlutter();
    Hive.registerAdapter(CacheEntryAdapter());
    
    _cacheBox = await Hive.openBox<CacheEntry>(_hiveBoxName);
    _preferences = await SharedPreferences.getInstance();
    
    // Limpiar entradas expiradas al iniciar
    await cleanExpired();
  }

  /// Guarda un valor en caché con TTL específico
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    final cacheKey = _normalizeKey(key);
    final effectiveTtl = ttl ?? Duration(minutes: _getDefaultTTL(key));
    
    final entry = CacheEntry(
      key: cacheKey,
      value: value,
      createdAt: DateTime.now(),
      ttl: effectiveTtl,
    );
    
    await _cacheBox.put(cacheKey, entry);
  }

  /// Obtiene un valor de caché si no está expirado
  T? get<T>(String key) {
    final cacheKey = _normalizeKey(key);
    final entry = _cacheBox.get(cacheKey);
    
    if (entry == null) return null;
    if (entry.isExpired) {
      _cacheBox.delete(cacheKey);
      return null;
    }
    
    return entry.value as T?;
  }

  /// Guarda en SharedPreferences para datos simples
  Future<bool> setPref(String key, dynamic value) async {
    final prefKey = _preferencesPrefix + _normalizeKey(key);
    
    if (value is String) {
      return await _preferences.setString(prefKey, value);
    } else if (value is int) {
      return await _preferences.setInt(prefKey, value);
    } else if (value is double) {
      return await _preferences.setDouble(prefKey, value);
    } else if (value is bool) {
      return await _preferences.setBool(prefKey, value);
    } else if (value is List<String>) {
      return await _preferences.setStringList(prefKey, value);
    }
    
    return false;
  }

  /// Obtiene de SharedPreferences
  dynamic getPref(String key) {
    final prefKey = _preferencesPrefix + _normalizeKey(key);
    return _preferences.get(prefKey);
  }

  /// Invalida una entrada específica de caché
  Future<void> invalidate(String key) async {
    final cacheKey = _normalizeKey(key);
    await _cacheBox.delete(cacheKey);
  }

  /// Invalida todas las entradas que coincidan con un patrón
  Future<void> invalidatePattern(String pattern) async {
    final keys = _cacheBox.keys.where((k) => k.toString().contains(pattern));
    for (final key in keys) {
      await _cacheBox.delete(key);
    }
  }

  /// Invalida todas las entradas de caché
  Future<void> clear() async {
    await _cacheBox.clear();
  }

  /// Limpia entradas expiradas
  Future<void> cleanExpired() async {
    final keysToDelete = <dynamic>[];
    
    for (final entry in _cacheBox.values) {
      if (entry.isExpired) {
        keysToDelete.add(entry.key);
      }
    }
    
    for (final key in keysToDelete) {
      await _cacheBox.delete(key);
    }
  }

  /// Obtiene estadísticas del caché
  Map<String, dynamic> getStats() {
    final totalEntries = _cacheBox.length;
    var expiredCount = 0;
    
    for (final entry in _cacheBox.values) {
      if (entry.isExpired) expiredCount++;
    }
    
    return {
      'total_entries': totalEntries,
      'expired_entries': expiredCount,
      'active_entries': totalEntries - expiredCount,
      'box_size': _cacheBox.length,
    };
  }

  /// Normaliza la clave para uso consistente
  String _normalizeKey(String key) {
    return key.toLowerCase().trim();
  }

  /// Obtiene TTL por defecto según el tipo de dato
  int _getDefaultTTL(String key) {
    for (final entry in _defaultTTL.entries) {
      if (key.contains(entry.key)) {
        return entry.value;
      }
    }
    return 30; // 30 minutos por defecto
  }

  /// Cachea catálogo de productos
  Future<void> cacheProducts(List<Map<String, dynamic>> products) async {
    await set('products_catalog', products);
  }

  /// Obtiene catálogo de productos desde caché
  List<Map<String, dynamic>>? getCachedProducts() {
    return get<List<Map<String, dynamic>>>('products_catalog');
  }

  /// Cachea clientes frecuentes
  Future<void> cacheFrequentCustomers(List<Map<String, dynamic>> customers) async {
    await set('customers_frequent', customers);
  }

  /// Obtiene clientes frecuentes desde caché
  List<Map<String, dynamic>>? getCachedFrequentCustomers() {
    return get<List<Map<String, dynamic>>>('customers_frequent');
  }

  /// Cachea configuración de empresa
  Future<void> cacheCompanyConfig(Map<String, dynamic> config) async {
    await set('company_config', config);
  }

  /// Obtiene configuración de empresa desde caché
  Map<String, dynamic>? getCachedCompanyConfig() {
    return get<Map<String, dynamic>>('company_config');
  }

  /// Cachea tasas de cambio
  Future<void> cacheExchangeRates(Map<String, double> rates) async {
    await set('exchange_rates', rates);
  }

  /// Obtiene tasas de cambio desde caché
  Map<String, double>? getCachedExchangeRates() {
    return get<Map<String, double>>('exchange_rates');
  }

  /// Invalida caché cuando se modifican datos relevantes
  Future<void> invalidateOnDataChange(String dataType) async {
    switch (dataType.toLowerCase()) {
      case 'product':
      case 'productos':
        await invalidatePattern('products');
        break;
      case 'customer':
      case 'cliente':
      case 'clientes':
        await invalidatePattern('customers');
        break;
      case 'supplier':
      case 'proveedor':
      case 'proveedores':
        await invalidatePattern('suppliers');
        break;
      case 'company':
      case 'empresa':
        await invalidatePattern('company');
        break;
      case 'inventory':
      case 'inventario':
        await invalidatePattern('products');
        await invalidatePattern('inventory');
        break;
    }
  }

  Future<void> close() async {
    await _cacheBox.close();
  }
}
