import 'package:merka_erp/features/company_configuration_service.dart';
import 'package:merka_erp/features/feature_key.dart';
import 'package:merka_erp/licensing/domain/product_family.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompanyConfigurationService', () {
    test('normaliza dependencias de capacidades habilitadas', () {
      final features = CompanyConfigurationService.normalizeFeatures({
        FeatureKey.pos: true,
        FeatureKey.cash: false,
      });

      expect(features[FeatureKey.pos], isTrue);
      expect(features[FeatureKey.cash], isTrue);
    });

    test('normaliza ajustes mezclando plantilla y datos de empresa', () {
      final settings = CompanyConfigurationService.normalizeSettings(
        {'currency': 'COP', 'default_tax': '8', 'vat_enabled': '1'},
        templateSettings: {
          'currency': 'USD',
          'default_tax': '19',
          'receipt_format': 'pos',
        },
        templateId: 'retail',
        templateName: 'Retail',
      );

      expect(settings['currency'], 'COP');
      expect(settings['default_tax'], '8');
      expect(settings['receipt_format'], 'pos');
      expect(settings['template_id'], 'retail');
      expect(settings['template_name'], 'Retail');
    });

    test('deshabilitar un módulo dependiente no apaga una capacidad base independiente', () {
      final features = CompanyConfigurationService.normalizeFeatures({
        FeatureKey.pos: false,
        FeatureKey.cash: true,
      });

      expect(features[FeatureKey.pos], isFalse);
      expect(features[FeatureKey.cash], isTrue);
    });

    test('la licencia pública fuerza apagadas las capacidades comerciales', () {
      final features = CompanyConfigurationService.enforceProductFamily({
        FeatureKey.pos: true,
        FeatureKey.accounting: true,
        FeatureKey.presupuesto_publico: true,
      }, ProductFamily.publicSector);

      expect(features[FeatureKey.pos], isFalse);
      expect(features[FeatureKey.accounting], isFalse);
      expect(features[FeatureKey.presupuesto_publico], isTrue);
      expect(features[FeatureKey.settings], isTrue);
    });

    test('la licencia comercial fuerza apagadas las capacidades públicas', () {
      final features = CompanyConfigurationService.enforceProductFamily({
        FeatureKey.pos: true,
        FeatureKey.presupuesto_publico: true,
        FeatureKey.contratacion_publica: true,
      }, ProductFamily.commercial);

      expect(features[FeatureKey.pos], isTrue);
      expect(features[FeatureKey.presupuesto_publico], isFalse);
      expect(features[FeatureKey.contratacion_publica], isFalse);
    });

    test('normaliza impuesto predeterminado cuando IVA esta deshabilitado', () {
      final settings = CompanyConfigurationService.normalizeSettings({
        'vat_enabled': '0',
        'default_tax': '19',
      });

      expect(settings['default_tax'], '0');
    });
  });
}
