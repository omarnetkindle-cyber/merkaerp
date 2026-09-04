/// Servicio de Configuración General
/// Pantalla de configuración general para cambiar tipo de entidad
/// Gestión de configuraciones globales de la entidad
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import 'selector_entidad_service.dart';
import 'matriz_visibilidad_service.dart';

class ConfiguracionGeneralService {
  final Database db;
  final AuditoriaService auditoriaService;
  final SelectorEntidadService selectorEntidadService;
  final MatrizVisibilidadService matrizVisibilidadService;
  final Uuid _uuid = const Uuid();

  ConfiguracionGeneralService({
    required this.db,
    required this.auditoriaService,
    required this.selectorEntidadService,
    required this.matrizVisibilidadService,
  });

  /// Obtiene la configuración completa de una entidad
  Future<Map<String, dynamic>> obtenerConfiguracionCompleta({
    required String entidadId,
  }) async {
    // Configuración de tipo de entidad
    final configTipo = await selectorEntidadService.consultarConfiguracion(entidadId: entidadId);

    // Configuración de visibilidad
    final configVisibilidad = await matrizVisibilidadService.consultarConfiguracionVisibilidad(entidadId: entidadId);

    // Módulos visibles
    final modulosVisibles = await matrizVisibilidadService.obtenerModulosVisiblesEntidad(entidadId: entidadId);

    // Configuraciones adicionales
    final configAdicional = await db.query(
      'configuraciones_generales',
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, 'activo'],
    );

    return {
      'entidad_id': entidadId,
      'configuracion_tipo': configTipo,
      'configuracion_visibilidad': configVisibilidad,
      'modulos_visibles': modulosVisibles.map((e) => e.toString().split('.').last).toList(),
      'total_modulos': modulosVisibles.length,
      'configuraciones_adicionales': configAdicional,
    };
  }

  /// Actualiza la configuración general de la entidad
  Future<Map<String, dynamic>> actualizarConfiguracionGeneral({
    required String entidadId,
    required String usuarioId,
    Map<String, dynamic>? configuraciones,
  }) async {
    if (configuraciones == null || configuraciones.isEmpty) {
      throw Exception('No se proporcionaron configuraciones para actualizar');
    }

    final id = _uuid.v4();

    // Guardar configuraciones adicionales. Solo puede existir una versión
    // activa por clave; las anteriores se conservan como historial.
    for (final entry in configuraciones.entries) {
      await db.update(
        'configuraciones_generales',
        {'estado': 'inactivo'},
        where: 'entidad_id = ? AND clave = ? AND estado = ?',
        whereArgs: [entidadId, entry.key, 'activo'],
      );
      await db.insert('configuraciones_generales', {
        'id': _uuid.v4(),
        'entidad_id': entidadId,
        'clave': entry.key,
        'valor': entry.value.toString(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'actualizado_por': usuarioId,
        'estado': 'activo',
      });
    }

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'configuracion',
      accion: 'actualizacion_configuracion_general',
      valorAnterior: {},
      valorNuevo: configuraciones,
      referenciaId: id,
    );

    return {
      'configuracion_id': id,
      'configuraciones_actualizadas': configuraciones.keys.toList(),
      'estado': 'actualizado',
    };
  }

  /// Cambia el tipo de entidad y actualiza la visibilidad de módulos
  Future<Map<String, dynamic>> cambiarTipoEntidad({
    required String entidadId,
    required String usuarioId,
    required TipoEntidad nuevoTipo,
    String? nuevoSubtipo,
    required String motivo,
    bool actualizarVisibilidad = true,
  }) async {
    // Cambiar tipo de entidad
    final resultadoTipo = await selectorEntidadService.actualizarTipoEntidad(
      entidadId: entidadId,
      usuarioId: usuarioId,
      nuevoTipo: nuevoTipo,
      nuevoSubtipo: nuevoSubtipo,
      motivo: motivo,
    );

    // Actualizar visibilidad de módulos si se solicita
    if (actualizarVisibilidad) {
      await matrizVisibilidadService.restaurarConfiguracionPorDefecto(
        entidadId: entidadId,
        usuarioId: usuarioId,
      );
    }

    return {
      'tipo_entidad_actualizado': resultadoTipo,
      'visibilidad_actualizada': actualizarVisibilidad,
    };
  }

  /// Consulta todas las configuraciones por clave
  Future<Map<String, dynamic>> consultarConfiguracionPorClave({
    required String entidadId,
    required String clave,
  }) async {
    final resultado = await db.query(
      'configuraciones_generales',
      where: 'entidad_id = ? AND clave = ? AND estado = ?',
      whereArgs: [entidadId, clave, 'activo'],
    );

    if (resultado.isEmpty) return {};

    return {
      'clave': clave,
      'valor': resultado.first['valor'],
      'fecha_actualizacion': resultado.first['fecha_actualizacion'],
      'actualizado_por': resultado.first['actualizado_por'],
    };
  }

  /// Elimina una configuración específica
  Future<Map<String, dynamic>> eliminarConfiguracion({
    required String entidadId,
    required String usuarioId,
    required String clave,
  }) async {
    await db.update(
      'configuraciones_generales',
      {'estado': 'inactivo'},
      where: 'entidad_id = ? AND clave = ? AND estado = ?',
      whereArgs: [entidadId, clave, 'activo'],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.intentoEliminacion,
      modulo: 'configuracion',
      accion: 'eliminacion_configuracion',
      valorAnterior: {
        'clave': clave,
      },
      valorNuevo: {},
    );

    return {
      'clave': clave,
      'estado': 'eliminada',
    };
  }

  /// Genera reporte de configuración de entidad
  Future<Map<String, dynamic>> generarReporteConfiguracion({
    required String entidadId,
  }) async {
    final configCompleta = await obtenerConfiguracionCompleta(entidadId: entidadId);

    // Historial de cambios de tipo
    final historialTipo = await selectorEntidadService.consultarHistorialCambios(entidadId: entidadId);

    // Configuraciones personalizadas de visibilidad
    final configVisibilidadPersonalizada = await matrizVisibilidadService.consultarConfiguracionesPersonalizadas();

    return {
      'configuracion_actual': configCompleta,
      'historial_cambios_tipo': historialTipo,
      'total_cambios_tipo': historialTipo.length,
      'tiene_visibilidad_personalizada': configCompleta['configuracion_visibilidad'] != null,
      'configuraciones_visibilidad_personalizada': configVisibilidadPersonalizada,
    };
  }

  /// Valida la configuración actual de la entidad
  Future<Map<String, dynamic>> validarConfiguracion({
    required String entidadId,
  }) async {
    final configCompleta = await obtenerConfiguracionCompleta(entidadId: entidadId);

    final validaciones = <String, bool>{};
    final advertencias = <String>[];

    // Validar que tenga tipo de entidad configurado
    final tieneTipo = configCompleta['configuracion_tipo'] != null;
    validaciones['tipo_entidad_configurado'] = tieneTipo;
    if (!tieneTipo) {
      advertencias.add('No se ha configurado el tipo de entidad');
    }

    // Validar que tenga módulos visibles
    final tieneModulos = (configCompleta['total_modulos'] as int) > 0;
    validaciones['modulos_visibles'] = tieneModulos;
    if (!tieneModulos) {
      advertencias.add('No hay módulos visibles configurados');
    }

    // Validar configuraciones esenciales
    final configAdicional = configCompleta['configuraciones_adicionales'] as List;
    final tieneConfigEsencial = configAdicional.any((c) => c['clave'] == 'configuracion_completada');
    validaciones['configuracion_completada'] = tieneConfigEsencial;
    if (!tieneConfigEsencial) {
      advertencias.add('La configuración no ha sido marcada como completada');
    }

    final esValida = validaciones.values.every((v) => v);

    return {
      'es_valida': esValida,
      'validaciones': validaciones,
      'advertencias': advertencias,
      'total_advertencias': advertencias.length,
    };
  }

  /// Marca la configuración como completada
  Future<Map<String, dynamic>> marcarConfiguracionCompletada({
    required String entidadId,
    required String usuarioId,
  }) async {
    await actualizarConfiguracionGeneral(
      entidadId: entidadId,
      usuarioId: usuarioId,
      configuraciones: {
        'configuracion_completada': 'true',
        'fecha_completado': DateTime.now().toIso8601String(),
      },
    );

    return {
      'entidad_id': entidadId,
      'estado': 'configuracion_completada',
    };
  }

  /// Restaura todas las configuraciones a valores por defecto
  Future<Map<String, dynamic>> restaurarConfiguracionesPorDefecto({
    required String entidadId,
    required String usuarioId,
  }) async {
    // Restaurar visibilidad
    await matrizVisibilidadService.restaurarConfiguracionPorDefecto(
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    // Desactivar configuraciones adicionales
    await db.update(
      'configuraciones_generales',
      {'estado': 'inactivo'},
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, 'activo'],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'configuracion',
      accion: 'restauracion_configuraciones_defecto',
      valorAnterior: {},
      valorNuevo: {
        'configuracion': 'valores_por_defecto',
      },
    );

    return {
      'entidad_id': entidadId,
      'estado': 'restaurado',
    };
  }
}

