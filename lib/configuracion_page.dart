import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';

import 'db_helper.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'features/company_configuration_service.dart';
import 'features/feature_registry.dart';
import 'sync/application/merka_sync_now_runner.dart';
import 'taxes/retention_rule_service.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  static const String _defaultMerkaSyncEndpoint =
      'https://merka-sync-server-sju2.onrender.com';

  final nombreCtrl = TextEditingController();
  final nitCtrl = TextEditingController();
  final regimenCtrl = TextEditingController();
  final direccionCtrl = TextEditingController();
  final telefonoCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final ciudadCtrl = TextEditingController();
  final monedaCtrl = TextEditingController(text: 'COP');
  final defaultTaxCtrl = TextEditingController(text: '19');
  final logoPathCtrl = TextEditingController();
  final syncEndpointCtrl = TextEditingController();
  bool cargando = true;
  bool sincronizando = false;
  bool vatEnabled = true;
  bool withholdingEnabled = false;
  Map<String, bool> features = FeatureRegistry.defaultFeatures();
  final _retentionService = const RetentionRuleService();
  List<RetentionRule> retentionRules = const [];
  Map<String, int> syncCounters = const {};
  String? syncLastMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargar);
      }
    });
  }

  @override
  void dispose() {
    nombreCtrl.dispose();
    nitCtrl.dispose();
    regimenCtrl.dispose();
    direccionCtrl.dispose();
    telefonoCtrl.dispose();
    emailCtrl.dispose();
    ciudadCtrl.dispose();
    monedaCtrl.dispose();
    defaultTaxCtrl.dispose();
    logoPathCtrl.dispose();
    syncEndpointCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final data = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final companyConfig = await CompanyConfigurationService.instance.loadActive(
      force: true,
    );
    final db = await DatabaseHelper.instance.database;
    if (!mounted) return;
    nombreCtrl.text = data['nombre']?.toString() ?? 'MerkaERP';
    nitCtrl.text = data['nit']?.toString() ?? '';
    regimenCtrl.text = data['regimen']?.toString() ?? '';
    direccionCtrl.text = data['direccion']?.toString() ?? '';
    telefonoCtrl.text = data['telefono']?.toString() ?? '';
    emailCtrl.text = data['email']?.toString() ?? '';
    ciudadCtrl.text = data['ciudad']?.toString() ?? '';
    monedaCtrl.text = data['moneda']?.toString() ?? 'COP';
    logoPathCtrl.text = data['logo_path']?.toString() ?? '';
    syncEndpointCtrl.text =
        await _leerAppConfig(db: db, clave: 'merka_sync_server_endpoint') ??
        _defaultMerkaSyncEndpoint;
    features = companyConfig.features;
    vatEnabled = companyConfig.settings['vat_enabled'] != '0';
    withholdingEnabled = companyConfig.settings['withholding_enabled'] == '1';
    defaultTaxCtrl.text = companyConfig.settings['default_tax'] ?? '19';
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    await _retentionService.seedDefaults(
      db: db,
      companyId: companyId,
      currency: currency,
    );
    retentionRules = await _retentionService.listRules(
      db: db,
      companyId: companyId,
      currency: currency,
    );
    syncCounters = await _leerResumenSync(db);
    setState(() => cargando = false);
  }

  Future<void> _editarReglaRetencion(RetentionRule rule) async {
    final tasaCtrl = TextEditingController(
      text: rule.ratePercent.toStringAsFixed(2),
    );
    final baseCtrl = TextEditingController(
      text: rule.minimumBase.toMajorUnitsString(),
    );
    var active = rule.active;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(rule.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tasaCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Tarifa (%)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: baseCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Base minima',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: active,
                title: const Text('Regla activa'),
                onChanged: (value) => setDialogState(() => active = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final db = await DatabaseHelper.instance.database;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: rule.companyId,
    );
    await _retentionService.updateRule(
      db: db,
      rule: RetentionRule(
        id: rule.id,
        companyId: rule.companyId,
        code: rule.code,
        name: rule.name,
        ratePercent: double.tryParse(tasaCtrl.text.replaceAll(',', '.')) ?? 0,
        minimumBase: MoneyValue.fromMajorUnits(
          baseCtrl.text.replaceAll(',', '.'),
          currency: currency,
        ),
        appliesSales: rule.appliesSales,
        appliesPurchases: rule.appliesPurchases,
        active: active,
      ),
    );
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    retentionRules = await _retentionService.listRules(
      db: db,
      companyId: companyId,
      currency: currency,
    );
    if (mounted) setState(() {});
  }

  Future<void> _guardar() async {
    await DatabaseHelper.instance.guardarEmpresaConfig({
      'nombre': nombreCtrl.text.trim(),
      'nit': nitCtrl.text.trim(),
      'regimen': regimenCtrl.text.trim(),
      'direccion': direccionCtrl.text.trim(),
      'telefono': telefonoCtrl.text.trim(),
      'email': emailCtrl.text.trim(),
      'ciudad': ciudadCtrl.text.trim(),
      'moneda': monedaCtrl.text.trim().isEmpty ? 'COP' : monedaCtrl.text.trim(),
      'logo_path': logoPathCtrl.text.trim(),
    });

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ACTUALIZAR_EMPRESA',
      entidad: 'empresa_config',
      entidadId: 1,
      detalle: 'Configuración de empresa actualizada',
    );
    await CompanyConfigurationService.instance.updateFeatures(features);
    await CompanyConfigurationService.instance.updateSettings({
      'currency': monedaCtrl.text.trim().isEmpty
          ? 'COP'
          : monedaCtrl.text.trim(),
      'vat_enabled': vatEnabled ? '1' : '0',
      'withholding_enabled': withholdingEnabled ? '1' : '0',
      'default_tax': vatEnabled ? defaultTaxCtrl.text.trim() : '0',
      'tax_regime': regimenCtrl.text.trim(),
    });
    await _guardarEndpointSync();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<String?> _leerAppConfig({
    required DatabaseExecutor db,
    required String clave,
  }) async {
    final rows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.single['valor']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<void> _guardarEndpointSync() async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_config(
        clave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');
    final endpoint = syncEndpointCtrl.text.trim();
    if (endpoint.isEmpty) {
      await db.delete(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['merka_sync_server_endpoint'],
      );
      return;
    }
    await db.insert('app_config', {
      'clave': 'merka_sync_server_endpoint',
      'valor': endpoint,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, int>> _leerResumenSync(DatabaseExecutor db) async {
    Future<int> count(String table, String status) async {
      final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [table],
      );
      if (exists.isEmpty) return 0;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS total FROM $table WHERE status = ?',
        [status],
      );
      return ((rows.single['total'] as num?) ?? 0).toInt();
    }

    return {
      'outbox_pending': await count('merka_sync_outbox', 'pending'),
      'outbox_retry': await count('merka_sync_outbox', 'retry'),
      'outbox_error': await count('merka_sync_outbox', 'error'),
      'inbox_pending': await count('merka_sync_inbox', 'pending'),
      'inbox_retry': await count('merka_sync_inbox', 'retry'),
      'inbox_error': await count('merka_sync_inbox', 'error'),
    };
  }

  Future<void> _sincronizarAhora() async {
    if (sincronizando) return;
    setState(() {
      sincronizando = true;
      syncLastMessage = null;
    });
    try {
      await _guardarEndpointSync();
      final result = await MerkaSyncNowRunner().syncNow();
      final db = await DatabaseHelper.instance.database;
      final counters = await _leerResumenSync(db);
      final message = result.completed
          ? 'Sincronización completada: catálogo ${result.bootstrap.queued}, enviados ${result.push.pushResult.pushed}, recibidos ${result.pull.pullResult.received}, aplicados ${result.apply.applied}.'
          : 'Sincronización no ejecutada: ${result.stopReason ?? 'revise la configuración'}.';
      if (!mounted) return;
      setState(() {
        syncCounters = counters;
        syncLastMessage = message;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.completed ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final message = 'No fue posible sincronizar: $e';
      setState(() => syncLastMessage = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => sincronizando = false);
    }
  }

  Widget _featuresCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Capacidades empresariales',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Activa solo los modulos que la empresa realmente usa.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...FeatureRegistry.definitions.map(
              (feature) => SwitchListTile(
                dense: true,
                value: features[feature.key] ?? false,
                title: Text(feature.name),
                subtitle: Text(feature.description),
                onChanged: (value) {
                  setState(() {
                    features[feature.key] = value;
                    if (value) {
                      for (final dependency in feature.dependencies) {
                        features[dependency] = true;
                      }
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fiscalCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reglas fiscales',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Estas reglas alimentan impuestos sugeridos en inventario, compras y ventas.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: vatEnabled,
              title: const Text('IVA habilitado'),
              subtitle: const Text(
                'Si se desactiva, solo se usara impuesto 0%.',
              ),
              onChanged: (value) => setState(() => vatEnabled = value),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: withholdingEnabled,
              title: const Text('Retenciones'),
              subtitle: const Text(
                'Prepara reportes y parametros tributarios.',
              ),
              onChanged: (value) => setState(() => withholdingEnabled = value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: defaultTaxCtrl,
              enabled: vatEnabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Impuesto predeterminado (%)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent),
              ),
            ),
            if (withholdingEnabled) ...[
              const SizedBox(height: 16),
              const Text(
                'ReteFuente por concepto',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...retentionRules.map(
                (rule) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(rule.name),
                  subtitle: Text(
                    '${rule.ratePercent.toStringAsFixed(2)}% desde ${rule.minimumBase.format()}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        rule.active ? Icons.check_circle : Icons.pause_circle,
                        color: rule.active ? Colors.green : Colors.grey,
                      ),
                      IconButton(
                        tooltip: 'Editar regla',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editarReglaRetencion(rule),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _syncCard() {
    int counter(String key) => syncCounters[key] ?? 0;
    final pending =
        counter('outbox_pending') +
        counter('outbox_retry') +
        counter('inbox_pending') +
        counter('inbox_retry');
    final errors = counter('outbox_error') + counter('inbox_error');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sincronización Merka Cloud',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Sincroniza catálogo, ventas e inventario entre Windows, Android y el servidor Render/PostgreSQL usando la licencia activa.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: syncEndpointCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Endpoint del servidor Merka Sync',
                hintText: _defaultMerkaSyncEndpoint,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.cloud_sync_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.outbox_outlined, size: 18),
                  label: Text(
                    'Por enviar: ${counter('outbox_pending') + counter('outbox_retry')}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.inbox_outlined, size: 18),
                  label: Text(
                    'Por aplicar: ${counter('inbox_pending') + counter('inbox_retry')}',
                  ),
                ),
                Chip(
                  avatar: Icon(
                    errors > 0 ? Icons.error_outline : Icons.check_circle,
                    size: 18,
                  ),
                  label: Text('Errores: $errors'),
                  backgroundColor: errors > 0 ? Colors.red.shade50 : null,
                ),
              ],
            ),
            if (syncLastMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                syncLastMessage!,
                style: TextStyle(
                  color: errors > 0
                      ? Colors.red.shade700
                      : Colors.grey.shade700,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: sincronizando ? null : _sincronizarAhora,
                    icon: sincronizando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(
                      sincronizando ? 'Sincronizando...' : 'Sincronizar ahora',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Pendientes/reintentos totales',
                  child: Chip(label: Text('$pending pendientes')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _campo(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Future<void> _seleccionarLogo() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    final path = result?.path;
    if (path == null) return;
    setState(() => logoPathCtrl.text = path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _campo(nombreCtrl, 'Nombre de la empresa'),
                _campo(nitCtrl, 'NIT / documento'),
                _campo(regimenCtrl, 'Régimen tributario'),
                _campo(direccionCtrl, 'Dirección'),
                _campo(telefonoCtrl, 'Teléfono'),
                _campo(emailCtrl, 'Email'),
                _campo(ciudadCtrl, 'Ciudad'),
                _campo(monedaCtrl, 'Moneda'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Imagen institucional',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (logoPathCtrl.text.isNotEmpty &&
                            File(logoPathCtrl.text).existsSync())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Image.file(
                              File(logoPathCtrl.text),
                              height: 72,
                              fit: BoxFit.contain,
                            ),
                          ),
                        TextField(
                          controller: logoPathCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Ruta del logo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _seleccionarLogo,
                          icon: const Icon(Icons.image),
                          label: const Text('Cargar logo'),
                        ),
                      ],
                    ),
                  ),
                ),
                _fiscalCard(),
                _featuresCard(),
                _syncCard(),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                ),
              ],
            ),
    );
  }
}
