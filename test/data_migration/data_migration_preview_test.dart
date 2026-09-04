import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/data_migration/application/data_migration_service.dart';
import 'package:merka_erp/data_migration/domain/migration_catalog.dart';
import 'package:merka_erp/data_migration/domain/migration_models.dart';
import 'package:merka_erp/licensing/domain/product_family.dart';

void main() {
  final service = DataMigrationService.instance;

  test('mapeo automático reconoce alias comerciales habituales', () {
    final entity = MigrationCatalog.byKey('products');
    final mapping = service.suggestMapping(
      entity,
      ['Descripción', 'SKU', 'Código de barras', 'Existencia', 'Costo', 'Precio Venta'],
    );

    expect(mapping['name'], 'Descripción');
    expect(mapping['code'], 'SKU');
    expect(mapping['barcode'], 'Código de barras');
    expect(mapping['stock'], 'Existencia');
    expect(mapping['cost'], 'Costo');
    expect(mapping['price'], 'Precio Venta');
  });

  test('catálogo nunca expone destinos públicos a licencia comercial', () {
    final commercial = service.entitiesFor(ProductFamily.commercial);
    expect(commercial.any((item) => item.key.startsWith('public_')), isFalse);
    expect(commercial.any((item) => item.key == 'legacy_archive'), isTrue);
  });

  test('catálogo nunca expone destinos comerciales a licencia pública', () {
    final publicEntities = service.entitiesFor(ProductFamily.publicSector);
    const commercialOnly = {'customers', 'suppliers', 'products', 'ar_opening', 'ap_opening', 'accounting_opening'};
    expect(publicEntities.any((item) => commercialOnly.contains(item.key)), isFalse);
    expect(publicEntities.any((item) => item.key == 'public_accounting_opening'), isTrue);
  });

  test('presupuesto público rechaza ejecución acumulada inconsistente', () {
    final entity = MigrationCatalog.byKey('public_budget_opening');
    const dataset = TabularDataset(
      name: 'presupuesto',
      headers: [
        'Vigencia', 'Rubro', 'Nombre', 'Inicial', 'Vigente', 'CDP', 'RP', 'Obligado', 'Pagado', 'Fuente',
      ],
      rows: [
        {
          'Vigencia': '2026',
          'Rubro': '2.1.1',
          'Nombre': 'Funcionamiento',
          'Inicial': '1000000',
          'Vigente': '1000000',
          'CDP': '900000',
          'RP': '800000',
          'Obligado': '700000',
          'Pagado': '750000',
          'Fuente': 'Recursos propios',
        },
      ],
    );
    final mapping = <String, String?>{
      'year': 'Vigencia',
      'code': 'Rubro',
      'name': 'Nombre',
      'initial_value': 'Inicial',
      'current_appropriation': 'Vigente',
      'cdp_accumulated': 'CDP',
      'rp_accumulated': 'RP',
      'obligated_accumulated': 'Obligado',
      'paid_accumulated': 'Pagado',
      'funding_source': 'Fuente',
    };

    final preview = service.preview(entity: entity, dataset: dataset, mapping: mapping);

    expect(preview.validRows, 0);
    expect(preview.issues.any((issue) => issue.message.contains('Pagado ≤ Obligado')), isTrue);
  });

  test('línea contable pública no permite débito y crédito simultáneos', () {
    final entity = MigrationCatalog.byKey('public_accounting_opening');
    const dataset = TabularDataset(
      name: 'balance',
      headers: ['Vigencia', 'Cuenta', 'Débito', 'Crédito'],
      rows: [
        {'Vigencia': '2026', 'Cuenta': '1110', 'Débito': '100', 'Crédito': '100'},
      ],
    );
    final preview = service.preview(
      entity: entity,
      dataset: dataset,
      mapping: const {
        'year': 'Vigencia',
        'account_code': 'Cuenta',
        'debit': 'Débito',
        'credit': 'Crédito',
      },
    );

    expect(preview.validRows, 0);
    expect(preview.issues.any((issue) => issue.message.contains('simultáneamente')), isTrue);
  });
}
