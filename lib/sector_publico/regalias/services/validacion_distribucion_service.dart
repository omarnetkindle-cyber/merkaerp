/// Servicio de Validación de Distribución de Regalías
/// Ley 1530/2012 y normas del SGR
/// Validación de la distribución de regalías y compensaciones
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoFondo {
  ahorro,
  pension,
  compensacionRegional,
  desarrolloRegional,
  reactivacionEconomica,
  cienciaTecnologia,
}

class ValidacionDistribucionService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  // Porcentajes de distribución según Ley 1530/2012
  static const Map<TipoFondo, double> _porcentajesDistribucion = {
    TipoFondo.ahorro: 0.20, // 20% Fondo de Ahorro
    TipoFondo.pension: 0.20, // 20% Fondo de Pensiones
    TipoFondo.compensacionRegional: 0.20, // 20% Compensación Regional
    TipoFondo.desarrolloRegional: 0.20, // 20% Desarrollo Regional
    TipoFondo.reactivacionEconomica: 0.10, // 10% Reactivación Económica
    TipoFondo.cienciaTecnologia: 0.10, // 10% Ciencia y Tecnología
  };

  ValidacionDistribucionService({
    required this.db,
    required this.auditoriaService,
  });

  /// Valida la distribución de regalías de un periodo
  Future<Map<String, dynamic>> validarDistribucion({
    required String entidadId,
    required String usuarioId,
    required String periodo, // Formato: '2024-01'
    required MoneyValue totalRegalias,
    required Map<TipoFondo, double> distribucion,
  }) async {
    final id = _uuid.v4();

    // Validar que la suma de distribuciones sea 100%
    final sumaDistribucion = distribucion.values.fold<double>(
      0,
      (sum, v) => sum + v,
    );
    if ((sumaDistribucion - 1.0).abs() > 0.01) {
      throw Exception(
        'La distribución debe sumar 100% (actual: ${(sumaDistribucion * 100).toStringAsFixed(2)}%)',
      );
    }

    // Calcular montos por fondo
    final montosPorFondo = <TipoFondo, MoneyValue>{};
    final diferencias = <TipoFondo, MoneyValue>{};
    bool esValida = true;

    for (final fondo in TipoFondo.values) {
      final porcentajeEsperado = _porcentajesDistribucion[fondo]!;
      final porcentajeAsignado = distribucion[fondo] ?? 0;
      final montoEsperado = totalRegalias.multiplyDecimal(
        porcentajeEsperado.toString(),
      );
      final montoAsignado = totalRegalias.multiplyDecimal(
        porcentajeAsignado.toString(),
      );
      final diferencia = (montoAsignado - montoEsperado).abs();

      montosPorFondo[fondo] = montoAsignado;
      diferencias[fondo] = diferencia;

      // Validar tolerancia del 1%
      if (diferencia > totalRegalias.multiplyDecimal('0.01')) {
        esValida = false;
      }
    }

    await db.insert('validaciones_distribucion_regalias', {
      'id': id,
      'entidad_id': entidadId,
      'periodo': periodo,
      'total_regalias': totalRegalias.toSql(),
      'distribucion_ahorro': montosPorFondo[TipoFondo.ahorro]?.toSql(),
      'distribucion_pension': montosPorFondo[TipoFondo.pension]?.toSql(),
      'distribucion_compensacion':
          montosPorFondo[TipoFondo.compensacionRegional]?.toSql(),
      'distribucion_desarrollo': montosPorFondo[TipoFondo.desarrolloRegional]
          ?.toSql(),
      'distribucion_reactivacion':
          montosPorFondo[TipoFondo.reactivacionEconomica]?.toSql(),
      'distribucion_ciencia': montosPorFondo[TipoFondo.cienciaTecnologia]
          ?.toSql(),
      'es_valida': esValida ? 1 : 0,
      'fecha_validacion': DateTime.now().toIso8601String(),
      'validado_por': usuarioId,
      'observaciones': esValida
          ? 'Distribución válida según Ley 1530/2012'
          : 'Distribución presenta diferencias significativas',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'validacion_distribucion_regalias',
      valorAnterior: {},
      valorNuevo: {
        'validacion_id': id,
        'periodo': periodo,
        'total_regalias': totalRegalias.toSql(),
        'es_valida': esValida,
      },
      referenciaId: id,
    );

    return {
      'validacion_id': id,
      'periodo': periodo,
      'total_regalias': publicMoneyForDisplay(totalRegalias),
      'montos_por_fondo': montosPorFondo.map(
        (key, value) => MapEntry(key, publicMoneyForDisplay(value)),
      ),
      'diferencias': diferencias.map(
        (key, value) => MapEntry(key, publicMoneyForDisplay(value)),
      ),
      'es_valida': esValida,
      'observaciones': esValida
          ? 'Distribución válida según Ley 1530/2012'
          : 'Distribución presenta diferencias significativas',
    };
  }

  /// Consulta validaciones de distribución por entidad
  Future<List<Map<String, dynamic>>> consultarValidaciones({
    required String entidadId,
    String? periodo,
    bool? soloInvalidas,
  }) async {
    String query =
        'SELECT * FROM validaciones_distribucion_regalias WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (periodo != null) {
      query += ' AND periodo = ?';
      args.add(periodo);
    }

    if (soloInvalidas != null && soloInvalidas) {
      query += ' AND es_valida = ?';
      args.add(0);
    }

    query += ' ORDER BY fecha_validacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Genera reporte de validaciones de distribución
  Future<Map<String, dynamic>> generarReporteValidaciones({
    required String entidadId,
    String? periodoInicio,
    String? periodoFin,
  }) async {
    String query =
        'SELECT * FROM validaciones_distribucion_regalias WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (periodoInicio != null) {
      query += ' AND periodo >= ?';
      args.add(periodoInicio);
    }

    if (periodoFin != null) {
      query += ' AND periodo <= ?';
      args.add(periodoFin);
    }

    final validaciones = await db.rawQuery(query, args);

    int totalValidaciones = validaciones.length;
    int validas = validaciones.where((v) => v['es_valida'] == 1).length;
    int invalidas = validaciones.where((v) => v['es_valida'] == 0).length;

    final totalRegalias = validaciones.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['total_regalias']),
    );

    // Total por fondo
    final totalAhorro = _sumMoney(validaciones, 'distribucion_ahorro');
    final totalPension = _sumMoney(validaciones, 'distribucion_pension');
    final totalCompensacion = _sumMoney(
      validaciones,
      'distribucion_compensacion',
    );
    final totalDesarrollo = _sumMoney(validaciones, 'distribucion_desarrollo');
    final totalReactivacion = _sumMoney(
      validaciones,
      'distribucion_reactivacion',
    );
    final totalCiencia = _sumMoney(validaciones, 'distribucion_ciencia');

    return {
      'total_validaciones': totalValidaciones,
      'validas': validas,
      'invalidas': invalidas,
      'porcentaje_validas': totalValidaciones > 0
          ? (validas / totalValidaciones) * 100
          : 0,
      'total_regalias': publicMoneyForDisplay(totalRegalias),
      'total_por_fondo': {
        'ahorro': publicMoneyForDisplay(totalAhorro),
        'pension': publicMoneyForDisplay(totalPension),
        'compensacion': publicMoneyForDisplay(totalCompensacion),
        'desarrollo': publicMoneyForDisplay(totalDesarrollo),
        'reactivacion': publicMoneyForDisplay(totalReactivacion),
        'ciencia': publicMoneyForDisplay(totalCiencia),
      },
      'detalles': validaciones,
    };
  }

  /// Valida la distribución SGP (Sistema General de Participaciones)
  Future<Map<String, dynamic>> validarDistribucionSGP({
    required String entidadId,
    required String usuarioId,
    required String periodo,
    required MoneyValue totalSGP,
    required double porcentajeSalud, // Debe ser 85% para municipios
    required double porcentajeEducacion, // Debe ser 15% para municipios
    required double porcentajeAguaPotable, // Variable
  }) async {
    final id = _uuid.v4();

    // Validar porcentajes según tipo de entidad
    final entidad = await db.query(
      'entidades_territoriales',
      where: 'id = ?',
      whereArgs: [entidadId],
    );

    if (entidad.isEmpty) {
      throw Exception('Entidad no encontrada');
    }

    final tipoEntidad = entidad.first['tipo'];
    bool esValida = true;
    final observaciones = <String>[];

    // Para municipios: 85% salud, 15% educación
    if (tipoEntidad == 'municipio') {
      if ((porcentajeSalud - 0.85).abs() > 0.01) {
        esValida = false;
        observaciones.add(
          'Porcentaje salud debe ser 85% (actual: ${(porcentajeSalud * 100).toStringAsFixed(2)}%)',
        );
      }
      if ((porcentajeEducacion - 0.15).abs() > 0.01) {
        esValida = false;
        observaciones.add(
          'Porcentaje educación debe ser 15% (actual: ${(porcentajeEducacion * 100).toStringAsFixed(2)}%)',
        );
      }
    }

    // Validar que la suma sea 100%
    final sumaPorcentajes =
        porcentajeSalud + porcentajeEducacion + porcentajeAguaPotable;
    if ((sumaPorcentajes - 1.0).abs() > 0.01) {
      esValida = false;
      observaciones.add(
        'La suma de porcentajes debe ser 100% (actual: ${(sumaPorcentajes * 100).toStringAsFixed(2)}%)',
      );
    }

    await db.insert('validaciones_distribucion_sgp', {
      'id': id,
      'entidad_id': entidadId,
      'periodo': periodo,
      'total_sgp': totalSGP.toSql(),
      'porcentaje_salud': porcentajeSalud,
      'monto_salud': totalSGP
          .multiplyDecimal(porcentajeSalud.toString())
          .toSql(),
      'porcentaje_educacion': porcentajeEducacion,
      'monto_educacion': totalSGP
          .multiplyDecimal(porcentajeEducacion.toString())
          .toSql(),
      'porcentaje_agua': porcentajeAguaPotable,
      'monto_agua': totalSGP
          .multiplyDecimal(porcentajeAguaPotable.toString())
          .toSql(),
      'es_valida': esValida ? 1 : 0,
      'fecha_validacion': DateTime.now().toIso8601String(),
      'validado_por': usuarioId,
      'observaciones': observaciones.join('\n'),
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'regalias',
      accion: 'validacion_distribucion_sgp',
      valorAnterior: {},
      valorNuevo: {
        'validacion_id': id,
        'periodo': periodo,
        'total_sgp': totalSGP.toSql(),
        'es_valida': esValida,
      },
      referenciaId: id,
    );

    return {
      'validacion_id': id,
      'periodo': periodo,
      'total_sgp': publicMoneyForDisplay(totalSGP),
      'monto_salud': publicMoneyForDisplay(
        totalSGP.multiplyDecimal(porcentajeSalud.toString()),
      ),
      'monto_educacion': publicMoneyForDisplay(
        totalSGP.multiplyDecimal(porcentajeEducacion.toString()),
      ),
      'monto_agua': publicMoneyForDisplay(
        totalSGP.multiplyDecimal(porcentajeAguaPotable.toString()),
      ),
      'es_valida': esValida,
      'observaciones': observaciones,
    };
  }

  /// Consulta validaciones SGP
  Future<List<Map<String, dynamic>>> consultarValidacionesSGP({
    required String entidadId,
    String? periodo,
  }) async {
    String query =
        'SELECT * FROM validaciones_distribucion_sgp WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (periodo != null) {
      query += ' AND periodo = ?';
      args.add(periodo);
    }

    query += ' ORDER BY fecha_validacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Obtiene los porcentajes de distribución según Ley 1530/2012
  Map<TipoFondo, double> obtenerPorcentajesDistribucion() {
    return Map.from(_porcentajesDistribucion);
  }

  /// Calcula la distribución sugerida para un monto de regalías
  Map<TipoFondo, double> calcularDistribucionSugerida(
    MoneyValue totalRegalias,
  ) {
    final distribucion = <TipoFondo, double>{};
    for (final entry in _porcentajesDistribucion.entries) {
      distribucion[entry.key] = publicMoneyForDisplay(
        totalRegalias.multiplyDecimal(entry.value.toString()),
      );
    }
    return distribucion;
  }

  MoneyValue _sumMoney(List<Map<String, Object?>> rows, String column) {
    return rows.fold(
      publicMoneyZero(),
      (sum, row) => sum + publicMoneyFromSql(row[column]),
    );
  }
}
