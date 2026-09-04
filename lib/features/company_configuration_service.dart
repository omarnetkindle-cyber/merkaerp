import '../db_helper.dart';
import '../models/company.dart';
import '../models/company_profile.dart';
import '../models/company_template.dart';
import 'feature_registry.dart';
import 'feature_key.dart';
import '../licensing/domain/product_family.dart';
import '../services/licencia_service.dart';

class CompanyConfiguration {
  const CompanyConfiguration({
    required this.companyId,
    required this.companyName,
    required this.features,
    required this.settings,
    required this.onboardingCompleted,
  });

  final int companyId;
  final String companyName;
  final Map<String, bool> features;
  final Map<String, String> settings;
  final bool onboardingCompleted;
}

class CompanyConfigurationService {
  CompanyConfigurationService._();

  static final CompanyConfigurationService instance =
      CompanyConfigurationService._();

  CompanyConfiguration? _cache;

  CompanyConfiguration? get cached => _cache;

  void resetForTests() {
    _cache = null;
  }

  Future<CompanyConfiguration> loadActive({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    final config = await DatabaseHelper.instance.obtenerConfiguracionActiva();
    final licensedFeatures = await _normalizeForLicensedProduct(config.features);
    _cache = CompanyConfiguration(
      companyId: config.companyId,
      companyName: config.companyName,
      features: licensedFeatures,
      settings: config.settings,
      onboardingCompleted: config.onboardingCompleted,
    );
    return _cache!;
  }

  Future<bool> needsOnboarding() async {
    final config = await loadActive(force: true);
    return !config.onboardingCompleted;
  }

  bool featureEnabledSync(String key) {
    final features = _cache?.features ?? FeatureRegistry.defaultFeatures();
    return features[key] ?? false;
  }

  Future<bool> featureEnabled(String key) async {
    final config = await loadActive();
    return config.features[key] ?? false;
  }

  Future<void> saveOnboarding({
    required Company company,
    required CompanyProfile profile,
    required Map<String, bool> features,
    required Map<String, String> settings,
    CompanyTemplate? template,
  }) async {
    final normalizedFeatures = await _normalizeForLicensedProduct(features);
    final normalizedSettings = normalizeSettings(
      settings,
      templateSettings: template?.settings,
      templateId: template?.id,
      templateName: template?.name,
    );
    await DatabaseHelper.instance.guardarConfiguracionInicial(
      company: company,
      profile: profile,
      features: normalizedFeatures,
      settings: normalizedSettings,
    );
    await loadActive(force: true);
    await DatabaseHelper.instance.aplicarCatalogoInicial(
      baseCatalog: template?.baseCatalog ?? const [],
      features: normalizedFeatures,
      settings: normalizedSettings,
    );
    await loadActive(force: true);
  }

  Future<void> updateFeatures(Map<String, bool> features) async {
    final config = await loadActive();
    await DatabaseHelper.instance.guardarCompanyFeatures(
      config.companyId,
      await _normalizeForLicensedProduct(features),
    );
    await loadActive(force: true);
  }

  Future<void> updateSettings(Map<String, String> settings) async {
    final config = await loadActive();
    await DatabaseHelper.instance.guardarCompanySettings(
      config.companyId,
      normalizeSettings(settings),
    );
    await loadActive(force: true);
  }

  Future<Map<String, bool>> _normalizeForLicensedProduct(Map<String, bool> features) async {
    final normalized = normalizeFeatures(features);
    final license = await LicenciaService.instance.obtenerLicencia();
    final family = license?.productFamily ?? ProductFamily.commercial;
    return enforceProductFamily(normalized, family);
  }

  static const Set<String> _commercialOnlyFeatures = {
    FeatureKey.inventory,
    FeatureKey.pos,
    FeatureKey.payroll,
    FeatureKey.projects,
    FeatureKey.crm,
    FeatureKey.production,
    FeatureKey.impactSimulator,
    FeatureKey.multiBranch,
    FeatureKey.electronicInvoice,
    FeatureKey.multiCurrency,
    FeatureKey.services,
    FeatureKey.accounting,
    FeatureKey.purchases,
    FeatureKey.cash,
    FeatureKey.reports,
    FeatureKey.treasury,
    FeatureKey.fixedAssets,
    FeatureKey.documents,
  };

  static const Set<String> _publicOnlyFeatures = {
    FeatureKey.presupuesto_publico,
    FeatureKey.contabilidad_nicsp,
    FeatureKey.contratacion_publica,
    FeatureKey.nomina_publica,
    FeatureKey.auditoria_forense,
    FeatureKey.predial,
    FeatureKey.rentas_departamentales,
    FeatureKey.planeacion,
    FeatureKey.activos_estado,
    FeatureKey.salud_publica,
    FeatureKey.sgp,
    FeatureKey.transparencia,
    FeatureKey.consolidacion_nicsp_40,
  };

  /// Pure family boundary used by configuration, onboarding and tests.
  /// The signed license decides which product family may remain enabled.
  static Map<String, bool> enforceProductFamily(
    Map<String, bool> features,
    ProductFamily family,
  ) {
    final result = Map<String, bool>.from(features);
    final forbidden = family == ProductFamily.publicSector
        ? _commercialOnlyFeatures
        : _publicOnlyFeatures;
    for (final key in forbidden) {
      result[key] = false;
    }
    result[FeatureKey.settings] = true;
    return result;
  }

  static Map<String, bool> normalizeFeatures(Map<String, bool> features) {
    final result = {...FeatureRegistry.defaultFeatures(), ...features};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in result.entries.toList()) {
        if (!entry.value) continue;
        for (final dependency in FeatureRegistry.dependenciesOf(entry.key)) {
          if (result[dependency] != true) {
            result[dependency] = true;
            changed = true;
          }
        }
      }
    }
    return result;
  }

  static Map<String, String> normalizeSettings(
    Map<String, String> settings, {
    Map<String, String>? templateSettings,
    String? templateId,
    String? templateName,
  }) {
    final merged = <String, String>{
      if (templateSettings != null) ...templateSettings,
      ...settings,
    };
    if (settings['vat_enabled'] == '0') {
      merged['default_tax'] = '0';
    }
    if (templateId != null) {
      merged['template_id'] = templateId;
    }
    if (templateName != null) {
      merged['template_name'] = templateName;
    }
    return merged;
  }
}
