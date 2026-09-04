/// Servicio de Consolidación NICSP 40
/// NICSP 40 - Información a revelar sobre transferencias
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/consolidacion_nicsp40.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class NICSP40Service {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  NICSP40Service({required this.db, required this.auditoriaService});

  /// Registra una transferencia para consolidación NICSP 40
  Future<ConsolidacionNICSP40> registrarTransferencia({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String entidadOrigen,
    required String entidadDestino,
    required TipoTransferencia tipoTransferencia,
    required String descripcion,
    required MoneyValue valorTransferido,
    required DateTime fechaTransferencia,
    String? proyecto,
  }) async {
    final id = _uuid.v4();
    final numeroConsolidacion =
        'CN-${DateTime.now().year}-${_generarNumeroSecuencial()}';

    final consolidacion = ConsolidacionNICSP40(
      id: id,
      entidadId: entidadId,
      numeroConsolidacion: numeroConsolidacion,
      vigencia: vigencia,
      entidadOrigen: entidadOrigen,
      entidadDestino: entidadDestino,
      tipoTransferencia: tipoTransferencia,
      descripcion: descripcion,
      valorTransferido: valorTransferido,
      valorEjecutado: publicMoneyZero(),
      valorNoEjecutado: valorTransferido,
      fechaTransferencia: fechaTransferencia,
      proyecto: proyecto,
    );

    await db.insert('consolidaciones_nicsp40', consolidacion.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'transparencia',
      accion: 'registro_transferencia_nicsp40',
      valorAnterior: {},
      valorNuevo: {
        'consolidacion_id': id,
        'numero_consolidacion': numeroConsolidacion,
        'valor_transferido': valorTransferido.toWireMap(),
      },
      referenciaId: id,
    );

    return consolidacion;
  }

  /// Actualiza ejecución de transferencia
  Future<ConsolidacionNICSP40> actualizarEjecucion({
    required String entidadId,
    required String usuarioId,
    required String consolidacionId,
    required MoneyValue valorEjecutado,
  }) async {
    final consolidacionResult = await db.query(
      'consolidaciones_nicsp40',
      where: 'id = ?',
      whereArgs: [consolidacionId],
    );

    if (consolidacionResult.isEmpty) {
      throw Exception('Consolidación no encontrada');
    }

    final consolidacion = ConsolidacionNICSP40.fromJson(
      consolidacionResult.first,
    );

    if (valorEjecutado > consolidacion.valorTransferido) {
      throw Exception(
        'El valor ejecutado no puede exceder el valor transferido',
      );
    }

    final valorNoEjecutado = consolidacion.valorTransferido - valorEjecutado;

    await db.update(
      'consolidaciones_nicsp40',
      {
        'valor_ejecutado': valorEjecutado.toSql(),
        'valor_no_ejecutado': valorNoEjecutado.toSql(),
      },
      where: 'id = ?',
      whereArgs: [consolidacionId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'transparencia',
      accion: 'actualizacion_ejecucion_nicsp40',
      valorAnterior: {
        'valor_ejecutado_anterior': consolidacion.valorEjecutado.toWireMap(),
        'valor_no_ejecutado_anterior': consolidacion.valorNoEjecutado
            .toWireMap(),
      },
      valorNuevo: {
        'valor_ejecutado_nuevo': valorEjecutado.toWireMap(),
        'valor_no_ejecutado_nuevo': valorNoEjecutado.toWireMap(),
      },
      referenciaId: consolidacionId,
    );

    return consolidacion.copyWith(
      valorEjecutado: valorEjecutado,
      valorNoEjecutado: valorNoEjecutado,
    );
  }

  Future<List<ConsolidacionNICSP40>> consultarConsolidaciones({
    required String entidadId,
    String? vigencia,
  }) async {
    String query = 'SELECT * FROM consolidaciones_nicsp40 WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (vigencia != null) {
      query += ' AND vigencia = ?';
      args.add(vigencia);
    }

    query += ' ORDER BY fecha_transferencia DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => ConsolidacionNICSP40.fromJson(r)).toList();
  }

  /// Genera reporte consolidado NICSP 40
  Future<Map<String, dynamic>> generarReporteNICSP40({
    required String entidadId,
    required String vigencia,
  }) async {
    final consolidaciones = await db.query(
      'consolidaciones_nicsp40',
      where: 'entidad_id = ? AND vigencia = ?',
      whereArgs: [entidadId, vigencia],
    );

    var totalTransferido = publicMoneyZero();
    var totalEjecutado = publicMoneyZero();
    var totalNoEjecutado = publicMoneyZero();
    for (final consolidacion in consolidaciones) {
      totalTransferido += publicMoneyFromSql(
        consolidacion['valor_transferido'],
      );
      totalEjecutado += publicMoneyFromSql(consolidacion['valor_ejecutado']);
      totalNoEjecutado += publicMoneyFromSql(
        consolidacion['valor_no_ejecutado'],
      );
    }

    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'total_transferencias': consolidaciones.length,
      'valor_total_transferido': publicMoneyForDisplay(totalTransferido),
      'valor_total_ejecutado': publicMoneyForDisplay(totalEjecutado),
      'valor_total_no_ejecutado': publicMoneyForDisplay(totalNoEjecutado),
      'porcentaje_ejecucion': totalTransferido > publicMoneyZero()
          ? (totalEjecutado.minorUnits / totalTransferido.minorUnits) * 100
          : 0,
    };
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
