/// Servicio de Retroactivos
/// Cálculo de retroactivos por ajustes salariales o sentencias
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/empleado.dart';
import '../models/retroactivo.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class RetroactivosService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  RetroactivosService({required this.db, required this.auditoriaService});

  /// Calcula retroactivo por ajuste salarial
  Future<Retroactivo> calcularRetroactivo({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required String motivo,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required MoneyValue salarioAnterior,
    required MoneyValue salarioNuevo,
    required TipoRetroactivo tipoRetroactivo,
  }) async {
    final empleadoResult = await db.query(
      'empleados_sp',
      where: 'id = ?',
      whereArgs: [empleadoId],
    );

    if (empleadoResult.isEmpty) {
      throw Exception('Empleado no encontrado');
    }

    final empleado = Empleado.fromJson(empleadoResult.first);

    final diferenciaMensual = salarioNuevo - salarioAnterior;
    final meses =
        ((fechaFin.year - fechaInicio.year) * 12) +
        (fechaFin.month - fechaInicio.month);
    final valorTotal = diferenciaMensual * meses;

    final id = _uuid.v4();
    final numeroRetroactivo =
        'RT-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaCalculo = DateTime.now();

    final retroactivo = Retroactivo(
      id: id,
      entidadId: entidadId,
      numeroRetroactivo: numeroRetroactivo,
      empleadoId: empleadoId,
      empleadoNombre: empleado.nombreCompleto,
      empleadoIdentificacion: empleado.numeroIdentificacion,
      tipoRetroactivo: tipoRetroactivo,
      motivo: motivo,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      meses: meses,
      salarioAnterior: salarioAnterior,
      salarioNuevo: salarioNuevo,
      diferenciaMensual: diferenciaMensual,
      valorTotal: valorTotal,
      valorPagado: publicMoneyZero(),
      saldoPendiente: valorTotal,
      estado: EstadoRetroactivo.calculado,
      fechaCalculo: fechaCalculo,
    );

    await db.insert('retroactivos', retroactivo.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.reliquidacion,
      modulo: 'nomina',
      accion: 'calculo_retroactivo',
      valorAnterior: {'empleado_id': empleadoId},
      valorNuevo: {
        'retroactivo_id': id,
        'numero_retroactivo': numeroRetroactivo,
        'valor_total': valorTotal.toWireMap(),
      },
      referenciaId: id,
    );

    return retroactivo;
  }

  /// Aprueba un retroactivo
  Future<Retroactivo> aprobarRetroactivo({
    required String entidadId,
    required String usuarioId,
    required String retroactivoId,
    required String actoAdministrativo,
  }) async {
    final retroactivoResult = await db.query(
      'retroactivos',
      where: 'id = ?',
      whereArgs: [retroactivoId],
    );

    if (retroactivoResult.isEmpty) {
      throw Exception('Retroactivo no encontrado');
    }

    final retroactivo = Retroactivo.fromJson(retroactivoResult.first);

    if (retroactivo.estado != EstadoRetroactivo.calculado) {
      throw Exception('Solo se pueden aprobar retroactivos calculados');
    }

    final fechaAprobacion = DateTime.now();

    await db.update(
      'retroactivos',
      {
        'estado': EstadoRetroactivo.aprobado.toString().split('.').last,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
        'acto_administrativo': actoAdministrativo,
      },
      where: 'id = ?',
      whereArgs: [retroactivoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'nomina',
      accion: 'aprobacion_retroactivo',
      valorAnterior: {'estado_anterior': retroactivo.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoRetroactivo.aprobado.toString(),
        'acto_administrativo': actoAdministrativo,
      },
      referenciaId: retroactivoId,
    );

    return retroactivo.copyWith(
      estado: EstadoRetroactivo.aprobado,
      fechaAprobacion: fechaAprobacion,
      actoAdministrativo: actoAdministrativo,
    );
  }

  /// Registra pago de retroactivo
  Future<Retroactivo> registrarPago({
    required String entidadId,
    required String usuarioId,
    required String retroactivoId,
    required MoneyValue montoPago,
  }) async {
    final retroactivoResult = await db.query(
      'retroactivos',
      where: 'id = ?',
      whereArgs: [retroactivoId],
    );

    if (retroactivoResult.isEmpty) {
      throw Exception('Retroactivo no encontrado');
    }

    final retroactivo = Retroactivo.fromJson(retroactivoResult.first);

    if (montoPago > retroactivo.saldoPendiente) {
      throw Exception('El pago excede el saldo pendiente');
    }

    final nuevoValorPagado = retroactivo.valorPagado + montoPago;
    final nuevoSaldoPendiente = retroactivo.saldoPendiente - montoPago;

    EstadoRetroactivo nuevoEstado = retroactivo.estado;
    if (nuevoSaldoPendiente == publicMoneyZero()) {
      nuevoEstado = EstadoRetroactivo.pagado;
    }

    await db.update(
      'retroactivos',
      {
        'valor_pagado': nuevoValorPagado.toSql(),
        'saldo_pendiente': nuevoSaldoPendiente.toSql(),
        'estado': nuevoEstado.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [retroactivoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.pago,
      modulo: 'nomina',
      accion: 'pago_retroactivo',
      valorAnterior: {
        'valor_pagado_anterior': retroactivo.valorPagado.toWireMap(),
        'saldo_anterior': retroactivo.saldoPendiente.toWireMap(),
      },
      valorNuevo: {
        'monto_pago': montoPago.toWireMap(),
        'valor_pagado_nuevo': nuevoValorPagado.toWireMap(),
        'saldo_nuevo': nuevoSaldoPendiente.toWireMap(),
      },
      referenciaId: retroactivoId,
    );

    return retroactivo.copyWith(
      valorPagado: nuevoValorPagado,
      saldoPendiente: nuevoSaldoPendiente,
      estado: nuevoEstado,
    );
  }

  Future<List<Retroactivo>> consultarRetroactivos({
    required String entidadId,
    EstadoRetroactivo? estado,
  }) async {
    String query = 'SELECT * FROM retroactivos WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_calculo DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => Retroactivo.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
