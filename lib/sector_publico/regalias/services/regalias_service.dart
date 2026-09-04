/// Servicio de Regalías (SGR)
/// Sistema General de Regalías - Ley 141 de 1993
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/regalia.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class RegaliasService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  RegaliasService({required this.db, required this.auditoriaService});

  /// Estima una regalía
  Future<Regalia> estimarRegalia({
    required String entidadId,
    required String usuarioId,
    required TipoRegalia tipoRegalia,
    required String proyecto,
    required String municipio,
    required String departamento,
    required MoneyValue valorEstimado,
    required DateTime vigencia,
  }) async {
    final id = _uuid.v4();
    final numeroRegalia =
        'RG-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaEstimacion = DateTime.now();

    final regalia = Regalia(
      id: id,
      entidadId: entidadId,
      numeroRegalia: numeroRegalia,
      tipoRegalia: tipoRegalia,
      proyecto: proyecto,
      municipio: municipio,
      departamento: departamento,
      valorEstimado: valorEstimado,
      valorRecibido: publicMoneyZero(),
      valorDistribuido: publicMoneyZero(),
      valorAsignado: publicMoneyZero(),
      valorEjecutado: publicMoneyZero(),
      vigencia: vigencia,
      fechaEstimacion: fechaEstimacion,
      estado: EstadoRegalia.estimada,
    );

    await db.insert('regalias', regalia.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'estimacion_regalia',
      valorAnterior: {},
      valorNuevo: {
        'regalia_id': id,
        'numero_regalia': numeroRegalia,
        'valor_estimado': valorEstimado.toSql(),
      },
      referenciaId: id,
    );

    return regalia;
  }

  /// Registra recepción de regalía
  Future<Regalia> registrarRecepcion({
    required String entidadId,
    required String usuarioId,
    required String regaliaId,
    required MoneyValue valorRecibido,
  }) async {
    final regaliaResult = await db.query(
      'regalias',
      where: 'id = ?',
      whereArgs: [regaliaId],
    );

    if (regaliaResult.isEmpty) {
      throw Exception('Regalía no encontrada');
    }

    final regalia = Regalia.fromJson(regaliaResult.first);

    if (regalia.estado != EstadoRegalia.estimada) {
      throw Exception(
        'Solo se puede registrar recepción de regalías estimadas',
      );
    }

    final fechaRecepcion = DateTime.now();

    await db.update(
      'regalias',
      {
        'valor_recibido': valorRecibido.toSql(),
        'fecha_recepcion': fechaRecepcion.toIso8601String(),
        'estado': EstadoRegalia.recibida.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [regaliaId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'regalias',
      accion: 'recepcion_regalia',
      valorAnterior: {'estado_anterior': regalia.estado.toString()},
      valorNuevo: {
        'valor_recibido': valorRecibido.toSql(),
        'estado_nuevo': EstadoRegalia.recibida.toString(),
      },
      referenciaId: regaliaId,
    );

    return regalia.copyWith(
      valorRecibido: valorRecibido,
      fechaRecepcion: fechaRecepcion,
      estado: EstadoRegalia.recibida,
    );
  }

  Future<List<Regalia>> consultarRegalias({
    required String entidadId,
    EstadoRegalia? estado,
  }) async {
    String query = 'SELECT * FROM regalias WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_estimacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => Regalia.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
