import '../security/action_permission.dart';

enum ApiMethod { get, post, put, delete }

class ApiEndpoint {
  const ApiEndpoint({
    required this.method,
    required this.path,
    required this.module,
    required this.action,
    required this.description,
    this.featureKey,
  });

  final ApiMethod method;
  final String path;
  final String module;
  final AppAction action;
  final String description;
  final String? featureKey;
}

class ApiContract {
  const ApiContract._();

  static const version = 'v1';

  static const endpoints = <ApiEndpoint>[
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/companies',
      module: 'companies',
      action: AppAction.view,
      description: 'Lista empresas disponibles para el usuario autenticado.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/products',
      module: 'inventory',
      action: AppAction.view,
      description: 'Lista productos filtrados por empresa activa.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/sales',
      module: 'sales',
      action: AppAction.view,
      description: 'Lista ventas filtradas por empresa activa.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/sales',
      module: 'sales',
      action: AppAction.create,
      description: 'Crea una factura POS con detalle, impuestos y asiento.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/sales/documents',
      module: 'sales',
      action: AppAction.view,
      description:
          'Lista documentos comerciales enterprise por alcance activo.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/sales/documents',
      module: 'sales',
      action: AppAction.create,
      description:
          'Crea cotizaciones, pedidos, facturas, POS, notas y devoluciones.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/sales/documents/post',
      module: 'sales',
      action: AppAction.post,
      description: 'Aprueba y contabiliza un documento comercial inmutable.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/sales/documents/reverse',
      module: 'sales',
      action: AppAction.reverse,
      description:
          'Reversa un documento posted mediante nota credito trazable.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/sales/analytics',
      module: 'sales',
      action: AppAction.view,
      description: 'Expone analitica comercial por empresa, sucursal y bodega.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/purchases',
      module: 'purchases',
      action: AppAction.view,
      description: 'Lista compras filtradas por empresa activa.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases',
      module: 'purchases',
      action: AppAction.create,
      description: 'Crea una compra con inventario, pago, CXP y asiento.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/purchases/documents',
      module: 'purchases',
      action: AppAction.view,
      description: 'Lista documentos enterprise de abastecimiento por alcance.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases/documents',
      module: 'purchases',
      action: AppAction.create,
      description:
          'Crea solicitudes, RFQ, ordenes, recepciones y facturas proveedor.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases/documents/approve',
      module: 'purchases',
      action: AppAction.approve,
      description: 'Ejecuta aprobacion multinivel con SLA y escalamiento.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases/documents/receive',
      module: 'purchases',
      action: AppAction.receive,
      description: 'Registra recepcion parcial o total warehouse-aware.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases/documents/post',
      module: 'purchases',
      action: AppAction.post,
      description: 'Postea factura proveedor, CXP, contabilidad e impuestos.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/purchases/documents/reverse',
      module: 'purchases',
      action: AppAction.reverse,
      description:
          'Reversa documento posted con trazabilidad y saldo proveedor.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/purchases/analytics',
      module: 'purchases',
      action: AppAction.view,
      description:
          'Expone analitica de compras, aprobaciones, impuestos y forecast CXP.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/accounting/trial-balance',
      module: 'accounting',
      action: AppAction.view,
      description: 'Obtiene balance de comprobacion por empresa.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/ar/ledger',
      module: 'accounts_receivable',
      action: AppAction.view,
      description: 'Consulta ledger de clientes, aplicaciones y saldos.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/ar/aging',
      module: 'accounts_receivable',
      action: AppAction.view,
      description: 'Calcula aging de cartera por alcance activo.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/ar/collect',
      module: 'accounts_receivable',
      action: AppAction.collect,
      description: 'Aplica recaudos parciales y liquida saldo de facturas.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/ar/payment-promises',
      module: 'accounts_receivable',
      action: AppAction.collect,
      description: 'Registra promesas de pago y gestion de cobranza.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/ar/credit-limit',
      module: 'accounts_receivable',
      action: AppAction.overrideLimit,
      description: 'Actualiza limite, riesgo y bloqueo de cliente.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/ap/ledger',
      module: 'accounts_payable',
      action: AppAction.view,
      description: 'Consulta ledger proveedor y liquidaciones parciales.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/ap/aging',
      module: 'accounts_payable',
      action: AppAction.view,
      description: 'Calcula aging de cuentas por pagar.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/ap/schedule-payment',
      module: 'accounts_payable',
      action: AppAction.schedulePayment,
      description: 'Programa pagos y forecast de tesoreria.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/ap/pay',
      module: 'accounts_payable',
      action: AppAction.approvePayment,
      description: 'Registra pago parcial o total a proveedor.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/treasury/dashboard',
      module: 'treasury',
      action: AppAction.view,
      description: 'Expone posicion de tesoreria y flujo proyectado.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/treasury/bank-accounts',
      module: 'treasury',
      action: AppAction.transfer,
      description: 'Crea cuentas bancarias operativas.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/treasury/transfers',
      module: 'treasury',
      action: AppAction.transfer,
      description: 'Registra transferencias y movimientos bancarios.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/bank/statements/import',
      module: 'bank_reconciliation',
      action: AppAction.reconcile,
      description: 'Importa extractos bancarios para conciliacion.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/bank/reconcile',
      module: 'bank_reconciliation',
      action: AppAction.reconcile,
      description: 'Ejecuta conciliacion automatica por referencia y monto.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/bank/unmatched',
      module: 'bank_reconciliation',
      action: AppAction.view,
      description: 'Lista operaciones bancarias no conciliadas.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/tax/rules',
      module: 'tax',
      action: AppAction.configure,
      description: 'Configura reglas tributarias tenant y pais-aware.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/tax/calculate',
      module: 'tax',
      action: AppAction.view,
      description: 'Calcula impuestos y retenciones por documento.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/assets/register',
      module: 'fixed_assets',
      action: AppAction.view,
      description: 'Consulta registro de activos fijos.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/assets/register',
      module: 'fixed_assets',
      action: AppAction.create,
      description: 'Registra activos, vida util y base depreciable.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/assets/depreciate',
      module: 'fixed_assets',
      action: AppAction.depreciate,
      description: 'Ejecuta depreciacion contable y fiscal.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/crm/pipeline',
      module: 'crm',
      action: AppAction.view,
      description: 'Consulta pipeline, funnel y proximos seguimientos.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/crm/opportunities',
      module: 'crm',
      action: AppAction.managePipeline,
      description: 'Gestiona oportunidades, timeline y notificaciones.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/reports/definitions',
      module: 'reports',
      action: AppAction.configure,
      description: 'Define reportes con filtros dinamicos y formatos.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/reports/generate',
      module: 'reports',
      action: AppAction.export,
      description: 'Genera reportes PDF, Excel, JSON y BI-ready.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/reports/materialized',
      module: 'reports',
      action: AppAction.view,
      description: 'Consulta reportes materializados por tenant y sucursal.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/reports/summary',
      module: 'reports',
      action: AppAction.view,
      description: 'Obtiene resumen operativo de inventario, ventas y compras.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/reports/tax',
      module: 'reports',
      action: AppAction.view,
      description: 'Obtiene reporte fiscal por periodo.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/system/readiness',
      module: 'settings',
      action: AppAction.view,
      description: 'Evalua preparacion para piloto, release y produccion.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/system/data-health',
      module: 'audit',
      action: AppAction.view,
      description: 'Audita inconsistencias operativas, contables e inventario.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/security/permissions',
      module: 'users',
      action: AppAction.view,
      description: 'Expone matriz de permisos y acciones sensibles.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/procurement/workflow',
      module: 'purchases',
      action: AppAction.view,
      description: 'Describe el flujo completo de abastecimiento empresarial.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/sales/workflow',
      module: 'sales',
      action: AppAction.view,
      description:
          'Describe el ciclo comercial desde cotizacion hasta recaudo.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/inventory/replenishment',
      module: 'inventory',
      action: AppAction.view,
      description: 'Sugiere reposicion y valora inventario activo.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/platform/scope',
      module: 'settings',
      action: AppAction.view,
      description: 'Devuelve empresa, sucursal, bodega y centro de costo.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/sync/status',
      module: 'sync',
      action: AppAction.view,
      description: 'Devuelve estado offline-first, outbox, inbox y conflictos.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/licensing/status',
      module: 'licensing',
      action: AppAction.view,
      description: 'Evalua licencia SaaS, plan, limites y modulos activos.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/telemetry/health',
      module: 'telemetry',
      action: AppAction.view,
      description: 'Expone health checks y diagnostico remoto local.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/workflows/templates',
      module: 'workflows',
      action: AppAction.view,
      description: 'Lista plantillas de aprobacion y automatizacion.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/rules/evaluate',
      module: 'rules',
      action: AppAction.view,
      description: 'Evalua reglas configurables contra un contexto enviado.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/events',
      module: 'events',
      action: AppAction.view,
      description: 'Consulta event store persistente con orden global.',
    ),
    ApiEndpoint(
      method: ApiMethod.post,
      path: '/api/v1/events/replay',
      module: 'events',
      action: AppAction.create,
      description: 'Reprocesa cola de eventos y actualiza proyecciones CQRS.',
    ),
    ApiEndpoint(
      method: ApiMethod.get,
      path: '/api/v1/cqrs/executive-dashboard',
      module: 'reports',
      action: AppAction.view,
      description: 'Consulta read model materializado del dashboard ejecutivo.',
    ),
  ];

  static ApiEndpoint? match(ApiMethod method, String path) {
    for (final endpoint in endpoints) {
      if (endpoint.method == method && endpoint.path == path) {
        return endpoint;
      }
    }
    return null;
  }
}
