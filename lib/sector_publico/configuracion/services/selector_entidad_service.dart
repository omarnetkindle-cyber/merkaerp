/// Servicio de Selector de Tipo de Entidad
/// Gestión de tipos y subtipos de entidades territoriales
/// Configuración inicial de la entidad en onboarding
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoEntidad {
  departamento,
  municipio,
  distrito,
  regionMetropolitana,
  hospitalEse,
  otroEnte,
}

extension TipoEntidadCompatibilidad on TipoEntidad {
  /// Traduce las etiquetas del onboarding legado en el borde del selector.
  static TipoEntidad desdeTipoOnboarding(String tipo) {
    switch (tipo) {
      case 'gobernacion':
        return TipoEntidad.departamento;
      case 'hospital':
        return TipoEntidad.hospitalEse;
      case 'otro':
        return TipoEntidad.otroEnte;
      default:
        return TipoEntidad.values.firstWhere(
          (valor) => valor.name == tipo,
          orElse: () => TipoEntidad.otroEnte,
        );
    }
  }
}

enum SubtipoMunicipio {
  categoriaEspecial,
  categoriaPrimera,
  categoriaSegunda,
  categoriaTercera,
  categoriaCuarta,
  categoriaQuinta,
  categoriaSexta,
}

enum SubtipoDistrito {
  distritoCapital,
  distritoEspecial,
  distritoTuristico,
  distritoCultural,
  distritoPortuario,
  distritoIndustrial,
}

class SelectorEntidadService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SelectorEntidadService({required this.db, required this.auditoriaService});

  /// Registra la configuración de tipo de entidad
  Future<Map<String, dynamic>> configurarTipoEntidad({
    required String entidadId,
    required String usuarioId,
    required TipoEntidad tipo,
    String? subtipo,
    required String nombreEntidad,
    required String codigoDANE,
    required String departamento,
    String? municipio,
  }) async {
    final id = _uuid.v4();

    // Validar subtipo según tipo
    if (tipo == TipoEntidad.municipio && subtipo != null) {
      if (!_esSubtipoMunicipioValido(subtipo)) {
        throw Exception('Subtipo no válido para municipio');
      }
    }

    if (tipo == TipoEntidad.distrito && subtipo != null) {
      if (!_esSubtipoDistritoValido(subtipo)) {
        throw Exception('Subtipo no válido para distrito');
      }
    }

    await db.insert('configuracion_entidad', {
      'id': id,
      'entidad_id': entidadId,
      'parametro': 'tipo_entidad',
      'valor': tipo.name,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
      'actualizado_por': usuarioId,
      'tipo': tipo.name,
      'subtipo': subtipo,
      'nombre_entidad': nombreEntidad,
      'codigo_dane': codigoDANE,
      'departamento': departamento,
      'municipio': municipio,
      'fecha_configuracion': DateTime.now().toIso8601String(),
      'configurado_por': usuarioId,
      'estado': 'activo',
      'vigente': 1,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'configuracion',
      accion: 'configuracion_tipo_entidad',
      valorAnterior: {},
      valorNuevo: {
        'configuracion_id': id,
        'tipo': tipo.toString(),
        'subtipo': subtipo,
        'nombre_entidad': nombreEntidad,
      },
      referenciaId: id,
    );

    return {
      'configuracion_id': id,
      'tipo': tipo.toString(),
      'subtipo': subtipo,
      'nombre_entidad': nombreEntidad,
      'estado': 'activo',
    };
  }

  /// Actualiza el tipo de entidad
  Future<Map<String, dynamic>> actualizarTipoEntidad({
    required String entidadId,
    required String usuarioId,
    required TipoEntidad nuevoTipo,
    String? nuevoSubtipo,
    required String motivo,
  }) async {
    final configuracion = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND parametro = ? AND vigente = 1 AND estado = ?',
      whereArgs: [entidadId, 'tipo_entidad', 'activo'],
    );

    if (configuracion.isEmpty) {
      throw Exception('No hay configuración activa para esta entidad');
    }

    final configId = configuracion.first['id'];
    final tipoAnterior = configuracion.first['tipo'];
    final subtipoAnterior = configuracion.first['subtipo'];

    await db.update(
      'configuracion_entidad',
      {
        'estado': 'inactivo', // Marcar anterior como inactivo
        'vigente': 0,
        'fecha_fin': DateTime.now().toIso8601String(),
        'fecha_actualizacion': DateTime.now().toIso8601String(),
        'actualizado_por': usuarioId,
      },
      where: 'id = ?',
      whereArgs: [configId],
    );

    // Crear nueva configuración
    final nuevaConfigId = _uuid.v4();
    await db.insert('configuracion_entidad', {
      'id': nuevaConfigId,
      'entidad_id': entidadId,
      'parametro': 'tipo_entidad',
      'valor': nuevoTipo.name,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
      'actualizado_por': usuarioId,
      'tipo': nuevoTipo.name,
      'subtipo': nuevoSubtipo,
      'nombre_entidad': configuracion.first['nombre_entidad'],
      'codigo_dane': configuracion.first['codigo_dane'],
      'departamento': configuracion.first['departamento'],
      'municipio': configuracion.first['municipio'],
      'fecha_configuracion': DateTime.now().toIso8601String(),
      'configurado_por': usuarioId,
      'motivo_cambio': motivo,
      'estado': 'activo',
      'vigente': 1,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'configuracion',
      accion: 'cambio_tipo_entidad',
      valorAnterior: {
        'tipo_anterior': tipoAnterior,
        'subtipo_anterior': subtipoAnterior,
      },
      valorNuevo: {
        'tipo_nuevo': nuevoTipo.toString(),
        'subtipo_nuevo': nuevoSubtipo,
        'motivo': motivo,
      },
      referenciaId: nuevaConfigId,
    );

    return {
      'configuracion_id': nuevaConfigId,
      'tipo_nuevo': nuevoTipo.toString(),
      'subtipo_nuevo': nuevoSubtipo,
      'estado': 'activo',
    };
  }

  /// Consulta la configuración actual de una entidad
  Future<Map<String, dynamic>?> consultarConfiguracion({
    required String entidadId,
  }) async {
    final resultado = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND parametro = ? AND vigente = 1 AND estado = ?',
      whereArgs: [entidadId, 'tipo_entidad', 'activo'],
    );

    if (resultado.isEmpty) return null;
    return resultado.first;
  }

  /// Obtiene los subtipos válidos para un tipo de entidad
  List<String> obtenerSubtiposValidos(TipoEntidad tipo) {
    switch (tipo) {
      case TipoEntidad.municipio:
        return SubtipoMunicipio.values
            .map((e) => e.toString().split('.').last)
            .toList();
      case TipoEntidad.distrito:
        return SubtipoDistrito.values
            .map((e) => e.toString().split('.').last)
            .toList();
      case TipoEntidad.departamento:
      case TipoEntidad.regionMetropolitana:
      case TipoEntidad.hospitalEse:
      case TipoEntidad.otroEnte:
        return []; // No tienen subtipos
    }
  }

  /// Valida si un subtipo es válido para municipio
  bool _esSubtipoMunicipioValido(String subtipo) {
    return SubtipoMunicipio.values.any(
      (e) => e.toString().split('.').last == subtipo,
    );
  }

  /// Valida si un subtipo es válido para distrito
  bool _esSubtipoDistritoValido(String subtipo) {
    return SubtipoDistrito.values.any(
      (e) => e.toString().split('.').last == subtipo,
    );
  }

  /// Obtiene todos los tipos de entidad disponibles
  List<String> obtenerTiposEntidad() {
    return TipoEntidad.values.map((e) => e.toString().split('.').last).toList();
  }

  /// Consulta historial de cambios de tipo de entidad
  Future<List<Map<String, dynamic>>> consultarHistorialCambios({
    required String entidadId,
  }) async {
    final resultados = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND parametro = ?',
      whereArgs: [entidadId, 'tipo_entidad'],
      orderBy: 'fecha_configuracion DESC',
    );

    return resultados;
  }

  /// Genera reporte de configuraciones de entidades
  Future<Map<String, dynamic>> generarReporteConfiguraciones({
    TipoEntidad? tipo,
  }) async {
    String query = '''
      SELECT * FROM configuracion_entidad
      WHERE parametro = ? AND vigente = 1 AND estado = ?
    ''';
    List<dynamic> args = ['tipo_entidad', 'activo'];

    if (tipo != null) {
      query += ' AND tipo = ?';
      args.add(tipo.name);
    }

    final configuraciones = await db.rawQuery(query, args);

    // Por tipo
    final porTipo = <String, int>{};
    for (final c in configuraciones) {
      final tipo = c['tipo']?.toString();
      if (tipo == null || tipo.isEmpty) continue;
      porTipo[tipo] = (porTipo[tipo] ?? 0) + 1;
    }

    // Por subtipo
    final porSubtipo = <String, int>{};
    for (final c in configuraciones) {
      final subtipo = c['subtipo']?.toString();
      if (subtipo != null) {
        porSubtipo[subtipo] = (porSubtipo[subtipo] ?? 0) + 1;
      }
    }

    return {
      'total_configuraciones': configuraciones.length,
      'por_tipo': porTipo,
      'por_subtipo': porSubtipo,
      'detalles': configuraciones,
    };
  }
}
