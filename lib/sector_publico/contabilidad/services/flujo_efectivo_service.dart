/// Servicio de Estado de Flujos de Efectivo
/// NICSP 2 - Estados de Flujos de Efectivo
/// Método directo (recomendado para entidades públicas)
library;

import 'package:sqflite/sqflite.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum MetodoFlujoEfectivo { directo, indirecto }

class FlujoEfectivoService {
  final Database db;
  final AuditoriaService auditoriaService;

  FlujoEfectivoService({required this.db, required this.auditoriaService});

  /// Genera el Estado de Flujos de Efectivo para un periodo
  Future<Map<String, dynamic>> generarEstadoFlujosEfectivo({
    required String entidadId,
    required String usuarioId,
    required String periodo, // Formato: '2024-06'
    MetodoFlujoEfectivo metodo = MetodoFlujoEfectivo.directo,
  }) async {
    final fechaInicio = DateTime.parse('$periodo-01');
    final fechaFin = DateTime(fechaInicio.year, fechaInicio.month + 1, 0);

    // Obtener saldos iniciales de efectivo
    final efectivoInicial = await _obtenerEfectivoInicial(
      entidadId: entidadId,
      fecha: fechaInicio,
    );

    // Generar flujos según método
    Map<String, dynamic> flujos;
    if (metodo == MetodoFlujoEfectivo.directo) {
      flujos = await _generarFlujoDirecto(
        entidadId: entidadId,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );
    } else {
      flujos = await _generarFlujoIndirecto(
        entidadId: entidadId,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );
    }

    // Calcular variación neta de efectivo
    final variacionNeta =
        (flujos['actividades_operacion'] as MoneyValue) +
        (flujos['actividades_inversion'] as MoneyValue) +
        (flujos['actividades_financiacion'] as MoneyValue);

    // Calcular efectivo final
    final efectivoFinal = efectivoInicial + variacionNeta;

    final estadoFlujos = {
      'entidad_id': entidadId,
      'periodo': periodo,
      'metodo': metodo.toString().split('.').last,
      'efectivo_inicial': efectivoInicial,
      'actividades_operacion': flujos['actividades_operacion'],
      'actividades_inversion': flujos['actividades_inversion'],
      'actividades_financiacion': flujos['actividades_financiacion'],
      'variacion_neta_efectivo': variacionNeta,
      'efectivo_final': efectivoFinal,
      'detalles_operacion': flujos['detalles_operacion'],
      'detalles_inversion': flujos['detalles_inversion'],
      'detalles_financiacion': flujos['detalles_financiacion'],
      'fecha_generacion': DateTime.now().toIso8601String(),
    };

    // Registrar evento en auditoría
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'contabilidad',
      accion: 'generacion_estado_flujos_efectivo',
      valorAnterior: {},
      valorNuevo: _auditSafeValue(estadoFlujos) as Map<String, dynamic>,
    );

    return estadoFlujos;
  }

  dynamic _auditSafeValue(Object? value) {
    if (value is MoneyValue) return value.toWireMap();
    if (value is Map) {
      final result = <String, dynamic>{};
      value.forEach((key, item) {
        result[key.toString()] = _auditSafeValue(item);
      });
      return result;
    }
    if (value is Iterable) return value.map(_auditSafeValue).toList();
    return value;
  }

  /// Obtiene el efectivo inicial al inicio del periodo
  Future<MoneyValue> _obtenerEfectivoInicial({
    required String entidadId,
    required DateTime fecha,
  }) async {
    // Consultar saldos de cuentas de efectivo
    final cuentasEfectivo = [
      '110501', // Efectivo en caja
      '110502', // Efectivo en bancos
      '110503', // Cuentas de ahorro
    ];

    var efectivoTotal = publicMoneyZero();
    for (final cuenta in cuentasEfectivo) {
      final resultado = await db.query(
        'saldos_cuentas',
        where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
        whereArgs: [entidadId, cuenta, '${fecha.year}'],
      );

      if (resultado.isNotEmpty) {
        final saldo = resultado.first;
        efectivoTotal += publicMoneyFromSql(saldo['saldo_neto']);
      }
    }

    return efectivoTotal;
  }

  /// Genera flujo de efectivo por método directo
  Future<Map<String, dynamic>> _generarFlujoDirecto({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    // Actividades de operación
    final flujosOperacion = await _obtenerFlujosOperacionDirecto(
      entidadId: entidadId,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
    );

    // Actividades de inversión
    final flujosInversion = await _obtenerFlujosInversionDirecto(
      entidadId: entidadId,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
    );

    // Actividades de financiación
    final flujosFinanciacion = await _obtenerFlujosFinanciacionDirecto(
      entidadId: entidadId,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
    );

    return {
      'actividades_operacion': flujosOperacion['total'],
      'actividades_inversion': flujosInversion['total'],
      'actividades_financiacion': flujosFinanciacion['total'],
      'detalles_operacion': flujosOperacion['detalles'],
      'detalles_inversion': flujosInversion['detalles'],
      'detalles_financiacion': flujosFinanciacion['detalles'],
    };
  }

  /// Obtiene flujos de operación por método directo
  Future<Map<String, dynamic>> _obtenerFlujosOperacionDirecto({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    var totalEntradas = publicMoneyZero();
    var totalSalidas = publicMoneyZero();
    final detalles = <String, MoneyValue>{};

    // Entradas de operación
    final cuentasEntradasOperacion = [
      {'codigo': '410101', 'nombre': 'Ingresos tributarios'},
      {'codigo': '410102', 'nombre': 'Ingresos no tributarios'},
      {'codigo': '410103', 'nombre': 'Transferencias corrientes'},
      {'codigo': '410104', 'nombre': 'Venta de bienes y servicios'},
    ];

    for (final cuenta in cuentasEntradasOperacion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.debito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['debito']),
      );

      if (suma > publicMoneyZero()) {
        totalEntradas += suma;
        detalles[cuenta['nombre']!] = suma;
      }
    }

    // Salidas de operación
    final cuentasSalidasOperacion = [
      {'codigo': '510101', 'nombre': 'Gastos de personal'},
      {'codigo': '510102', 'nombre': 'Gastos generales'},
      {'codigo': '510103', 'nombre': 'Transferencias corrientes'},
      {'codigo': '510104', 'nombre': 'Compra de bienes y servicios'},
    ];

    for (final cuenta in cuentasSalidasOperacion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.credito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['credito']),
      );

      if (suma > publicMoneyZero()) {
        totalSalidas += suma;
        detalles[cuenta['nombre']!] = -suma;
      }
    }

    return {'total': totalEntradas - totalSalidas, 'detalles': detalles};
  }

  /// Obtiene flujos de inversión por método directo
  Future<Map<String, dynamic>> _obtenerFlujosInversionDirecto({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    var totalEntradas = publicMoneyZero();
    var totalSalidas = publicMoneyZero();
    final detalles = <String, MoneyValue>{};

    // Entradas de inversión
    final cuentasEntradasInversion = [
      {'codigo': '120101', 'nombre': 'Venta de propiedades planta y equipo'},
      {'codigo': '120102', 'nombre': 'Recuperación de préstamos'},
    ];

    for (final cuenta in cuentasEntradasInversion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.debito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['debito']),
      );

      if (suma > publicMoneyZero()) {
        totalEntradas += suma;
        detalles[cuenta['nombre']!] = suma;
      }
    }

    // Salidas de inversión
    final cuentasSalidasInversion = [
      {
        'codigo': '160101',
        'nombre': 'Adquisición de propiedades planta y equipo',
      },
      {'codigo': '160102', 'nombre': 'Otorgamiento de préstamos'},
    ];

    for (final cuenta in cuentasSalidasInversion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.credito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['credito']),
      );

      if (suma > publicMoneyZero()) {
        totalSalidas += suma;
        detalles[cuenta['nombre']!] = -suma;
      }
    }

    return {'total': totalEntradas - totalSalidas, 'detalles': detalles};
  }

  /// Obtiene flujos de financiación por método directo
  Future<Map<String, dynamic>> _obtenerFlujosFinanciacionDirecto({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    var totalEntradas = publicMoneyZero();
    var totalSalidas = publicMoneyZero();
    final detalles = <String, MoneyValue>{};

    // Entradas de financiación
    final cuentasEntradasFinanciacion = [
      {'codigo': '210101', 'nombre': 'Emisión de deuda pública'},
      {'codigo': '210102', 'nombre': 'Transferencias de capital'},
    ];

    for (final cuenta in cuentasEntradasFinanciacion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.debito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['debito']),
      );

      if (suma > publicMoneyZero()) {
        totalEntradas += suma;
        detalles[cuenta['nombre']!] = suma;
      }
    }

    // Salidas de financiación
    final cuentasSalidasFinanciacion = [
      {'codigo': '210201', 'nombre': 'Amortización de deuda pública'},
      {'codigo': '210202', 'nombre': 'Pago de intereses'},
    ];

    for (final cuenta in cuentasSalidasFinanciacion) {
      final resultado = await db.rawQuery(
        '''
          SELECT da.*
          FROM detalles_asientos da
          INNER JOIN asientos_contables_sp ac ON da.asiento_id = ac.id
          WHERE ac.entidad_id = ?
            AND da.cuenta_codigo = ?
            AND ac.fecha_asiento BETWEEN ? AND ?
            AND da.credito > 0
        ''',
        [
          entidadId,
          cuenta['codigo']!,
          fechaInicio.toIso8601String(),
          fechaFin.toIso8601String(),
        ],
      );

      final suma = resultado.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['credito']),
      );

      if (suma > publicMoneyZero()) {
        totalSalidas += suma;
        detalles[cuenta['nombre']!] = -suma;
      }
    }

    return {'total': totalEntradas - totalSalidas, 'detalles': detalles};
  }

  /// Genera flujo de efectivo por método indirecto
  Future<Map<String, dynamic>> _generarFlujoIndirecto({
    required String entidadId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    // El método indirecto parte de la utilidad neta y ajusta por partidas no monetarias
    // Por simplicidad, implementamos una versión básica
    // En producción, esto debe ajustarse según las partidas específicas de cada entidad

    // Utilidad neta del periodo
    final resultadoUtilidad = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
      whereArgs: [entidadId, '310101', '${fechaInicio.year}'],
    );

    var utilidadNeta = publicMoneyZero();
    if (resultadoUtilidad.isNotEmpty) {
      utilidadNeta = publicMoneyFromSql(resultadoUtilidad.first['saldo_neto']);
    }

    // Ajustes por depreciación (partida no monetaria)
    final resultadoDepreciacion = await db.query(
      'asientos_contables_sp',
      where: '''
        entidad_id = ? AND 
        tipo_documento_origen = ? AND 
        referencia_origen = ? AND 
        fecha_asiento BETWEEN ? AND ?
      ''',
      whereArgs: [
        entidadId,
        'job',
        'job_depreciacion',
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
      ],
    );

    final depreciacion = resultadoDepreciacion.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['total_debito']),
    );

    // Flujo neto de operación (simplificado)
    final flujoOperacion = utilidadNeta + depreciacion;

    return {
      'actividades_operacion': flujoOperacion,
      'actividades_inversion':
          publicMoneyZero(), // Debe calcularse desde datos reales
      'actividades_financiacion':
          publicMoneyZero(), // Debe calcularse desde datos reales
      'detalles_operacion': {
        'utilidad_neta': utilidadNeta,
        'depreciacion': depreciacion,
      },
      'detalles_inversion': {},
      'detalles_financiacion': {},
    };
  }
}
