import 'feature_definition.dart';
import 'feature_key.dart';

class FeatureRegistry {
  const FeatureRegistry._();

  static const definitions = <FeatureDefinition>[
    FeatureDefinition(
      key: FeatureKey.inventory,
      name: 'Inventario',
      description:
          'Productos, existencias, costos, kardex y codigos de barras.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.pos,
      name: 'POS y ventas',
      description: 'Ventas, caja de punto de venta, recibos y facturas POS.',
      defaultEnabled: true,
      dependencies: [FeatureKey.cash],
    ),
    FeatureDefinition(
      key: FeatureKey.purchases,
      name: 'Compras',
      description: 'Compras, proveedores y cuentas por pagar.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.cash,
      name: 'Caja y bancos',
      description: 'Movimientos de caja, bancos, transferencias y cierres.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.accounting,
      name: 'Contabilidad',
      description: 'Plan de cuentas, asientos, comprobantes y periodos.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.reports,
      name: 'Reportes gerenciales',
      description: 'Reportes financieros, fiscales y tableros de control.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.services,
      name: 'Servicios',
      description:
          'Operaciones donde la empresa vende horas, conceptos o servicios.',
      defaultEnabled: false,
    ),
    FeatureDefinition(
      key: FeatureKey.payroll,
      name: 'Nomina',
      description: 'Empleados y liquidaciones de nomina.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.projects,
      name: 'Proyectos',
      description: 'Control futuro de proyectos, costos y presupuestos.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.crm,
      name: 'CRM',
      description: 'Clientes, seguimiento comercial y cartera.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.production,
      name: 'Produccion',
      description: 'Procesos productivos y manufactura.',
    ),
    FeatureDefinition(
      key: FeatureKey.impactSimulator,
      name: 'Simulador de impacto',
      description: 'Escenarios locales con datos de CRM, MRP y HRM.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.multiBranch,
      name: 'Multiples sucursales',
      description: 'Operacion por sedes o puntos de atencion.',
    ),
    FeatureDefinition(
      key: FeatureKey.electronicInvoice,
      name: 'Facturacion electronica',
      description: 'Borradores, estados y preparacion para integracion legal.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.multiCurrency,
      name: 'Multimoneda',
      description: 'Configuracion para operaciones en varias monedas.',
    ),
    FeatureDefinition(
      key: FeatureKey.treasury,
      name: 'Tesoreria',
      description: 'Cuentas por cobrar, pagar, conciliacion y extractos.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.fixedAssets,
      name: 'Activos fijos',
      description: 'Registro y depreciacion de activos fijos.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.documents,
      name: 'Documentos y adjuntos',
      description: 'Adjuntos, comprobantes, recibos y respaldos.',
      defaultEnabled: true,
    ),
    FeatureDefinition(
      key: FeatureKey.settings,
      name: 'Administracion',
      description: 'Usuarios, empresas, configuracion, manual y auditoria.',
      defaultEnabled: true,
    ),
  ];

  static Map<String, bool> defaultFeatures() => {
    for (final feature in definitions) feature.key: feature.defaultEnabled,
  };

  static bool isKnown(String key) => definitions.any((item) => item.key == key);

  static List<String> dependenciesOf(String key) {
    return definitions
        .where((item) => item.key == key)
        .expand((item) => item.dependencies)
        .toList();
  }
}
