import 'dart:io';

import 'package:merka_erp/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _nonMonetaryRealColumns = <String>{
  'accounting_journal_lines.exchange_rate',
  'autorizaciones_vigencias_futuras.porcentaje_respaldo_actual',
  'avisos_tablero.area_metros',
  'comisiones_liquidadas.porcentaje',
  'comisiones_vendedor.porcentaje',
  'commission_rules.commission_rate',
  'commissions.commission_rate',
  'compras.impuesto_pct',
  'compras_detalle.cantidad',
  'configuracion_depreciacion.porcentaje_depreciacion',
  'configuracion_depreciacion_unidades.unidades_producidas_acumuladas',
  'configuracion_depreciacion_unidades.unidades_totales_estimadas',
  'cotizacion_detalle.cantidad',
  'currency_exchange_rates.rate',
  'customer_credit_profiles.risk_score',
  'declaraciones_ica.tarifa',
  'devoluciones_compras_detalle.cantidad',
  'devoluciones_ventas_detalle.cantidad',
  'documentos_compra_flujo_lineas.cantidad',
  'documentos_compra_flujo_lineas.impuesto_pct',
  'documentos_venta_flujo_lineas.cantidad',
  'documentos_venta_flujo_lineas.impuesto_pct',
  'enterprise_event_metrics.metric_value',
  'enterprise_tax_rules.rate',
  'enterprise_tax_rules.retention_rate',
  'estampillas_parafiscales.tarifa',
  'exchange_rates.rate_to_base',
  'executive_kpi_read_model.metric_value',
  'horas_extra.cantidad_horas',
  'horas_extra.porcentaje_recargo',
  'inventory_lots.quantity',
  'inventory_reservations.quantity',
  'kardex_inventario.cantidad',
  'kardex_inventario.stock_anterior',
  'kardex_inventario.stock_nuevo',
  'liquidaciones_prediales.tarifa',
  'lotes.cantidad',
  'movimientos_inventario.cantidad',
  'movimientos_inventario.stock_anterior',
  'movimientos_inventario.stock_nuevo',
  'order_lines.quantity',
  'order_lines.tax_percentage',
  'payroll_novelties.horas',
  'payroll_parameters.arl_level_1_rate',
  'payroll_parameters.arl_level_2_rate',
  'payroll_parameters.arl_level_3_rate',
  'payroll_parameters.arl_level_4_rate',
  'payroll_parameters.arl_level_5_rate',
  'payroll_parameters.fsp_rate_1',
  'payroll_parameters.fsp_rate_2',
  'payroll_parameters.fsp_rate_3',
  'payroll_parameters.fsp_rate_4',
  'payroll_parameters.fsp_rate_5',
  'payroll_parameters.fsp_rate_6',
  'payroll_parameters.fsp_trigger_smmlv',
  'payroll_parameters.health_employee_rate',
  'payroll_parameters.health_employer_rate',
  'payroll_parameters.parafiscal_caja_rate',
  'payroll_parameters.parafiscal_icbf_rate',
  'payroll_parameters.parafiscal_sena_rate',
  'payroll_parameters.pension_employee_rate',
  'payroll_parameters.pension_employer_rate',
  'payroll_parameters.service_bonus_rate',
  'payroll_parameters.severance_interest_rate',
  'payroll_parameters.severance_rate',
  'payroll_parameters.vacation_rate',
  'pedido_detalle.cantidad',
  'predios.area',
  'presupuesto_lineas.alerta_pct',
  'price_history.percentage_change',
  'productos.conversion_cantidad',
  'productos.impuesto_pct',
  'productos.stock',
  'proyecto_rubros_metas.avance_fisico_porcentaje',
  'purchase_document_lines.quantity',
  'purchase_document_lines.received_quantity',
  'purchase_document_lines.retention_rate',
  'purchase_document_lines.tax_rate',
  'quote_lines.quantity',
  'quote_lines.tax_percentage',
  'recargos.cantidad_horas',
  'recargos.porcentaje_recargo',
  'registros_produccion.unidades_producidas',
  'reglas_impuestos_empresa.tasa',
  'reglas_retenciones_empresa.tasa',
  'revalorizaciones.porcentaje_incremento',
  'sales_document_lines.quantity',
  'sales_document_lines.tax_rate',
  'stock_bodega.cantidad',
  'tarifas_prediales.tarifa',
  'tax_catalog.rate',
  'tax_parameters.inc_restaurant_rate',
  'tax_parameters.inc_telecom_rate',
  'tax_parameters.iva_exempt_rate',
  'tax_parameters.iva_general_rate',
  'tax_parameters.iva_reduced_rate',
  'tax_parameters.retefuente_general_uvt',
  'tax_parameters.retefuente_honoraries_1',
  'tax_parameters.retefuente_honoraries_2',
  'tax_parameters.retefuente_purchases_declaring',
  'tax_parameters.retefuente_purchases_non_declaring',
  'tax_parameters.retefuente_services_1',
  'tax_parameters.retefuente_services_2',
  'tax_parameters.reteica_base_rate',
  'traslados_bodega.cantidad',
  'ventas.cantidad',
  'ventas.impuesto_pct',
  'ventas_detalle.cantidad',
};

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  try {
    // ignore: invalid_use_of_visible_for_testing_member
    await DatabaseHelper.instance.crearDBForTesting(db, 74);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final money = <String, List<String>>{};
    final allReal = <String>[];

    for (final row in tables) {
      final table = row['name']! as String;
      final columns = await db.rawQuery('PRAGMA table_info("$table")');
      for (final column in columns) {
        if (column['type'].toString().toUpperCase() != 'REAL') continue;
        final name = column['name']! as String;
        final qualified = '$table.$name';
        allReal.add(qualified);
        if (!_nonMonetaryRealColumns.contains(qualified)) {
          money.putIfAbsent(table, () => <String>[]).add(name);
        }
      }
    }

    if (allReal.length != 463 || money.values.expand((e) => e).length != 355) {
      throw StateError(
        'Unexpected inventory: REAL=${allReal.length}, '
        'money=${money.values.expand((e) => e).length}',
      );
    }
    final absentExclusions = _nonMonetaryRealColumns
        .where((entry) => !allReal.contains(entry))
        .toList();
    if (absentExclusions.isNotEmpty) {
      throw StateError('Unknown exclusions: $absentExclusions');
    }

    final publicTables = await _publicSchemaTables();
    final output = StringBuffer()
      ..writeln('// Generated by tool/generate_money_schema_manifest.dart.')
      ..writeln('// Do not edit by hand.')
      ..writeln()
      ..writeln('const moneySchemaColumns = <String, Set<String>>{');
    for (final entry in money.entries) {
      entry.value.sort();
      output.writeln("  '${entry.key}': {");
      for (final column in entry.value) {
        output.writeln("    '$column',");
      }
      output.writeln('  },');
    }
    output
      ..writeln('};')
      ..writeln()
      ..writeln('const publicMoneyTables = <String>{');
    for (final table in money.keys.where(publicTables.contains)) {
      output.writeln("  '$table',");
    }
    output
      ..writeln('};')
      ..writeln()
      ..writeln('const moneySchemaColumnCount = 355;');

    await File(
      'lib/core/currency/money_schema_manifest.g.dart',
    ).writeAsString(output.toString());
    stdout.writeln(
      'Generated ${money.length} tables / '
      '${money.values.expand((e) => e).length} columns.',
    );
  } finally {
    await db.close();
    await DatabaseHelper.resetForTests();
  }
}

Future<Set<String>> _publicSchemaTables() async {
  final result = <String>{};
  final schemaFiles = Directory('lib/sector_publico')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => RegExp(r'schema_.*\.dart$').hasMatch(file.path));
  final pattern = RegExp(
    r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?["`\[]?([A-Za-z0-9_]+)',
    caseSensitive: false,
  );
  for (final file in schemaFiles) {
    final source = await file.readAsString();
    result.addAll(pattern.allMatches(source).map((match) => match.group(1)!));
  }
  return result;
}
