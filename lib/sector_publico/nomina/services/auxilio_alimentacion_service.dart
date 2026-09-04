/// Servicio de Auxilio de Alimentación
/// Decreto 1250/2021 y normas complementarias
/// Auxilio no salarial de alimentación para trabajadores
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class AuxilioAlimentacionService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  // Valor 2026: Decreto 1470/2025 ($249.095 auxilio transporte).
  // El auxilio de alimentación del sector público NO tiene decreto uniforme
  // vigente para 2026; el valor se obtiene de la tabla
  // `parametros_auxilio_alimentacion` y cae al último valor configurado.
  // $162.000 es solo el fallback si la tabla está vacía (valor aproximado 2024).
  static const int _kFallbackValor2024 = 162000;

  AuxilioAlimentacionService({
    required this.db,
    required this.auditoriaService,
  });

  /// Retorna el valor mensual vigente del auxilio para [entidadId] en [year].
  /// Busca primero en `parametros_auxilio_alimentacion`; si no existe,
  /// retorna el fallback de 2024 con una advertencia en el log.
  Future<MoneyValue> valorVigente(String entidadId, int year) async {
    final rows = await db.query(
      'parametros_auxilio_alimentacion',
      where: 'entidad_id = ? AND year <= ?',
      whereArgs: [entidadId, year],
      orderBy: 'year DESC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return publicMoneyFromSql(rows.first['valor_mensual']);
    }
    // Fallback: constante del último valor conocido.
    return publicMoneyFromMajor(_kFallbackValor2024.toString());
  }

  /// Configura el valor del auxilio para [entidadId] / [year].
  /// Idempotente — si ya existe, actualiza.
  Future<void> configurarValor({
    required String entidadId,
    required String usuarioId,
    required int year,
    required MoneyValue valor,
    required String decretoReferencia,
    required DateTime fechaVigencia,
  }) async {
    if (valor.minorUnits <= 0) {
      throw ArgumentError('El valor del auxilio debe ser mayor a 0.');
    }
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'parametros_auxilio_alimentacion',
      where: 'entidad_id = ? AND year = ?',
      whereArgs: [entidadId, year],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('parametros_auxilio_alimentacion', {
        'entidad_id': entidadId,
        'year': year,
        'valor_mensual': valor.toSql(),
        'decreto_referencia': decretoReferencia,
        'fecha_vigencia': fechaVigencia.toIso8601String(),
        'created_at': now,
      });
    } else {
      await db.update(
        'parametros_auxilio_alimentacion',
        {
          'valor_mensual': valor.toSql(),
          'decreto_referencia': decretoReferencia,
          'fecha_vigencia': fechaVigencia.toIso8601String(),
          'updated_at': now,
        },
        where: 'entidad_id = ? AND year = ?',
        whereArgs: [entidadId, year],
      );
    }
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'nomina',
      accion: 'configuracion_auxilio_alimentacion',
      valorAnterior: {},
      valorNuevo: {
        'year': year,
        'valor_mensual': valor.toWireMap(),
        'decreto_referencia': decretoReferencia,
      },
    );
  }

  /// Registra pago de auxilio de alimentación
  Future<Map<String, dynamic>> registrarPagoAuxilio({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required String periodo, // Formato: '2024-06'
    required int diasTrabajados,
    required MoneyValue valorDia,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    // Validar días trabajados (máximo 30 días)
    if (diasTrabajados > 30) {
      throw Exception('El número de días trabajados no puede exceder 30');
    }

    // Calcular valor total del auxilio
    final valorTotal = valorDia * diasTrabajados;

    await db.insert('auxilio_alimentacion', {
      'id': id,
      'entidad_id': entidadId,
      'empleado_id': empleadoId,
      'periodo': periodo,
      'dias_trabajados': diasTrabajados,
      'valor_dia': valorDia.toSql(),
      'valor_total': valorTotal.toSql(),
      'observaciones': observaciones,
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'pagado',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'pago_auxilio_alimentacion',
      valorAnterior: {},
      valorNuevo: {
        'auxilio_id': id,
        'empleado_id': empleadoId,
        'periodo': periodo,
        'dias_trabajados': diasTrabajados,
        'valor_total': valorTotal.toWireMap(),
      },
      referenciaId: id,
    );

    return {
      'auxilio_id': id,
      'empleado_id': empleadoId,
      'periodo': periodo,
      'dias_trabajados': diasTrabajados,
      'valor_total': publicMoneyForDisplay(valorTotal),
      'estado': 'pagado',
    };
  }

  /// Calcula automáticamente el auxilio de alimentación para un periodo
  Future<Map<String, dynamic>> calcularAuxilioPeriodo({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required String periodo,
  }) async {
    final partesPeriodo = periodo.split('-');
    final anio = int.parse(partesPeriodo[0]);
    final mes = int.parse(partesPeriodo[1]);

    final fechaInicio = DateTime(anio, mes, 1);
    final fechaFin = DateTime(anio, mes + 1, 0);

    // Obtener valor vigente desde BD (no constante hardcodeada).
    final valorMensual = await valorVigente(entidadId, anio);

    final registrosAsistencia = await db.query(
      'asistencia',
      where: 'empleado_id = ? AND fecha BETWEEN ? AND ?',
      whereArgs: [
        empleadoId,
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
      ],
    );

    int diasTrabajados = 0;
    for (final registro in registrosAsistencia) {
      if (registro['estado'] == 'presente') {
        diasTrabajados++;
      }
    }

    final valorDia = valorMensual / 30;
    final valorTotal = valorDia * diasTrabajados;

    return {
      'empleado_id': empleadoId,
      'periodo': periodo,
      'dias_trabajados': diasTrabajados,
      'valor_dia': valorDia,
      'valor_total': valorTotal,
      'valor_auxilio_mensual': valorMensual,
    };
  }

  /// Genera liquidación de auxilio de alimentación para nómina
  Future<Map<String, dynamic>> generarLiquidacionAuxilio({
    required String entidadId,
    required String usuarioId,
    required String periodo,
  }) async {
    // Obtener todos los empleados activos
    final empleados = await db.query(
      'empleados_sp',
      where: 'entidad_id = ? AND activo = ?',
      whereArgs: [entidadId, 1],
    );

    var totalAuxilio = publicMoneyZero();
    final detalles = <Map<String, dynamic>>[];

    for (final empleado in empleados) {
      final empleadoId = empleado['id'] as String;
      final calculo = await calcularAuxilioPeriodo(
        entidadId: entidadId,
        usuarioId: usuarioId,
        empleadoId: empleadoId,
        periodo: periodo,
      );

      if (calculo['dias_trabajados'] > 0) {
        final valorTotal = calculo['valor_total'] as MoneyValue;
        totalAuxilio += valorTotal;
        detalles.add({
          'empleado_id': empleadoId,
          'empleado_nombre': empleado['nombre'],
          'dias_trabajados': calculo['dias_trabajados'],
          'valor_dia': calculo['valor_dia'],
          'valor_total': calculo['valor_total'],
        });
      }
    }

    return {
      'periodo': periodo,
      'total_empleados': empleados.length,
      'empleados_con_auxilio': detalles.length,
      'total_auxilio': publicMoneyForDisplay(totalAuxilio),
      'detalles': detalles,
    };
  }

  /// Actualiza el valor del auxilio de alimentación (cuando cambia por decreto)
  Future<Map<String, dynamic>> actualizarValorAuxilio({
    required String entidadId,
    required String usuarioId,
    required MoneyValue nuevoValor,
    required String decretoReferencia,
    required DateTime fechaVigencia,
  }) async {
    final anio = fechaVigencia.year;
    final anterior = await valorVigente(entidadId, anio);
    await configurarValor(
      entidadId: entidadId,
      usuarioId: usuarioId,
      year: anio,
      valor: nuevoValor,
      decretoReferencia: decretoReferencia,
      fechaVigencia: fechaVigencia,
    );
    await db.insert('historico_valor_auxilio', {
      'id': _uuid.v4(),
      'entidad_id': entidadId,
      'valor_anterior': anterior.toSql(),
      'valor_nuevo': nuevoValor.toSql(),
      'decreto_referencia': decretoReferencia,
      'fecha_vigencia': fechaVigencia.toIso8601String(),
      'fecha_actualizacion': DateTime.now().toIso8601String(),
      'actualizado_por': usuarioId,
    });
    return {
      'valor_anterior': publicMoneyForDisplay(anterior),
      'valor_nuevo': publicMoneyForDisplay(nuevoValor),
      'decreto_referencia': decretoReferencia,
      'fecha_vigencia': fechaVigencia.toIso8601String(),
    };
  }

  /// Obtiene el valor actual del auxilio para [entidadId] en el año actual.
  Future<MoneyValue> obtenerValorActual(String entidadId) =>
      valorVigente(entidadId, DateTime.now().year);

  /// Consulta pagos de auxilio de alimentación de un empleado
  Future<List<Map<String, dynamic>>> consultarPagosAuxilio({
    required String empleadoId,
    String? periodo,
  }) async {
    String query = 'SELECT * FROM auxilio_alimentacion WHERE empleado_id = ?';
    List<dynamic> args = [empleadoId];

    if (periodo != null) {
      query += ' AND periodo = ?';
      args.add(periodo);
    }

    query += ' ORDER BY periodo DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta histórico de valores del auxilio
  Future<List<Map<String, dynamic>>> consultarHistoricoValores({
    required String entidadId,
  }) async {
    final resultados = await db.query(
      'historico_valor_auxilio',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
      orderBy: 'fecha_actualizacion DESC',
    );

    return resultados;
  }

  /// Genera reporte de auxilio de alimentación por periodo
  Future<Map<String, dynamic>> generarReporteAuxilio({
    required String entidadId,
    required String periodoInicio,
    required String periodoFin,
  }) async {
    final pagos = await db.query(
      'auxilio_alimentacion',
      where: 'entidad_id = ? AND periodo BETWEEN ? AND ?',
      whereArgs: [entidadId, periodoInicio, periodoFin],
    );

    var totalPagado = publicMoneyZero();
    for (final pago in pagos) {
      totalPagado += publicMoneyFromSql(pago['valor_total']);
    }

    int totalDias = pagos.fold<int>(
      0,
      (sum, r) => sum + (r['dias_trabajados'] as int),
    );

    // Por empleado
    final porEmpleado = <String, Map<String, dynamic>>{};
    for (final pago in pagos) {
      final empleadoId = pago['empleado_id'] as String;
      if (!porEmpleado.containsKey(empleadoId)) {
        porEmpleado[empleadoId] = {
          'empleado_id': empleadoId,
          'total_dias': 0,
          'total_valor': publicMoneyZero(),
        };
      }
      porEmpleado[empleadoId]!['total_dias'] += pago['dias_trabajados'] as int;
      porEmpleado[empleadoId]!['total_valor'] =
          (porEmpleado[empleadoId]!['total_valor'] as MoneyValue) +
          publicMoneyFromSql(pago['valor_total']);
    }

    return {
      'periodo_inicio': periodoInicio,
      'periodo_fin': periodoFin,
      'total_pagos': pagos.length,
      'total_dias': totalDias,
      'total_pagado': publicMoneyForDisplay(totalPagado),
      'promedio_por_empleado': pagos.isNotEmpty
          ? publicMoneyForDisplay(totalPagado / pagos.length)
          : 0,
      'por_empleado': porEmpleado.values.map((detalle) {
        final valor = detalle['total_valor'] as MoneyValue;
        return {...detalle, 'total_valor': publicMoneyForDisplay(valor)};
      }).toList(),
    };
  }
}
