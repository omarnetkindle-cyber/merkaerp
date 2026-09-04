import '../../db_helper.dart';
import '../../features/company_configuration_service.dart';
import '../domain/master_catalog.dart';

class CatalogService {
  CatalogService._();

  static final CatalogService instance = CatalogService._();

  Future<List<TaxOption>> taxOptionsForActiveCompany() async {
    final config = await CompanyConfigurationService.instance.loadActive();
    final rows = await DatabaseHelper.instance.obtenerCatalogoImpuestos();
    final persisted = rows.map(_taxFromMap).toList();
    return taxOptionsFromSettings(
      config.settings,
      baseTaxes: persisted.isEmpty ? MasterCatalog.taxes : persisted,
    );
  }

  List<TaxOption> taxOptionsFromSettings(
    Map<String, String> settings, {
    List<TaxOption> baseTaxes = MasterCatalog.taxes,
  }) {
    final vatEnabled = settings['vat_enabled'] != '0';
    if (!vatEnabled) {
      return [
        baseTaxes.firstWhere(
          (tax) => tax.rate == 0,
          orElse: () => MasterCatalog.taxes.first,
        ),
      ];
    }

    final configuredDefault =
        double.tryParse(settings['default_tax']?.replaceAll(',', '.') ?? '') ??
        0;
    final taxes = [...baseTaxes];
    final hasConfigured = taxes.any((tax) => tax.rate == configuredDefault);
    if (!hasConfigured) {
      taxes.add(
        TaxOption(
          code: 'CUSTOM_$configuredDefault',
          label: 'Impuesto $configuredDefault%',
          rate: configuredDefault,
        ),
      );
    }
    taxes.sort((a, b) {
      if (a.rate == configuredDefault) return -1;
      if (b.rate == configuredDefault) return 1;
      return a.rate.compareTo(b.rate);
    });
    return taxes;
  }

  List<UnitOption> unitOptions() => MasterCatalog.units;

  Future<List<UnitOption>> unitOptionsForActiveCompany() async {
    final rows = await DatabaseHelper.instance.obtenerCatalogoUnidades();
    if (rows.isEmpty) return MasterCatalog.units;
    return rows.map(_unitFromMap).toList();
  }

  List<PaymentMethodOption> paymentMethods() => MasterCatalog.paymentMethods;

  List<NiifAccountOption> niifAccounts() => MasterCatalog.niifAccounts;

  Future<Map<String, String>> accountingRulesForActiveCompany() async {
    return await DatabaseHelper.instance.obtenerReglasContablesEmpresa();
  }

  TaxOption _taxFromMap(Map<String, dynamic> map) {
    return TaxOption(
      code: map['code']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      rate: (map['rate'] as num?)?.toDouble() ?? 0,
      sales: ((map['sales_enabled'] as num?)?.toInt() ?? 1) == 1,
      purchases: ((map['purchases_enabled'] as num?)?.toInt() ?? 1) == 1,
    );
  }

  UnitOption _unitFromMap(Map<String, dynamic> map) {
    return UnitOption(
      code: map['code']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
    );
  }
}
