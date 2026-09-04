/// Servicio de Consolidador y Reportador FUT Territorial (Formulario Único Territorial DNP / CHIP)
/// Consolidación trimestral de Ingresos, Gastos, Deuda Pública y Regalías para DNP
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/reporte_fut_territorial.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';

class FUTTerritorialService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  FUTTerritorialService({required this.db, required this.auditoriaService});

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

  /// Genera Formulario FUT Ingresos Trimestral DNP
  ///
  /// NOTA NORMATIVA DNP/CHIP: Formato de captura oficial del Formulario Único Territorial (FUT)
  /// administrado por el Departamento Nacional de Planeación (DNP) para la categoría de Ingresos.
  Future<ReporteFUTTerritorial> generarFUTIngresos({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int trimestre,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.consultarAuditoria,
    );
    final id = _uuid.v4();

    final resPredial = await db.rawQuery(
      'SELECT SUM(total_pagar) as total FROM liquidaciones_prediales WHERE entidad_id = ? AND vigencia = ? AND estado = ?',
      [entidadId, vigencia, 'pagada'],
    );
    final tributarioPredial = publicMoneyFromSql(
      resPredial.first['total'],
      nullableAsZero: true,
    );

    final resICA = await db.rawQuery(
      'SELECT SUM(total_pagar) as total FROM declaraciones_ica WHERE entidad_id = ? AND periodo LIKE ?',
      [entidadId, '$vigencia%'],
    );
    final tributarioICA = publicMoneyFromSql(
      resICA.first['total'],
      nullableAsZero: true,
    );

    final totalTributario = tributarioPredial + tributarioICA;

    final resRegalias = await db.rawQuery(
      'SELECT SUM(monto_aprobado) as total FROM proyectos_ocad WHERE entidad_id = ? AND bienalidad LIKE ?',
      [entidadId, '%$vigencia%'],
    );
    final totalRegalias = publicMoneyFromSql(
      resRegalias.first['total'],
      nullableAsZero: true,
    );

    final datos = DatosFUTIngresos(
      ingresosCorrientes: totalTributario,
      tributarios: totalTributario,
      noTributarios: publicMoneyZero(),
      transferenciasSGP: publicMoneyZero(),
      regalias: totalRegalias,
      totalRecaudado: totalTributario + totalRegalias,
    );

    final reporte = ReporteFUTTerritorial(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioFUTTerritorial.futIngresos,
      vigencia: vigencia,
      trimestre: trimestre,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_fut_territorial', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generar_fut_ingresos',
      valorAnterior: {},
      valorNuevo: {
        'reporte_id': id,
        'vigencia': vigencia,
        'trimestre': trimestre,
      },
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera Formulario FUT Gastos Trimestral DNP
  Future<ReporteFUTTerritorial> generarFUTGastos({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int trimestre,
  }) async {
    final id = _uuid.v4();

    final resPagos = await db.rawQuery(
      'SELECT SUM(monto_total) as total FROM pagos WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    final totalPagos = publicMoneyFromSql(
      resPagos.first['total'],
      nullableAsZero: true,
    );

    final resNomina = await db.rawQuery(
      'SELECT SUM(neto_pagar) as total FROM liquidaciones_nomina WHERE entidad_id = ? AND periodo LIKE ?',
      [entidadId, '$vigencia%'],
    );
    final totalNomina = publicMoneyFromSql(
      resNomina.first['total'],
      nullableAsZero: true,
    );

    final datos = DatosFUTGastos(
      funcionamiento: totalNomina,
      serviciosPersonales: totalNomina,
      gastosGenerales: publicMoneyZero(),
      transferencias: publicMoneyZero(),
      inversion: totalPagos > totalNomina
          ? totalPagos - totalNomina
          : publicMoneyZero(),
      servicioDeuda: publicMoneyZero(),
      totalObligado: totalPagos > totalNomina ? totalPagos : totalNomina,
    );

    final reporte = ReporteFUTTerritorial(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioFUTTerritorial.futGastos,
      vigencia: vigencia,
      trimestre: trimestre,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_fut_territorial', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generar_fut_gastos',
      valorAnterior: {},
      valorNuevo: {
        'reporte_id': id,
        'vigencia': vigencia,
        'trimestre': trimestre,
      },
      referenciaId: id,
    );

    return reporte;
  }

  /// Consulta reportes FUT por entidad y vigencia
  Future<List<ReporteFUTTerritorial>> consultarReportes({
    required String entidadId,
    String? vigencia,
    int? trimestre,
  }) async {
    String query =
        'SELECT * FROM reportes_fut_territorial WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (vigencia != null) {
      query += ' AND vigencia = ?';
      args.add(vigencia);
    }
    if (trimestre != null) {
      query += ' AND trimestre = ?';
      args.add(trimestre);
    }

    query += ' ORDER BY fecha_generacion DESC';
    final result = await db.rawQuery(query, args);
    return result.map((r) => ReporteFUTTerritorial.fromJson(r)).toList();
  }

  /// Exporta reporte FUT a formato CSV / Plano CHIP DNP
  Future<String> exportarAPlano(String reporteId) async {
    final res = await db.query(
      'reportes_fut_territorial',
      where: 'id = ?',
      whereArgs: [reporteId],
    );
    if (res.isEmpty) throw Exception('Reporte FUT no encontrado');
    final reporte = ReporteFUTTerritorial.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'FUT_DNP_HEADER;${reporte.entidadId};${reporte.vigencia};T${reporte.trimestre};${reporte.tipoFormulario.name}',
    );

    final mapDatos = reporte.datos;
    mapDatos.forEach((k, v) {
      buffer.writeln('FUT_DNP_ROW;$k;$v');
    });

    buffer.writeln(
      'FUT_DNP_FOOTER;TOTAL_REGISTROS;${mapDatos.length};ESTADO;${reporte.estado}',
    );
    return buffer.toString();
  }
}
