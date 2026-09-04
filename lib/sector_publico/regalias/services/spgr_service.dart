/// Servicio de SPGR (Sistema de Presupuesto y Giro de Regalías)
/// Gestión de bienios presupuestales SGR, proyectos OCAD (vinculados a MGA) y giros MinHacienda
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/proyecto_ocad.dart';
import '../models/bienio_sgr.dart';
import '../models/reporte_spgr.dart';
import '../../security/auditoria_service.dart';
import '../../models/registro_auditoria.dart';

class SPGRService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SPGRService({required this.db, required this.auditoriaService});

  /// Crea o registra un Bienio Presupuestal SGR
  Future<BienioSGR> crearBienioSGR({
    required String entidadId,
    required String usuarioId,
    required String codigoBienio,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required MoneyValue montoPresupuestado,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    final bienio = BienioSGR(
      id: id,
      entidadId: entidadId,
      codigoBienio: codigoBienio,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      montoPresupuestadoBienio: montoPresupuestado,
      montoEjecutadoBienio: publicMoneyZero(),
      estado: EstadoBienioSGR.vigente,
      observaciones: observaciones,
    );

    await db.insert('bienios_sgr', bienio.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'crear_bienio_sgr',
      valorAnterior: {},
      valorNuevo: {'bienio_id': id, 'codigo_bienio': codigoBienio},
      referenciaId: id,
    );

    return bienio;
  }

  /// Consultar Bienios SGR
  Future<List<BienioSGR>> consultarBieniosSGR({
    required String entidadId,
  }) async {
    final result = await db.query(
      'bienios_sgr',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
      orderBy: 'codigo_bienio DESC',
    );
    return result.map((r) => BienioSGR.fromJson(r)).toList();
  }

  /// Registra un nuevo proyecto OCAD vinculado a un Proyecto MGA y Bienio SGR
  Future<ProyectoOCAD> crearProyectoOCAD({
    required String entidadId,
    required String usuarioId,
    String? proyectoMgaId,
    String? bienioId,
    required String codigoBPIN,
    required String nombreProyecto,
    required String bienalidad,
    required TipoOCAD tipoOCAD,
    required MoneyValue montoAprobado,
    required DateTime fechaAprobacion,
    required String actaAprobacion,
    required String fuenteFinanciacion,
    required String entidadEjecutora,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    final proyecto = ProyectoOCAD(
      id: id,
      entidadId: entidadId,
      proyectoMgaId: proyectoMgaId,
      bienioId: bienioId,
      codigoBPIN: codigoBPIN,
      nombreProyecto: nombreProyecto,
      bienalidad: bienalidad,
      tipoOCAD: tipoOCAD,
      montoAprobado: montoAprobado,
      montoGiroSPGR: publicMoneyZero(),
      estadoOCAD: EstadoOCAD.aprobado,
      fechaAprobacion: fechaAprobacion,
      actaAprobacion: actaAprobacion,
      fuenteFinanciacion: fuenteFinanciacion,
      entidadEjecutora: entidadEjecutora,
      observaciones: observaciones,
    );

    await db.insert('proyectos_ocad', proyecto.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'crear_proyecto_ocad',
      valorAnterior: {},
      valorNuevo: {
        'proyecto_id': id,
        'bpin': codigoBPIN,
        'proyecto_mga_id': proyectoMgaId,
        'bienio_id': bienioId,
        'monto_aprobado': montoAprobado.toSql(),
        'bienalidad': bienalidad,
        'acta_aprobacion': actaAprobacion,
        'fuente_financiacion': fuenteFinanciacion,
        'entidad_ejecutora': entidadEjecutora,
      },
      referenciaId: id,
    );

    return proyecto;
  }

  /// Registra un giro desde el SPGR (Ministerio de Hacienda / DNP)
  Future<ProyectoOCAD> registrarGiroSPGR({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    required MoneyValue montoGiro,
  }) async {
    final res = await db.query(
      'proyectos_ocad',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );
    if (res.isEmpty) throw Exception('Proyecto OCAD no encontrado');

    final proy = ProyectoOCAD.fromJson(res.first);

    if (montoGiro > proy.saldoPendienteGiro) {
      throw Exception(
        'El monto del giro excede el saldo pendiente del proyecto',
      );
    }

    final nuevoGiroTotal = proy.montoGiroSPGR + montoGiro;
    final nuevoEstado = nuevoGiroTotal >= proy.montoAprobado
        ? EstadoOCAD.ejecucion
        : proy.estadoOCAD;

    await db.update(
      'proyectos_ocad',
      {
        'monto_giro_spgr': nuevoGiroTotal.toSql(),
        'estado_ocad': nuevoEstado.name,
      },
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'regalias',
      accion: 'registrar_giro_spgr',
      valorAnterior: {'monto_giro_anterior': proy.montoGiroSPGR.toSql()},
      valorNuevo: {
        'monto_giro_adicional': montoGiro.toSql(),
        'monto_giro_total': nuevoGiroTotal.toSql(),
      },
      referenciaId: proyectoId,
    );

    return ProyectoOCAD(
      id: proy.id,
      entidadId: proy.entidadId,
      proyectoMgaId: proy.proyectoMgaId,
      bienioId: proy.bienioId,
      codigoBPIN: proy.codigoBPIN,
      nombreProyecto: proy.nombreProyecto,
      bienalidad: proy.bienalidad,
      tipoOCAD: proy.tipoOCAD,
      montoAprobado: proy.montoAprobado,
      montoGiroSPGR: nuevoGiroTotal,
      estadoOCAD: nuevoEstado,
      fechaAprobacion: proy.fechaAprobacion,
      actaAprobacion: proy.actaAprobacion,
      fuenteFinanciacion: proy.fuenteFinanciacion,
      entidadEjecutora: proy.entidadEjecutora,
      observaciones: proy.observaciones,
    );
  }

  /// Consultar Proyectos OCAD
  Future<List<ProyectoOCAD>> consultarProyectosOCAD({
    required String entidadId,
    String? bienalidad,
  }) async {
    String query = 'SELECT * FROM proyectos_ocad WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (bienalidad != null) {
      query += ' AND bienalidad = ?';
      args.add(bienalidad);
    }

    query += ' ORDER BY fecha_aprobacion DESC';
    final result = await db.rawQuery(query, args);
    return result.map((r) => ProyectoOCAD.fromJson(r)).toList();
  }

  /// Genera reporte SPGR consolidado para la bienalidad
  Future<ReporteSPGR> generarReporteSPGR({
    required String entidadId,
    required String usuarioId,
    required String bienalidad,
  }) async {
    final id = _uuid.v4();

    final proyectos = await consultarProyectosOCAD(
      entidadId: entidadId,
      bienalidad: bienalidad,
    );

    var totalAprobado = publicMoneyZero();
    var totalGirado = publicMoneyZero();

    for (final p in proyectos) {
      totalAprobado += p.montoAprobado;
      totalGirado += p.montoGiroSPGR;
    }

    final mapDatos = {
      'total_proyectos': proyectos.length,
      'total_monto_aprobado': totalAprobado.toSql(),
      'total_monto_girado_spgr': totalGirado.toSql(),
      'saldo_pendiente_giros': (totalAprobado - totalGirado).toSql(),
      'proyectos': proyectos.map((p) => p.toJson()).toList(),
    };

    final reporte = ReporteSPGR(
      id: id,
      entidadId: entidadId,
      bienalidad: bienalidad,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: mapDatos,
      estado: 'generado',
    );

    await db.insert('reportes_spgr', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'generar_reporte_spgr',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'bienalidad': bienalidad},
      referenciaId: id,
    );

    return reporte;
  }

  /// Exporta reporte SPGR a formato plano .txt oficial para el MHCP
  Future<String> exportarAPlano(String reporteId) async {
    final res = await db.query(
      'reportes_spgr',
      where: 'id = ?',
      whereArgs: [reporteId],
    );
    if (res.isEmpty) throw Exception('Reporte SPGR no encontrado');
    final reporte = ReporteSPGR.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'SPGR_MHCP_HEADER|${reporte.entidadId}|${reporte.bienalidad}|${reporte.fechaGeneracion.toIso8601String()}',
    );

    final mapDatos = reporte.datos;
    buffer.writeln(
      'SPGR_SUMMARY|TOTAL_PROYECTOS|${mapDatos['total_proyectos']}|APROBADO|${publicMoneyFromSql(mapDatos['total_monto_aprobado']).toMajorUnitsString()}|GIRADO|${publicMoneyFromSql(mapDatos['total_monto_girado_spgr']).toMajorUnitsString()}',
    );

    final listaProy = mapDatos['proyectos'] as List<dynamic>? ?? [];
    for (final p in listaProy) {
      buffer.writeln(
        'SPGR_PROJECT|${p['codigo_bpin']}|${p['nombre_proyecto']}|${p['tipo_ocad']}|${publicMoneyFromSql(p['monto_aprobado']).toMajorUnitsString()}|${publicMoneyFromSql(p['monto_giro_spgr']).toMajorUnitsString()}',
      );
    }

    buffer.writeln('SPGR_MHCP_FOOTER|ESTADO|${reporte.estado}');
    return buffer.toString();
  }
}
