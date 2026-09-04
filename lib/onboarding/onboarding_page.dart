import 'package:flutter/material.dart';

import '../features/company_configuration_service.dart';
import '../features/company_template_service.dart';
import '../features/feature_key.dart';
import '../features/feature_registry.dart';
import '../models/company.dart';
import '../models/company_profile.dart';
import '../models/company_template.dart';
import '../services/licencia_service.dart';
import '../licensing/domain/product_family.dart';
import '../data_migration/pages/data_migration_page.dart';
import '../app_session.dart';
import '../db_helper.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final companyNameCtrl = TextEditingController(text: 'Mi empresa');
  final taxIdCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final countryCtrl = TextEditingController(text: 'Colombia');
  final currencyCtrl = TextEditingController(text: 'COP');
  final timezoneCtrl = TextEditingController(text: 'America/Bogota');
  final taxRegimeCtrl = TextEditingController();
  final defaultTaxCtrl = TextEditingController(text: '19');
  final employeesCtrl = TextEditingController(text: '1-5');
  final branchesCtrl = TextEditingController(text: '1');
  final volumeCtrl = TextEditingController(text: 'Bajo');
  final adminNameCtrl = TextEditingController(text: 'Administrador');
  final adminUserCtrl = TextEditingController(text: 'admin');
  final adminPinCtrl = TextEditingController();
  final adminPinConfirmCtrl = TextEditingController();

  int currentStep = 0;
  bool vatEnabled = true;
  bool withholdingEnabled = false;
  bool saving = false;
  bool migrateExistingData = false;
  bool continuityAcknowledged = false;
  CompanyTemplate? selectedTemplate;
  List<CompanyTemplate> templates = [];
  late Map<String, bool> features;

  // Selector de tipo de entidad
  String _tipoEntidad = 'privada'; // 'privada' o 'publica'
  String?
  _subtipoEntidadPublica; // 'municipio', 'gobernacion', 'hospital', 'otro'

  List<_OnboardingStep> get _steps {
    if (_tipoEntidad == 'publica') {
      return [
        const _OnboardingStep('Producto', Icons.verified_user_outlined),
        const _OnboardingStep('Entidad', Icons.account_balance),
        const _OnboardingStep('Sector Público', Icons.gavel),
        const _OnboardingStep('Continuidad y datos', Icons.shield_outlined),
        const _OnboardingStep('Finalizar', Icons.check_circle_outline),
      ];
    }
    return [
      const _OnboardingStep('Producto', Icons.verified_user_outlined),
      const _OnboardingStep('Empresa', Icons.domain),
      const _OnboardingStep('Operación', Icons.storefront),
      const _OnboardingStep('Fiscal', Icons.receipt_long),
      const _OnboardingStep('Escala', Icons.tune),
      const _OnboardingStep('Continuidad y datos', Icons.shield_outlined),
      const _OnboardingStep('Finalizar', Icons.check_circle_outline),
    ];
  }

  @override
  void initState() {
    super.initState();
    features = FeatureRegistry.defaultFeatures();
    _loadTemplates();
    _loadProductFamily();
  }

  @override
  void dispose() {
    companyNameCtrl.dispose();
    taxIdCtrl.dispose();
    addressCtrl.dispose();
    cityCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    countryCtrl.dispose();
    currencyCtrl.dispose();
    timezoneCtrl.dispose();
    taxRegimeCtrl.dispose();
    defaultTaxCtrl.dispose();
    employeesCtrl.dispose();
    branchesCtrl.dispose();
    volumeCtrl.dispose();
    adminNameCtrl.dispose();
    adminUserCtrl.dispose();
    adminPinCtrl.dispose();
    adminPinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProductFamily() async {
    final licencia = await LicenciaService.instance.obtenerLicencia();
    if (!mounted) return;
    final isPublic = licencia?.productFamily == ProductFamily.publicSector;
    setState(() {
      _tipoEntidad = isPublic ? 'publica' : 'privada';
      currentStep = 0;
      if (isPublic) {
        selectedTemplate = null;
      } else {
        _subtipoEntidadPublica = null;
      }
    });
  }

  Future<void> _loadTemplates() async {
    final loaded = await CompanyTemplateService.loadTemplates();
    if (!mounted) return;
    setState(() {
      templates = loaded;
      if (loaded.isNotEmpty) {
        selectedTemplate = loaded.first;
        _applyTemplate(loaded.first, notify: false);
      }
    });
  }

  void _applyTemplate(CompanyTemplate template, {bool notify = true}) {
    features = {...FeatureRegistry.defaultFeatures(), ...template.features};
    defaultTaxCtrl.text =
        template.settings['default_tax'] ?? defaultTaxCtrl.text;
    if (notify) setState(() => selectedTemplate = template);
  }

  void _toggle(String key, bool value) {
    setState(() {
      features[key] = value;
      if (value) {
        for (final dependency in FeatureRegistry.dependenciesOf(key)) {
          features[dependency] = true;
        }
      }
    });
  }

  String? _validateRequiredConfiguration() {
    if (companyNameCtrl.text.trim().isEmpty) {
      return 'Escribe el nombre de la organización.';
    }
    if (taxIdCtrl.text.trim().isEmpty) {
      return 'Escribe el NIT o documento de la organización.';
    }
    final currency = currencyCtrl.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      return 'La moneda debe usar un código ISO de tres letras, por ejemplo COP.';
    }
    final email = emailCtrl.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'El correo institucional no tiene un formato válido.';
    }
    if (!continuityAcknowledged) {
      return 'Confirma la política de respaldo y recuperación.';
    }
    if (adminNameCtrl.text.trim().isEmpty ||
        adminUserCtrl.text.trim().isEmpty) {
      return 'Define el nombre y usuario del administrador inicial.';
    }
    if (adminPinCtrl.text.length < 6) {
      return 'El PIN del administrador debe tener al menos 6 caracteres.';
    }
    if (adminPinCtrl.text != adminPinConfirmCtrl.text) {
      return 'Los PIN del administrador no coinciden.';
    }
    if (_tipoEntidad == 'publica' && _subtipoEntidadPublica == null) {
      return 'Selecciona el tipo institucional de la entidad pública.';
    }
    if (_tipoEntidad != 'publica' && vatEnabled) {
      final tax = double.tryParse(
        defaultTaxCtrl.text.trim().replaceAll(',', '.'),
      );
      if (tax == null || tax < 0 || tax > 100) {
        return 'El IVA predeterminado debe ser un porcentaje entre 0 y 100.';
      }
    }
    return null;
  }

  Future<void> _finish() async {
    final validationError = _validateRequiredConfiguration();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => saving = true);

    // Si es entidad pública, desactivar módulos privados y activar solo módulos públicos
    if (_tipoEntidad == 'publica') {
      _configurarModulosPublicos();
    }

    final company = Company(
      name: companyNameCtrl.text.trim(),
      taxId: taxIdCtrl.text.trim(),
      country: countryCtrl.text.trim().isEmpty
          ? 'Colombia'
          : countryCtrl.text.trim(),
      currency: currencyCtrl.text.trim().isEmpty
          ? 'COP'
          : currencyCtrl.text.trim().toUpperCase(),
      timezone: timezoneCtrl.text.trim().isEmpty
          ? 'America/Bogota'
          : timezoneCtrl.text.trim(),
    );

    final profile = CompanyProfile(
      companyId: 0,
      employeeCount: employeesCtrl.text.trim(),
      branchCount: branchesCtrl.text.trim(),
      operationVolume: volumeCtrl.text.trim(),
      taxRegime: taxRegimeCtrl.text.trim(),
      vatEnabled: vatEnabled,
      withholdingEnabled: withholdingEnabled,
    );

    try {
      await CompanyConfigurationService.instance.saveOnboarding(
        company: company,
        profile: profile,
        features: features,
        settings: {
          'country': company.country,
          'currency': company.currency,
          'timezone': company.timezone,
          'vat_enabled': vatEnabled ? '1' : '0',
          'withholding_enabled': withholdingEnabled ? '1' : '0',
          'default_tax': vatEnabled ? defaultTaxCtrl.text.trim() : '0',
          'tax_regime': profile.taxRegime,
          'employees': profile.employeeCount,
          'branches': profile.branchCount,
          'operation_volume': profile.operationVolume,
          // Configuración de tipo de entidad
          'tipo_entidad': _tipoEntidad,
          'subtipo_entidad_publica': _subtipoEntidadPublica ?? '',
          'migration_pending': migrateExistingData ? '1' : '0',
          'backup_policy': 'daily_local',
          'onboarding_version': '2',
        },
        template: _tipoEntidad == 'publica' ? null : selectedTemplate,
      );
      await DatabaseHelper.instance.guardarEmpresaConfig({
        'nombre': company.name,
        'nit': company.taxId,
        'regimen': profile.taxRegime,
        'direccion': addressCtrl.text.trim(),
        'telefono': phoneCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'ciudad': cityCtrl.text.trim(),
        'moneda': company.currency,
      });
      await DatabaseHelper.instance.guardarUsuario(
        nombre: adminNameCtrl.text.trim(),
        usuario: adminUserCtrl.text.trim(),
        rol: 'administrador',
        pin: adminPinCtrl.text,
      );
      if (_tipoEntidad == 'publica') {
        await AppSession.resolverEntidadActiva();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
      return;
    }

    if (!mounted) return;
    setState(() => saving = false);
    if (migrateExistingData) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DataMigrationPage(
            onboardingMode: true,
            onFinished: () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              widget.onFinished();
            },
          ),
        ),
      );
      return;
    }
    widget.onFinished();
  }

  void _configurarModulosPublicos() {
    // La licencia Pública no comparte capacidades operativas con Comercial.
    for (final key in const [
      FeatureKey.pos,
      FeatureKey.inventory,
      FeatureKey.purchases,
      FeatureKey.cash,
      FeatureKey.crm,
      FeatureKey.services,
      FeatureKey.production,
      FeatureKey.multiBranch,
      FeatureKey.accounting,
      FeatureKey.treasury,
      FeatureKey.reports,
      FeatureKey.documents,
      FeatureKey.electronicInvoice,
      FeatureKey.payroll,
      FeatureKey.projects,
      FeatureKey.impactSimulator,
      FeatureKey.multiCurrency,
      FeatureKey.fixedAssets,
    ]) {
      features[key] = false;
    }
    // Administración permanece disponible para usuarios autorizados.
    features[FeatureKey.settings] = true;

    // Los valores seleccionados por el usuario se respetan; solo se aplican
    // defaults cuando el interruptor todavía no fue tocado.
    features.putIfAbsent(FeatureKey.presupuesto_publico, () => true);
    features.putIfAbsent(FeatureKey.contabilidad_nicsp, () => true);
    features.putIfAbsent(FeatureKey.contratacion_publica, () => true);
    features.putIfAbsent(FeatureKey.nomina_publica, () => true);
    features.putIfAbsent(FeatureKey.auditoria_forense, () => true);
    features.putIfAbsent(FeatureKey.activos_estado, () => true);
    features.putIfAbsent(FeatureKey.transparencia, () => true);

    switch (_subtipoEntidadPublica) {
      case 'municipio':
        features.putIfAbsent(FeatureKey.predial, () => true);
        features.putIfAbsent(FeatureKey.planeacion, () => true);
        break;
      case 'gobernacion':
        features.putIfAbsent(FeatureKey.rentas_departamentales, () => true);
        features.putIfAbsent(FeatureKey.planeacion, () => true);
        features.putIfAbsent(FeatureKey.consolidacion_nicsp_40, () => true);
        break;
      case 'hospital':
        features.putIfAbsent(FeatureKey.salud_publica, () => true);
        features.putIfAbsent(FeatureKey.sgp, () => true);
        break;
      case 'otro':
        break;
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData? icon,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _featureSwitch(String key) {
    final definition = FeatureRegistry.definitions.firstWhere(
      (item) => item.key == key,
    );
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: features[key] ?? false,
      title: Text(definition.name),
      subtitle: Text(
        definition.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (value) => _toggle(key, value),
    );
  }

  Widget _stepContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(
        key: ValueKey('${_tipoEntidad}_$currentStep'),
        child: _tipoEntidad == 'publica'
            ? switch (currentStep) {
                0 => _tipoEntidadStep(),
                1 => _escalaPublicoStep(),
                2 => _configuracionPublicaStep(),
                3 => _continuidadDatosStep(),
                4 => _finalStep(),
                _ => const SizedBox.shrink(),
              }
            : switch (currentStep) {
                0 => _tipoEntidadStep(),
                1 => _empresaStep(),
                2 => _operacionStep(),
                3 => _fiscalStep(),
                4 => _escalaStep(),
                5 => _continuidadDatosStep(),
                6 => _finalStep(),
                _ => const SizedBox.shrink(),
              },
      ),
    );
  }

  Widget _tipoEntidadStep() {
    final esPublica = _tipoEntidad == 'publica';
    return _Panel(
      title: 'Producto licenciado',
      subtitle:
          'La familia Comercial/Público está fijada por la licencia y no puede cambiarse desde esta instalación.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Icon(
                  esPublica ? Icons.account_balance : Icons.storefront,
                ),
              ),
              title: Text(
                esPublica ? 'MerkaERP Público' : 'MerkaERP Comercial',
              ),
              subtitle: Text(
                esPublica
                    ? 'Entorno exclusivo para entidades públicas. Los módulos comerciales permanecen aislados.'
                    : 'Entorno exclusivo para empresas privadas. Los módulos del Sector Público permanecen aislados.',
              ),
              trailing: const Icon(Icons.verified_user),
            ),
          ),
          if (esPublica) ...[
            const SizedBox(height: 20),
            const Text(
              'Tipo de entidad pública',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta clasificación parametriza módulos e instrumentos sin cambiar la familia del producto.',
            ),
            const SizedBox(height: 12),
            ...[
              (
                'municipio',
                'Municipio / Alcaldía',
                'Entidad territorial municipal',
                Icons.location_city,
              ),
              (
                'gobernacion',
                'Gobernación / Departamento',
                'Entidad territorial departamental',
                Icons.map,
              ),
              (
                'hospital',
                'Hospital público / ESE',
                'Entidad de salud del sector público',
                Icons.local_hospital,
              ),
              (
                'otro',
                'Otro ente descentralizado',
                'Otra entidad pública',
                Icons.corporate_fare,
              ),
            ].map(
              (item) => RadioListTile<String>(
                value: item.$1,
                groupValue: _subtipoEntidadPublica,
                title: Text(item.$2),
                subtitle: Text(item.$3),
                secondary: Icon(item.$4),
                onChanged: (value) =>
                    setState(() => _subtipoEntidadPublica = value),
              ),
            ),
            if (_subtipoEntidadPublica == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Selecciona el tipo institucional para completar la configuración.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _empresaStep() {
    return _Panel(
      title: 'Datos base',
      subtitle: 'Esta informacion alimenta comprobantes, moneda y reportes.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compacto = constraints.maxWidth < 620;
          final fields = [
            _field(companyNameCtrl, 'Nombre de la empresa', icon: Icons.domain),
            _field(taxIdCtrl, 'NIT / documento', icon: Icons.badge_outlined),
            _field(addressCtrl, 'Dirección', icon: Icons.location_on_outlined),
            _field(
              cityCtrl,
              'Ciudad / municipio',
              icon: Icons.location_city_outlined,
            ),
            _field(phoneCtrl, 'Teléfono', icon: Icons.phone_outlined),
            _field(
              emailCtrl,
              'Correo institucional',
              icon: Icons.email_outlined,
            ),
            _field(countryCtrl, 'País', icon: Icons.public),
            _field(currencyCtrl, 'Moneda', icon: Icons.payments),
            _field(timezoneCtrl, 'Zona horaria', icon: Icons.schedule),
          ];
          if (compacto) {
            return Column(
              children: fields
                  .map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: field,
                    ),
                  )
                  .toList(),
            );
          }
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: fields
                .map(
                  (field) => SizedBox(
                    width: (constraints.maxWidth - 10) / 2,
                    child: field,
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }

  Widget _operacionStep() {
    final grupos = [
      [
        FeatureKey.pos,
        FeatureKey.inventory,
        FeatureKey.purchases,
        FeatureKey.cash,
      ],
      [
        FeatureKey.crm,
        FeatureKey.services,
        FeatureKey.production,
        FeatureKey.multiBranch,
      ],
      [
        FeatureKey.accounting,
        FeatureKey.treasury,
        FeatureKey.reports,
        FeatureKey.documents,
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          title: 'Plantilla de negocio',
          subtitle: 'Elige un punto de partida y ajusta modulos despues.',
          child: templates.isEmpty
              ? const LinearProgressIndicator()
              : Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: templates.map((template) {
                    final selected = selectedTemplate?.id == template.id;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(template.name),
                      avatar: Icon(
                        selected ? Icons.check_circle : Icons.business_center,
                        size: 18,
                      ),
                      onSelected: (_) => _applyTemplate(template),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: 'Modulos activos',
          subtitle:
              'Estos interruptores definen que tarjetas aparecen en el menu principal.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 3 : 1;
              final width = columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 20) / 3;
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: grupos
                    .expand((grupo) => grupo)
                    .map(
                      (key) =>
                          SizedBox(width: width, child: _featureSwitch(key)),
                    )
                    .toList(),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: 'Vista previa del menu',
          subtitle: 'Asi quedara el centro de trabajo para esta empresa.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FeatureRegistry.definitions.map((definition) {
              final active = features[definition.key] ?? false;
              return FilterChip(
                selected: active,
                onSelected: (value) => _toggle(definition.key, value),
                avatar: Icon(
                  active ? Icons.check_circle : Icons.remove_circle_outline,
                  size: 18,
                ),
                label: Text(definition.name),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _fiscalStep() {
    return _Panel(
      title: 'Impuestos y documentos',
      subtitle:
          'Define la base fiscal inicial para compras, ventas y reportes.',
      child: Column(
        children: [
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: vatEnabled,
            title: const Text('IVA habilitado'),
            subtitle: const Text('Permite calcular impuestos en documentos.'),
            onChanged: (value) => setState(() => vatEnabled = value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: withholdingEnabled,
            title: const Text('Retenciones'),
            subtitle: const Text('Prepara reportes y parametros tributarios.'),
            onChanged: (value) => setState(() => withholdingEnabled = value),
          ),
          const Divider(),
          _featureSwitch(FeatureKey.electronicInvoice),
          const SizedBox(height: 10),
          _field(defaultTaxCtrl, 'IVA predeterminado (%)', icon: Icons.percent),
          const SizedBox(height: 10),
          _field(
            taxRegimeCtrl,
            'Regimen tributario',
            icon: Icons.account_balance,
          ),
        ],
      ),
    );
  }

  Widget _configuracionPublicaStep() {
    return _Panel(
      title: 'Configuración Sector Público',
      subtitle: 'Parámetros específicos para entidades públicas colombianas.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Módulos del Sector Público',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: features[FeatureKey.presupuesto_publico] ?? true,
            title: const Text('Presupuesto Público + PAC'),
            subtitle: const Text('Plan Anual de Caja y ejecución presupuestal'),
            onChanged: (value) =>
                _toggle(FeatureKey.presupuesto_publico, value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: features[FeatureKey.contabilidad_nicsp] ?? true,
            title: const Text('Contabilidad NICSP'),
            subtitle: const Text(
              'Normas Internacionales de Contabilidad del Sector Público',
            ),
            onChanged: (value) => _toggle(FeatureKey.contabilidad_nicsp, value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: features[FeatureKey.contratacion_publica] ?? true,
            title: const Text('Contratación Pública + SECOP II'),
            subtitle: const Text(
              'Integración con SECOP II Colombia Compra Eficiente',
            ),
            onChanged: (value) =>
                _toggle(FeatureKey.contratacion_publica, value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: features[FeatureKey.nomina_publica] ?? true,
            title: const Text('Nómina Pública + PILA'),
            subtitle: const Text('Nómina para trabajadores oficiales y PILA'),
            onChanged: (value) => _toggle(FeatureKey.nomina_publica, value),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: features[FeatureKey.auditoria_forense] ?? true,
            title: const Text('Auditoría Forense + CHIP'),
            subtitle: const Text('Control disciplinario y CHIP'),
            onChanged: (value) => _toggle(FeatureKey.auditoria_forense, value),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Módulos según tipo de entidad:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _mostrarModulosPorSubtipo(),
        ],
      ),
    );
  }

  Widget _mostrarModulosPorSubtipo() {
    switch (_subtipoEntidadPublica) {
      case 'municipio':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.predial] ?? true,
              title: const Text('Predial + ICA'),
              subtitle: const Text(
                'Impuesto predial e industria, comercio y avisos',
              ),
              onChanged: (value) => _toggle(FeatureKey.predial, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.planeacion] ?? true,
              title: const Text('Planeación + Banco de Proyectos'),
              subtitle: const Text('MGA y PDT'),
              onChanged: (value) => _toggle(FeatureKey.planeacion, value),
            ),
          ],
        );
      case 'gobernacion':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.rentas_departamentales] ?? true,
              title: const Text('Rentas Departamentales'),
              subtitle: const Text(
                'Impuesto de vehículos, registro, licores, estampillas',
              ),
              onChanged: (value) =>
                  _toggle(FeatureKey.rentas_departamentales, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.planeacion] ?? true,
              title: const Text('Planeación + Banco de Proyectos'),
              subtitle: const Text('MGA y PDT'),
              onChanged: (value) => _toggle(FeatureKey.planeacion, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.consolidacion_nicsp_40] ?? true,
              title: const Text('Consolidación NICSP 40'),
              subtitle: const Text('Estados financieros consolidados'),
              onChanged: (value) =>
                  _toggle(FeatureKey.consolidacion_nicsp_40, value),
            ),
          ],
        );
      case 'hospital':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.salud_publica] ?? true,
              title: const Text('Salud Pública: RIPS/EPS/Glosas'),
              subtitle: const Text(
                'Registro Individual de Prestación de Servicios',
              ),
              onChanged: (value) => _toggle(FeatureKey.salud_publica, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.sgp] ?? true,
              title: const Text('SGP - Sistema General de Participaciones'),
              subtitle: const Text('Componente salud'),
              onChanged: (value) => _toggle(FeatureKey.sgp, value),
            ),
          ],
        );
      case 'otro':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.predial] ?? false,
              title: const Text('Predial + ICA (opcional)'),
              subtitle: const Text('Si aplica para este ente'),
              onChanged: (value) => _toggle(FeatureKey.predial, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.rentas_departamentales] ?? false,
              title: const Text('Rentas Departamentales (opcional)'),
              subtitle: const Text('Si aplica para este ente'),
              onChanged: (value) =>
                  _toggle(FeatureKey.rentas_departamentales, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.planeacion] ?? false,
              title: const Text('Planeación + Banco de Proyectos (opcional)'),
              subtitle: const Text('Si aplica para este ente'),
              onChanged: (value) => _toggle(FeatureKey.planeacion, value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: features[FeatureKey.salud_publica] ?? false,
              title: const Text('Salud Pública (opcional)'),
              subtitle: const Text('Si aplica para este ente'),
              onChanged: (value) => _toggle(FeatureKey.salud_publica, value),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _escalaPublicoStep() {
    return _Panel(
      title: 'Datos de la Entidad',
      subtitle: 'Información básica de la entidad pública.',
      child: Column(
        children: [
          _field(
            companyNameCtrl,
            'Nombre de la entidad',
            icon: Icons.account_balance,
          ),
          const SizedBox(height: 10),
          _field(taxIdCtrl, 'NIT de la entidad', icon: Icons.badge_outlined),
          const SizedBox(height: 10),
          _field(addressCtrl, 'Dirección', icon: Icons.location_on_outlined),
          const SizedBox(height: 10),
          _field(
            cityCtrl,
            'Municipio / ciudad',
            icon: Icons.location_city_outlined,
          ),
          const SizedBox(height: 10),
          _field(phoneCtrl, 'Teléfono', icon: Icons.phone_outlined),
          const SizedBox(height: 10),
          _field(emailCtrl, 'Correo institucional', icon: Icons.email_outlined),
          const SizedBox(height: 10),
          _field(countryCtrl, 'País', icon: Icons.public),
          const SizedBox(height: 10),
          _field(currencyCtrl, 'Moneda', icon: Icons.payments),
          const SizedBox(height: 10),
          _field(timezoneCtrl, 'Zona horaria', icon: Icons.schedule),
          const SizedBox(height: 16),
          const Text(
            'Nota: La configuración fiscal de entidades públicas usa normas NICSP automáticamente.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _escalaStep() {
    return _Panel(
      title: 'Tamano operativo',
      subtitle: 'Estos datos ayudan a preparar permisos, reportes y modulos.',
      child: Column(
        children: [
          _QuickOptions(
            label: 'Empleados',
            controller: employeesCtrl,
            options: const ['1-5', '6-20', '21-50', '50+'],
          ),
          const SizedBox(height: 12),
          _QuickOptions(
            label: 'Sucursales',
            controller: branchesCtrl,
            options: const ['1', '2-3', '4-10', '10+'],
          ),
          const SizedBox(height: 12),
          _QuickOptions(
            label: 'Volumen operativo',
            controller: volumeCtrl,
            options: const ['Bajo', 'Medio', 'Alto'],
          ),
        ],
      ),
    );
  }

  Widget _continuidadDatosStep() {
    return Column(
      children: [
        _Panel(
          title: 'Continuidad operativa',
          subtitle:
              'MerkaERP protege la transición antes de comenzar a operar.',
          child: Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.backup_outlined, color: Colors.green),
                title: Text('Respaldo integral diario'),
                subtitle: Text(
                  'La base y el repositorio documental se respaldan localmente. El respaldo remoto se configura después con las credenciales del cliente.',
                ),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.security_outlined, color: Colors.green),
                title: Text('Credenciales fuera de la base operativa'),
                subtitle: Text(
                  'Las integraciones se configuran por empresa desde el Centro de Integraciones y los secretos usan almacenamiento seguro.',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: continuityAcknowledged,
                onChanged: (value) =>
                    setState(() => continuityAcknowledged = value ?? false),
                title: const Text(
                  'Entiendo la política de respaldo y recuperación',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: '¿Ya utilizabas otro sistema?',
          subtitle:
              'Puedes traer la información existente sin empezar de cero.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: migrateExistingData,
                onChanged: (value) =>
                    setState(() => migrateExistingData = value),
                title: const Text(
                  'Migrar datos después de crear la organización',
                ),
                subtitle: const Text(
                  'Abre el asistente CSV/Excel/JSON/SQLite con mapeo, validación, backup previo, archivo histórico, documentos SGDEA y rollback controlado.',
                ),
              ),
              if (migrateExistingData)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('No es necesario conocer el formato de MerkaERP'),
                  subtitle: Text(
                    'El asistente intenta reconocer columnas del sistema anterior y permite relacionarlas manualmente.',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _finalStep() {
    final isPublic = _tipoEntidad == 'publica';
    return _Panel(
      title: 'Listo para crear ${isPublic ? 'la entidad' : 'la empresa'}',
      subtitle:
          'Revisa la configuración inicial. Todo podrá administrarse posteriormente según permisos y licencia.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            label: isPublic ? 'Entidad' : 'Empresa',
            value: companyNameCtrl.text.trim(),
          ),
          _SummaryRow(
            label: 'NIT / documento',
            value: taxIdCtrl.text.trim().isEmpty
                ? 'No informado'
                : taxIdCtrl.text.trim(),
          ),
          _SummaryRow(
            label: 'Producto',
            value: isPublic ? 'MerkaERP Público' : 'MerkaERP Comercial',
          ),
          if (isPublic && _subtipoEntidadPublica != null)
            _SummaryRow(
              label: 'Tipo institucional',
              value: _obtenerNombreSubtipo(_subtipoEntidadPublica!),
            ),
          _SummaryRow(
            label: 'Moneda',
            value: currencyCtrl.text.trim().isEmpty
                ? 'COP'
                : currencyCtrl.text.trim().toUpperCase(),
          ),
          _SummaryRow(
            label: 'Migración inicial',
            value: migrateExistingData
                ? 'Se abrirá al finalizar'
                : 'Pendiente / no requerida',
          ),
          const Divider(height: 24),
          const Text(
            'Administrador inicial',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: adminNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del administrador',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: adminUserCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: adminPinCtrl,
            obscureText: true,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'PIN (mínimo 6 caracteres)',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: adminPinConfirmCtrl,
            obscureText: true,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Confirmar PIN',
              prefixIcon: Icon(Icons.lock_reset_outlined),
            ),
          ),
          const Divider(height: 24),
          const Text(
            'Al finalizar se crearán la organización, el administrador, la auditoría inicial y los catálogos correspondientes a la familia licenciada.',
          ),
        ],
      ),
    );
  }

  void _continuar() {
    if (currentStep == 1 && companyNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe el nombre de la organización.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final continuityStep = _tipoEntidad == 'publica' ? 3 : 5;
    if (currentStep == continuityStep && !continuityAcknowledged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Confirma la política de continuidad antes de continuar.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // Validar que si es pública, se haya seleccionado subtipo
    if (currentStep == 0 &&
        _tipoEntidad == 'publica' &&
        _subtipoEntidadPublica == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes seleccionar un subtipo de entidad pública'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (currentStep == _steps.length - 1) {
      _finish();
      return;
    }
    setState(() => currentStep++);
  }

  String _obtenerNombreSubtipo(String subtipo) {
    switch (subtipo) {
      case 'municipio':
        return 'Municipio / Alcaldía';
      case 'gobernacion':
        return 'Gobernación / Departamento';
      case 'hospital':
        return 'Hospital público / ESE';
      case 'otro':
        return 'Otro ente descentralizado';
      default:
        return subtipo;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = currentStep == _steps.length - 1;
    final enabledCount = features.values.where((enabled) => enabled).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Configuracion inicial')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 280,
                          child: _Sidebar(
                            steps: _steps,
                            currentStep: currentStep,
                            enabledCount: enabledCount,
                            companyName: companyNameCtrl.text,
                            onStepSelected: (step) =>
                                setState(() => currentStep = step),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _content(isLast)),
                      ],
                    )
                  : Column(
                      children: [
                        _MobileProgress(
                          steps: _steps,
                          currentStep: currentStep,
                          enabledCount: enabledCount,
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: _content(isLast)),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _content(bool isLast) {
    return Column(
      children: [
        Expanded(child: SingleChildScrollView(child: _stepContent())),
        const SizedBox(height: 12),
        Row(
          children: [
            if (currentStep > 0)
              TextButton.icon(
                onPressed: saving ? null : () => setState(() => currentStep--),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Atras'),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: saving ? null : _continuar,
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isLast ? Icons.check : Icons.arrow_forward),
              label: Text(isLast ? 'Finalizar' : 'Continuar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _OnboardingStep {
  const _OnboardingStep(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.steps,
    required this.currentStep,
    required this.enabledCount,
    required this.companyName,
    required this.onStepSelected,
  });

  final List<_OnboardingStep> steps;
  final int currentStep;
  final int enabledCount;
  final String companyName;
  final ValueChanged<int> onStepSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              child: const Icon(Icons.rocket_launch),
            ),
            const SizedBox(height: 12),
            Text(
              companyName.trim().isEmpty ? 'Nueva empresa' : companyName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '$enabledCount modulos activos',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const Divider(height: 26),
            ...steps.asMap().entries.map((entry) {
              final index = entry.key;
              final step = entry.value;
              final selected = index == currentStep;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: selected
                      ? Colors.green.shade700
                      : Colors.grey.shade100,
                  foregroundColor: selected ? Colors.white : Colors.black87,
                  child: Icon(step.icon, size: 17),
                ),
                title: Text(
                  step.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                onTap: () => onStepSelected(index),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _MobileProgress extends StatelessWidget {
  const _MobileProgress({
    required this.steps,
    required this.currentStep,
    required this.enabledCount,
  });

  final List<_OnboardingStep> steps;
  final int currentStep;
  final int enabledCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    steps[currentStep].label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('$enabledCount modulos activos'),
                ],
              ),
            ),
            Text('${currentStep + 1}/${steps.length}'),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _QuickOptions extends StatefulWidget {
  const _QuickOptions({
    required this.label,
    required this.controller,
    required this.options,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;

  @override
  State<_QuickOptions> createState() => _QuickOptionsState();
}

class _QuickOptionsState extends State<_QuickOptions> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: widget.options.map((option) {
            return ChoiceChip(
              label: Text(option),
              selected: widget.controller.text == option,
              onSelected: (_) {
                setState(() => widget.controller.text = option);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
