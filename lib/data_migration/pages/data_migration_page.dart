import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_session.dart';
import '../../core/go_live/go_live_service.dart';
import '../../licensing/domain/product_family.dart';
import '../../services/licencia_service.dart';
import '../../ui/enterprise_design_system.dart';
import '../application/data_migration_service.dart';
import '../application/tabular_file_parser.dart';
import '../application/migration_template_service.dart';
import '../domain/migration_models.dart';

class DataMigrationPage extends StatefulWidget {
  const DataMigrationPage({
    super.key,
    this.onboardingMode = false,
    this.onFinished,
  });

  final bool onboardingMode;
  final VoidCallback? onFinished;

  @override
  State<DataMigrationPage> createState() => _DataMigrationPageState();
}

class _DataMigrationPageState extends State<DataMigrationPage> {
  final _service = DataMigrationService.instance;
  final _parser = const TabularFileParser();
  final _templateService = const MigrationTemplateService();

  ProductFamily? _family;
  File? _sourceFile;
  List<TabularDataset> _datasets = const [];
  TabularDataset? _dataset;
  MigrationEntityDefinition? _entity;
  Map<String, String?> _mapping = const {};
  MigrationPreview? _preview;
  MigrationDuplicatePolicy _duplicatePolicy = MigrationDuplicatePolicy.skip;
  bool _loading = true;
  bool _working = false;
  String? _message;
  late Future<List<MigrationJobSummary>> _historyFuture;
  final _legacySearchCtrl = TextEditingController();
  late Future<List<Map<String, Object?>>> _legacyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _service.history();
    _legacyFuture = _service.searchLegacyRecords();
    _initialize();
  }

  @override
  void dispose() {
    _legacySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _service.ensureSchema();
      final license = await LicenciaService.instance.obtenerLicencia();
      if (!mounted) return;
      setState(() {
        _family = license?.productFamily ?? ProductFamily.commercial;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'No se pudo iniciar el asistente: $error';
      });
    }
  }

  List<MigrationEntityDefinition> get _entities =>
      _family == null ? const [] : _service.entitiesFor(_family!);

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'tsv', 'txt', 'psv', 'xlsx', 'json', 'db', 'sqlite', 'sqlite3'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _working = true;
      _message = null;
      _preview = null;
    });
    try {
      final file = File(path);
      final datasets = await _parser.parse(file);
      if (datasets.isEmpty) throw StateError('El archivo no contiene hojas o filas utilizables.');
      final first = datasets.first;
      final entity = _guessEntity(first.name, first.headers);
      final mapping = _service.suggestMapping(entity, first.headers);
      if (!mounted) return;
      setState(() {
        _sourceFile = file;
        _datasets = datasets;
        _dataset = first;
        _entity = entity;
        _mapping = mapping;
        _working = false;
      });
      _buildPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = 'No se pudo leer el archivo: $error';
      });
    }
  }

  MigrationEntityDefinition _guessEntity(String sheet, List<String> headers) {
    final haystack = '${sheet.toLowerCase()} ${headers.join(' ').toLowerCase()}';
    String? key;
    if (_family == ProductFamily.publicSector) {
      if (haystack.contains('tercero') || haystack.contains('contratista')) key = 'public_third_parties';
      if (haystack.contains('apropi') || haystack.contains('rubro') || haystack.contains('presupuesto')) key = 'public_budget_opening';
      if (haystack.contains('plan') && haystack.contains('cuenta')) key = 'public_chart_accounts';
      if (haystack.contains('balance') || (haystack.contains('debito') && haystack.contains('credito'))) key = 'public_accounting_opening';
    } else {
      if (haystack.contains('cliente')) key = 'customers';
      if (haystack.contains('proveedor')) key = 'suppliers';
      if (haystack.contains('producto') || haystack.contains('inventario') || haystack.contains('stock')) key = 'products';
      if (haystack.contains('cobrar') || haystack.contains('cartera')) key = 'ar_opening';
      if (haystack.contains('pagar')) key = 'ap_opening';
      if (haystack.contains('balance') || (haystack.contains('debito') && haystack.contains('credito'))) key = 'accounting_opening';
    }
    return _entities.firstWhere(
      (entity) => entity.key == key,
      orElse: () => _entities.firstWhere((entity) => entity.key == 'legacy_archive'),
    );
  }

  void _selectDataset(TabularDataset dataset) {
    final entity = _guessEntity(dataset.name, dataset.headers);
    setState(() {
      _dataset = dataset;
      _entity = entity;
      _mapping = _service.suggestMapping(entity, dataset.headers);
      _preview = null;
    });
    _buildPreview();
  }

  void _selectEntity(MigrationEntityDefinition entity) {
    final dataset = _dataset;
    if (dataset == null) return;
    setState(() {
      _entity = entity;
      _mapping = _service.suggestMapping(entity, dataset.headers);
      _preview = null;
    });
    _buildPreview();
  }

  void _buildPreview() {
    final dataset = _dataset;
    final entity = _entity;
    if (dataset == null || entity == null) return;
    final preview = _service.preview(entity: entity, dataset: dataset, mapping: _mapping);
    setState(() => _preview = preview);
  }

  Future<void> _shareTemplate(MigrationEntityDefinition entity) async {
    if (entity.key == 'legacy_archive') {
      _snack('El archivo histórico no requiere plantilla: conserva la fuente original tal como está.');
      return;
    }
    setState(() => _working = true);
    try {
      final file = await _templateService.createTemplate(entity);
      if (!mounted) return;
      setState(() => _working = false);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Plantilla de migración · ${entity.label}',
        text: 'Plantilla opcional. También puedes importar la exportación original y mapear las columnas dentro de MerkaERP.',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _working = false);
        _snack('No fue posible generar la plantilla: $error', error: true);
      }
    }
  }

  Future<void> _import() async {
    final sourceFile = _sourceFile;
    final dataset = _dataset;
    final preview = _preview;
    final family = _family;
    if (sourceFile == null || dataset == null || preview == null || family == null) return;
    if (!preview.canImport) {
      _snack('Corrige el mapeo o las filas inválidas antes de importar.', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar migración'),
        content: Text(
          'Se creará un respaldo integral antes de importar ${preview.validRows} filas de “${preview.entity.label}”. '
          'Las filas originales quedarán registradas en el historial de migración. ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Migrar')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _working = true;
      _message = 'Creando respaldo y migrando datos…';
    });
    try {
      final result = await _service.importDataset(
        sourceFile: sourceFile,
        dataset: dataset,
        preview: preview,
        productFamily: family,
        duplicatePolicy: _duplicatePolicy,
        publicEntityId: family == ProductFamily.publicSector ? AppSession.entidadId : null,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = 'Migración completada: ${result.imported} importados, ${result.skipped} omitidos y ${result.errors} con observaciones.';
        _historyFuture = _service.history();
        _legacyFuture = _service.searchLegacyRecords();
      });
      _snack('Migración completada. Respaldo previo creado automáticamente.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = 'La migración fue detenida: $error';
        _historyFuture = _service.history();
        _legacyFuture = _service.searchLegacyRecords();
      });
      _snack('La migración se detuvo. Los cambios transaccionales no confirmados fueron revertidos y el historial conserva el diagnóstico.', error: true);
    }
  }

  Future<void> _importLegacyDocumentFolder() async {
    final family = _family;
    if (family == null) return;
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta de documentos del sistema anterior',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Migrar carpeta documental'),
        content: const Text(
          'MerkaERP creará un respaldo integral y un expediente SGDEA de migración. '
          'Copiará los archivos sin seguir enlaces simbólicos, conservará la ruta relativa en el título, '
          'calculará SHA-256 y dejará la trazabilidad hacia cada documento.\n\n'
          'Por seguridad, los documentos heredados se importarán inicialmente con acceso restringido; '
          'un administrador documental podrá reclasificarlos después.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Migrar documentos')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _working = true;
      _message = 'Creando respaldo e incorporando documentos al SGDEA…';
    });
    try {
      final result = await _service.importLegacyDocumentFolder(
        sourceDirectory: Directory(selectedPath),
        productFamily: family,
        publicEntityId: family == ProductFamily.publicSector ? AppSession.entidadId : null,
        accessLevel: 'restricted',
      );
      if (!mounted) return;
      final mb = result.totalBytes / (1024 * 1024);
      setState(() {
        _working = false;
        _message = 'Migración documental completada: ${result.filesImported} archivos · ${mb.toStringAsFixed(1)} MB · expediente #${result.caseId}.';
        _historyFuture = _service.history();
        _legacyFuture = _service.searchLegacyRecords();
      });
      _snack('Los documentos heredados quedaron incorporados al SGDEA con integridad y trazabilidad.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = 'No fue posible completar la migración documental: $error';
        _historyFuture = _service.history();
      });
      _snack('La migración documental se detuvo. El respaldo previo se conserva para recuperación.', error: true);
    }
  }

  Future<void> _archiveAll() async {
    final source = _sourceFile;
    final family = _family;
    if (source == null || family == null || _datasets.isEmpty) return;
    final totalRows = _datasets.fold<int>(0, (sum, item) => sum + item.rows.length);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conservar exportación completa'),
        content: Text(
          'Se preservarán ${_datasets.length} hojas/tablas y $totalRows filas del contenido legado, '
          'sin afectar módulos operativos. Los campos que parezcan credenciales se redactan por seguridad; la fuente queda identificada por SHA-256. ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Conservar todo')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() { _working = true; _message = 'Preservando la exportación completa…'; });
    try {
      final result = await _service.archiveAllDatasets(
        sourceFile: source,
        datasets: _datasets,
        productFamily: family,
        publicEntityId: family == ProductFamily.publicSector ? AppSession.entidadId : null,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _message = 'Archivo histórico completo: ${result.imported} filas preservadas en ${_datasets.length} hojas/tablas.';
        _historyFuture = _service.history();
        _legacyFuture = _service.searchLegacyRecords();
      });
      _snack('La exportación completa quedó preservada sin alterar los módulos operativos.');
    } catch (error) {
      if (!mounted) return;
      setState(() { _working = false; _message = 'No fue posible conservar la fuente: $error'; });
      _snack('No se pudo conservar la exportación completa.', error: true);
    }
  }

  Future<void> _reconcile(MigrationJobSummary job) async {
    setState(() => _working = true);
    try {
      final result = await _service.reconcileJob(job.id);
      if (!mounted) return;
      final ok = result['ok'] == true;
      setState(() { _working = false; _message = ok
          ? 'Conciliación correcta: ${result['trace_ok']} cambios trazados siguen íntegros; ${result['legacy_rows_preserved']} filas legado preservadas.'
          : 'Conciliación con observaciones: ${result['missing']} faltantes y ${result['changed_after_migration']} registros modificados después de migrar.'; });
      _snack(ok ? 'La migración conserva integridad contra su traza.' : 'La conciliación encontró cambios posteriores.', error: !ok);
    } catch (error) {
      if (mounted) {
        setState(() => _working = false);
        _snack('No fue posible conciliar: $error', error: true);
      }
    }
  }

  Future<void> _exportReport(MigrationJobSummary job) async {
    setState(() => _working = true);
    try {
      final file = await _service.exportJobReport(job.id);
      if (!mounted) return;
      setState(() => _working = false);
      await Share.shareXFiles([XFile(file.path)], subject: 'Reporte de migración MerkaERP');
    } catch (error) {
      if (mounted) {
        setState(() => _working = false);
        _snack('No fue posible exportar el reporte: $error', error: true);
      }
    }
  }

  Future<void> _reconcileAll() async {
    setState(() { _working = true; _message = 'Conciliando todas las migraciones activas…'; });
    try {
      final result = await _service.reconcileAllJobs();
      final hasMigrations = result['has_migrations'] == true;
      final ok = result['ok'] == true;
      await GoLiveService.instance.update(
        'migration_reconcile',
        hasMigrations ? (ok ? 'pass' : 'fail') : 'na',
        note: hasMigrations
            ? 'Conciliación automática: ${result['jobs_ok']}/${result['jobs_checked']} migraciones íntegras.'
            : 'No existen migraciones de un sistema anterior para esta organización.',
      );
      if (!mounted) return;
      setState(() => _message = hasMigrations
          ? (ok
              ? 'Conciliación aprobada: ${result['jobs_ok']}/${result['jobs_checked']} migraciones conservan integridad.'
              : 'Conciliación con diferencias: ${result['jobs_failed']} migraciones requieren revisión.')
          : 'No hay migraciones operativas que conciliar; el control Go-Live quedó como No aplica.');
      _snack(ok ? 'Conciliación global completada.' : 'Se detectaron diferencias posteriores a la migración.', error: !ok);
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No fue posible conciliar las migraciones: $error');
        _snack('No fue posible completar la conciliación global.', error: true);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _rollback(MigrationJobSummary job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revertir migración'),
        content: const Text(
          'MerkaERP intentará deshacer solo los registros creados o modificados por esta migración. '
          'Si alguno cambió después, el proceso se detendrá para no sobrescribir trabajo posterior. ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Revertir')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _working = true);
    try {
      await _service.rollback(job.id);
      if (!mounted) return;
      setState(() {
        _working = false;
        _historyFuture = _service.history();
        _legacyFuture = _service.searchLegacyRecords();
      });
      _snack('Migración revertida. El registro histórico y la auditoría se conservaron.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _working = false);
      _snack('No fue posible revertir: $error', error: true);
    }
  }

  Future<void> _showIssues(MigrationJobSummary job) async {
    final issues = await _service.issuesForJob(job.id);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Observaciones de migración'),
        content: SizedBox(
          width: EnterpriseDialogSizing.width(context, 760),
          height: EnterpriseDialogSizing.height(context, 420),
          child: issues.isEmpty
              ? const Center(child: Text('Esta migración no registró observaciones.'))
              : ListView.separated(
                  itemCount: issues.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final issue = issues[index];
                    final severity = issue['severity']?.toString() ?? 'info';
                    return ListTile(
                      leading: Icon(
                        severity == 'error' ? Icons.error_outline : Icons.warning_amber,
                        color: severity == 'error' ? Colors.red : Colors.orange,
                      ),
                      title: Text(issue['message']?.toString() ?? ''),
                      subtitle: Text('Fila ${issue['row_number'] ?? '-'}${issue['field_name'] == null ? '' : ' · ${issue['field_name']}'}'),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.onboardingMode ? 'Traer datos del sistema anterior' : 'Migración de datos'),
          bottom: const TabBar(tabs: [Tab(text: 'Nueva migración'), Tab(text: 'Archivo legado'), Tab(text: 'Historial')]),
          actions: [
            if (widget.onboardingMode)
              TextButton(
                onPressed: _working ? null : widget.onFinished,
                child: const Text('Hacerlo después'),
              ),
          ],
        ),
        body: Stack(
          children: [
            TabBarView(children: [_newMigrationTab(), _legacyArchiveTab(), _historyTab()]),
            if (_working)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text(_message ?? 'Procesando…'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _newMigrationTab() {
    final dataset = _dataset;
    final entity = _entity;
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Migración asistida', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Importa CSV/TSV, Excel, JSON o SQLite, relaciona las columnas del sistema anterior y valida antes de escribir. '
                  'MerkaERP crea un respaldo integral, conserva la fila original y permite reversión controlada.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _GuaranteeChip(icon: Icons.backup_outlined, label: 'Backup automático'),
                    _GuaranteeChip(icon: Icons.visibility_outlined, label: 'Vista previa'),
                    _GuaranteeChip(icon: Icons.history, label: 'Auditoría completa'),
                    _GuaranteeChip(icon: Icons.undo, label: 'Rollback controlado'),
                    _GuaranteeChip(icon: Icons.archive_outlined, label: 'Archivo legado íntegro'),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('1. Archivo de origen', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _working ? null : _pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: Text(_sourceFile == null ? 'Seleccionar CSV / XLSX / JSON / SQLite' : 'Cambiar archivo'),
                ),
                if (_sourceFile != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(_sourceFile!.path, style: const TextStyle(fontSize: 12)),
                  if (_datasets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _working ? null : _archiveAll,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Conservar todas las hojas/tablas como archivo histórico'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Documentos y soportes del sistema anterior', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  'Puedes migrar una carpeta completa de PDFs, imágenes, oficios, contratos y otros soportes. '
                  'MerkaERP los incorpora a un expediente SGDEA, preserva la estructura relativa en el título y verifica cada archivo con SHA-256.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _working ? null : _importLegacyDocumentFolder,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: const Text('Migrar carpeta documental al SGDEA'),
                ),
              ],
            ),
          ),
        ),
        if (_datasets.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('2. Hoja y destino', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TabularDataset>(
                    initialValue: dataset,
                    decoration: const InputDecoration(labelText: 'Hoja / tabla', border: OutlineInputBorder()),
                    items: _datasets.map((item) => DropdownMenuItem(value: item, child: Text('${item.name} · ${item.rows.length} filas'))).toList(),
                    onChanged: (value) { if (value != null) _selectDataset(value); },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<MigrationEntityDefinition>(
                    initialValue: entity,
                    decoration: const InputDecoration(labelText: 'Migrar hacia', border: OutlineInputBorder()),
                    items: _entities.map((item) => DropdownMenuItem(value: item, child: Text(item.label))).toList(),
                    onChanged: (value) { if (value != null) _selectEntity(value); },
                  ),
                  if (entity != null && entity.key != 'legacy_archive') ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _working ? null : () => _shareTemplate(entity),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Compartir plantilla opcional'),
                      ),
                    ),
                  ],
                  if (entity != null) ...[
                    const SizedBox(height: 8),
                    Text(entity.description, style: TextStyle(color: Colors.grey.shade700)),
                  ],
                  const SizedBox(height: 10),
                  SegmentedButton<MigrationDuplicatePolicy>(
                    segments: const [
                      ButtonSegment(value: MigrationDuplicatePolicy.skip, label: Text('Omitir duplicados'), icon: Icon(Icons.skip_next)),
                      ButtonSegment(value: MigrationDuplicatePolicy.merge, label: Text('Fusionar'), icon: Icon(Icons.merge_type)),
                    ],
                    selected: {_duplicatePolicy},
                    onSelectionChanged: (value) => setState(() => _duplicatePolicy = value.first),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (dataset != null && entity != null && entity.fields.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('3. Relacionar columnas', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('MerkaERP propone coincidencias; puedes corregirlas antes de validar.'),
                  const SizedBox(height: 12),
                  ...entity.fields.map((field) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text('${field.label}${field.required ? ' *' : ''}', style: TextStyle(fontWeight: field.required ? FontWeight.w600 : FontWeight.normal)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: _mapping[field.key] ?? '',
                                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                items: [
                                  const DropdownMenuItem(value: '', child: Text('— No importar —')),
                                  ...dataset.headers.map((header) => DropdownMenuItem(value: header, child: Text(header, overflow: TextOverflow.ellipsis))),
                                ],
                                onChanged: (value) {
                                  setState(() => _mapping = {..._mapping, field.key: (value == null || value.isEmpty) ? null : value});
                                  _buildPreview();
                                },
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
        ],
        if (preview != null) ...[
          const SizedBox(height: 12),
          _previewCard(preview),
        ],
        if (_message != null && !_working) ...[
          const SizedBox(height: 12),
          Card(
            color: _message!.startsWith('La migración') ? Colors.red.shade50 : Colors.green.shade50,
            child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
          ),
        ],
        if (widget.onboardingMode && _message != null && _message!.startsWith('Migración completada')) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.onFinished,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar a MerkaERP'),
          ),
        ],
      ],
    );
  }

  Widget _previewCard(MigrationPreview preview) {
    final sample = preview.normalizedRows.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('4. Validar e importar', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Metric(label: 'Filas', value: '${preview.totalRows}'),
                _Metric(label: 'Válidas', value: '${preview.validRows}', color: Colors.green),
                _Metric(label: 'Con error', value: '${preview.invalidRows}', color: preview.invalidRows == 0 ? Colors.green : Colors.red),
              ],
            ),
            if (preview.issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${preview.issues.length} observaciones de validación'),
                children: preview.issues.take(30).map((issue) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline, color: Colors.red),
                      title: Text(issue.message),
                      subtitle: Text('Fila ${issue.rowNumber}${issue.field == null ? '' : ' · ${issue.field}'}'),
                    )).toList(),
              ),
            ],
            if (sample.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Vista previa', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: sample.length,
                  itemBuilder: (context, index) {
                    final row = sample[index];
                    final visible = row.entries.where((entry) => !entry.key.startsWith('__') && entry.value.toString().isNotEmpty).take(5).map((entry) => '${entry.key}: ${entry.value}').join(' · ');
                    return ListTile(
                      dense: true,
                      leading: Icon(row['__valid'] == true ? Icons.check_circle : Icons.cancel, color: row['__valid'] == true ? Colors.green : Colors.red),
                      title: Text(visible.isEmpty ? 'Fila original preservada' : visible, maxLines: 2, overflow: TextOverflow.ellipsis),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: preview.canImport && !_working ? _import : null,
              icon: const Icon(Icons.playlist_add_check),
              label: Text(preview.entity.key == 'legacy_archive' ? 'Conservar archivo histórico' : 'Crear backup e importar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legacyArchiveTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _legacySearchCtrl,
            decoration: InputDecoration(
              labelText: 'Buscar en información del sistema anterior',
              hintText: 'Número, nombre, factura, concepto, código…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: () => setState(() => _legacyFuture = _service.searchLegacyRecords(query: _legacySearchCtrl.text)),
                icon: const Icon(Icons.arrow_forward),
              ),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (value) => setState(() => _legacyFuture = _service.searchLegacyRecords(query: value)),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _legacyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Text('No fue posible consultar el archivo legado: ${snapshot.error}'));
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) return const Center(child: Text('No hay filas históricas para mostrar con este filtro.'));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final raw = row['raw_json']?.toString() ?? '{}';
                  String summary = raw;
                  try {
                    final decoded = jsonDecode(raw);
                    if (decoded is Map) {
                      summary = decoded.entries.take(6).map((entry) => '${entry.key}: ${entry.value}').join(' · ');
                    }
                  } catch (_) {}
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${row['row_number'] ?? '-'}')),
                      title: Text('${row['source_name'] ?? 'Fuente'} · ${row['source_sheet'] ?? 'tabla'}'),
                      subtitle: Text(summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                      trailing: row['imported'] == 1 ? const Icon(Icons.link, color: Colors.green) : const Icon(Icons.archive_outlined),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('${row['source_sheet'] ?? 'Registro'} · fila ${row['row_number'] ?? '-'}'),
                          content: SizedBox(
                            width: EnterpriseDialogSizing.width(context, 760),
                            height: EnterpriseDialogSizing.height(context, 420),
                            child: SingleChildScrollView(child: SelectableText(raw)),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _historyTab() {
    return FutureBuilder<List<MigrationJobSummary>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        final jobs = snapshot.data ?? const [];
        if (jobs.isEmpty) return const Center(child: Text('Aún no hay migraciones registradas.'));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('Concilia todas las migraciones antes de la puesta en marcha para comprobar que los registros importados siguen íntegros.')),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _working ? null : _reconcileAll,
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Conciliar todas'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: jobs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final job = jobs[index];
                  final rolledBack = job.status == 'rolled_back';
                  final imported = job.summary['rows_imported'] ?? 0;
                  final errors = job.summary['rows_errors'] ?? 0;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(rolledBack ? Icons.undo : (errors == 0 ? Icons.check : Icons.warning_amber)),
                      ),
                      title: Text(job.sourceName),
                      subtitle: Text('${job.status} · $imported importados · $errors observaciones\n${job.startedAt.toLocal()}'),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(tooltip: 'Ver observaciones', onPressed: () => _showIssues(job), icon: const Icon(Icons.fact_check_outlined)),
                          if (!rolledBack && job.status != 'running' && job.status != 'failed')
                            IconButton(tooltip: 'Conciliar integridad', onPressed: _working ? null : () => _reconcile(job), icon: const Icon(Icons.rule_folder_outlined)),
                          IconButton(tooltip: 'Exportar reporte', onPressed: _working ? null : () => _exportReport(job), icon: const Icon(Icons.ios_share_outlined)),
                          if (!rolledBack && job.status != 'running' && job.status != 'failed')
                            IconButton(tooltip: 'Revertir migración', onPressed: _working ? null : () => _rollback(job), icon: const Icon(Icons.undo)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuaranteeChip extends StatelessWidget {
  const _GuaranteeChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 18), label: Text(label));
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color?.withValues(alpha: 0.35) ?? Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
