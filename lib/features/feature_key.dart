class FeatureKey {
  static const inventory = 'inventory_enabled';
  static const pos = 'pos_enabled';
  static const payroll = 'payroll_enabled';
  static const projects = 'projects_enabled';
  static const crm = 'crm_enabled';
  static const production = 'production_enabled';
  static const impactSimulator = 'impact_simulator_enabled';
  static const multiBranch = 'multi_branch_enabled';
  static const electronicInvoice = 'electronic_invoice_enabled';
  static const multiCurrency = 'multi_currency_enabled';
  static const services = 'services_enabled';
  static const accounting = 'accounting_enabled';
  static const purchases = 'purchases_enabled';
  static const cash = 'cash_enabled';
  static const reports = 'reports_enabled';
  static const treasury = 'treasury_enabled';
  static const fixedAssets = 'fixed_assets_enabled';
  static const documents = 'documents_enabled';
  static const settings = 'settings_enabled';

  // FeatureKeys para módulos del sector público
  static const presupuesto_publico = 'presupuesto_publico_enabled';
  static const contabilidad_nicsp = 'contabilidad_nicsp_enabled';
  static const contratacion_publica = 'contratacion_publica_enabled';
  static const nomina_publica = 'nomina_publica_enabled';
  static const auditoria_forense = 'auditoria_forense_enabled';
  static const predial = 'predial_enabled';
  static const rentas_departamentales = 'rentas_departamentales_enabled';
  static const planeacion = 'planeacion_enabled';
  static const activos_estado = 'activos_estado_enabled';
  static const salud_publica = 'salud_publica_enabled';
  static const sgp = 'sgp_enabled';
  static const transparencia = 'transparencia_enabled';
  static const consolidacion_nicsp_40 = 'consolidacion_nicsp_40_enabled';

  static const all = [
    inventory,
    pos,
    payroll,
    projects,
    crm,
    production,
    impactSimulator,
    multiBranch,
    electronicInvoice,
    multiCurrency,
    services,
    accounting,
    purchases,
    cash,
    reports,
    treasury,
    fixedAssets,
    documents,
    settings,
    // Módulos del sector público
    presupuesto_publico,
    contabilidad_nicsp,
    contratacion_publica,
    nomina_publica,
    auditoria_forense,
    predial,
    rentas_departamentales,
    planeacion,
    activos_estado,
    salud_publica,
    sgp,
    transparencia,
    consolidacion_nicsp_40,
  ];
}
