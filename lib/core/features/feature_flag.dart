// ============================================================
// feature_flag.dart
// Sistema de feature flags para activación progresiva
// ============================================================

import 'package:shared_preferences/shared_preferences.dart';

class FeatureFlag {
  final String key;
  final String name;
  final String description;
  final bool defaultValue;
  final bool requiresRemoteConfig;
  final String category;

  FeatureFlag({
    required this.key,
    required this.name,
    required this.description,
    this.defaultValue = false,
    this.requiresRemoteConfig = false,
    this.category = 'general',
  });

  FeatureFlag copyWith({
    String? key,
    String? name,
    String? description,
    bool? defaultValue,
    bool? requiresRemoteConfig,
    String? category,
  }) {
    return FeatureFlag(
      key: key ?? this.key,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultValue: defaultValue ?? this.defaultValue,
      requiresRemoteConfig: requiresRemoteConfig ?? this.requiresRemoteConfig,
      category: category ?? this.category,
    );
  }
}

class FeatureFlagService {
  static final FeatureFlagService instance = FeatureFlagService._internal();
  
  static const String _prefix = 'feature_flag_';
  
  final Map<String, FeatureFlag> _flags = {};
  final Map<String, bool> _remoteOverrides = {};
  
  FeatureFlagService._internal();
  
  /// Inicializa el servicio con las flags predefinidas
  Future<void> initialize() async {
    _registerDefaultFlags();
    await _loadLocalOverrides();
  }
  
  /// Registra las flags por defecto
  void _registerDefaultFlags() {
    // Seguridad
    _registerFlag(FeatureFlag(
      key: 'biometric_auth',
      name: 'Autenticación Biométrica',
      description: 'Permite autenticación con huella digital o Face ID',
      defaultValue: true,
      category: 'security',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'mfa_required',
      name: 'MFA Requerido',
      description: 'Requiere autenticación de dos factores',
      defaultValue: false,
      category: 'security',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'database_encryption',
      name: 'Cifrado de Base de Datos',
      description: 'Cifra la base de datos con AES-256',
      defaultValue: false,
      category: 'security',
    ));
    
    // Inventario
    _registerFlag(FeatureFlag(
      key: 'inventory_lots',
      name: 'Gestión de Lotes',
      description: 'Habilita gestión de lotes y fechas de vencimiento',
      defaultValue: true,
      category: 'inventory',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'barcode_scanner',
      name: 'Escáner de Códigos',
      description: 'Habilita escaneo de códigos de barras y QR',
      defaultValue: true,
      category: 'inventory',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'inventory_reservations',
      name: 'Reservas de Inventario',
      description: 'Habilita sistema de reservas de stock',
      defaultValue: true,
      category: 'inventory',
    ));
    
    // Ventas
    _registerFlag(FeatureFlag(
      key: 'orders_system',
      name: 'Sistema de Pedidos',
      description: 'Habilita gestión de pedidos/pre-ventas',
      defaultValue: true,
      category: 'sales',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'quotes_system',
      name: 'Sistema de Cotizaciones',
      description: 'Habilita gestión de presupuestos y cotizaciones',
      defaultValue: true,
      category: 'sales',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'multi_currency',
      name: 'Multi-Moneda',
      description: 'Habilita transacciones en múltiples monedas',
      defaultValue: false,
      category: 'sales',
    ));
    
    // CRM
    _registerFlag(FeatureFlag(
      key: 'crm_enabled',
      name: 'CRM Habilitado',
      description: 'Habilita módulo de gestión de relaciones con clientes',
      defaultValue: true,
      category: 'crm',
    ));
    
    // UI/UX
    _registerFlag(FeatureFlag(
      key: 'dark_mode',
      name: 'Modo Oscuro',
      description: 'Habilita tema oscuro de la aplicación',
      defaultValue: true,
      category: 'ui',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'customizable_dashboard',
      name: 'Dashboard Personalizable',
      description: 'Permite personalizar el dashboard con widgets',
      defaultValue: true,
      category: 'ui',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'accessibility_features',
      name: 'Características de Accesibilidad',
      description: 'Habilita opciones de accesibilidad',
      defaultValue: true,
      category: 'ui',
    ));
    
    // API
    _registerFlag(FeatureFlag(
      key: 'rest_api_enabled',
      name: 'API REST Habilitada',
      description: 'Habilita endpoints de API REST',
      defaultValue: true,
      category: 'api',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'webhooks_enabled',
      name: 'Webhooks Habilitados',
      description: 'Habilita sistema de webhooks',
      defaultValue: true,
      category: 'api',
    ));
    
    // Exportación
    _registerFlag(FeatureFlag(
      key: 'export_xml',
      name: 'Exportación XML',
      description: 'Habilita exportación a formato XML DIAN',
      defaultValue: true,
      category: 'export',
    ));
    
    _registerFlag(FeatureFlag(
      key: 'export_excel',
      name: 'Exportación Excel',
      description: 'Habilita exportación a formato Excel',
      defaultValue: true,
      category: 'export',
    ));
  }
  
  /// Registra una nueva flag
  void _registerFlag(FeatureFlag flag) {
    _flags[flag.key] = flag;
  }
  
  /// Carga los overrides locales desde SharedPreferences
  Future<void> _loadLocalOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    
    for (final flag in _flags.values) {
      final key = _prefix + flag.key;
      final value = prefs.getBool(key);
      if (value != null) {
        _remoteOverrides[flag.key] = value;
      }
    }
  }
  
  /// Verifica si una flag está habilitada
  bool isEnabled(String key) {
    final flag = _flags[key];
    if (flag == null) return false;
    
    // Prioridad: override remoto > valor local > valor por defecto
    if (_remoteOverrides.containsKey(key)) {
      return _remoteOverrides[key]!;
    }
    
    return flag.defaultValue;
  }
  
  /// Habilita una flag localmente
  Future<void> enable(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefix + key, true);
    _remoteOverrides[key] = true;
  }
  
  /// Deshabilita una flag localmente
  Future<void> disable(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefix + key, false);
    _remoteOverrides[key] = false;
  }
  
  /// Restablece una flag a su valor por defecto
  Future<void> reset(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefix + key);
    _remoteOverrides.remove(key);
  }
  
  /// Actualiza flags desde configuración remota
  void updateFromRemoteConfig(Map<String, bool> remoteFlags) {
    _remoteOverrides.clear();
    _remoteOverrides.addAll(remoteFlags);
  }
  
  /// Obtiene todas las flags
  List<FeatureFlag> getAllFlags() {
    return _flags.values.toList();
  }
  
  /// Obtiene flags por categoría
  List<FeatureFlag> getFlagsByCategory(String category) {
    return _flags.values.where((flag) => flag.category == category).toList();
  }
  
  /// Obtiene el estado de todas las flags
  Map<String, bool> getAllFlagsStatus() {
    final result = <String, bool>{};
    
    for (final flag in _flags.values) {
      result[flag.key] = isEnabled(flag.key);
    }
    
    return result;
  }
  
  /// Obtiene una flag específica
  FeatureFlag? getFlag(String key) {
    return _flags[key];
  }
  
  /// Habilita todas las flags de una categoría
  Future<void> enableCategory(String category) async {
    final flags = getFlagsByCategory(category);
    for (final flag in flags) {
      await enable(flag.key);
    }
  }
  
  /// Deshabilita todas las flags de una categoría
  Future<void> disableCategory(String category) async {
    final flags = getFlagsByCategory(category);
    for (final flag in flags) {
      await disable(flag.key);
    }
  }
  
  /// Restablece todas las flags a sus valores por defecto
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    
    for (final flag in _flags.values) {
      await prefs.remove(_prefix + flag.key);
    }
    
    _remoteOverrides.clear();
  }
}
