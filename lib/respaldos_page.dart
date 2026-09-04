import 'dart:io';

import 'package:flutter/material.dart';

import 'core/backup/full_backup_service.dart';
import 'core/backup/remote_backup_service.dart';
import 'db_helper.dart';
import 'integrations/application/integration_settings_service.dart';

class RespaldosPage extends StatefulWidget {
  const RespaldosPage({super.key});

  @override
  State<RespaldosPage> createState() => _RespaldosPageState();
}

class _RespaldosPageState extends State<RespaldosPage> {
  List<File> respaldos = [];
  bool cargando = true;
  String? operacion;
  int retencion = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargar);
      }
    });
  }

  Future<void> _cargar() async {
    final data = await FullBackupService.instance.listBackups();
    final configuredRetention = await _retencionConfigurada();
    if (!mounted) return;
    setState(() {
      respaldos = data;
      retencion = configuredRetention;
      cargando = false;
      operacion = null;
    });
  }

  Future<void> _configurarRetencion() async {
    var selected = const [7, 30, 90].contains(retencion) ? retencion : 30;
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Retención de respaldos locales'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Elige cuántos respaldos integrales conservar en este equipo. '
                'Cuando se crea uno nuevo, los más antiguos que excedan este límite se eliminan. '
                'Los respaldos remotos siguen la política del proveedor que configure la organización.',
              ),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7'), icon: Icon(Icons.calendar_view_week)),
                  ButtonSegment(value: 30, label: Text('30'), icon: Icon(Icons.calendar_month)),
                  ButtonSegment(value: 90, label: Text('90'), icon: Icon(Icons.date_range)),
                ],
                selected: {selected == 7 || selected == 30 || selected == 90 ? selected : 30},
                onSelectionChanged: (value) => setDialogState(() => selected = value.first),
              ),
              const SizedBox(height: 10),
              Text('Política seleccionada: conservar los últimos $selected respaldos locales.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Guardar política')),
          ],
        ),
      ),
    );
    if (result == null) return;
    await IntegrationSettingsService.instance.updatePublicConfig(
      'cloud_backup',
      {'retention_count': '$result'},
    );
    await FullBackupService.instance.applyRetention(keep: result);
    if (!mounted) return;
    setState(() => retencion = result);
    await _cargar();
  }

  Future<int> _retencionConfigurada() async {
    final raw = await IntegrationSettingsService.instance.config(
      'cloud_backup',
      'retention_count',
    );
    return (int.tryParse(raw ?? '') ?? 30).clamp(1, 365).toInt();
  }

  Future<File?> _crearRespaldo({bool subirRemoto = false}) async {
    if (mounted) {
      setState(() {
        cargando = true;
        operacion = subirRemoto ? 'Creando y cifrando respaldo…' : 'Creando respaldo local…';
      });
    }
    try {
      final archivo = await FullBackupService.instance.createFullBackup();
      await FullBackupService.instance.applyRetention(
        keep: await _retencionConfigurada(),
      );
      if (subirRemoto) {
        final result = await RemoteBackupService.instance.uploadBackup(archivo);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Respaldo local y remoto completado (${result.provider}, ${_tamanoBytes(result.bytes)}).',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Respaldo creado: ${archivo.uri.pathSegments.last}'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _cargar();
      return archivo;
    } catch (e) {
      await _cargar();
      if (mounted) _mostrarError(e);
      return null;
    }
  }

  Future<void> _subir(File archivo) async {
    setState(() {
      cargando = true;
      operacion = 'Cifrando y subiendo respaldo…';
    });
    try {
      final result = await RemoteBackupService.instance.uploadBackup(archivo);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Respaldo remoto confirmado por ${result.provider}.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      await _cargar();
      if (mounted) _mostrarError(e);
    }
  }

  Future<void> _verificar(File archivo) async {
    setState(() {
      cargando = true;
      operacion = 'Verificando base y repositorio documental…';
    });
    final verification = await FullBackupService.instance.verify(archivo);
    final result = <String, Object?>{
      'ok': verification.ok,
      'message': verification.message,
      'user_version': verification.databaseVersion,
      'tables': verification.entries,
      'documents': verification.documentFiles,
    };
    await _cargar();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(result['ok'] == true ? 'Respaldo íntegro' : 'Respaldo no válido'),
        content: Text(
          '${result['message'] ?? ''}\n'
          '${result['user_version'] == null ? '' : 'Esquema: v${result['user_version']}\n'}'
          '${result['tables'] == null ? '' : 'Entradas verificadas: ${result['tables']}\n'}'
          '${result['documents'] == null ? '' : 'Archivos documentales: ${result['documents']}'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _compartir(File archivo) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Respaldo disponible en: ${archivo.path}')),
    );
  }

  Future<void> _restaurar(File archivo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: const Text(
          'MerkaERP verificará la integridad del respaldo y creará automáticamente '
          'un punto de retorno de la base actual antes de reemplazarla. Si la '
          'restauración falla, intentará recuperar ese punto de retorno.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Verificar y restaurar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() {
      cargando = true;
      operacion = 'Verificando y restaurando…';
    });
    try {
      await FullBackupService.instance.restore(archivo);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Respaldo restaurado y verificado.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      await _cargar();
      if (mounted) _mostrarError(e);
    }
  }

  String _tamano(File archivo) => _tamanoBytes(archivo.lengthSync());

  String _tamanoBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _mostrarError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Bad state: ', '')),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Respaldos y recuperación'),
        actions: [
          IconButton(
            tooltip: 'Configurar retención ($retencion respaldos)',
            onPressed: cargando ? null : _configurarRetencion,
            icon: const Icon(Icons.policy_outlined),
          ),
          IconButton(
            tooltip: 'Crear respaldo local y subir cifrado',
            onPressed: cargando ? null : () => _crearRespaldo(subirRemoto: true),
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: cargando ? null : () => _crearRespaldo(),
        icon: const Icon(Icons.backup),
        label: const Text('Respaldo local'),
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Continuidad operativa'),
              subtitle: Text(
                'El respaldo integral incluye la base y el repositorio documental. Los respaldos remotos se cifran antes de salir del equipo. '
                'Configura el destino y su clave en Integraciones → Respaldo remoto. La política local conserva los últimos 7, 30 o 90 respaldos según lo definido por la empresa.',
              ),
            ),
          ),
          if (cargando)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(operacion ?? 'Cargando respaldos…'),
                  ],
                ),
              ),
            )
          else if (respaldos.isEmpty)
            const Expanded(child: Center(child: Text('No hay respaldos creados.')))
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargar,
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: respaldos.length,
                  itemBuilder: (context, index) {
                    final archivo = respaldos[index];
                    final stat = archivo.statSync();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.storage),
                        title: Text(archivo.uri.pathSegments.last),
                        subtitle: Text('${stat.modified}\n${_tamano(archivo)}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'verificar') _verificar(archivo);
                            if (value == 'remoto') _subir(archivo);
                            if (value == 'compartir') _compartir(archivo);
                            if (value == 'restaurar') _restaurar(archivo);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'verificar', child: Text('Verificar integridad')),
                            PopupMenuItem(value: 'remoto', child: Text('Subir cifrado al destino remoto')),
                            PopupMenuItem(value: 'compartir', child: Text('Ver ubicación local')),
                            PopupMenuDivider(),
                            PopupMenuItem(value: 'restaurar', child: Text('Restaurar')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
