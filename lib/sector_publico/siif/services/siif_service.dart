/// Servicio de Integración con SIIF Nación (Ministerio de Hacienda y Crédito Público)
/// Lectura de Presupuesto/Tesorería, validaciones contables y exportación a plano mensual
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/reporte_siif.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';
import '../../../integrations/application/institutional_connector_service.dart';

class SIIFService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SIIFService({required this.db, required this.auditoriaService});

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

  /// Genera reporte mensual de Presupuesto para SIIF Nación
  ///
  /// NOTA NORMATIVA MHCP: Estructura basada en las especificaciones oficiales del Ministerio de Hacienda y
  /// Crédito Público (MHCP) para la consolidación mensual del Catálogo Integrado de Clasificación Presupuestal (CICP)
  /// en la plataforma SIIF Nación II.
  Future<ReporteSIIF> generarReportePresupuestoMensual({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int mes,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.consultarAuditoria,
    );
    final id = _uuid.v4();

    // 1. Consultar Apropiaciones
    final resApropiaciones = await db.rawQuery(
      'SELECT SUM(valor_inicial) as inicial, SUM(valor_apropiado) as definitivo FROM apropiaciones WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final rowApr = resApropiaciones.first;
    final inicial = publicMoneyFromSql(rowApr['inicial'], nullableAsZero: true);
    final definitivo = publicMoneyFromSql(
      rowApr['definitivo'],
      nullableAsZero: true,
    );
    final diferenciaApropiacion = definitivo - inicial;
    final adiciones = diferenciaApropiacion.minorUnits > 0
        ? diferenciaApropiacion
        : publicMoneyZero();
    final reducciones = diferenciaApropiacion.minorUnits < 0
        ? diferenciaApropiacion.abs()
        : publicMoneyZero();

    // 2. Consultar CDP
    final resCDP = await db.rawQuery(
      'SELECT SUM(valor_cdp) as total FROM cdps WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalCDP = publicMoneyFromSql(
      resCDP.first['total'],
      nullableAsZero: true,
    );

    // 3. Consultar RP (Registros Presupuestales)
    final resRP = await db.rawQuery(
      'SELECT SUM(valor_rp) as total FROM rps WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalRP = publicMoneyFromSql(
      resRP.first['total'],
      nullableAsZero: true,
    );

    // 4. Consultar Obligaciones
    final resObl = await db.rawQuery(
      'SELECT SUM(valor_obligacion) as total FROM obligaciones WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalObligaciones = publicMoneyFromSql(
      resObl.first['total'],
      nullableAsZero: true,
    );

    // 5. Consultar Pagos
    final resPagos = await db.rawQuery(
      'SELECT SUM(valor_pago) as total FROM pagos WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalPagos = publicMoneyFromSql(
      resPagos.first['total'],
      nullableAsZero: true,
    );

    final datos = DatosSIIFPresupuesto(
      totalApropiacionInicial: inicial,
      totalAdiciones: adiciones,
      totalReducciones: reducciones,
      totalApropiacionDefinitiva: definitivo,
      totalCDP: totalCDP,
      totalRP: totalRP,
      totalObligaciones: totalObligaciones,
      totalPagos: totalPagos,
      saldoPorComprometer: definitivo - totalRP,
      saldoPorPagar: totalObligaciones - totalPagos,
    );

    // Validar cuadres contables antes de guardar
    final validacion = validarCuadresPresupuesto(datos);
    if (!validacion['valido']) {
      throw Exception(
        'Error de consistencia presupuestal para SIIF Nación: ${validacion['errores'].join(", ")}',
      );
    }

    final reporte = ReporteSIIF(
      id: id,
      entidadId: entidadId,
      tipoReporte: TipoReporteSIIF.presupuestoMensual,
      vigencia: vigencia,
      mes: mes,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_siif_nacion', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'siif',
      accion: 'generar_reporte_siif_presupuesto',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia, 'mes': mes},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera reporte mensual de Tesorería y Pagos para SIIF Nación
  Future<ReporteSIIF> generarReporteTesoreriaMensual({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int mes,
  }) async {
    final id = _uuid.v4();

    final resPagos = await db.rawQuery(
      'SELECT SUM(valor_pago) as total_bruto, 0 as total_retenciones, SUM(valor_pago) as total_neto FROM pagos WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );

    final row = resPagos.first;
    final bruto = publicMoneyFromSql(row['total_bruto'], nullableAsZero: true);
    final retenciones = publicMoneyFromSql(
      row['total_retenciones'],
      nullableAsZero: true,
    );
    final neto = publicMoneyFromSql(row['total_neto'], nullableAsZero: true);

    final datos = DatosSIIFTesoreria(
      totalPagosEfectuados: bruto,
      totalRetencionesEfectuadas: retenciones,
      totalNetoPagado: neto,
      numeroCuentasBancariasOperativas: 1,
      totalTransferenciasSIIF: neto,
    );

    final reporte = ReporteSIIF(
      id: id,
      entidadId: entidadId,
      tipoReporte: TipoReporteSIIF.tesoreriaPagos,
      vigencia: vigencia,
      mes: mes,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_siif_nacion', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'siif',
      accion: 'generar_reporte_siif_tesoreria',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia, 'mes': mes},
      referenciaId: id,
    );

    return reporte;
  }

  /// Transmite un reporte por el canal SIIF configurado por la entidad.
  /// Si no existe un servicio autorizado/configurado, la operación falla y el
  /// reporte conserva su estado local; nunca se simula aceptación.
  Future<void> transmitirReporte({
    required String reporteId,
    required String entidadId,
    required String usuarioId,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.exportarDatos,
    );
    final rows = await db.query(
      'reportes_siif_nacion',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Reporte SIIF no encontrado.');
    final reporte = ReporteSIIF.fromJson(rows.first);
    final response = await InstitutionalConnectorService.instance.postJson(
      'siif_nacion',
      payload: {
        'reporte_id': reporte.id,
        'entidad_id': reporte.entidadId,
        'tipo_reporte': reporte.tipoReporte.name,
        'vigencia': reporte.vigencia,
        'mes': reporte.mes,
        'fecha_generacion': reporte.fechaGeneracion.toUtc().toIso8601String(),
        'datos': reporte.datos,
      },
    );
    if (!response.ok) throw StateError(response.message);
    await db.update(
      'reportes_siif_nacion',
      {'estado': 'enviado', 'observaciones': response.message},
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
    );
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'siif',
      accion: 'transmision_siif_configurada',
      valorAnterior: {'estado': reporte.estado},
      valorNuevo: {'estado': 'enviado', 'http_status': response.statusCode},
      referenciaId: reporteId,
    );
  }

  /// Validaciones de consistencia matemática/presupuestal
  Map<String, dynamic> validarCuadresPresupuesto(DatosSIIFPresupuesto datos) {
    final errores = <String>[];

    if (datos.totalRP > datos.totalCDP) {
      errores.add(
        'Total Registros Presupuestales (RP: \$${datos.totalRP}) supera el Total CDP (\$${datos.totalCDP})',
      );
    }
    if (datos.totalObligaciones > datos.totalRP) {
      errores.add(
        'Total Obligaciones (\$${datos.totalObligaciones}) supera el Total RP (\$${datos.totalRP})',
      );
    }
    if (datos.totalPagos > datos.totalObligaciones) {
      errores.add(
        'Total Pagos (\$${datos.totalPagos}) supera el Total Obligaciones (\$${datos.totalObligaciones})',
      );
    }

    return {'valido': errores.isEmpty, 'errores': errores};
  }

  /// Consultar reportes SIIF de una entidad
  Future<List<ReporteSIIF>> consultarReportes({
    required String entidadId,
    String? vigencia,
    int? mes,
  }) async {
    String query = 'SELECT * FROM reportes_siif_nacion WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (vigencia != null) {
      query += ' AND vigencia = ?';
      args.add(vigencia);
    }
    if (mes != null) {
      query += ' AND mes = ?';
      args.add(mes);
    }

    query += ' ORDER BY fecha_generacion DESC';
    final result = await db.rawQuery(query, args);
    return result.map((r) => ReporteSIIF.fromJson(r)).toList();
  }

  /// Exporta reporte SIIF Nación a archivo plano (.txt)
  Future<String> exportarAPlano(String reporteId) async {
    final res = await db.query(
      'reportes_siif_nacion',
      where: 'id = ?',
      whereArgs: [reporteId],
    );
    if (res.isEmpty) throw Exception('Reporte SIIF Nación no encontrado');
    final reporte = ReporteSIIF.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'HDR|SIIF_NACION|${reporte.entidadId}|${reporte.vigencia}|${reporte.mes.toString().padLeft(2, '0')}|${reporte.tipoReporte.name}',
    );

    final mapDatos = reporte.datos;
    mapDatos.forEach((key, val) {
      buffer.writeln('DAT|$key|$val');
    });

    buffer.writeln(
      'FTR|TOTAL_CAMPOS|${mapDatos.length}|ESTADO|${reporte.estado}',
    );
    return buffer.toString();
  }
}
