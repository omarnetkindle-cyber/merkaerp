import 'package:sqflite/sqflite.dart';

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

/// Servicio de Consolidación Jerárquica de Saldos Contables y Presupuestales (NICSP 40 / CGN).
///
/// NOTA DE LIMITACIÓN ARQUITECTÓNICA:
/// Este servicio es estrictamente de SOLO LECTURA (no modifica ningún registro transaccional).
/// Agrega los saldos de una Entidad Territorial Padre (Gobernación) y sus entidades hijas
/// asociadas mediante `gobernacion_id`.
///
/// Las operaciones reciprocas solo se eliminan cuando un contador aprueba una
/// conciliacion explicita entre partidas. Los asientos fuente no se modifican.
class ConsolidacionJerarquicaService {
  final Database db;

  ConsolidacionJerarquicaService({required this.db});

  /// Resuelve la jerarquía de entidades (Entidad Padre + Entidades Hijas).
  /// Lanza [StateError] de forma Fail-Closed si la entidad padre no existe o no tiene hijas.
  Future<List<Map<String, dynamic>>> _resolverEntidadesJerarquia(
    String entidadIdPadre,
  ) async {
    final padreRows = await db.query(
      'entidades_territoriales',
      where: 'id = ? AND activo = 1',
      whereArgs: [entidadIdPadre],
    );

    if (padreRows.isEmpty) {
      throw StateError(
        'La entidad padre "$entidadIdPadre" no existe o no está activa en la base de datos.',
      );
    }

    final hijasRows = await db.query(
      'entidades_territoriales',
      where: 'gobernacion_id = ? AND activo = 1',
      whereArgs: [entidadIdPadre],
    );

    if (hijasRows.isEmpty) {
      throw StateError(
        'La entidad padre "$entidadIdPadre" no tiene entidades hijas adscritas para consolidar (gobernacion_id).',
      );
    }

    final todas = <Map<String, dynamic>>[
      padreRows.first,
      ...hijasRows,
    ];

    return todas;
  }

  /// Genera el consolidado de saldos contables agrupado por clase de cuenta (1, 2, 3, 4, 5...).
  Future<Map<String, dynamic>> obtenerConsolidadoContable({
    required String entidadIdPadre,
    required String vigencia,
  }) async {
    final entidades = await _resolverEntidadesJerarquia(entidadIdPadre);
    final entidadIds = entidades.map((e) => e['id'].toString()).toList();
    final placeholders = List.filled(entidadIds.length, '?').join(',');

    final result = await db.rawQuery('''
      SELECT 
        SUBSTR(cuenta_codigo, 1, 1) AS clase,
        SUM(saldo_deudor) AS total_deudor,
        SUM(saldo_acreedor) AS total_acreedor,
        SUM(saldo_neto) AS total_neto,
        COUNT(DISTINCT cuenta_codigo) AS total_cuentas
      FROM saldos_cuentas
      WHERE entidad_id IN ($placeholders) AND vigencia = ?
      GROUP BY SUBSTR(cuenta_codigo, 1, 1)
      ORDER BY clase ASC
    ''', [...entidadIds, vigencia]);

    final clasesMap = <String, Map<String, dynamic>>{};
    for (final row in result) {
      final clase = row['clase']?.toString() ?? '0';
      final deudor = publicMoneyFromSql(row['total_deudor'], nullableAsZero: true);
      final acreedor = publicMoneyFromSql(row['total_acreedor'], nullableAsZero: true);
      final neto = publicMoneyFromSql(row['total_neto'], nullableAsZero: true);
      final totalCuentas = (row['total_cuentas'] as num?)?.toInt() ?? 0;

      clasesMap[clase] = {
        'clase': clase,
        'deudor': deudor,
        'acreedor': acreedor,
        'neto': neto,
        'total_cuentas': totalCuentas,
      };

    }

    // Solo se eliminan partidas que un contador concilio expresamente.
    // Los saldos y asientos fuente permanecen intactos.
    final eliminaciones = await db.rawQuery('''
      SELECT SUBSTR(d.cuenta_codigo, 1, 1) AS clase, p.lado,
             SUM(p.monto_eliminar) AS total_eliminado
      FROM conciliaciones_reciprocas c
      INNER JOIN conciliaciones_reciprocas_partidas p
        ON p.conciliacion_id = c.id
      INNER JOIN detalles_asientos d ON d.id = p.detalle_asiento_id
      WHERE c.entidad_consolidadora_id = ?
        AND c.vigencia = ?
        AND c.estado = 'aprobada'
        AND p.entidad_id IN ($placeholders)
      GROUP BY SUBSTR(d.cuenta_codigo, 1, 1), p.lado
    ''', [entidadIdPadre, vigencia, ...entidadIds]);

    var totalEliminadoDebito = publicMoneyZero();
    var totalEliminadoCredito = publicMoneyZero();
    for (final eliminacion in eliminaciones) {
      final clase = eliminacion['clase']?.toString() ?? '0';
      final lado = eliminacion['lado']?.toString();
      final monto = publicMoneyFromSql(
        eliminacion['total_eliminado'],
        nullableAsZero: true,
      );
      final claseActual = clasesMap.putIfAbsent(
        clase,
        () => {
          'clase': clase,
          'deudor': publicMoneyZero(),
          'acreedor': publicMoneyZero(),
          'neto': publicMoneyZero(),
          'total_cuentas': 0,
        },
      );
      if (lado == 'debito') {
        claseActual['deudor'] = (claseActual['deudor'] as MoneyValue) - monto;
        totalEliminadoDebito += monto;
      } else {
        claseActual['acreedor'] =
            (claseActual['acreedor'] as MoneyValue) - monto;
        totalEliminadoCredito += monto;
      }
      claseActual['neto'] =
          (claseActual['deudor'] as MoneyValue) -
          (claseActual['acreedor'] as MoneyValue);
    }

    MoneyValue netoClase(String clase) =>
        clasesMap[clase]?['neto'] as MoneyValue? ?? publicMoneyZero();
    final totalActivos = netoClase('1');
    final totalPasivos = netoClase('2');
    final totalPatrimonio = netoClase('3');
    final totalIngresos = netoClase('4');
    final totalGastos = netoClase('5');
    final conteoConciliaciones = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM conciliaciones_reciprocas
      WHERE entidad_consolidadora_id = ? AND vigencia = ? AND estado = 'aprobada'
    ''', [entidadIdPadre, vigencia]);

    return {
      'entidad_padre_id': entidadIdPadre,
      'entidad_padre_nombre': entidades.first['razon_social'],
      'vigencia': vigencia,
      'total_entidades_consolidadas': entidades.length,
      'entidades': entidades.map((e) => {
        'id': e['id'],
        'razon_social': e['razon_social'],
        'nit': e['nit'],
        'tipo_entidad': e['tipo_entidad'],
      }).toList(),
      'clases': clasesMap,
      'eliminaciones_reciprocas': {
        'conciliaciones_aplicadas':
            (conteoConciliaciones.first['total'] as num?)?.toInt() ?? 0,
        'debito_eliminado': totalEliminadoDebito,
        'credito_eliminado': totalEliminadoCredito,
      },
      'resumen': {
        'activos': totalActivos,
        'pasivos': totalPasivos,
        'patrimonio': totalPatrimonio,
        'ingresos': totalIngresos,
        'gastos': totalGastos,
        'superavit_deficit': totalIngresos - totalGastos,
      },
    };
  }

  /// Genera el consolidado del flujo presupuestal (Apropiaciones, CDPs, RPs, Pagos).
  Future<Map<String, dynamic>> obtenerConsolidadoPresupuestal({
    required String entidadIdPadre,
    required String vigencia,
  }) async {
    final entidades = await _resolverEntidadesJerarquia(entidadIdPadre);
    final entidadIds = entidades.map((e) => e['id'].toString()).toList();
    final placeholders = List.filled(entidadIds.length, '?').join(',');

    final resApropiado = await db.rawQuery('''
      SELECT COALESCE(SUM(valor_apropiado), 0) AS total FROM apropiaciones 
      WHERE entidad_id IN ($placeholders) AND vigencia = ?
    ''', [...entidadIds, vigencia]);

    final resCDP = await db.rawQuery('''
      SELECT COALESCE(SUM(valor_cdp), 0) AS total FROM cdps 
      WHERE entidad_id IN ($placeholders) AND vigencia = ?
    ''', [...entidadIds, vigencia]);

    final resRP = await db.rawQuery('''
      SELECT COALESCE(SUM(valor_rp), 0) AS total FROM rps 
      WHERE entidad_id IN ($placeholders) AND vigencia = ?
    ''', [...entidadIds, vigencia]);

    final resPagos = await db.rawQuery('''
      SELECT COALESCE(SUM(valor_pagado), 0) AS total FROM pagos 
      WHERE entidad_id IN ($placeholders) AND vigencia = ?
    ''', [...entidadIds, vigencia]);

    final totalApropiado = publicMoneyFromSql(
      resApropiado.first['total'],
      nullableAsZero: true,
    );
    final totalCDP = publicMoneyFromSql(
      resCDP.first['total'],
      nullableAsZero: true,
    );
    final totalRP = publicMoneyFromSql(
      resRP.first['total'],
      nullableAsZero: true,
    );
    final totalPagado = publicMoneyFromSql(
      resPagos.first['total'],
      nullableAsZero: true,
    );

    return {
      'entidad_padre_id': entidadIdPadre,
      'vigencia': vigencia,
      'total_entidades_consolidadas': entidades.length,
      'apropiacion_total': totalApropiado,
      'cdp_total': totalCDP,
      'rp_total': totalRP,
      'pago_total': totalPagado,
      'saldo_por_comprometer': totalApropiado - totalCDP,
      'saldo_por_pagar': totalRP - totalPagado,
    };
  }
}
