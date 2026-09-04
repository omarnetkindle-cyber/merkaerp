/// Servicio de Reporte y Certificación SICODIS SGP (DNP Colombia)
/// Certificación de destinación de recursos SGP (Educación, Salud, Agua Potable, Propósito General)
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/reporte_sicodis.dart';
import '../../security/auditoria_service.dart';
import '../../models/registro_auditoria.dart';

class SICODISService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SICODISService({required this.db, required this.auditoriaService});

  /// Genera la certificación de destinación SICODIS para SGP
  Future<ReporteSICODIS> generarCertificacionSICODIS({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String sectorParticipacion,
  }) async {
    final id = _uuid.v4();

    final resSGP = await db.rawQuery(
      'SELECT SUM(valor_asignado) as total_asignado, SUM(valor_ejecutado) as total_ejecutado FROM sgp WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );

    final rowSgp = resSGP.first;
    final asignado = publicMoneyFromSql(
      rowSgp['total_asignado'],
      nullableAsZero: true,
    );
    final ejecutado = publicMoneyFromSql(
      rowSgp['total_ejecutado'],
      nullableAsZero: true,
    );

    final datos = {
      'sector': sectorParticipacion,
      'vigencia': vigencia,
      'monto_asignado_sgp': publicMoneyForDisplay(asignado),
      'monto_ejecutado_sgp': publicMoneyForDisplay(ejecutado),
      'porcentaje_cumplimiento_destinacion': asignado > publicMoneyZero()
          ? (ejecutado.minorUnits / asignado.minorUnits) * 100.0
          : 100.0,
      'cumple_normativa_ley_1176': ejecutado <= asignado,
    };

    final reporte = ReporteSICODIS(
      id: id,
      entidadId: entidadId,
      vigencia: vigencia,
      sectorParticipacion: sectorParticipacion,
      fechaGeneracion: DateTime.now(),
      usuarioGenero: usuarioId,
      datos: datos,
      estado: 'generado',
    );

    await db.insert('reportes_sicodis', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'generar_certificacion_sicodis',
      valorAnterior: {},
      valorNuevo: {
        'reporte_id': id,
        'vigencia': vigencia,
        'sector': sectorParticipacion,
      },
      referenciaId: id,
    );

    return reporte;
  }

  /// Exporta el reporte SICODIS a plano oficial DNP (.txt / CSV)
  Future<String> exportarAPlano(String reporteId) async {
    final res = await db.query(
      'reportes_sicodis',
      where: 'id = ?',
      whereArgs: [reporteId],
    );
    if (res.isEmpty) throw Exception('Reporte SICODIS no encontrado');
    final rep = ReporteSICODIS.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'SICODIS_DNP_HEADER|${rep.entidadId}|${rep.vigencia}|${rep.sectorParticipacion}|${rep.fechaGeneracion.toIso8601String()}',
    );

    rep.datos.forEach((k, v) {
      buffer.writeln('SICODIS_DATA|$k|$v');
    });

    buffer.writeln('SICODIS_DNP_FOOTER|ESTADO|${rep.estado}');
    return buffer.toString();
  }
}
