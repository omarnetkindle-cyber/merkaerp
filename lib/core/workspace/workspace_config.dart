import 'package:flutter/material.dart';

import '../../features/module_definition.dart';
import '../../features/feature_key.dart';
import '../../logo_widget.dart';
import '../../ui/merka_theme_tokens.dart';

import '../../caja_page.dart';
import '../../ventas_page.dart';
import '../../compras_page.dart';
import '../../inventario_page.dart';
import '../../clientes_page.dart';
import '../../proveedores_page.dart';
import '../../contabilidad_page.dart';
import '../../cuentas_por_cobrar_page.dart';
import '../../cuentas_por_pagar_page.dart';
import '../../comprobantes_page.dart';
import '../../reportes_page.dart';
import '../../extracto_caja_page.dart';
import '../../bancos_page.dart';
import '../../presupuestos_page.dart';
import '../../cierres_caja_page.dart';
import '../../erp_readiness_page.dart';
import '../../manual_page.dart';
import '../../empresas_page.dart';
import '../../facturacion_electronica_page.dart';
import '../../recibos_page.dart';
import '../../activos_fijos_page.dart';
import '../../adjuntos_page.dart';
import '../../usuarios_page.dart';
import '../../auditoria_page.dart';
import '../../respaldos_page.dart';
import '../../licensing_page.dart';
import '../../configuracion_page.dart';
import '../../currency_config_page.dart';
import '../../webhooks_page.dart';
import '../../templates_page.dart';
import '../../commissions_page.dart';
import '../../warranties_page.dart';
import '../../crm/pages/crm_pipeline_page.dart';
import '../../crm/pages/crm_account_page.dart';
import '../../crm/pages/crm_leads_page.dart';
import '../../hrm/pages/hrm_employee_page.dart';
import '../../mrp/pages/mrp_page.dart';
import '../../impact/pages/impact_simulator_page.dart';
import '../../document_management/pages/document_management_page.dart';
import '../../integrations/pages/integrations_page.dart';
import '../../data_migration/pages/data_migration_page.dart';
import '../support/support_center_page.dart';

List<ModuleDefinition> operacion() => [
  ModuleDefinition(
    id: 'cash',
    title: 'Caja y bancos',
    icon: Icons.account_balance_wallet,
    builder: (_) => const CajaPage(),
    color: AppBrand.primary,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.cash,
    permissionLabel: 'Caja',
  ),
  ModuleDefinition(
    id: 'sales',
    title: 'Ventas',
    icon: Icons.receipt_long,
    builder: (_) => const VentasPage(),
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.pos,
  ),
  ModuleDefinition(
    id: 'purchases',
    title: 'Compras',
    icon: Icons.shopping_bag,
    builder: (_) => const ComprasPage(),
    color: MerkaThemeTokens.success,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.purchases,
  ),
  ModuleDefinition(
    id: 'inventory',
    title: 'Inventario',
    icon: Icons.inventory_2,
    builder: (_) => const InventarioPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.inventory,
  ),
  ModuleDefinition(
    id: 'clients',
    title: 'Clientes',
    icon: Icons.people,
    builder: (_) => const ClientesPage(),
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.crm,
  ),
  ModuleDefinition(
    id: 'crm_pipeline',
    title: 'CRM Pipeline',
    icon: Icons.view_kanban,
    builder: (_) => const CrmPipelinePage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.crm,
  ),
  ModuleDefinition(
    id: 'crm_accounts',
    title: 'Cuentas CRM',
    icon: Icons.business_center,
    builder: (_) => const CrmAccountsPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.crm,
  ),
  ModuleDefinition(
    id: 'crm_leads',
    title: 'Leads CRM',
    icon: Icons.person_search,
    builder: (_) => const CrmLeadsPage(),
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.crm,
  ),
  ModuleDefinition(
    id: 'suppliers',
    title: 'Proveedores',
    icon: Icons.business,
    builder: (_) => const ProveedoresPage(),
    color: MerkaThemeTokens.success,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.purchases,
  ),
];

List<ModuleDefinition> finanzas() => [
  ModuleDefinition(
    id: 'accounting',
    title: 'Contabilidad',
    icon: Icons.account_balance,
    builder: (_) => const ContabilidadPage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.accounting,
    featureKey: FeatureKey.accounting,
  ),
  ModuleDefinition(
    id: 'receivables',
    title: 'Cuentas por cobrar',
    icon: Icons.request_quote,
    builder: (_) => const CuentasPorCobrarPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.accounting,
    featureKey: FeatureKey.treasury,
  ),
  ModuleDefinition(
    id: 'payables',
    title: 'Cuentas por pagar',
    icon: Icons.payments,
    builder: (_) => const CuentasPorPagarPage(),
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.accounting,
    featureKey: FeatureKey.treasury,
  ),
  ModuleDefinition(
    id: 'vouchers',
    title: 'Comprobantes',
    icon: Icons.description,
    builder: (_) => const ComprobantesPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.accounting,
    featureKey: FeatureKey.accounting,
  ),
];

List<ModuleDefinition> control() => [
  ModuleDefinition(
    id: 'reports',
    title: 'Reportes',
    icon: Icons.bar_chart,
    builder: (_) => const ReportesPage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.control,
    featureKey: FeatureKey.reports,
  ),
  ModuleDefinition(
    id: 'cash_extract',
    title: 'Extracto caja',
    icon: Icons.receipt_long,
    builder: (_) => const ExtractoCajaPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.control,
    featureKey: FeatureKey.cash,
  ),
  ModuleDefinition(
    id: 'banks_catalog',
    title: 'Bancos',
    icon: Icons.account_balance,
    builder: (_) => const BancosPage(),
    color: MerkaThemeTokens.navy800,
    category: ModuleCategory.control,
    featureKey: FeatureKey.treasury,
  ),
  ModuleDefinition(
    id: 'budgets',
    title: 'Presupuestos',
    icon: Icons.add_chart,
    builder: (_) => const PresupuestosPage(),
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.control,
    featureKey: FeatureKey.projects,
  ),
  ModuleDefinition(
    id: 'cash_closings',
    title: 'Cierres caja',
    icon: Icons.lock_clock,
    builder: (_) => const CierresCajaPage(),
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.control,
    featureKey: FeatureKey.cash,
    permissionLabel: 'Cierres Caja',
  ),
];

List<ModuleDefinition> gestion() => [
  ModuleDefinition(
    id: 'document_management',
    title: 'Gestión documental',
    icon: Icons.folder_copy_outlined,
    builder: (_) => const DocumentManagementPage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.management,
    featureKey: FeatureKey.documents,
    permissionLabel: 'Gestión documental',
  ),
  ModuleDefinition(
    id: 'integrations',
    title: 'Integraciones',
    icon: Icons.hub_outlined,
    builder: (_) => const IntegrationsPage(),
    color: MerkaThemeTokens.success,
    category: ModuleCategory.management,
    requiresAdmin: true,
    permissionLabel: 'Config.',
  ),
  ModuleDefinition(
    id: 'impact_simulator',
    title: 'Simulador de impacto',
    icon: Icons.insights,
    builder: (_) => const ImpactSimulatorPage(),
    color: AppBrand.primary,
    category: ModuleCategory.management,
    featureKey: FeatureKey.impactSimulator,
    permissionLabel: 'Reportes',
  ),
  ModuleDefinition(
    id: 'erp_readiness',
    title: 'Centro ERP',
    icon: Icons.fact_check,
    builder: (_) => const ErpReadinessPage(),
    color: AppBrand.primary,
    category: ModuleCategory.management,
    featureKey: FeatureKey.reports,
  ),
  ModuleDefinition(
    id: 'support_center',
    title: 'Salud y soporte',
    icon: Icons.support_agent,
    builder: (_) => const SupportCenterPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
    requiresAdmin: true,
    permissionLabel: 'Config.',
  ),
  ModuleDefinition(
    id: 'manual',
    title: 'Manual',
    icon: Icons.menu_book,
    builder: (_) => const ManualPage(),
    color: AppBrand.primary,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
  ),
  ModuleDefinition(
    id: 'companies',
    title: 'Empresas',
    icon: Icons.domain_add,
    builder: (_) => const EmpresasPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
  ),
  ModuleDefinition(
    id: 'electronic_invoice',
    title: 'Facturacion',
    icon: Icons.verified,
    builder: (_) => const FacturacionElectronicaPage(),
    color: MerkaThemeTokens.success,
    category: ModuleCategory.management,
    featureKey: FeatureKey.electronicInvoice,
  ),
  ModuleDefinition(
    id: 'receipts',
    title: 'Recibos',
    icon: Icons.receipt,
    builder: (_) => const RecibosPage(),
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.management,
    featureKey: FeatureKey.documents,
  ),
  ModuleDefinition(
    id: 'hrm',
    title: 'Recursos humanos y nómina',
    icon: Icons.badge_outlined,
    builder: (_) => const HrmEmployeePage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.management,
    featureKey: FeatureKey.payroll,
  ),
  ModuleDefinition(
    id: 'mrp',
    title: 'Produccion MRP',
    icon: Icons.precision_manufacturing,
    builder: (_) => const MrpPage(),
    color: MerkaThemeTokens.warning,
    category: ModuleCategory.operation,
    featureKey: FeatureKey.production,
  ),
  ModuleDefinition(
    id: 'fixed_assets',
    title: 'Activos fijos',
    icon: Icons.factory,
    builder: (_) => const ActivosFijosPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.fixedAssets,
  ),
  ModuleDefinition(
    id: 'attachments',
    title: 'Adjuntos',
    icon: Icons.attach_file,
    builder: (_) => const AdjuntosPage(),
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.management,
    featureKey: FeatureKey.documents,
  ),
  ModuleDefinition(
    id: 'users',
    title: 'Usuarios',
    icon: Icons.security,
    builder: (_) => const UsuariosPage(),
    color: MerkaThemeTokens.graphite900,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
    requiresAdmin: true,
  ),
  ModuleDefinition(
    id: 'audit',
    title: 'Auditoria',
    icon: Icons.history,
    builder: (_) => const AuditoriaPage(),
    color: MerkaThemeTokens.graphite900,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
  ),
  ModuleDefinition(
    id: 'data_migration',
    title: 'Migración de datos',
    icon: Icons.move_down_outlined,
    builder: (_) => const DataMigrationPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
    requiresAdmin: true,
    permissionLabel: 'Config.',
  ),
  ModuleDefinition(
    id: 'backups',
    title: 'Respaldos',
    icon: Icons.backup,
    builder: (_) => const RespaldosPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.documents,
    requiresAdmin: true,
  ),
  ModuleDefinition(
    id: 'licensing',
    title: 'Licencias',
    icon: Icons.vpn_key,
    builder: (_) => const LicensingPage(),
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
    requiresAdmin: true,
  ),
  ModuleDefinition(
    id: 'settings',
    title: 'Configuracion',
    icon: Icons.settings,
    builder: (_) => const ConfiguracionPage(),
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
    requiresAdmin: true,
    permissionLabel: 'Config.',
  ),
  ModuleDefinition(
    id: 'currency_config',
    title: 'Monedas',
    icon: Icons.currency_exchange,
    builder: (_) => const CurrencyConfigPage(),
    color: MerkaThemeTokens.success,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
  ),
  ModuleDefinition(
    id: 'webhooks',
    title: 'Webhooks',
    icon: Icons.webhook,
    builder: (_) => const WebhooksPage(),
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.management,
    featureKey: FeatureKey.settings,
  ),
  ModuleDefinition(
    id: 'templates',
    title: 'Plantillas',
    icon: Icons.description,
    builder: (_) => const TemplatesPage(),
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    featureKey: FeatureKey.documents,
  ),
  ModuleDefinition(
    id: 'commissions',
    title: 'Comisiones',
    icon: Icons.payments,
    builder: (_) => const CommissionsPage(),
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.management,
    featureKey: FeatureKey.pos,
  ),
  ModuleDefinition(
    id: 'warranties',
    title: 'Garantias',
    icon: Icons.verified_user,
    builder: (_) => const WarrantiesPage(),
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.management,
    featureKey: FeatureKey.pos,
  ),
];
