/// Servicio de Matriz de Visibilidad de Módulos
/// Define qué módulos son visibles según tipo y subtipo de entidad
/// Matriz definitiva de configuración de módulos
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum Modulo {
  presupuesto,
  contabilidad,
  auditoria,
  rentas,
  contratacion,
  nomina,
  planeacion,
  activos,
  salud,
  regalias,
  transparencia,
}

class MatrizVisibilidadService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  // Matriz de visibilidad definitiva según tipo/subtipo de entidad
  static const Map<String, Set<Modulo>> _matrizDefinitiva = {
    // Departamentos
    'departamento': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.salud,
      Modulo.regalias,
      Modulo.transparencia,
    },
    // Municipios - Categoría Especial
    'municipio_categoriaEspecial': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.salud,
      Modulo.regalias,
      Modulo.transparencia,
    },
    // Municipios - Categoría Primera
    'municipio_categoriaPrimera': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.salud,
      Modulo.transparencia,
    },
    // Municipios - Categoría Segunda
    'municipio_categoriaSegunda': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.transparencia,
    },
    // Municipios - Categoría Tercera
    'municipio_categoriaTercera': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.transparencia,
    },
    // Municipios - Categoría Cuarta
    'municipio_categoriaCuarta': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.transparencia,
    },
    // Municipios - Categoría Quinta
    'municipio_categoriaQuinta': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.transparencia,
    },
    // Municipios - Categoría Sexta
    'municipio_categoriaSexta': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.transparencia,
    },
    // Distrito Capital
    'distrito_distritoCapital': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.salud,
      Modulo.regalias,
      Modulo.transparencia,
    },
    // Distrito Especial
    'distrito_distritoEspecial': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.salud,
      Modulo.transparencia,
    },
    // Distrito Turístico
    'distrito_distritoTuristico': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.transparencia,
    },
    // Distrito Cultural
    'distrito_distritoCultural': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.rentas,
      Modulo.contratacion,
      Modulo.nomina,
      Modulo.planeacion,
      Modulo.activos,
      Modulo.transparencia,
    },
    // Región Metropolitana
    'regionMetropolitana': {
      Modulo.presupuesto,
      Modulo.contabilidad,
      Modulo.auditoria,
      Modulo.planeacion,
      Modulo.transparencia,
    },
  };

  MatrizVisibilidadService({required this.db, required this.auditoriaService});

  static Future<void> poblarMatrizInicial(DatabaseExecutor db) async {
    final existente = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM modulos_por_tipo_entidad'),
    );
    if ((existente ?? 0) > 0) return;

    final batch = db.batch();
    for (final entrada in _matrizDefinitiva.entries) {
      final separador = entrada.key.indexOf('_');
      final tipo = separador == -1
          ? entrada.key
          : entrada.key.substring(0, separador);
      final subtipo = separador == -1
          ? ''
          : entrada.key.substring(separador + 1);
      for (final modulo in entrada.value) {
        batch.insert('modulos_por_tipo_entidad', {
          'tipo': tipo,
          'subtipo': subtipo,
          'modulo': modulo.name,
        });
      }
    }
    await batch.commit(noResult: true);
  }

  /// Obtiene los módulos visibles para un tipo/subtipo de entidad
  Future<Set<Modulo>> obtenerModulosVisibles({
    required String tipo,
    String? subtipo,
  }) async {
    var resultado = await db.query(
      'modulos_por_tipo_entidad',
      where: 'tipo = ? AND subtipo = ?',
      whereArgs: [tipo, subtipo ?? ''],
    );
    if (resultado.isEmpty && subtipo != null) {
      resultado = await db.query(
        'modulos_por_tipo_entidad',
        where: 'tipo = ? AND subtipo = ?',
        whereArgs: [tipo, ''],
      );
    }
    final nombres = resultado
        .map((fila) => fila['modulo']?.toString())
        .whereType<String>()
        .toSet();
    return Modulo.values
        .where((modulo) => nombres.contains(modulo.name))
        .toSet();
  }

  /// Verifica si un módulo es visible para un tipo/subtipo
  Future<bool> esModuloVisible({
    required String tipo,
    String? subtipo,
    required Modulo modulo,
  }) async {
    final modulosVisibles = await obtenerModulosVisibles(
      tipo: tipo,
      subtipo: subtipo,
    );
    return modulosVisibles.contains(modulo);
  }

  /// Configura una visibilidad personalizada (sobrescribe la matriz definitiva)
  Future<Map<String, dynamic>> configurarVisibilidadPersonalizada({
    required String entidadId,
    required String usuarioId,
    required String tipo,
    String? subtipo,
    required Set<Modulo> modulosHabilitados,
    required String motivo,
  }) async {
    final id = _uuid.v4();

    await db.insert('configuracion_visibilidad', {
      'id': id,
      'entidad_id': entidadId,
      'tipo': tipo,
      'subtipo': subtipo,
      'modulos_habilitados': modulosHabilitados
          .map((e) => e.toString().split('.').last)
          .join(','),
      'motivo': motivo,
      'fecha_configuracion': DateTime.now().toIso8601String(),
      'configurado_por': usuarioId,
      'estado': 'activo',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'configuracion',
      accion: 'configuracion_visibilidad_personalizada',
      valorAnterior: {},
      valorNuevo: {
        'configuracion_id': id,
        'tipo': tipo,
        'subtipo': subtipo,
        'modulos_habilitados': modulosHabilitados.length,
      },
      referenciaId: id,
    );

    return {
      'configuracion_id': id,
      'tipo': tipo,
      'subtipo': subtipo,
      'modulos_habilitados': modulosHabilitados.length,
      'estado': 'activo',
    };
  }

  /// Consulta la configuración de visibilidad de una entidad
  Future<Map<String, dynamic>?> consultarConfiguracionVisibilidad({
    required String entidadId,
  }) async {
    final resultado = await db.query(
      'configuracion_visibilidad',
      where: 'entidad_id = ? AND parametro = ? AND vigente = 1 AND estado = ?',
      whereArgs: [entidadId, 'tipo_entidad', 'activo'],
    );

    if (resultado.isEmpty) return null;
    return resultado.first;
  }

  /// Obtiene los módulos visibles para una entidad (considerando configuración personalizada)
  Future<Set<Modulo>> obtenerModulosVisiblesEntidad({
    required String entidadId,
  }) async {
    // Primero verificar si hay configuración personalizada
    final configPersonalizada = await consultarConfiguracionVisibilidad(
      entidadId: entidadId,
    );

    if (configPersonalizada != null) {
      final modulosStr =
          configPersonalizada['modulos_habilitados']?.toString() ?? '';
      if (modulosStr.trim().isEmpty) return {};
      final modulosLista = modulosStr.split(',');
      return modulosLista
          .map(
            (m) => Modulo.values.firstWhere(
              (e) => e.toString().split('.').last == m.trim(),
            ),
          )
          .toSet();
    }

    // Si no hay configuración personalizada, usar la configuración de tipo de entidad
    final configEntidad = await db.query(
      'configuracion_entidad',
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, 'activo'],
    );

    if (configEntidad.isEmpty) {
      return {}; // Sin configuración, sin módulos
    }

    final tipo =
        configEntidad.first['tipo']?.toString() ??
        configEntidad.first['valor']?.toString();
    if (tipo == null || tipo.isEmpty) return {};
    final subtipo = configEntidad.first['subtipo']?.toString();

    return obtenerModulosVisibles(tipo: tipo, subtipo: subtipo);
  }

  /// Restaura la configuración por defecto (matriz definitiva)
  Future<Map<String, dynamic>> restaurarConfiguracionPorDefecto({
    required String entidadId,
    required String usuarioId,
  }) async {
    final configPersonalizada = await consultarConfiguracionVisibilidad(
      entidadId: entidadId,
    );

    if (configPersonalizada != null) {
      await db.update(
        'configuracion_visibilidad',
        {'estado': 'inactivo'},
        where: 'entidad_id = ? AND estado = ?',
        whereArgs: [entidadId, 'activo'],
      );

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'configuracion',
        accion: 'restauracion_configuracion_defecto',
        valorAnterior: {'configuracion_anterior': configPersonalizada['id']},
        valorNuevo: {'configuracion_nueva': 'matriz_definitiva'},
        referenciaId: configPersonalizada['id'],
      );
    }

    return {
      'entidad_id': entidadId,
      'configuracion': 'matriz_definitiva',
      'estado': 'restaurado',
    };
  }

  /// Genera reporte de visibilidad de módulos
  Future<Map<String, dynamic>> generarReporteVisibilidad({
    String? tipo,
    String? subtipo,
  }) async {
    final modulosVisibles = await obtenerModulosVisibles(
      tipo: tipo ?? 'departamento',
      subtipo: subtipo,
    );

    return {
      'tipo': tipo,
      'subtipo': subtipo,
      'total_modulos': modulosVisibles.length,
      'modulos_visibles': modulosVisibles
          .map((e) => e.toString().split('.').last)
          .toList(),
    };
  }

  /// Obtiene la matriz completa de visibilidad
  Future<Map<String, List<String>>> obtenerMatrizCompleta() async {
    final filas = await db.query('modulos_por_tipo_entidad');
    final matriz = <String, List<String>>{};
    for (final fila in filas) {
      final tipo = fila['tipo'] as String;
      final subtipo = fila['subtipo'] as String;
      final clave = subtipo.isEmpty ? tipo : '${tipo}_$subtipo';
      matriz.putIfAbsent(clave, () => []).add(fila['modulo'] as String);
    }
    return matriz;
  }

  /// Consulta todas las configuraciones personalizadas
  Future<List<Map<String, dynamic>>> consultarConfiguracionesPersonalizadas({
    String? tipo,
  }) async {
    String query = 'SELECT * FROM configuracion_visibilidad WHERE estado = ?';
    List<dynamic> args = ['activo'];

    if (tipo != null) {
      query += ' AND tipo = ?';
      args.add(tipo);
    }

    query += ' ORDER BY fecha_configuracion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }
}
