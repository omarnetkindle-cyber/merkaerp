import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../backup/full_backup_service.dart';
import '../database/data_health_service.dart';
import '../go_live/go_live_page.dart';
import '../go_live/go_live_service.dart';
import '../../accounting/application/accounting_diagnostic_service.dart';
import '../../db_helper.dart';
import '../../licensing/domain/product_family.dart';
import '../../sector_publico/health/public_sector_health_service.dart';
import '../../services/licencia_service.dart';
import '../../services/health_reporter.dart';
import 'support_bundle_service.dart';

class SupportCenterPage extends StatefulWidget {
  const SupportCenterPage({super.key});

  @override
  State<SupportCenterPage> createState() => _SupportCenterPageState();
}

class _SupportCenterPageState extends State<SupportCenterPage> {
  Future<_SupportOverview>? _future;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_SupportOverview> _load() async {
    DataHealthReport? health;
    String? healthError;
    try {
      health = await DataHealthService().audit();
    } catch (error) {
      healthError = error.toString();
    }
    final backups = await FullBackupService.instance.listBackups();
    final metrics = await HealthReporter.instance.recolectarMetricas();
    final db = await DatabaseHelper.instance.database;
    final versionRows = await db.rawQuery('PRAGMA user_version');
    final schemaVersion = versionRows.isEmpty
        ? 0
        : (versionRows.first.values.first as num?)?.toInt() ?? 0;
    final syncRows = await db.query(
      'app_config',
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: ['last_sync_timestamp'],
      limit: 1,
    );
    final lastSync = syncRows.isEmpty
        ? null
        : DateTime.tryParse(syncRows.first['valor']?.toString() ?? '');
    final freeDiskMb = await _freeDiskMb();
    PublicSectorHealthReport? publicHealth;
    final license = await LicenciaService.instance.obtenerLicencia();
    if (license?.productFamily == ProductFamily.publicSector) {
      publicHealth = await PublicSectorHealthService.instance.audit();
    }
    return _SupportOverview(
      health: health,
      healthError: healthError,
      backups: backups,
      publicHealth: publicHealth,
      metrics: metrics,
      schemaVersion: schemaVersion,
      lastSync: lastSync,
      freeDiskMb: freeDiskMb,
      license: license,
    );
  }

  Future<double?> _freeDiskMb() async {
    try {
      final dbPath = await DatabaseHelper.instance.obtenerRutaBaseDatos();
      if (Platform.isWindows) {
        final drive = dbPath.length >= 2 && dbPath[1] == ':' ? dbPath[0] : 'C';
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '(Get-PSDrive -Name $drive).Free',
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode != 0) return null;
        final bytes = double.tryParse(result.stdout.toString().trim());
        return bytes == null ? null : bytes / (1024 * 1024);
      }
      final result = await Process.run('df', [
        '-Pk',
        File(dbPath).parent.path,
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final lines = result.stdout.toString().trim().split('\n');
      if (lines.length < 2) return null;
      final fields = lines.last.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) return null;
      final availableKb = double.tryParse(fields[3]);
      return availableKb == null ? null : availableKb / 1024;
    } catch (_) {
      return null;
    }
  }

  Future<void> _verifyBackup() async {
    setState(() {
      _busy = true;
      _message = 'Creando respaldo integral de verificación…';
    });
    try {
      final file = await FullBackupService.instance.createFullBackup(
        label: 'verificacion_soporte',
      );
      final result = await FullBackupService.instance.verify(file);
      if (result.ok) {
        await GoLiveService.instance.update(
          'backup_verify',
          'pass',
          note:
              'Verificación automática: ${result.entries} entradas, ${result.documentFiles} documentos, schema ${result.databaseVersion ?? '-'}.',
        );
      }
      if (!mounted) return;
      setState(
        () => _message = result.ok
            ? 'Respaldo verificado: ${result.entries} entradas, ${result.documentFiles} documentos, ${result.bytes} bytes.'
            : 'El respaldo no superó la verificación: ${result.message}',
      );
      _reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No fue posible verificar el respaldo: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDrill() async {
    setState(() {
      _busy = true;
      _message = 'Preparando simulacro no destructivo de restauración…';
    });
    try {
      final backups = await FullBackupService.instance.listBackups();
      final file = backups.isEmpty
          ? await FullBackupService.instance.createFullBackup(
              label: 'simulacro_restauracion',
            )
          : backups.first;
      final result = await FullBackupService.instance.drillRestore(file);
      if (result.ok) {
        await GoLiveService.instance.update(
          'restore_drill',
          'pass',
          note:
              'Simulacro automático sobre ${file.uri.pathSegments.last}: ${result.tables} tablas, ${result.documentReferences} referencias documentales, schema ${result.databaseVersion ?? '-'}.',
        );
      }
      if (!mounted) return;
      setState(
        () => _message = result.ok
            ? 'Simulacro aprobado: ${result.tables} tablas y ${result.documentReferences} referencias documentales verificadas sin tocar la instalación activa.'
            : 'El simulacro falló: ${result.message}',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No fue posible ejecutar el simulacro: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _repairIndexes() async {
    setState(() {
      _busy = true;
      _message = 'Optimizando índices y estadísticas SQLite…';
    });
    try {
      final db = await DatabaseHelper.instance.database;
      await db.execute('REINDEX');
      await db.execute('ANALYZE');
      await db.execute('PRAGMA optimize');
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'OPTIMIZAR_BASE_DATOS',
        entidad: 'database',
        detalle:
            'REINDEX + ANALYZE + PRAGMA optimize ejecutados desde Salud y soporte.',
      );
      if (mounted) {
        setState(
          () => _message =
              'Índices y estadísticas optimizados correctamente. No se modificaron datos de negocio.',
        );
      }
      _reload();
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No fue posible optimizar la base: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyInventory() async {
    setState(() {
      _busy = true;
      _message = 'Verificando integridad de inventario…';
    });
    try {
      final report = await DataHealthService().audit();
      final inventory = report.issues
          .where(
            (issue) => const {
              'negative_stock',
              'orphan_sale_lines',
              'orphan_purchase_lines',
              'duplicate_products',
            }.contains(issue.id),
          )
          .where((issue) => issue.active)
          .toList();
      if (!mounted) return;
      setState(
        () => _message = inventory.isEmpty
            ? 'Inventario verificado: no se detectaron observaciones en stock ni en líneas de ventas/compras.'
            : 'Inventario: ${inventory.length} control(es) requieren revisión: ${inventory.map((e) => '${e.title} (${e.count})').join(' · ')}',
      );
      _reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No fue posible verificar inventario: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyAccounting() async {
    setState(() {
      _busy = true;
      _message = 'Ejecutando diagnóstico contable…';
    });
    try {
      final report = await AccountingDiagnosticService.instance.run();
      if (!mounted) return;
      setState(
        () => _message = report.issues.isEmpty
            ? 'Contabilidad verificada: no se detectaron observaciones en los controles disponibles.'
            : 'Diagnóstico contable: ${report.critical} crítico(s) y ${report.warnings} advertencia(s). Revísalos en Contabilidad → Diagnóstico.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = 'No fue posible verificar contabilidad: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSupport() async {
    setState(() {
      _busy = true;
      _message = 'Generando paquete técnico sanitizado…';
    });
    try {
      final result = await SupportBundleService.instance.exportBundle();
      if (!mounted) return;
      setState(() => _message = 'Paquete creado. SHA-256: ${result.sha256}');
      await Share.shareXFiles(
        [XFile(result.file.path), XFile('${result.file.path}.sha256')],
        subject: 'Paquete de soporte MerkaERP',
        text:
            'Diagnóstico técnico sanitizado de MerkaERP. No incluye base de datos, documentos ni credenciales.',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'No fue posible generar el paquete: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatStorage(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de salud y soporte'),
        actions: [
          IconButton(
            tooltip: 'Actualizar diagnóstico',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_SupportOverview>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (snapshot.hasError || data == null) {
            return Center(
              child: Text(
                'No fue posible cargar el diagnóstico: ${snapshot.error}',
              ),
            );
          }
          final activeIssues = data.health?.activeIssues ?? const [];
          final blocking = data.health?.blockingIssues ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatusCard(
                    title: 'Salud de datos',
                    value: data.healthError != null
                        ? 'No disponible'
                        : (blocking.isEmpty
                              ? 'Sin bloqueos'
                              : '${blocking.length} bloqueos'),
                    icon: blocking.isEmpty
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    warning: blocking.isNotEmpty || data.healthError != null,
                  ),
                  _StatusCard(
                    title: 'Observaciones',
                    value: '${activeIssues.length}',
                    icon: Icons.monitor_heart_outlined,
                    warning: activeIssues.isNotEmpty,
                  ),
                  _StatusCard(
                    title: 'Respaldos locales',
                    value: '${data.backups.length}',
                    icon: Icons.backup_outlined,
                    warning: data.backups.isEmpty,
                  ),
                  _StatusCard(
                    title: 'Base de datos',
                    value:
                        'Schema v${data.schemaVersion} · ${data.metrics.dbSizeMb.toStringAsFixed(1)} MB · ${data.metrics.dbResponseMs} ms',
                    icon: Icons.storage_outlined,
                    warning: data.metrics.dbResponseMs > 1000,
                  ),
                  _StatusCard(
                    title: 'Espacio disponible',
                    value: data.freeDiskMb == null
                        ? 'No disponible'
                        : _formatStorage(data.freeDiskMb!),
                    icon: Icons.storage_outlined,
                    warning: data.freeDiskMb != null && data.freeDiskMb! < 1024,
                  ),
                  _StatusCard(
                    title: 'Último respaldo',
                    value: data.metrics.ultimoRespaldo == null
                        ? 'Nunca'
                        : _formatDateTime(data.metrics.ultimoRespaldo!),
                    icon: Icons.history_outlined,
                    warning:
                        data.metrics.ultimoRespaldo == null ||
                        DateTime.now()
                                .difference(data.metrics.ultimoRespaldo!)
                                .inHours >
                            48,
                  ),
                  _StatusCard(
                    title: 'Última sincronización',
                    value: data.lastSync == null
                        ? 'Sin sincronización registrada'
                        : _formatDateTime(data.lastSync!),
                    icon: Icons.sync_outlined,
                    warning: false,
                  ),
                  _StatusCard(
                    title: 'Licencia',
                    value: data.license == null
                        ? 'No disponible'
                        : '${data.license!.productFamily.label} · ${data.license!.estado.name}',
                    icon: Icons.verified_user_outlined,
                    warning: data.license == null || !data.license!.esValida,
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_message!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Acciones de diagnóstico',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _verifyBackup,
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Crear y verificar respaldo'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _restoreDrill,
                            icon: const Icon(Icons.restore_page_outlined),
                            label: const Text('Simular restauración'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _repairIndexes,
                            icon: const Icon(Icons.build_circle_outlined),
                            label: const Text('Reparar / optimizar índices'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _verifyInventory,
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Verificar inventario'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _verifyAccounting,
                            icon: const Icon(Icons.account_balance_outlined),
                            label: const Text('Verificar contabilidad'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _exportSupport,
                            icon: const Icon(Icons.support_agent),
                            label: const Text('Exportar paquete de soporte'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const GoLivePage(),
                                    ),
                                  ),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Checklist Go-Live / UAT'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'El paquete de soporte excluye deliberadamente bases, documentos y credenciales. Sirve para diagnóstico técnico sin entregar información operativa del cliente.',
                      ),
                    ],
                  ),
                ),
              ),
              if (data.publicHealth != null) ...[
                const SizedBox(height: 12),
                _PublicSectorHealthCard(report: data.publicHealth!),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hallazgos de salud',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (data.healthError != null)
                        ListTile(
                          leading: const Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                          ),
                          title: const Text('Auditoría no disponible'),
                          subtitle: Text(data.healthError!),
                        )
                      else if (activeIssues.isEmpty)
                        const ListTile(
                          leading: Icon(
                            Icons.check_circle,
                            color: Colors.green,
                          ),
                          title: Text(
                            'No se detectaron observaciones en los controles disponibles.',
                          ),
                        )
                      else
                        ...activeIssues.map(
                          (issue) => ListTile(
                            leading: Icon(
                              issue.blocking
                                  ? Icons.error
                                  : Icons.warning_amber,
                              color: issue.blocking
                                  ? Colors.red
                                  : Colors.orange,
                            ),
                            title: Text('${issue.title} · ${issue.count}'),
                            subtitle: Text(issue.recommendation),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SupportOverview {
  const _SupportOverview({
    required this.health,
    required this.healthError,
    required this.backups,
    required this.publicHealth,
    required this.metrics,
    required this.schemaVersion,
    required this.lastSync,
    required this.freeDiskMb,
    required this.license,
  });
  final DataHealthReport? health;
  final String? healthError;
  final List<File> backups;
  final PublicSectorHealthReport? publicHealth;
  final MetricasSalud metrics;
  final int schemaVersion;
  final DateTime? lastSync;
  final double? freeDiskMb;
  final LicenciaInfo? license;
}

class _PublicSectorHealthCard extends StatelessWidget {
  const _PublicSectorHealthCard({required this.report});

  final PublicSectorHealthReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Salud institucional · Sector Público',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  avatar: Icon(
                    report.blocking > 0
                        ? Icons.error_outline
                        : report.warnings > 0
                        ? Icons.warning_amber_outlined
                        : Icons.verified_outlined,
                    size: 18,
                  ),
                  label: Text(
                    report.blocking > 0
                        ? '${report.blocking} bloqueos'
                        : report.warnings > 0
                        ? '${report.warnings} advertencias'
                        : 'Controles sin hallazgos',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Control preventivo de presupuesto, contabilidad NICSP, tesorería/PAC, contratación, supervisión y SGDEA. No sustituye la revisión profesional ni los controles fiscales de la entidad.',
            ),
            const SizedBox(height: 12),
            ...report.checks.map((check) {
              final icon = switch (check.status) {
                PublicSectorHealthStatus.ok => Icons.check_circle_outline,
                PublicSectorHealthStatus.warning =>
                  Icons.warning_amber_outlined,
                PublicSectorHealthStatus.blocking => Icons.error_outline,
              };
              final color = switch (check.status) {
                PublicSectorHealthStatus.ok => Colors.green,
                PublicSectorHealthStatus.warning => Colors.orange,
                PublicSectorHealthStatus.blocking => scheme.error,
              };
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon, color: color),
                title: Text(check.title),
                subtitle: Text('${check.detail}\n${check.recommendation}'),
                trailing: check.count == 0
                    ? null
                    : Badge(label: Text('${check.count}')),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.value,
    required this.icon,
    this.warning = false,
  });
  final String title;
  final String value;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 250,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: warning ? Colors.orange : Colors.green, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(value),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
