/// Servicio de Horas Extra y Recargos
/// Cálculo de horas extra, recargos nocturnos, dominicales y festivos
/// Código Sustantivo del Trabajo + Decreto 2351/1965
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoHoraExtra {
  diurna, // 25% recargo
  nocturna, // 75% recargo
  dominicalDiurna, // 75% recargo
  dominicalNocturna, // 150% recargo
  festivoDiurna, // 75% recargo
  festivoNocturna, // 150% recargo
}

enum TipoRecargo {
  nocturno, // 35% recargo
  dominical, // 75% recargo
  festivo, // 75% recargo
}

class HorasExtraService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  HorasExtraService({required this.db, required this.auditoriaService});

  /// Registra horas extra de un empleado
  Future<Map<String, dynamic>> registrarHorasExtra({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required TipoHoraExtra tipo,
    required DateTime fecha,
    required double cantidadHoras,
    required MoneyValue salarioHora,
    String? motivo,
    String? aprobadoPor,
  }) async {
    final id = _uuid.v4();

    // Calcular recargo según tipo
    final porcentajeRecargo = _obtenerPorcentajeRecargo(tipo);
    final valorBase = salarioHora.multiplyDecimal(cantidadHoras.toString());
    final valorRecargo = valorBase.multiplyDecimal(
      porcentajeRecargo.toString(),
    );
    final valorTotal = valorBase + valorRecargo;

    await db.insert('horas_extra', {
      'id': id,
      'entidad_id': entidadId,
      'empleado_id': empleadoId,
      'tipo_hora': tipo.toString().split('.').last,
      'fecha': fecha.toIso8601String(),
      'cantidad_horas': cantidadHoras,
      'salario_hora': salarioHora.toSql(),
      'porcentaje_recargo': porcentajeRecargo,
      'valor_recargo': valorRecargo.toSql(),
      'valor_total': valorTotal.toSql(),
      'motivo': motivo,
      'aprobado_por': aprobadoPor,
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'aprobado',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'registro_horas_extra',
      valorAnterior: {},
      valorNuevo: {
        'horas_extra_id': id,
        'empleado_id': empleadoId,
        'tipo_hora': tipo.toString(),
        'cantidad_horas': cantidadHoras,
        'valor_total': valorTotal.toWireMap(),
      },
      referenciaId: id,
    );

    return {
      'horas_extra_id': id,
      'empleado_id': empleadoId,
      'tipo_hora': tipo.toString(),
      'cantidad_horas': cantidadHoras,
      'valor_recargo': valorRecargo.toWireMap(),
      'valor_total': valorTotal.toWireMap(),
      'estado': 'aprobado',
    };
  }

  /// Registra recargos nocturnos/dominicales/festivos
  Future<Map<String, dynamic>> registrarRecargo({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required TipoRecargo tipo,
    required DateTime fecha,
    required double cantidadHoras,
    required MoneyValue salarioHora,
    String? motivo,
  }) async {
    final id = _uuid.v4();

    // Calcular recargo según tipo
    final porcentajeRecargo = _obtenerPorcentajeRecargoTipo(tipo);
    final valorRecargo = salarioHora
        .multiplyDecimal(cantidadHoras.toString())
        .multiplyDecimal(porcentajeRecargo.toString());

    await db.insert('recargos', {
      'id': id,
      'entidad_id': entidadId,
      'empleado_id': empleadoId,
      'tipo_recargo': tipo.toString().split('.').last,
      'fecha': fecha.toIso8601String(),
      'cantidad_horas': cantidadHoras,
      'salario_hora': salarioHora.toSql(),
      'porcentaje_recargo': porcentajeRecargo,
      'valor_recargo': valorRecargo.toSql(),
      'motivo': motivo,
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'aprobado',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'registro_recargo',
      valorAnterior: {},
      valorNuevo: {
        'recargo_id': id,
        'empleado_id': empleadoId,
        'tipo_recargo': tipo.toString(),
        'cantidad_horas': cantidadHoras,
        'valor_recargo': valorRecargo.toWireMap(),
      },
      referenciaId: id,
    );

    return {
      'recargo_id': id,
      'empleado_id': empleadoId,
      'tipo_recargo': tipo.toString(),
      'cantidad_horas': cantidadHoras,
      'valor_recargo': valorRecargo.toWireMap(),
      'estado': 'aprobado',
    };
  }

  /// Calcula automáticamente horas extra y recargos de un periodo
  Future<Map<String, dynamic>> calcularHorasExtraPeriodo({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required MoneyValue salarioHora,
  }) async {
    // Obtener registros de asistencia del periodo
    final registrosAsistencia = await db.query(
      'asistencia',
      where: 'empleado_id = ? AND fecha BETWEEN ? AND ?',
      whereArgs: [
        empleadoId,
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
      ],
    );

    var totalHorasExtra = publicMoneyZero();
    var totalRecargos = publicMoneyZero();
    final detalles = <Map<String, dynamic>>[];

    for (final registro in registrosAsistencia) {
      final fecha = DateTime.parse(registro['fecha'] as String);
      final horaEntrada = DateTime.parse(
        '${fecha.toIso8601String().split('T')[0]}T${registro['hora_entrada'] as String}',
      );
      final horaSalida = DateTime.parse(
        '${fecha.toIso8601String().split('T')[0]}T${registro['hora_salida'] as String}',
      );
      final horaFinJornada = DateTime.parse(
        '${fecha.toIso8601String().split('T')[0]}T18:00:00',
      ); // 6 PM

      // Verificar si trabajó después de las 6 PM (recargo nocturno)
      if (horaSalida.isAfter(horaFinJornada)) {
        final duracionNocturna = horaSalida
            .difference(horaFinJornada)
            .inHours
            .toDouble();
        if (duracionNocturna > 0) {
          final valorRecargo = salarioHora
              .multiplyDecimal(duracionNocturna.toString())
              .multiplyDecimal('0.35'); // 35% recargo nocturno
          totalRecargos += valorRecargo;

          detalles.add({
            'fecha': fecha.toIso8601String(),
            'tipo': 'recargo_nocturno',
            'horas': duracionNocturna,
            'valor': publicMoneyForDisplay(valorRecargo),
          });
        }
      }

      // Verificar si trabajó más de 8 horas (hora extra diurna)
      final duracionJornada = horaSalida
          .difference(horaEntrada)
          .inHours
          .toDouble();
      if (duracionJornada > 8) {
        final horasExtra = duracionJornada - 8;
        final valorExtra = salarioHora
            .multiplyDecimal(horasExtra.toString())
            .multiplyDecimal('0.25'); // 25% recargo hora extra diurna
        totalHorasExtra += valorExtra;

        detalles.add({
          'fecha': fecha.toIso8601String(),
          'tipo': 'hora_extra_diurna',
          'horas': horasExtra,
          'valor': publicMoneyForDisplay(valorExtra),
        });
      }

      // Verificar si trabajó en domingo/festivo
      if (_esDominicoFestivo(fecha)) {
        final valorDominical = salarioHora
            .multiplyDecimal(duracionJornada.toString())
            .multiplyDecimal('0.75'); // 75% recargo dominical
        totalRecargos += valorDominical;

        detalles.add({
          'fecha': fecha.toIso8601String(),
          'tipo': 'recargo_dominical',
          'horas': duracionJornada,
          'valor': publicMoneyForDisplay(valorDominical),
        });
      }
    }

    return {
      'empleado_id': empleadoId,
      'periodo_inicio': fechaInicio.toIso8601String(),
      'periodo_fin': fechaFin.toIso8601String(),
      'total_horas_extra': publicMoneyForDisplay(totalHorasExtra),
      'total_recargos': publicMoneyForDisplay(totalRecargos),
      'total_pagar': publicMoneyForDisplay(totalHorasExtra + totalRecargos),
      'detalles': detalles,
    };
  }

  /// Obtiene el porcentaje de recargo según tipo de hora extra
  double _obtenerPorcentajeRecargo(TipoHoraExtra tipo) {
    switch (tipo) {
      case TipoHoraExtra.diurna:
        return 0.25; // 25%
      case TipoHoraExtra.nocturna:
        return 0.75; // 75%
      case TipoHoraExtra.dominicalDiurna:
        return 0.75; // 75%
      case TipoHoraExtra.dominicalNocturna:
        return 1.50; // 150%
      case TipoHoraExtra.festivoDiurna:
        return 0.75; // 75%
      case TipoHoraExtra.festivoNocturna:
        return 1.50; // 150%
    }
  }

  /// Obtiene el porcentaje de recargo según tipo de recargo
  double _obtenerPorcentajeRecargoTipo(TipoRecargo tipo) {
    switch (tipo) {
      case TipoRecargo.nocturno:
        return 0.35; // 35%
      case TipoRecargo.dominical:
        return 0.75; // 75%
      case TipoRecargo.festivo:
        return 0.75; // 75%
    }
  }

  /// Verifica si una fecha es domingo o festivo
  bool _esDominicoFestivo(DateTime fecha) {
    // Domingo
    if (fecha.weekday == DateTime.sunday) return true;

    // Festivos (simplificado - en producción debe consultar tabla de festivos)
    final festivos = [
      '01-01', // Año Nuevo
      '01-06', // Epifanía
      '03-19', // San José
      '05-01', // Día del Trabajo
      '06-XX', // Corpus Christi (variable)
      '07-20', // Independencia
      '08-07', // Batalla de Boyacá
      '12-08', // Inmaculada
      '12-25', // Navidad
    ];

    final fechaStr =
        '${fecha.month.toString().padLeft(2, '0')}-${fecha.day.toString().padLeft(2, '0')}';
    return festivos.contains(fechaStr);
  }

  /// Consulta horas extra de un empleado
  Future<List<Map<String, dynamic>>> consultarHorasExtra({
    required String empleadoId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    String query = 'SELECT * FROM horas_extra WHERE empleado_id = ?';
    List<dynamic> args = [empleadoId];

    if (fechaInicio != null) {
      query += ' AND fecha >= ?';
      args.add(fechaInicio.toIso8601String());
    }

    if (fechaFin != null) {
      query += ' AND fecha <= ?';
      args.add(fechaFin.toIso8601String());
    }

    query += ' ORDER BY fecha DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta recargos de un empleado
  Future<List<Map<String, dynamic>>> consultarRecargos({
    required String empleadoId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    String query = 'SELECT * FROM recargos WHERE empleado_id = ?';
    List<dynamic> args = [empleadoId];

    if (fechaInicio != null) {
      query += ' AND fecha >= ?';
      args.add(fechaInicio.toIso8601String());
    }

    if (fechaFin != null) {
      query += ' AND fecha <= ?';
      args.add(fechaFin.toIso8601String());
    }

    query += ' ORDER BY fecha DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Genera resumen de horas extra y recargos de un periodo
  Future<Map<String, dynamic>> generarResumenHorasExtra({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    // Total de horas extra
    final horasExtra = await db.query(
      'horas_extra',
      where: 'entidad_id = ? AND fecha BETWEEN ? AND ?',
      whereArgs: [
        entidadId,
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
      ],
    );

    final totalHorasExtra = horasExtra.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['valor_total']),
    );

    // Total de recargos
    final recargos = await db.query(
      'recargos',
      where: 'entidad_id = ? AND fecha BETWEEN ? AND ?',
      whereArgs: [
        entidadId,
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
      ],
    );

    final totalRecargos = recargos.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['valor_recargo']),
    );

    // Por tipo de hora extra
    final porTipo = <String, MoneyValue>{};
    for (final he in horasExtra) {
      final tipo = he['tipo_hora'] as String;
      porTipo[tipo] =
          (porTipo[tipo] ?? publicMoneyZero()) +
          publicMoneyFromSql(he['valor_total']);
    }

    // Por tipo de recargo
    final porTipoRecargo = <String, MoneyValue>{};
    for (final r in recargos) {
      final tipo = r['tipo_recargo'] as String;
      porTipoRecargo[tipo] =
          (porTipoRecargo[tipo] ?? publicMoneyZero()) +
          publicMoneyFromSql(r['valor_recargo']);
    }

    return {
      'periodo_inicio': fechaInicio.toIso8601String(),
      'periodo_fin': fechaFin.toIso8601String(),
      'total_horas_extra': publicMoneyForDisplay(totalHorasExtra),
      'total_recargos': publicMoneyForDisplay(totalRecargos),
      'total_pagar': publicMoneyForDisplay(totalHorasExtra + totalRecargos),
      'por_tipo_hora_extra': porTipo.map(
        (key, value) => MapEntry(key, publicMoneyForDisplay(value)),
      ),
      'por_tipo_recargo': porTipoRecargo.map(
        (key, value) => MapEntry(key, publicMoneyForDisplay(value)),
      ),
      'cantidad_registros_horas_extra': horasExtra.length,
      'cantidad_registros_recargos': recargos.length,
    };
  }
}
