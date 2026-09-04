/// Servicio de Depreciación por Unidades de Producción
/// Método de depreciación alternativo según NICSP 17
/// Depreciación basada en el uso real del activo (unidades producidas)
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class DepreciacionUnidadesService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  DepreciacionUnidadesService({
    required this.db,
    required this.auditoriaService,
  });

  /// Configura un activo para depreciación por unidades de producción
  Future<Map<String, dynamic>> configurarDepreciacionUnidades({
    required String entidadId,
    required String usuarioId,
    required String activoId,
    required double unidadesTotalesEstimadas,
    required MoneyValue valorAdquisicion,
    required MoneyValue valorResidual,
    required DateTime fechaInicio,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    // Verificar que el activo existe
    final activo = await db.query(
      'activos_estado',
      where: 'id = ?',
      whereArgs: [activoId],
    );

    if (activo.isEmpty) {
      throw Exception('Activo no encontrado');
    }

    // Calcular costo depreciable
    final costoDepreciable = valorAdquisicion - valorResidual;

    // Calcular costo por unidad
    final costoPorUnidad = costoDepreciable.divideDecimal(
      unidadesTotalesEstimadas.toString(),
    );

    await db.insert('configuracion_depreciacion_unidades', {
      'id': id,
      'entidad_id': entidadId,
      'activo_id': activoId,
      'numero_inventario': activo.first['numero_inventario'],
      'unidades_totales_estimadas': unidadesTotalesEstimadas,
      'valor_adquisicion': valorAdquisicion.toSql(),
      'valor_residual': valorResidual.toSql(),
      'costo_depreciable': costoDepreciable.toSql(),
      'costo_por_unidad': costoPorUnidad.toSql(),
      'fecha_inicio': fechaInicio.toIso8601String(),
      'unidades_producidas_acumuladas': 0,
      'depreciacion_acumulada': publicMoneyZero().toSql(),
      'observaciones': observaciones,
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'activo',
    });

    // Actualizar método de depreciación del activo
    await db.update(
      'activos_estado',
      {'metodo_depreciacion': 'unidades_produccion'},
      where: 'id = ?',
      whereArgs: [activoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'configuracion_depreciacion_unidades',
      valorAnterior: {'metodo_anterior': activo.first['metodo_depreciacion']},
      valorNuevo: {
        'metodo_nuevo': 'unidades_produccion',
        'unidades_totales_estimadas': unidadesTotalesEstimadas,
        'costo_por_unidad': costoPorUnidad.toSql(),
      },
      referenciaId: id,
    );

    return {
      'configuracion_id': id,
      'activo_id': activoId,
      'unidades_totales_estimadas': unidadesTotalesEstimadas,
      'costo_por_unidad': costoPorUnidad.toSql(),
      'estado': 'activo',
    };
  }

  /// Registra producción y calcula depreciación correspondiente
  Future<Map<String, dynamic>> registrarProduccion({
    required String entidadId,
    required String usuarioId,
    required String configuracionId,
    required double unidadesProducidas,
    required DateTime fechaProduccion,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    // Obtener configuración
    final config = await db.query(
      'configuracion_depreciacion_unidades',
      where: 'id = ? AND estado = ?',
      whereArgs: [configuracionId, 'activo'],
    );

    if (config.isEmpty) {
      throw Exception('Configuración no encontrada o inactiva');
    }

    final configuracion = config.first;
    final costoPorUnidad = publicMoneyFromSql(
      configuracion['costo_por_unidad'],
    );
    final unidadesAcumuladas =
        (configuracion['unidades_producidas_acumuladas'] as num).toDouble();
    final unidadesTotales = (configuracion['unidades_totales_estimadas'] as num)
        .toDouble();

    // Validar que no exceda las unidades totales
    if (unidadesAcumuladas + unidadesProducidas > unidadesTotales) {
      throw Exception('Las unidades producidas exceden el total estimado');
    }

    // Calcular depreciación del periodo
    final depreciacionPeriodo = costoPorUnidad.multiplyDecimal(
      unidadesProducidas.toString(),
    );

    // Calcular nueva depreciación acumulada
    final nuevaDepreciacionAcumulada =
        publicMoneyFromSql(configuracion['depreciacion_acumulada']) +
        depreciacionPeriodo;

    await db.insert('registros_produccion', {
      'id': id,
      'entidad_id': entidadId,
      'configuracion_id': configuracionId,
      'activo_id': configuracion['activo_id'],
      'unidades_producidas': unidadesProducidas,
      'costo_por_unidad': costoPorUnidad.toSql(),
      'depreciacion_periodo': depreciacionPeriodo.toSql(),
      'fecha_produccion': fechaProduccion.toIso8601String(),
      'observaciones': observaciones,
      'fecha_registro': DateTime.now().toIso8601String(),
    });

    // Actualizar configuración
    await db.update(
      'configuracion_depreciacion_unidades',
      {
        'unidades_producidas_acumuladas':
            unidadesAcumuladas + unidadesProducidas,
        'depreciacion_acumulada': nuevaDepreciacionAcumulada.toSql(),
      },
      where: 'id = ?',
      whereArgs: [configuracionId],
    );

    // Actualizar depreciación acumulada del activo
    await db.update(
      'activos_estado',
      {'depreciacion_acumulada': nuevaDepreciacionAcumulada.toSql()},
      where: 'id = ?',
      whereArgs: [configuracion['activo_id']],
    );

    // Generar asiento contable
    final asientoId = await _generarAsientoDepreciacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      registroId: id,
      activoId: configuracion['activo_id'] as String,
      depreciacionPeriodo: depreciacionPeriodo,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'activos',
      accion: 'registro_produccion_depreciacion',
      valorAnterior: {},
      valorNuevo: {
        'registro_id': id,
        'unidades_producidas': unidadesProducidas,
        'depreciacion_periodo': depreciacionPeriodo.toSql(),
        'asiento_id': asientoId,
      },
      referenciaId: id,
    );

    return {
      'registro_id': id,
      'unidades_producidas': unidadesProducidas,
      'depreciacion_periodo': depreciacionPeriodo.toSql(),
      'depreciacion_acumulada': nuevaDepreciacionAcumulada.toSql(),
      'asiento_id': asientoId,
    };
  }

  /// Genera el asiento contable de depreciación
  Future<String> _generarAsientoDepreciacion({
    required String entidadId,
    required String usuarioId,
    required String registroId,
    required String activoId,
    required MoneyValue depreciacionPeriodo,
  }) async {
    final asientoId = _uuid.v4();
    final numeroAsiento = await _generarNumeroAsiento(entidadId);
    final fechaAsiento = DateTime.now();

    // Cuentas contables según NICSP 17
    // Débito: Gasto por depreciación
    // Crédito: Depreciación acumulada
    final cuentaGasto = '510501'; // Gasto por depreciación
    final cuentaDepreciacion = '159901'; // Depreciación acumulada

    await db.insert('asientos_contables_sp', {
      'id': asientoId,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': 'Depreciación por unidades de producción - $activoId',
      'tipo_asiento': 'automatico',
      'estado': 'borrador',
      'total_debito': depreciacionPeriodo.toSql(),
      'total_credito': depreciacionPeriodo.toSql(),
      'usuario_creo': usuarioId,
      'usuario_reviso': usuarioId,
      'fecha_revision': DateTime.now().toIso8601String(),
      'referencia_origen': registroId,
      'tipo_documento_origen': 'depreciacion_unidades',
      'observaciones':
          'Asiento generado automáticamente por depreciación por unidades',
    });

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaGasto,
      'cuenta_nombre': 'Gasto por depreciación',
      'debito': depreciacionPeriodo.toSql(),
      'credito': publicMoneyZero().toSql(),
      'referencia_id': registroId,
    });

    await db.update(
      'asientos_contables_sp',
      {'estado': 'aprobado'},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaDepreciacion,
      'cuenta_nombre': 'Depreciación acumulada',
      'debito': publicMoneyZero().toSql(),
      'credito': depreciacionPeriodo.toSql(),
      'referencia_id': registroId,
    });

    return asientoId;
  }

  /// Consulta configuraciones de depreciación por unidades
  Future<List<Map<String, dynamic>>> consultarConfiguraciones({
    required String entidadId,
    String? activoId,
  }) async {
    String query =
        'SELECT * FROM configuracion_depreciacion_unidades WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (activoId != null) {
      query += ' AND activo_id = ?';
      args.add(activoId);
    }

    query += ' ORDER BY fecha_registro DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta registros de producción
  Future<List<Map<String, dynamic>>> consultarRegistrosProduccion({
    required String configuracionId,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    String query =
        'SELECT * FROM registros_produccion WHERE configuracion_id = ?';
    List<dynamic> args = [configuracionId];

    if (fechaInicio != null) {
      query += ' AND fecha_produccion >= ?';
      args.add(fechaInicio.toIso8601String());
    }

    if (fechaFin != null) {
      query += ' AND fecha_produccion <= ?';
      args.add(fechaFin.toIso8601String());
    }

    query += ' ORDER BY fecha_produccion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Genera reporte de depreciación por unidades
  Future<Map<String, dynamic>> generarReporteDepreciacionUnidades({
    required String entidadId,
    String? periodo,
  }) async {
    String query =
        'SELECT * FROM configuracion_depreciacion_unidades WHERE entidad_id = ? AND estado = ?';
    List<dynamic> args = [entidadId, 'activo'];

    final configuraciones = await db.rawQuery(query, args);

    double totalUnidadesProducidas = 0;
    var totalDepreciacion = publicMoneyZero();
    final detalles = <Map<String, dynamic>>[];

    for (final config in configuraciones) {
      final configId = config['id'] as String;
      final registros = await consultarRegistrosProduccion(
        configuracionId: configId,
      );

      final unidadesConfig = registros.fold<double>(
        0,
        (sum, r) => sum + (r['unidades_producidas'] as num).toDouble(),
      );

      final depreciacionConfig = registros.fold<MoneyValue>(
        publicMoneyZero(),
        (sum, r) => sum + publicMoneyFromSql(r['depreciacion_periodo']),
      );

      totalUnidadesProducidas += unidadesConfig;
      totalDepreciacion += depreciacionConfig;

      detalles.add({
        'activo_id': config['activo_id'],
        'numero_inventario': config['numero_inventario'],
        'unidades_totales_estimadas': config['unidades_totales_estimadas'],
        'unidades_producidas_acumuladas':
            config['unidades_producidas_acumuladas'],
        'depreciacion_acumulada': config['depreciacion_acumulada'],
        'porcentaje_uso':
            (config['unidades_producidas_acumuladas'] as num).toDouble() /
            (config['unidades_totales_estimadas'] as num).toDouble() *
            100,
      });
    }

    return {
      'periodo': periodo,
      'total_activos': configuraciones.length,
      'total_unidades_producidas': totalUnidadesProducidas,
      'total_depreciacion': totalDepreciacion.toSql(),
      'detalles': detalles,
    };
  }

  /// Calcula el porcentaje de uso de un activo
  Future<double> calcularPorcentajeUso({
    required String configuracionId,
  }) async {
    final config = await db.query(
      'configuracion_depreciacion_unidades',
      where: 'id = ?',
      whereArgs: [configuracionId],
    );

    if (config.isEmpty) {
      throw Exception('Configuración no encontrada');
    }

    final unidadesProducidas =
        config.first['unidades_producidas_acumuladas'] as double;
    final unidadesTotales =
        config.first['unidades_totales_estimadas'] as double;

    return (unidadesProducidas / unidadesTotales) * 100;
  }

  /// Genera el número de asiento siguiente
  Future<String> _generarNumeroAsiento(String entidadId) async {
    final resultado = await db.rawQuery(
      "SELECT MAX(numero_asiento) as max_numero FROM asientos_contables_sp WHERE entidad_id = ?",
      [entidadId],
    );

    final maxNumero = resultado.first['max_numero'];
    if (maxNumero == null) return 'AS-0001';

    final numeroActual = int.parse(maxNumero.toString().split('-')[1]);
    return 'AS-${(numeroActual + 1).toString().padLeft(4, '0')}';
  }
}
