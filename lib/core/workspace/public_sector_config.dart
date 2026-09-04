import 'package:flutter/material.dart';

import '../../ui/merka_theme_tokens.dart';

import '../../app_session.dart';
import '../../features/module_definition.dart';
import '../../features/feature_key.dart';

import '../../sector_publico/presupuesto/pages/presupuesto_publico_page.dart';
import '../../sector_publico/presupuesto/pages/pac_tesoreria_page.dart';
import '../../sector_publico/contabilidad/pages/contabilidad_nicsp_page.dart';
import '../../sector_publico/contratacion/pages/contratacion_publica_page.dart';
import '../../sector_publico/contratacion/pages/supervision_contractual_page.dart';
import '../../sector_publico/contabilidad/pages/provisiones_nicsp_page.dart';
import '../../sector_publico/nomina/pages/nomina_publica_page.dart';
import '../../sector_publico/rentas/pages/predial_ica_page.dart';
import '../../sector_publico/rentas_departamentales/pages/rentas_departamentales_page.dart';
import '../../sector_publico/planeacion/pages/planeacion_page.dart';
import '../../sector_publico/activos/pages/activos_estado_page.dart';
import '../../sector_publico/auditoria/pages/auditoria_forense_page.dart';
import '../../sector_publico/transparencia/pages/transparencia_page.dart';
import '../../sector_publico/regalias/pages/regalias_sgp_page.dart';
import '../../sector_publico/salud/pages/salud_publica_page.dart';
import '../../sector_publico/siif/pages/siif_page.dart';
import '../../sector_publico/configuracion/pages/configuracion_general_page.dart';
import '../../document_management/pages/document_management_page.dart';
import '../../integrations/pages/integrations_page.dart';
import '../../data_migration/pages/data_migration_page.dart';
import '../support/support_center_page.dart';

List<ModuleDefinition> modulosPresupuestoPublico() => [
  ModuleDefinition(
    id: 'presupuesto_publico',
    title: 'Presupuesto Público',
    icon: Icons.account_balance,
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.operation,
    builder: (context) => PresupuestoPublicoPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.presupuesto_publico,
  ),
  ModuleDefinition(
    id: 'pac',
    title: 'Plan Anual de Caja',
    icon: Icons.calendar_month,
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.operation,
    builder: (context) => PACTesoreriaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.presupuesto_publico,
  ),
];

List<ModuleDefinition> modulosContabilidadNICSP() => [
  ModuleDefinition(
    id: 'contabilidad_nicsp',
    title: 'Contabilidad NICSP',
    icon: Icons.receipt_long,
    color: MerkaThemeTokens.success,
    category: ModuleCategory.accounting,
    builder: (context) => ContabilidadNICSPPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.contabilidad_nicsp,
  ),
  ModuleDefinition(
    id: 'estado_flujos_efectivo',
    title: 'Estado de Flujos de Efectivo',
    icon: Icons.trending_up,
    color: MerkaThemeTokens.success,
    category: ModuleCategory.accounting,
    builder: (context) => ContabilidadNICSPPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      initialTabIndex: 4,
    ),
    featureKey: FeatureKey.contabilidad_nicsp,
  ),
  ModuleDefinition(
    id: 'provisiones_nicsp',
    title: 'Provisiones NICSP 19',
    icon: Icons.warning,
    color: MerkaThemeTokens.success,
    category: ModuleCategory.accounting,
    // Página propia de provisiones — antes abría ContabilidadNICSPPage
    // sin ningún tab de provisiones, lo que dejaba el servicio sin UI.
    builder: (context) => ProvisionesNICSPPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.contabilidad_nicsp,
  ),
];

List<ModuleDefinition> modulosContratacionPublica() => [
  ModuleDefinition(
    id: 'contratacion_publica',
    title: 'Contratación Pública',
    icon: Icons.gavel,
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.operation,
    builder: (context) => ContratacionPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.contratacion_publica,
  ),
  ModuleDefinition(
    id: 'secop_ii',
    title: 'SECOP II',
    icon: Icons.public,
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.operation,
    builder: (context) => ContratacionPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      tabInicial: 3,
    ),
    featureKey: FeatureKey.contratacion_publica,
  ),
  ModuleDefinition(
    id: 'interventoria',
    title: 'Interventoría',
    icon: Icons.assignment,
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.operation,
    // Supervisión/Interventoría contractual — página propia (no Contratación).
    builder: (context) => SupervisionContractualPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.contratacion_publica,
  ),
];

List<ModuleDefinition> modulosNominaPublica() => [
  ModuleDefinition(
    id: 'nomina_publica',
    title: 'Nómina Pública',
    icon: Icons.badge,
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.management,
    builder: (context) => NominaPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.nomina_publica,
  ),
  ModuleDefinition(
    id: 'pila',
    title: 'PILA',
    icon: Icons.description,
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.management,
    builder: (context) => NominaPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      tabInicial: 3,
    ),
    featureKey: FeatureKey.nomina_publica,
  ),
  ModuleDefinition(
    id: 'horas_extra',
    title: 'Horas Extra',
    icon: Icons.schedule,
    color: MerkaThemeTokens.gold400,
    category: ModuleCategory.management,
    builder: (context) => NominaPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      tabInicial: 5,
    ),
    featureKey: FeatureKey.nomina_publica,
  ),
];

List<ModuleDefinition> modulosRentas() => [
  ModuleDefinition(
    id: 'predial',
    title: 'Predial',
    icon: Icons.home,
    color: MerkaThemeTokens.danger,
    category: ModuleCategory.operation,
    builder: (context) => PredialICAPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.predial,
  ),
  ModuleDefinition(
    id: 'ica',
    title: 'ICA',
    icon: Icons.business,
    color: MerkaThemeTokens.danger,
    category: ModuleCategory.operation,
    builder: (context) => PredialICAPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      initialTabIndex: 1, // Tab 1 = ICA
    ),
    featureKey: FeatureKey.predial,
  ),
  ModuleDefinition(
    id: 'rentas_departamentales',
    title: 'Rentas Departamentales',
    icon: Icons.directions_car,
    color: MerkaThemeTokens.danger,
    category: ModuleCategory.operation,
    // Página propia — antes abría PredialICAPage (equivocado).
    builder: (context) => RentasDepartamentalesPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.rentas_departamentales,
  ),
];

List<ModuleDefinition> modulosPlaneacion() => [
  ModuleDefinition(
    id: 'planeacion',
    title: 'Planeación',
    icon: Icons.map,
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.operation,
    builder: (context) => PlaneacionPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      tabInicial: 0,
    ),
    featureKey: FeatureKey.planeacion,
  ),
  ModuleDefinition(
    id: 'mga',
    title: 'MGA',
    icon: Icons.analytics,
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.operation,
    builder: (context) => PlaneacionPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.planeacion,
  ),
  ModuleDefinition(
    id: 'pdt',
    title: 'PDT',
    icon: Icons.description,
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.operation,
    builder: (context) => PlaneacionPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      tabInicial: 1,
    ),
    featureKey: FeatureKey.planeacion,
  ),
];

List<ModuleDefinition> modulosRegaliasYTransferencias() => [
  ModuleDefinition(
    id: 'regalias_sgp',
    title: 'Regalías y SGP',
    icon: Icons.savings_outlined,
    color: MerkaThemeTokens.gold500,
    category: ModuleCategory.operation,
    builder: (context) => RegaliasSGPPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.sgp,
  ),
];

List<ModuleDefinition> modulosSaludPublica() => [
  ModuleDefinition(
    id: 'salud_publica',
    title: 'Salud Pública',
    icon: Icons.local_hospital_outlined,
    color: MerkaThemeTokens.success,
    category: ModuleCategory.operation,
    builder: (context) => SaludPublicaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.salud_publica,
  ),
];

List<ModuleDefinition> modulosActivosEstado() => [
  ModuleDefinition(
    id: 'activos_estado',
    title: 'Activos del Estado',
    icon: Icons.factory,
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.accounting,
    builder: (context) => ActivosEstadoPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.activos_estado,
  ),
  ModuleDefinition(
    id: 'fut',
    title: 'FUT',
    icon: Icons.inventory,
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.accounting,
    builder: (context) => AuditoriaForensePage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      initialTabIndex: 2,
    ),
    featureKey: FeatureKey.auditoria_forense,
  ),
];

List<ModuleDefinition> modulosAuditoriaTransparencia() => [
  ModuleDefinition(
    id: 'auditoria_forense',
    title: 'Auditoría Forense',
    icon: Icons.security,
    color: MerkaThemeTokens.navy800,
    category: ModuleCategory.control,
    builder: (context) => AuditoriaForensePage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.auditoria_forense,
  ),
  ModuleDefinition(
    id: 'chip',
    title: 'CHIP',
    icon: Icons.verified_user,
    color: MerkaThemeTokens.navy800,
    category: ModuleCategory.control,
    builder: (context) => AuditoriaForensePage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
      initialTabIndex: 1, // Tab 1 = Reportes CHIP CGN
    ),
    featureKey: FeatureKey.auditoria_forense,
  ),
  ModuleDefinition(
    id: 'siif',
    title: 'SIIF',
    icon: Icons.account_tree_outlined,
    color: MerkaThemeTokens.navy800,
    category: ModuleCategory.control,
    builder: (context) => SIIFPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.auditoria_forense,
  ),
  ModuleDefinition(
    id: 'transparencia',
    title: 'Transparencia',
    icon: Icons.public,
    color: MerkaThemeTokens.navy800,
    category: ModuleCategory.control,
    builder: (context) => TransparenciaPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
    featureKey: FeatureKey.transparencia,
  ),
];

List<ModuleDefinition> modulosGestionDocumentalPublica() => [
  ModuleDefinition(
    id: 'gestion_documental',
    title: 'Gestión Documental · SGDEA',
    icon: Icons.folder_copy_outlined,
    color: MerkaThemeTokens.navy700,
    category: ModuleCategory.management,
    builder: (_) => const DocumentManagementPage(),
  ),
];

List<ModuleDefinition> modulosConfiguracionEntidad() => [
  ModuleDefinition(
    id: 'data_migration',
    title: 'Migración de datos',
    icon: Icons.move_down_outlined,
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    builder: (_) => const DataMigrationPage(),
    requiresAdmin: true,
  ),
  ModuleDefinition(
    id: 'integrations',
    title: 'Integraciones institucionales',
    icon: Icons.hub_outlined,
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.management,
    builder: (_) => const IntegrationsPage(),
  ),
  ModuleDefinition(
    id: 'support_center',
    title: 'Salud, soporte y Go-Live',
    icon: Icons.support_agent,
    color: MerkaThemeTokens.navy600,
    category: ModuleCategory.management,
    builder: (_) => const SupportCenterPage(),
    requiresAdmin: true,
  ),
  ModuleDefinition(
    id: 'configuracion_entidad',
    title: 'Configuración de la Entidad',
    icon: Icons.settings,
    color: MerkaThemeTokens.graphite600,
    category: ModuleCategory.management,
    builder: (context) => ConfiguracionGeneralPage(
      entidadId: AppSession.entidadId,
      usuarioId: AppSession.usuarioId ?? '',
    ),
  ),
];
