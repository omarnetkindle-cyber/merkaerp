/// Servicio de Rendición de Cuentas SIA Observa (Contraloría General de la República - CGR)
/// Integración de Contratación, Presupuesto y Nómina para Plan de Mejoramiento Anual
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/reporte_sia_observa.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';

class SIAObservaService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SIAObservaService({required this.db, required this.auditoriaService});

  Future<RolSectorPublico> _validarPermiso({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    if (rol == null) {
      throw Exception(
        'Acceso denegado: El usuario $usuarioId no tiene un rol asignado en la entidad $entidadId',
      );
    }

    if (!RolesPermisosService.tienePermiso(rol, permiso)) {
      throw Exception(
        'Acceso denegado: El rol ${rol.name} no tiene permiso para ${permiso.name}',
      );
    }

    return rol;
  }

  /// Genera reporte anual de Plan de Mejoramiento SIA Observa
  ///
  /// NOTA NORMATIVA CONTRALORÍA: Formato oficial de cargue masivo para la plataforma SIA Observa
  /// de la Contraloría General de la República (CGR) sobre contratación estatal y ejecución del gasto.
  Future<ReporteSIAObserva> generarReportePlanMejoramiento({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int hallazgosAtendidos,
    required int accionesImplementadas,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.consultarAuditoria,
    );
    final id = _uuid.v4();

    // 1. Consultar Contratación Estatal
    final resContratos = await db.rawQuery(
      "SELECT COUNT(*) as total_count, SUM(valor_contrato) as valor_total FROM contratos WHERE entidad_id = ? AND strftime('%Y', fecha_firma) = ?",
      [entidadId, vigencia],
    );
    final rowContratos = resContratos.first;
    final int totalContratos =
        (rowContratos['total_count'] as num?)?.toInt() ?? 0;
    final valorContratado = publicMoneyFromSql(
      rowContratos['valor_total'],
      nullableAsZero: true,
    );

    // 2. Consultar Ejecución Presupuestal de Gastos (Pagos)
    final resPagos = await db.rawQuery(
      'SELECT SUM(valor_pago) as total_pagos FROM pagos WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalPagadoPresupuesto = publicMoneyFromSql(
      resPagos.first['total_pagos'],
      nullableAsZero: true,
    );

    // 3. Consultar Nómina Liquidada (Tabla real: liquidaciones_nomina)
    final resNomina = await db.rawQuery(
      'SELECT SUM(neto_pagar) as total_nomina FROM liquidaciones_nomina WHERE entidad_id = ? AND periodo LIKE ?',
      [entidadId, '$vigencia%'],
    );
    final totalNomina = publicMoneyFromSql(
      resNomina.first['total_nomina'],
      nullableAsZero: true,
    );

    final double cumplimientoPct =
        (accionesImplementadas > 0 && hallazgosAtendidos > 0)
        ? (accionesImplementadas / hallazgosAtendidos) * 100.0
        : 100.0;

    final datos = DatosSIAObservaPlan(
      totalHallazgosAtendidos: hallazgosAtendidos,
      totalAccionesImplementadas: accionesImplementadas,
      totalContratosAuditados: totalContratos,
      valorTotalContratado: valorContratado,
      valorTotalEjecutadoPresupuesto: totalPagadoPresupuesto,
      valorTotalNominaLiquidada: totalNomina,
      cumplimientoPorcentaje: cumplimientoPct > 100.0 ? 100.0 : cumplimientoPct,
    );

    final reporte = ReporteSIAObserva(
      id: id,
      entidadId: entidadId,
      tipoReporte: TipoReporteSIAObserva.planMejoramiento,
      vigencia: vigencia,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_sia_observa', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generar_reporte_sia_observa',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Consulta reportes SIA Observa por entidad y vigencia
  Future<List<ReporteSIAObserva>> consultarReportes({
    required String entidadId,
    String? vigencia,
  }) async {
    String query = 'SELECT * FROM reportes_sia_observa WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (vigencia != null) {
      query += ' AND vigencia = ?';
      args.add(vigencia);
    }

    query += ' ORDER BY fecha_generacion DESC';
    final result = await db.rawQuery(query, args);
    return result.map((r) => ReporteSIAObserva.fromJson(r)).toList();
  }

  /// Exporta reporte SIA Observa a archivo plano .txt para la CGR
  Future<String> exportarAPlano(String reporteId) async {
    final res = await db.query(
      'reportes_sia_observa',
      where: 'id = ?',
      whereArgs: [reporteId],
    );
    if (res.isEmpty) throw Exception('Reporte SIA Observa no encontrado');
    final reporte = ReporteSIAObserva.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'SIA_OBSERVA_HEADER|${reporte.entidadId}|${reporte.vigencia}|${reporte.tipoReporte.name}|${reporte.fechaGeneracion.toIso8601String()}',
    );

    final mapDatos = reporte.datos;
    mapDatos.forEach((k, v) {
      buffer.writeln('SIA_RECORD|$k|$v');
    });

    buffer.writeln(
      'SIA_OBSERVA_FOOTER|TOTAL_RECORDS|${mapDatos.length}|ESTADO|${reporte.estado}',
    );
    return buffer.toString();
  }
}
