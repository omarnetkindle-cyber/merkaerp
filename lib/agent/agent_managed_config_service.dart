import 'dart:convert';

import '../core/features/feature_flag.dart';
import '../db_helper.dart';
import '../features/company_configuration_service.dart';
import '../features/feature_registry.dart';
import 'agent_store.dart';

final class AgentManagedConfigRequestException implements Exception {
  const AgentManagedConfigRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

final class AgentManagedConfigService {
  AgentManagedConfigService({
    CompanyConfigurationService? companyConfigurationService,
    FeatureFlagService? featureFlagService,
    MerkaAgentStore? store,
    DateTime Function()? clock,
  }) : _companyConfigurationService =
           companyConfigurationService ?? CompanyConfigurationService.instance,
       _featureFlagService = featureFlagService ?? FeatureFlagService.instance,
       _store = store ?? MerkaAgentStore.instance,
       _clock = clock ?? DateTime.now;

  static final AgentManagedConfigService instance = AgentManagedConfigService();

  static const Set<String> allowedSettings = {
    'currency',
    'vat_enabled',
    'withholding_enabled',
    'default_tax',
  };

  final CompanyConfigurationService _companyConfigurationService;
  final FeatureFlagService _featureFlagService;
  final MerkaAgentStore _store;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> applyConfiguration(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {'settings', 'request_id'});
    final rawSettings = params['settings'];
    if (rawSettings is! Map || rawSettings.isEmpty) {
      throw const AgentManagedConfigRequestException(
        'INVALID_MANAGED_CONFIGURATION',
        'settings debe ser un mapa no vacío de claves permitidas',
      );
    }

    final settings = <String, String>{};
    for (final entry in rawSettings.entries) {
      final key = entry.key.toString();
      if (!allowedSettings.contains(key)) {
        throw AgentManagedConfigRequestException(
          'UNSUPPORTED_MANAGED_CONFIGURATION_KEY',
          'Clave de configuración no permitida: $key',
        );
      }
      settings[key] = _normalizeSetting(key, entry.value);
    }

    await _companyConfigurationService.updateSettings(settings);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_APLICAR_CONFIGURACION',
      entidad: 'company_settings',
      detalle: settings.keys.join(', '),
    );

    return {
      'format': 'MERKAERP_AGENT_MANAGED_CONFIG_1',
      'applied_at': _clock().toUtc().toIso8601String(),
      'applied_settings': settings.keys.toList(growable: false)..sort(),
      'sanitized': true,
    };
  }

  Future<Map<String, dynamic>> applyFeatureFlags(
    Map<String, dynamic> params,
  ) async {
    _validateParameterKeys(params, const {
      'flags',
      'business_features',
      'technical_flags',
      'from_bootstrap',
      'request_id',
    });
    await _featureFlagService.initialize();

    final parsed = await _parseFeatureFlags(params);
    if (parsed.business.isEmpty && parsed.technical.isEmpty) {
      throw const AgentManagedConfigRequestException(
        'INVALID_FEATURE_FLAGS',
        'No hay feature flags compatibles para aplicar',
      );
    }

    if (parsed.business.isNotEmpty) {
      final current = await _companyConfigurationService.loadActive();
      await _companyConfigurationService.updateFeatures({
        ...current.features,
        ...parsed.business,
      });
    }

    for (final entry in parsed.technical.entries) {
      if (entry.value) {
        await _featureFlagService.enable(entry.key);
      } else {
        await _featureFlagService.disable(entry.key);
      }
    }

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CC_APLICAR_FEATURE_FLAGS',
      entidad: 'feature_flags',
      detalle: [...parsed.business.keys, ...parsed.technical.keys].join(', '),
    );

    return {
      'format': 'MERKAERP_AGENT_FEATURE_FLAGS_1',
      'applied_at': _clock().toUtc().toIso8601String(),
      'source': parsed.source,
      'bootstrap_refreshed': false,
      'applied_business_features': parsed.business.keys.toList(growable: false)
        ..sort(),
      'applied_technical_flags': parsed.technical.keys.toList(growable: false)
        ..sort(),
      'sanitized': true,
    };
  }

  Future<_ParsedFeatureFlags> _parseFeatureFlags(
    Map<String, dynamic> params,
  ) async {
    final business = <String, bool>{};
    final technical = <String, bool>{};
    var source = 'command';

    void consumeGenericMap(dynamic raw, String errorCode) {
      if (raw == null) return;
      if (raw is! Map || raw.isEmpty) {
        throw AgentManagedConfigRequestException(
          errorCode,
          'Los feature flags deben llegar como mapa no vacío',
        );
      }
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = _parseBool(entry.value, key);
        if (FeatureRegistry.isKnown(key)) {
          business[key] = value;
        } else if (_featureFlagService.getFlag(key) != null) {
          technical[key] = value;
        } else {
          throw AgentManagedConfigRequestException(
            'UNSUPPORTED_FEATURE_FLAG',
            'Feature flag no permitida: $key',
          );
        }
      }
    }

    void consumeBusinessMap(dynamic raw) {
      if (raw == null) return;
      if (raw is! Map || raw.isEmpty) {
        throw const AgentManagedConfigRequestException(
          'INVALID_BUSINESS_FEATURES',
          'business_features debe ser un mapa no vacío',
        );
      }
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        if (!FeatureRegistry.isKnown(key)) {
          throw AgentManagedConfigRequestException(
            'UNSUPPORTED_BUSINESS_FEATURE',
            'Feature empresarial no permitida: $key',
          );
        }
        business[key] = _parseBool(entry.value, key);
      }
    }

    void consumeTechnicalMap(dynamic raw) {
      if (raw == null) return;
      if (raw is! Map || raw.isEmpty) {
        throw const AgentManagedConfigRequestException(
          'INVALID_TECHNICAL_FLAGS',
          'technical_flags debe ser un mapa no vacío',
        );
      }
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        if (_featureFlagService.getFlag(key) == null) {
          throw AgentManagedConfigRequestException(
            'UNSUPPORTED_TECHNICAL_FLAG',
            'Feature flag técnica no permitida: $key',
          );
        }
        technical[key] = _parseBool(entry.value, key);
      }
    }

    consumeGenericMap(params['flags'], 'INVALID_FEATURE_FLAGS');
    consumeBusinessMap(params['business_features']);
    consumeTechnicalMap(params['technical_flags']);

    final fromBootstrap = _parseOptionalBool(params['from_bootstrap']) == true;
    if (business.isEmpty && technical.isEmpty && fromBootstrap) {
      final bootstrap = await _readBootstrapFlags();
      consumeGenericMap(bootstrap, 'INVALID_BOOTSTRAP_FEATURE_FLAGS');
      source = 'bootstrap_v2';
    }

    return _ParsedFeatureFlags(
      business: business,
      technical: technical,
      source: source,
    );
  }

  Future<Map<String, dynamic>?> _readBootstrapFlags() async {
    final stored = await _store.readState('bootstrap_v2');
    if (stored == null || stored.trim().isEmpty) return null;
    final decoded = jsonDecode(stored);
    if (decoded is! Map) return null;
    final flags =
        decoded['feature_flags'] ??
        decoded['flags'] ??
        (decoded['config'] is Map ? decoded['config']['feature_flags'] : null);
    return flags is Map ? flags.cast<String, dynamic>() : null;
  }

  void _validateParameterKeys(
    Map<String, dynamic> params,
    Set<String> allowed,
  ) {
    final unsupported = params.keys.toSet().difference(allowed);
    if (unsupported.isNotEmpty) {
      throw AgentManagedConfigRequestException(
        'UNSUPPORTED_MANAGED_CONFIG_PARAMETER',
        'Parámetro de configuración no permitido: ${unsupported.first}',
      );
    }
  }

  String _normalizeSetting(String key, dynamic value) {
    return switch (key) {
      'currency' => _normalizeCurrency(value),
      'vat_enabled' ||
      'withholding_enabled' => _parseBool(value, key) ? '1' : '0',
      'default_tax' => _normalizePercent(value, key),
      _ => throw AgentManagedConfigRequestException(
        'UNSUPPORTED_MANAGED_CONFIGURATION_KEY',
        'Clave de configuración no permitida: $key',
      ),
    };
  }

  String _normalizeCurrency(dynamic value) {
    final currency = value?.toString().trim().toUpperCase() ?? '';
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const AgentManagedConfigRequestException(
        'INVALID_MANAGED_CONFIGURATION_VALUE',
        'currency debe ser un código ISO de tres letras',
      );
    }
    return currency;
  }

  String _normalizePercent(dynamic value, String key) {
    final text = value?.toString().trim().replaceAll(',', '.') ?? '';
    final parsed = num.tryParse(text);
    if (parsed == null || parsed < 0 || parsed > 100) {
      throw AgentManagedConfigRequestException(
        'INVALID_MANAGED_CONFIGURATION_VALUE',
        '$key debe ser un porcentaje entre 0 y 100',
      );
    }
    return parsed % 1 == 0 ? parsed.toInt().toString() : parsed.toString();
  }

  bool? _parseOptionalBool(dynamic value) {
    if (value == null) return null;
    return _parseBool(value, 'from_bootstrap');
  }

  bool _parseBool(dynamic value, String key) {
    if (value is bool) return value;
    if (value is num) {
      if (value == 1) return true;
      if (value == 0) return false;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    throw AgentManagedConfigRequestException(
      'INVALID_BOOLEAN_VALUE',
      '$key debe ser booleano',
    );
  }
}

final class _ParsedFeatureFlags {
  const _ParsedFeatureFlags({
    required this.business,
    required this.technical,
    required this.source,
  });

  final Map<String, bool> business;
  final Map<String, bool> technical;
  final String source;
}
