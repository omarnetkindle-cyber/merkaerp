/// Vincula rubros presupuestales a metas MGA y calcula desviaciones de avance.
library;

import 'package:sqflite/sqflite.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

class SeguimientoProyectoRubroMeta {
  const SeguimientoProyectoRubroMeta({
    required this.metaCodigo,
    required this.avanceFisicoPorcentaje,
    required this.ejecucionFinancieraPorcentaje,
    required this.alertaDesviacion,
  });

  final String metaCodigo;
  final double avanceFisicoPorcentaje;
  final double ejecucionFinancieraPorcentaje;
  final bool alertaDesviacion;
}

class MetaPresupuestalSugerida {
  const MetaPresupuestalSugerida({
    required this.proyectoId,
    required this.codigoBPIN,
    required this.nombreProyecto,
    required this.apropiacionId,
    required this.codigoRubro,
    required this.metaCodigo,
    required this.metaDescripcion,
    required this.avanceFisicoPorcentaje,
  });

  final String proyectoId;
  final String codigoBPIN;
  final String nombreProyecto;
  final String apropiacionId;
  final String codigoRubro;
  final String metaCodigo;
  final String metaDescripcion;
  final double avanceFisicoPorcentaje;
}

class TrazabilidadPlanPresupuestoService {
  const TrazabilidadPlanPresupuestoService(this._db);

  final DatabaseExecutor _db;

  Future<void> vincularRubroAMeta({
    required String id,
    required String entidadId,
    required String proyectoId,
    required String apropiacionId,
    required String metaCodigo,
    required String metaDescripcion,
    required double avanceFisicoPorcentaje,
    required DateTime fechaReporte,
  }) async {
    if (avanceFisicoPorcentaje < 0 || avanceFisicoPorcentaje > 100) {
      throw ArgumentError.value(
        avanceFisicoPorcentaje,
        'avanceFisicoPorcentaje',
        'Debe estar entre 0 y 100',
      );
    }

    final proyecto = await _db.query(
      'proyectos_mga',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [proyectoId, entidadId],
    );
    final apropiacion = await _db.query(
      'apropiaciones',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [apropiacionId, entidadId],
    );
    if (proyecto.isEmpty || apropiacion.isEmpty) {
      throw StateError(
        'Proyecto y apropiacion deben pertenecer a la misma entidad',
      );
    }

    await _db.insert('proyecto_rubros_metas', {
      'id': id,
      'entidad_id': entidadId,
      'proyecto_id': proyectoId,
      'apropiacion_id': apropiacionId,
      'meta_codigo': metaCodigo,
      'meta_descripcion': metaDescripcion,
      'avance_fisico_porcentaje': avanceFisicoPorcentaje,
      'fecha_reporte': fechaReporte.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<MetaPresupuestalSugerida>> sugerirMetasParaApropiacion({
    required String entidadId,
    required String apropiacionId,
  }) async {
    final filas = await _db.rawQuery(
      '''
      SELECT p.id AS proyecto_id, p.codigo_bpin, p.nombre_proyecto,
             a.id AS apropiacion_id, a.codigo_rubro,
             m.meta_codigo, m.meta_descripcion,
             m.avance_fisico_porcentaje
      FROM proyecto_rubros_metas m
      JOIN proyectos_mga p
        ON p.id = m.proyecto_id
       AND p.entidad_id = m.entidad_id
      JOIN apropiaciones a
        ON a.id = m.apropiacion_id
       AND a.entidad_id = m.entidad_id
      WHERE m.entidad_id = ? AND m.apropiacion_id = ?
      ORDER BY p.codigo_bpin, m.meta_codigo
    ''',
      [entidadId, apropiacionId],
    );

    return filas.map((fila) {
      return MetaPresupuestalSugerida(
        proyectoId: fila['proyecto_id'] as String,
        codigoBPIN: fila['codigo_bpin'] as String,
        nombreProyecto: fila['nombre_proyecto'] as String,
        apropiacionId: fila['apropiacion_id'] as String,
        codigoRubro: fila['codigo_rubro'] as String,
        metaCodigo: fila['meta_codigo'] as String,
        metaDescripcion: fila['meta_descripcion'] as String,
        avanceFisicoPorcentaje: (fila['avance_fisico_porcentaje'] as num)
            .toDouble(),
      );
    }).toList();
  }

  Future<MetaPresupuestalSugerida> validarMetaParaApropiacion({
    required String entidadId,
    required String apropiacionId,
    required String proyectoId,
    required String metaCodigo,
  }) async {
    final sugeridas = await sugerirMetasParaApropiacion(
      entidadId: entidadId,
      apropiacionId: apropiacionId,
    );
    for (final meta in sugeridas) {
      if (meta.proyectoId == proyectoId && meta.metaCodigo == metaCodigo) {
        return meta;
      }
    }
    throw StateError(
      'La meta $metaCodigo del proyecto $proyectoId no esta vinculada '
      'al rubro presupuestal de la apropiacion $apropiacionId.',
    );
  }

  Future<void> registrarTrazabilidadCDP({
    required String id,
    required String entidadId,
    required String cdpId,
    required String apropiacionId,
    required String proyectoId,
    required String metaCodigo,
    required DateTime fechaVinculacion,
  }) async {
    final meta = await validarMetaParaApropiacion(
      entidadId: entidadId,
      apropiacionId: apropiacionId,
      proyectoId: proyectoId,
      metaCodigo: metaCodigo,
    );

    await _db.insert('cdp_meta_trazabilidad', {
      'id': id,
      'entidad_id': entidadId,
      'cdp_id': cdpId,
      'proyecto_id': proyectoId,
      'apropiacion_id': apropiacionId,
      'meta_codigo': meta.metaCodigo,
      'meta_descripcion': meta.metaDescripcion,
      'codigo_bpin': meta.codigoBPIN,
      'codigo_rubro': meta.codigoRubro,
      'fecha_vinculacion': fechaVinculacion.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> registrarTrazabilidadRPDesdeCDP({
    required String id,
    required String entidadId,
    required String rpId,
    required String cdpId,
    required DateTime fechaVinculacion,
  }) async {
    final cdpTrace = await _db.query(
      'cdp_meta_trazabilidad',
      where: 'entidad_id = ? AND cdp_id = ?',
      whereArgs: [entidadId, cdpId],
      limit: 1,
    );
    if (cdpTrace.isEmpty) return;

    final trace = cdpTrace.single;
    await _db.insert('rp_meta_trazabilidad', {
      'id': id,
      'entidad_id': entidadId,
      'rp_id': rpId,
      'cdp_id': cdpId,
      'proyecto_id': trace['proyecto_id'],
      'meta_codigo': trace['meta_codigo'],
      'meta_descripcion': trace['meta_descripcion'],
      'codigo_bpin': trace['codigo_bpin'],
      'fecha_vinculacion': fechaVinculacion.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SeguimientoProyectoRubroMeta>> consultarSeguimiento({
    required String entidadId,
    required String proyectoId,
  }) async {
    final filas = await _db.rawQuery(
      '''
      SELECT m.meta_codigo, m.avance_fisico_porcentaje,
             a.valor_apropiado, a.valor_pagado
      FROM proyecto_rubros_metas m
      JOIN apropiaciones a ON a.id = m.apropiacion_id
      WHERE m.entidad_id = ? AND m.proyecto_id = ?
    ''',
      [entidadId, proyectoId],
    );

    return filas.map((fila) {
      final apropiado = publicMoneyFromSql(fila['valor_apropiado']);
      final pagado = publicMoneyFromSql(fila['valor_pagado']);
      final financiero = apropiado == publicMoneyZero()
          ? 0.0
          : (pagado.minorUnits / apropiado.minorUnits) * 100;
      final fisico = (fila['avance_fisico_porcentaje'] as num).toDouble();
      return SeguimientoProyectoRubroMeta(
        metaCodigo: fila['meta_codigo'] as String,
        avanceFisicoPorcentaje: fisico,
        ejecucionFinancieraPorcentaje: financiero,
        alertaDesviacion: (financiero - fisico).abs() > 20,
      );
    }).toList();
  }
}
