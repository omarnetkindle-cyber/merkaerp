/// Página de Configuración General
/// Formulario funcional para configuración general de la entidad
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/configuracion_general_service.dart';
import '../services/selector_entidad_service.dart';
import '../services/matriz_visibilidad_service.dart';

class ConfiguracionGeneralPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const ConfiguracionGeneralPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<ConfiguracionGeneralPage> createState() =>
      _ConfiguracionGeneralPageState();
}

class _ConfiguracionGeneralPageState extends State<ConfiguracionGeneralPage> {
  late ConfiguracionGeneralService _configuracionGeneralService;
  late SelectorEntidadService _selectorEntidadService;
  late MatrizVisibilidadService _matrizVisibilidadService;
  Map<String, dynamic>? _configuracionCompleta;
  bool _isLoading = true;
  bool _isValida = false;
  bool _servicesInitialized = false;

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoriaService = AuditoriaService(db);
      _selectorEntidadService = SelectorEntidadService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _matrizVisibilidadService = MatrizVisibilidadService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _configuracionGeneralService = ConfiguracionGeneralService(
        db: db,
        auditoriaService: auditoriaService,
        selectorEntidadService: _selectorEntidadService,
        matrizVisibilidadService: _matrizVisibilidadService,
      );
      _servicesInitialized = true;
      await _cargarConfiguracion();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al inicializar configuración: $e')),
      );
    }
  }

  Future<void> _cargarConfiguracion() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final config = await _configuracionGeneralService
          .obtenerConfiguracionCompleta(entidadId: widget.entidadId);
      final validacion = await _configuracionGeneralService
          .validarConfiguracion(entidadId: widget.entidadId);

      if (!mounted) return;
      setState(() {
        _configuracionCompleta = config;
        _isValida = validacion['es_valida'];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _marcarCompletada() async {
    try {
      await _configuracionGeneralService.marcarConfiguracionCompletada(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración marcada como completada'),
          ),
        );
        _cargarConfiguracion();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _restaurarDefecto() async {
    final confirmacion = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar Configuración'),
        content: const Text(
          '¿Está seguro de restaurar todas las configuraciones a valores por defecto?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );

    if (confirmacion == true) {
      try {
        await _configuracionGeneralService.restaurarConfiguracionesPorDefecto(
          entidadId: widget.entidadId,
          usuarioId: widget.usuarioId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuración restaurada a valores por defecto'),
            ),
          );
          _cargarConfiguracion();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  String? _configuracionAdicional(String clave) {
    final rows = _configuracionCompleta?['configuraciones_adicionales'];
    if (rows is! List) return null;
    for (final row in rows.reversed) {
      if (row is Map && row['clave']?.toString() == clave) {
        return row['valor']?.toString();
      }
    }
    return null;
  }

  Future<void> _configurarRetencionAuditoria() async {
    final controller = TextEditingController(
      text: _configuracionAdicional(AuditoriaService.retentionSettingKey) ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Política de retención de auditoría'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingrese los años adoptados por la entidad en sus instrumentos archivísticos y actos vigentes. MerkaERP no impone un plazo legal fijo.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Años de retención',
                hintText: 'Ej. 10',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final years = int.tryParse(controller.text.trim());
              if (years == null || years <= 0 || years > 500) return;
              Navigator.pop(context, years.toString());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    await _configuracionGeneralService.actualizarConfiguracionGeneral(
      entidadId: widget.entidadId,
      usuarioId: widget.usuarioId,
      configuraciones: {AuditoriaService.retentionSettingKey: value},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Política de retención actualizada y auditada.')),
    );
    await _cargarConfiguracion();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración General'),
        actions: [
          IconButton(
            tooltip: 'Recargar configuración',
            icon: const Icon(Icons.refresh),
            onPressed: _servicesInitialized ? _cargarConfiguracion : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _configuracionCompleta == null
          ? const Center(child: Text('No hay configuración disponible'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Estado de configuración
                  Card(
                    color: _isValida
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            _isValida ? Icons.check_circle : Icons.warning,
                            color: _isValida ? Colors.green : Colors.orange,
                            size: 32,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isValida
                                      ? 'Configuración Completa'
                                      : 'Configuración Incompleta',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _isValida
                                      ? 'La entidad está correctamente configurada'
                                      : 'Complete la configuración de la entidad',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tipo de entidad
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tipo de Entidad',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_configuracionCompleta!['configuracion_tipo'] !=
                              null)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow(
                                  'Tipo',
                                  _configuracionCompleta!['configuracion_tipo']['tipo'],
                                ),
                                _buildInfoRow(
                                  'Subtipo',
                                  _configuracionCompleta!['configuracion_tipo']['subtipo'] ??
                                      'N/A',
                                ),
                                _buildInfoRow(
                                  'Nombre',
                                  _configuracionCompleta!['configuracion_tipo']['nombre_entidad'],
                                ),
                                _buildInfoRow(
                                  'Código DANE',
                                  _configuracionCompleta!['configuracion_tipo']['codigo_dane'],
                                ),
                              ],
                            )
                          else
                            const Text('No configurado'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Módulos visibles
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Módulos Visibles',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Total: ${_configuracionCompleta!['total_modulos']} módulos',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                (_configuracionCompleta!['modulos_visibles']
                                        as List)
                                    .map((modulo) => Chip(label: Text(modulo)))
                                    .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Visibilidad personalizada
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Visibilidad de Módulos',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                _configuracionCompleta!['configuracion_visibilidad'] !=
                                        null
                                    ? Icons.check_circle
                                    : Icons.info,
                                color:
                                    _configuracionCompleta!['configuracion_visibilidad'] !=
                                        null
                                    ? Colors.green
                                    : MerkaThemeTokens.info,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _configuracionCompleta!['configuracion_visibilidad'] !=
                                        null
                                    ? 'Visibilidad personalizada activa'
                                    : 'Usando matriz por defecto',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Política institucional de auditoría',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _configuracionAdicional(AuditoriaService.retentionSettingKey) == null
                                ? 'Retención no configurada: el archivado automático permanece deshabilitado.'
                                : 'Retención configurada: ${_configuracionAdicional(AuditoriaService.retentionSettingKey)} años.',
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _configurarRetencionAuditoria,
                            icon: const Icon(Icons.policy_outlined),
                            label: const Text('Configurar retención'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Acciones
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _marcarCompletada,
                          icon: const Icon(Icons.check),
                          label: const Text('Marcar como Completada'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restaurarDefecto,
                          icon: const Icon(Icons.restore),
                          label: const Text('Restaurar Defecto'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value?.toString() ?? 'No configurado')),
        ],
      ),
    );
  }
}
