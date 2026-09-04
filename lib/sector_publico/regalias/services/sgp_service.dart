/// Servicio de SGP (Sistema General de Participaciones)
/// Ley 1176 de 2007
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/sgp.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class SGPService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  SGPService({required this.db, required this.auditoriaService});

  /// Asigna un SGP
  Future<SGP> asignarSGP({
    required String entidadId,
    required String usuarioId,
    required TipoParticipacion tipoParticipacion,
    required String programa,
    required String municipio,
    required String departamento,
    required MoneyValue valorAsignado,
    required DateTime vigencia,
  }) async {
    final id = _uuid.v4();
    final numeroSGP =
        'SGP-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaAsignacion = DateTime.now();

    final sgp = SGP(
      id: id,
      entidadId: entidadId,
      numeroSGP: numeroSGP,
      tipoParticipacion: tipoParticipacion,
      programa: programa,
      municipio: municipio,
      departamento: departamento,
      valorAsignado: valorAsignado,
      valorTransferido: publicMoneyZero(),
      valorRecibido: publicMoneyZero(),
      valorEjecutado: publicMoneyZero(),
      saldoDisponible: valorAsignado,
      vigencia: vigencia,
      fechaAsignacion: fechaAsignacion,
      estado: EstadoSGP.asignado,
    );

    await db.insert('sgp', sgp.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'asignacion_sgp',
      valorAnterior: {},
      valorNuevo: {
        'sgp_id': id,
        'numero_sgp': numeroSGP,
        'valor_asignado': valorAsignado.toSql(),
      },
      referenciaId: id,
    );

    return sgp;
  }

  /// Registra transferencia de SGP
  Future<SGP> registrarTransferencia({
    required String entidadId,
    required String usuarioId,
    required String sgpId,
    required MoneyValue valorTransferido,
  }) async {
    final sgpResult = await db.query(
      'sgp',
      where: 'id = ?',
      whereArgs: [sgpId],
    );

    if (sgpResult.isEmpty) {
      throw Exception('SGP no encontrado');
    }

    final sgp = SGP.fromJson(sgpResult.first);

    if (sgp.estado != EstadoSGP.asignado) {
      throw Exception('Solo se puede transferir SGP asignado');
    }

    if (valorTransferido > sgp.valorAsignado) {
      throw Exception('El valor excede el valor asignado');
    }

    final fechaTransferencia = DateTime.now();

    await db.update(
      'sgp',
      {
        'valor_transferido': valorTransferido.toSql(),
        'fecha_transferencia': fechaTransferencia.toIso8601String(),
        'estado': EstadoSGP.transferido.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [sgpId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'regalias',
      accion: 'transferencia_sgp',
      valorAnterior: {'estado_anterior': sgp.estado.toString()},
      valorNuevo: {
        'valor_transferido': valorTransferido.toSql(),
        'estado_nuevo': EstadoSGP.transferido.toString(),
      },
      referenciaId: sgpId,
    );

    return sgp.copyWith(
      valorTransferido: valorTransferido,
      fechaTransferencia: fechaTransferencia,
      estado: EstadoSGP.transferido,
    );
  }

  /// Registra ejecución de SGP
  Future<void> configurarDestinacionRubro({
    required String id,
    required String entidadId,
    required String sgpId,
    required String codigoRubro,
  }) async {
    final asignacion = await db.query(
      'sgp',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [sgpId, entidadId],
    );
    if (asignacion.isEmpty) {
      throw Exception('SGP no encontrado para la entidad');
    }
    await db.insert('sgp_destinaciones_rubro', {
      'id': id,
      'entidad_id': entidadId,
      'sgp_id': sgpId,
      'codigo_rubro': codigoRubro,
      'componente': asignacion.first['tipo_participacion'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<SGP> registrarEjecucion({
    required String entidadId,
    required String usuarioId,
    required String sgpId,
    required String codigoRubro,
    required MoneyValue montoEjecucion,
  }) async {
    final sgpResult = await db.query(
      'sgp',
      where: 'id = ?',
      whereArgs: [sgpId],
    );

    if (sgpResult.isEmpty) {
      throw Exception('SGP no encontrado');
    }

    final sgp = SGP.fromJson(sgpResult.first);
    final destino = await db.query(
      'sgp_destinaciones_rubro',
      where:
          'sgp_id = ? AND codigo_rubro = ? AND componente = ? AND activo = 1',
      whereArgs: [sgpId, codigoRubro, sgp.tipoParticipacion.name],
    );
    if (destino.isEmpty) {
      throw Exception(
        'Bloqueado: rubro no autorizado para el componente SGP ${sgp.tipoParticipacion.name}',
      );
    }

    if (!sgp.tieneSaldo()) {
      throw Exception('No hay saldo disponible');
    }

    if (montoEjecucion > sgp.saldoDisponible) {
      throw Exception('El monto excede el saldo disponible');
    }

    final nuevoValorEjecutado = sgp.valorEjecutado + montoEjecucion;
    final nuevoSaldo = sgp.saldoDisponible - montoEjecucion;

    await db.update(
      'sgp',
      {
        'valor_ejecutado': nuevoValorEjecutado.toSql(),
        'saldo_disponible': nuevoSaldo.toSql(),
        'estado': EstadoSGP.enEjecucion.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [sgpId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'regalias',
      accion: 'ejecucion_sgp',
      valorAnterior: {
        'valor_ejecutado_anterior': sgp.valorEjecutado.toSql(),
        'saldo_anterior': sgp.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'monto_ejecucion': montoEjecucion.toSql(),
        'codigo_rubro': codigoRubro,
        'valor_ejecutado_nuevo': nuevoValorEjecutado.toSql(),
        'saldo_nuevo': nuevoSaldo.toSql(),
      },
      referenciaId: sgpId,
    );

    return sgp.copyWith(
      valorEjecutado: nuevoValorEjecutado,
      saldoDisponible: nuevoSaldo,
      estado: EstadoSGP.enEjecucion,
    );
  }

  Future<List<SGP>> consultarSGP({
    required String entidadId,
    EstadoSGP? estado,
  }) async {
    String query = 'SELECT * FROM sgp WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_asignacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => SGP.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
