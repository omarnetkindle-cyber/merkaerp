// ============================================================
// exportar_excel.dart
// Servicio de exportación contable a Excel (.xlsx).
// Genera un libro con 4 hojas:
//   1. Resumen    – métricas clave del negocio
//   2. Inventario – todos los productos
//   3. Caja       – movimientos de ingresos y egresos
//   4. Ventas     – historial de ventas
// ============================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'core/currency/currency.dart';
import 'core/currency/money_schema_manifest.g.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';

class ExportarExcel {
  // ── Punto de entrada público ─────────────────────────────

  /// Genera el archivo Excel con todos los datos contables
  /// y lanza el diálogo de compartir del sistema operativo.
  static Future<void> exportar(BuildContext context) async {
    // Mostrar indicador de carga mientras se procesa
    _mostrarCargando(context);

    try {
      // 1. Obtener datos de la base de datos
      final productos = await DatabaseHelper.instance.obtenerProductos();
      final movimientos = await DatabaseHelper.instance.obtenerMovimientos();
      final ventas = await DatabaseHelper.instance.obtenerVentas();
      final compras = await DatabaseHelper.instance.obtenerCompras();
      final saldoCaja = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
        'caja',
      );
      final totalVentas = await DatabaseHelper.instance.obtenerTotalVentas();
      final balance = await DatabaseHelper.instance
          .obtenerBalanceComprobacion();
      final asientos = await DatabaseHelper.instance.obtenerAsientosContables();
      final cuentasPorCobrar = await DatabaseHelper.instance
          .obtenerCuentasPorCobrar();
      final cuentasPorPagar = await DatabaseHelper.instance.database.then(
        (db) => db.query('cuentas_por_pagar', orderBy: 'fecha DESC'),
      );
      final cierres = await DatabaseHelper.instance.obtenerCierresCaja();
      final auditoria = await DatabaseHelper.instance.obtenerAuditoria();
      final estados = await DatabaseHelper.instance.obtenerEstadosFinancieros();
      final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
      final comprobantes = await DatabaseHelper.instance.obtenerComprobantes();
      final periodos = await DatabaseHelper.instance.obtenerPeriodosContables();
      final conciliaciones = await DatabaseHelper.instance
          .obtenerConciliacionesBancarias();
      final presupuestos = await DatabaseHelper.instance.obtenerPresupuestos();
      final usuarios = await DatabaseHelper.instance.obtenerUsuarios();
      final facturasElectronicas = await DatabaseHelper.instance
          .obtenerFacturasElectronicas();
      final empleados = await DatabaseHelper.instance.obtenerEmpleados();
      final nomina = await DatabaseHelper.instance.obtenerNomina();
      final activos = await DatabaseHelper.instance.obtenerActivosFijos();
      final extractos = await DatabaseHelper.instance
          .obtenerExtractosBancarios();
      final adjuntos = await DatabaseHelper.instance.obtenerAdjuntos();
      final currency = saldoCaja.currency;
      final productosVista = _displayRows('productos', productos, currency);
      final movimientosVista = _displayRows(
        'movimientos_caja',
        movimientos,
        currency,
      );
      final ventasVista = _displayRows('ventas', ventas, currency);
      final comprasVista = _displayRows('compras', compras, currency);
      final balanceVista = _displayRows(
        'asiento_lineas',
        balance,
        currency,
        extraColumns: const {'saldo'},
      );
      final asientosVista = _displayRows('asiento_lineas', asientos, currency);
      final carteraVista = _displayRows(
        'cuentas_por_cobrar',
        cuentasPorCobrar,
        currency,
      );
      final pagarVista = _displayRows(
        'cuentas_por_pagar',
        cuentasPorPagar,
        currency,
      );
      final cierresVista = _displayRows('cierres_caja', cierres, currency);
      final comprobantesVista = _displayRows(
        'comprobantes_contables',
        comprobantes,
        currency,
      );
      final conciliacionesVista = _displayRows(
        'conciliaciones_bancarias',
        conciliaciones,
        currency,
      );
      final presupuestosVista = _displayRows(
        'presupuestos',
        presupuestos,
        currency,
      );
      final empleadosVista = _displayRows('empleados', empleados, currency);
      final nominaVista = _displayRows(
        'nomina_liquidaciones',
        nomina,
        currency,
      );
      final activosVista = _displayRows('activos_fijos', activos, currency);
      final extractosVista = _displayRows(
        'extractos_bancarios',
        extractos,
        currency,
      );

      // 2. Crear el libro de Excel
      final excel = Excel.createExcel();

      // Eliminar la hoja por defecto que crea el paquete
      excel.delete('Sheet1');

      // 3. Construir cada hoja
      _construirHojaResumen(
        excel,
        productos: productosVista,
        movimientos: movimientosVista,
        ventas: ventasVista,
        saldo: saldoCaja.toMajorUnitsDoubleForDisplay(),
        totalVentas: totalVentas.toMajorUnitsDoubleForDisplay(),
      );

      _construirHojaInventario(excel, productosVista);
      _construirHojaCaja(
        excel,
        movimientosVista,
        saldoCaja.toMajorUnitsDoubleForDisplay(),
      );
      _construirHojaVentas(
        excel,
        ventasVista,
        totalVentas.toMajorUnitsDoubleForDisplay(),
      );
      _construirHojaCompras(excel, comprasVista);
      _construirHojaBalance(excel, balanceVista);
      _construirHojaDiario(excel, asientosVista);
      _construirHojaCartera(excel, carteraVista);
      _construirHojaCuentasPorPagar(excel, pagarVista);
      _construirHojaCierres(excel, cierresVista);
      _construirHojaAuditoria(excel, auditoria);
      _construirHojaEstados(excel, estados);
      _construirHojaEmpresa(excel, empresa);
      _construirHojaComprobantes(excel, comprobantesVista);
      _construirHojaPeriodos(excel, periodos);
      _construirHojaConciliaciones(excel, conciliacionesVista);
      _construirHojaPresupuestos(excel, presupuestosVista);
      _construirHojaUsuarios(excel, usuarios);
      _construirHojaFacturasElectronicas(excel, facturasElectronicas);
      _construirHojaEmpleados(excel, empleadosVista);
      _construirHojaNomina(excel, nominaVista);
      _construirHojaActivos(excel, activosVista);
      _construirHojaExtractos(excel, extractosVista);
      _construirHojaAdjuntos(excel, adjuntos);

      // 4. Codificar el libro a bytes
      final bytes = excel.encode();
      if (bytes == null) throw Exception('No se pudo codificar el archivo');

      final ahora = DateTime.now();

      // 5. Guardar en ruta elegida por el usuario
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar reporte Excel',
        fileName:
            'reporte_${ahora.year}${_pad(ahora.month)}${_pad(ahora.day)}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (savePath == null) {
        if (context.mounted) Navigator.of(context).pop();
        return;
      }

      final path = savePath.endsWith('.xlsx') ? savePath : '$savePath.xlsx';
      final archivo = File(path);
      await archivo.writeAsBytes(bytes);

      // 6. Cerrar el diálogo de carga
      if (context.mounted) Navigator.of(context).pop();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel generado en: ${archivo.path}')),
        );
      }
    } catch (e) {
      // Cerrar el diálogo de carga en caso de error
      if (context.mounted) Navigator.of(context).pop();

      // Mostrar mensaje de error al usuario
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el reporte: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Construcción de hojas ────────────────────────────────

  /// Hoja "Resumen": métricas clave del negocio en una vista rápida.
  static void _construirHojaResumen(
    Excel excel, {
    required List<Map<String, dynamic>> productos,
    required List<Map<String, dynamic>> movimientos,
    required List<Map<String, dynamic>> ventas,
    required double saldo,
    required double totalVentas,
  }) {
    final hoja = excel['Resumen'];

    // Calcular totales de ingresos y egresos por separado
    double totalIngresos = 0;
    double totalEgresos = 0;
    for (final m in movimientos) {
      if (m['tipo'] == 'ingreso') {
        totalIngresos += (m['monto'] as num).toDouble();
      } else {
        totalEgresos += (m['monto'] as num).toDouble();
      }
    }

    // Valor del inventario al costo y al precio de venta
    double valorInventarioCosto = 0;
    double valorInventarioPrecio = 0;
    for (final p in productos) {
      valorInventarioCosto += (p['stock'] as num) * (p['costo'] as num);
      valorInventarioPrecio += (p['stock'] as num) * (p['precio'] as num);
    }

    // Título del reporte
    _escribirCelda(
      hoja,
      0,
      0,
      'REPORTE CONTABLE – CAJA SIMPLE',
      negrita: true,
      tamano: 14,
    );
    _escribirCelda(hoja, 0, 1, 'Generado: ${_fechaHoy()}', tamano: 10);

    hoja.appendRow([TextCellValue('')]);

    // Encabezado de la tabla de métricas
    _escribirCelda(hoja, 0, 3, 'Métrica', negrita: true);
    _escribirCelda(hoja, 1, 3, 'Valor', negrita: true);

    // Filas de métricas
    final metricas = [
      ['Total de ingresos (caja)', '\$${_fmt(totalIngresos)}'],
      ['Total de egresos (caja)', '\$${_fmt(totalEgresos)}'],
      ['Saldo actual de caja', '\$${_fmt(saldo)}'],
      ['Valor del inventario (al costo)', '\$${_fmt(valorInventarioCosto)}'],
      [
        'Valor del inventario (precio venta)',
        '\$${_fmt(valorInventarioPrecio)}',
      ],
      ['Total de ventas registradas', '\$${_fmt(totalVentas)}'],
      ['Número de productos en inventario', '${productos.length}'],
      ['Número de ventas realizadas', '${ventas.length}'],
      ['Número de movimientos de caja', '${movimientos.length}'],
    ];

    for (final fila in metricas) {
      hoja.appendRow([TextCellValue(fila[0]), TextCellValue(fila[1])]);
    }

    // Ajustar ancho de columnas
    hoja.setColumnWidth(0, 40);
    hoja.setColumnWidth(1, 20);
  }

  /// Hoja "Inventario": detalle completo de todos los productos.
  static void _construirHojaInventario(
    Excel excel,
    List<Map<String, dynamic>> productos,
  ) {
    final hoja = excel['Inventario'];

    // Encabezados de columna
    final encabezados = [
      'Nombre',
      'Unidad',
      'Stock',
      'Costo unitario',
      'Precio venta',
      'Valor en costo',
      'Valor en precio',
      'Conversión',
      'Cant. conversión',
    ];

    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());

    // Estilo negrita para encabezados (fila 0)
    for (var col = 0; col < encabezados.length; col++) {
      final celda = hoja.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      celda.cellStyle = CellStyle(bold: true);
    }

    // Filas de datos
    double totalCosto = 0;
    double totalPrecio = 0;

    for (final p in productos) {
      final stock = (p['stock'] as num).toDouble();
      final costo = (p['costo'] as num).toDouble();
      final precio = (p['precio'] as num).toDouble();
      final valCosto = stock * costo;
      final valPrecio = stock * precio;
      totalCosto += valCosto;
      totalPrecio += valPrecio;

      hoja.appendRow([
        TextCellValue(p['nombre'] as String),
        TextCellValue(p['unidad_base'] as String),
        DoubleCellValue(stock),
        DoubleCellValue(costo),
        DoubleCellValue(precio),
        DoubleCellValue(valCosto),
        DoubleCellValue(valPrecio),
        TextCellValue(p['conversion_nombre'] as String? ?? ''),
        DoubleCellValue((p['conversion_cantidad'] as num? ?? 0).toDouble()),
      ]);
    }

    // Fila de totales al final
    hoja.appendRow([
      TextCellValue('TOTAL'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(totalCosto),
      DoubleCellValue(totalPrecio),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    // Ajustar anchos de columna
    hoja.setColumnWidth(0, 25);
    hoja.setColumnWidth(1, 10);
    hoja.setColumnWidth(2, 10);
    hoja.setColumnWidth(3, 15);
    hoja.setColumnWidth(4, 15);
    hoja.setColumnWidth(5, 15);
    hoja.setColumnWidth(6, 18);
    hoja.setColumnWidth(7, 18);
    hoja.setColumnWidth(8, 16);
  }

  /// Hoja "Caja": historial de movimientos con saldo final.
  static void _construirHojaCaja(
    Excel excel,
    List<Map<String, dynamic>> movimientos,
    double saldo,
  ) {
    final hoja = excel['Caja'];

    // Encabezados
    final encabezados = ['Fecha', 'Tipo', 'Concepto', 'Monto'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());

    // Estilo negrita para encabezados
    for (var col = 0; col < encabezados.length; col++) {
      final celda = hoja.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      celda.cellStyle = CellStyle(bold: true);
    }

    // Los movimientos llegan ordenados más reciente primero;
    // para el Excel los invertimos (más antiguo arriba)
    final ordenados = movimientos.reversed.toList();

    for (final m in ordenados) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(m['fecha'] as String)),
        TextCellValue(
          (m['tipo'] as String) == 'ingreso' ? 'Ingreso' : 'Egreso',
        ),
        TextCellValue(m['concepto'] as String),
        DoubleCellValue((m['monto'] as num).toDouble()),
      ]);
    }

    // Fila de saldo final
    hoja.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('SALDO FINAL'),
      DoubleCellValue(saldo),
    ]);

    // Ajustar anchos
    hoja.setColumnWidth(0, 20);
    hoja.setColumnWidth(1, 10);
    hoja.setColumnWidth(2, 30);
    hoja.setColumnWidth(3, 15);
  }

  /// Hoja "Ventas": historial completo de ventas con total.
  static void _construirHojaVentas(
    Excel excel,
    List<Map<String, dynamic>> ventas,
    double totalVentas,
  ) {
    final hoja = excel['Ventas'];

    // Encabezados
    final encabezados = [
      'Fecha',
      'Producto',
      'Cantidad',
      'Subtotal',
      'Impuesto %',
      'Impuesto',
      'Total',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());

    // Estilo negrita para encabezados
    for (var col = 0; col < encabezados.length; col++) {
      final celda = hoja.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      celda.cellStyle = CellStyle(bold: true);
    }

    // Las ventas llegan más reciente primero; las invertimos
    final ordenadas = ventas.reversed.toList();

    for (final v in ordenadas) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(v['fecha'] as String)),
        TextCellValue(v['producto'] as String),
        DoubleCellValue((v['cantidad'] as num).toDouble()),
        DoubleCellValue((v['subtotal'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((v['impuesto_pct'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((v['impuesto_total'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((v['total'] as num).toDouble()),
      ]);
    }

    // Fila de total de ventas
    hoja.appendRow([
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('TOTAL'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(totalVentas),
    ]);

    // Ajustar anchos
    hoja.setColumnWidth(0, 20);
    hoja.setColumnWidth(1, 25);
    hoja.setColumnWidth(2, 12);
    hoja.setColumnWidth(3, 15);
    hoja.setColumnWidth(4, 12);
    hoja.setColumnWidth(5, 15);
    hoja.setColumnWidth(6, 15);
  }

  static void _construirHojaCompras(
    Excel excel,
    List<Map<String, dynamic>> compras,
  ) {
    final hoja = excel['Compras'];
    final encabezados = [
      'Fecha',
      'Proveedor',
      'Factura',
      'Subtotal',
      'Impuesto %',
      'Impuesto',
      'Total',
      'Estado',
      'Observacion',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in compras.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        TextCellValue(c['proveedor']?.toString() ?? ''),
        TextCellValue(c['numero_factura']?.toString() ?? ''),
        DoubleCellValue((c['subtotal'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((c['impuesto_pct'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((c['impuesto_total'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((c['total'] as num?)?.toDouble() ?? 0),
        TextCellValue(c['estado']?.toString() ?? ''),
        TextCellValue(c['observacion']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaBalance(
    Excel excel,
    List<Map<String, dynamic>> balance,
  ) {
    final hoja = excel['Balance'];
    final encabezados = [
      'Código',
      'Cuenta',
      'Tipo',
      'Débito',
      'Crédito',
      'Saldo',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in balance) {
      hoja.appendRow([
        TextCellValue(c['codigo'].toString()),
        TextCellValue(c['nombre'].toString()),
        TextCellValue(c['tipo'].toString()),
        DoubleCellValue((c['debito'] as num).toDouble()),
        DoubleCellValue((c['credito'] as num).toDouble()),
        DoubleCellValue((c['saldo'] as num).toDouble()),
      ]);
    }
  }

  static void _construirHojaDiario(
    Excel excel,
    List<Map<String, dynamic>> asientos,
  ) {
    final hoja = excel['Libro diario'];
    final encabezados = [
      'Fecha',
      'Concepto',
      'Referencia',
      'Origen',
      'Débito',
      'Crédito',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final a in asientos.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(a['fecha'].toString())),
        TextCellValue(a['concepto'].toString()),
        TextCellValue(a['referencia']?.toString() ?? ''),
        TextCellValue(a['origen'].toString()),
        DoubleCellValue((a['debito'] as num).toDouble()),
        DoubleCellValue((a['credito'] as num).toDouble()),
      ]);
    }
  }

  static void _construirHojaCartera(
    Excel excel,
    List<Map<String, dynamic>> cuentas,
  ) {
    final hoja = excel['Cuentas por cobrar'];
    final encabezados = [
      'Fecha',
      'Cliente',
      'Venta',
      'Total',
      'Saldo',
      'Estado',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in cuentas.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        TextCellValue(c['cliente']?.toString() ?? ''),
        TextCellValue(c['venta_id']?.toString() ?? ''),
        DoubleCellValue((c['total'] as num).toDouble()),
        DoubleCellValue((c['saldo'] as num).toDouble()),
        TextCellValue(c['estado'].toString()),
      ]);
    }
  }

  static void _construirHojaCuentasPorPagar(
    Excel excel,
    List<Map<String, dynamic>> cuentas,
  ) {
    final hoja = excel['Cuentas por pagar'];
    final encabezados = [
      'Fecha',
      'Proveedor',
      'Factura',
      'Total',
      'Saldo',
      'Estado',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in cuentas.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        TextCellValue(c['proveedor']?.toString() ?? ''),
        TextCellValue(c['numero_factura']?.toString() ?? ''),
        DoubleCellValue((c['total'] as num).toDouble()),
        DoubleCellValue((c['saldo'] as num).toDouble()),
        TextCellValue(c['estado'].toString()),
      ]);
    }
  }

  static void _construirHojaCierres(
    Excel excel,
    List<Map<String, dynamic>> cierres,
  ) {
    final hoja = excel['Cierres caja'];
    final encabezados = [
      'Fecha',
      'Saldo sistema',
      'Efectivo contado',
      'Diferencia',
      'Observación',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in cierres.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        DoubleCellValue((c['saldo_sistema'] as num).toDouble()),
        DoubleCellValue((c['efectivo_contado'] as num).toDouble()),
        DoubleCellValue((c['diferencia'] as num).toDouble()),
        TextCellValue(c['observacion']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaAuditoria(
    Excel excel,
    List<Map<String, dynamic>> eventos,
  ) {
    final hoja = excel['Auditoria'];
    final encabezados = ['Fecha', 'Acción', 'Entidad', 'ID', 'Detalle'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final e in eventos.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(e['fecha'].toString())),
        TextCellValue(e['accion'].toString()),
        TextCellValue(e['entidad'].toString()),
        TextCellValue(e['entidad_id']?.toString() ?? ''),
        TextCellValue(e['detalle']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaEstados(
    Excel excel,
    Map<String, MoneyValue> estados,
  ) {
    final hoja = excel['Estados financieros'];
    final filas = [
      ['Activos', estados['activos']],
      ['Pasivos', estados['pasivos']],
      ['Patrimonio', estados['patrimonio']],
      ['Ingresos', estados['ingresos']],
      ['Costos', estados['costos']],
      ['Gastos', estados['gastos']],
      ['Utilidad', estados['utilidad']],
      ['Cuadre', estados['cuadre']],
    ];

    hoja.appendRow([TextCellValue('Concepto'), TextCellValue('Valor')]);
    _negritaEncabezado(hoja, 2);
    for (final fila in filas) {
      hoja.appendRow([
        TextCellValue(fila[0] as String),
        TextCellValue((fila[1] as MoneyValue?)?.toMajorUnitsString() ?? '0'),
      ]);
    }
  }

  static List<Map<String, dynamic>> _displayRows(
    String table,
    List<Map<String, dynamic>> rows,
    Currency currency, {
    Set<String> extraColumns = const {},
  }) {
    final columns = <String>{...?moneySchemaColumns[table], ...extraColumns};
    return rows.map((row) {
      final result = Map<String, dynamic>.from(row);
      for (final column in columns) {
        final value = result[column];
        if (value == null) continue;
        result[column] = MoneyValue.fromSql(
          value,
          currency: currency,
        ).toMajorUnitsDoubleForDisplay();
      }
      return result;
    }).toList();
  }

  // ── Helpers internos ─────────────────────────────────────

  /// Escribe un valor de texto en una celda específica con estilo opcional.
  static void _construirHojaEmpresa(Excel excel, Map<String, dynamic> empresa) {
    final hoja = excel['Empresa'];
    hoja.appendRow([TextCellValue('Campo'), TextCellValue('Valor')]);
    _negritaEncabezado(hoja, 2);

    for (final entry in empresa.entries) {
      hoja.appendRow([
        TextCellValue(entry.key),
        TextCellValue(entry.value?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaComprobantes(
    Excel excel,
    List<Map<String, dynamic>> comprobantes,
  ) {
    final hoja = excel['Comprobantes'];
    final encabezados = [
      'Fecha',
      'Consecutivo',
      'Tipo',
      'Concepto',
      'Tercero',
      'Total',
      'Estado',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in comprobantes.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        TextCellValue(c['consecutivo']?.toString() ?? ''),
        TextCellValue(c['tipo']?.toString() ?? ''),
        TextCellValue(c['concepto']?.toString() ?? ''),
        TextCellValue(c['tercero']?.toString() ?? ''),
        DoubleCellValue((c['total'] as num?)?.toDouble() ?? 0),
        TextCellValue(c['estado']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaPeriodos(
    Excel excel,
    List<Map<String, dynamic>> periodos,
  ) {
    final hoja = excel['Periodos'];
    final encabezados = [
      'Año',
      'Mes',
      'Estado',
      'Apertura',
      'Cierre',
      'Observación',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final p in periodos.reversed) {
      hoja.appendRow([
        IntCellValue((p['anio'] as num).toInt()),
        IntCellValue((p['mes'] as num).toInt()),
        TextCellValue(p['estado']?.toString() ?? ''),
        TextCellValue(p['fecha_apertura']?.toString() ?? ''),
        TextCellValue(p['fecha_cierre']?.toString() ?? ''),
        TextCellValue(p['observacion']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaConciliaciones(
    Excel excel,
    List<Map<String, dynamic>> conciliaciones,
  ) {
    final hoja = excel['Conciliaciones'];
    final encabezados = [
      'Fecha',
      'Cuenta',
      'Saldo libros',
      'Saldo extracto',
      'Diferencia',
      'Estado',
      'Observacion',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final c in conciliaciones.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(c['fecha'].toString())),
        TextCellValue(c['cuenta']?.toString() ?? ''),
        DoubleCellValue((c['saldo_libros'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((c['saldo_extracto'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((c['diferencia'] as num?)?.toDouble() ?? 0),
        TextCellValue(c['estado']?.toString() ?? ''),
        TextCellValue(c['observacion']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaPresupuestos(
    Excel excel,
    List<Map<String, dynamic>> presupuestos,
  ) {
    final hoja = excel['Presupuestos'];
    final encabezados = [
      'Año',
      'Mes',
      'Tipo',
      'Categoria',
      'Presupuestado',
      'Real',
      'Diferencia',
      'Observacion',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);

    for (final p in presupuestos.reversed) {
      hoja.appendRow([
        IntCellValue((p['anio'] as num).toInt()),
        IntCellValue((p['mes'] as num).toInt()),
        TextCellValue(p['tipo']?.toString() ?? ''),
        TextCellValue(p['categoria']?.toString() ?? ''),
        DoubleCellValue((p['valor_presupuestado'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((p['valor_real'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((p['diferencia'] as num?)?.toDouble() ?? 0),
        TextCellValue(p['observacion']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaUsuarios(
    Excel excel,
    List<Map<String, dynamic>> usuarios,
  ) {
    final hoja = excel['Usuarios'];
    final encabezados = ['Nombre', 'Usuario', 'Rol', 'Activo', 'Fecha'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final u in usuarios) {
      hoja.appendRow([
        TextCellValue(u['nombre']?.toString() ?? ''),
        TextCellValue(u['usuario']?.toString() ?? ''),
        TextCellValue(u['rol']?.toString() ?? ''),
        TextCellValue(((u['activo'] as num?) ?? 0) == 1 ? 'Si' : 'No'),
        TextCellValue(u['fecha']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaFacturasElectronicas(
    Excel excel,
    List<Map<String, dynamic>> facturas,
  ) {
    final hoja = excel['Facturacion electronica'];
    final encabezados = [
      'Fecha',
      'Consecutivo',
      'Venta',
      'Estado',
      'CUFE/CUDE',
      'Respuesta',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final f in facturas.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(f['fecha'].toString())),
        TextCellValue(f['consecutivo']?.toString() ?? ''),
        TextCellValue(f['venta_id']?.toString() ?? ''),
        TextCellValue(f['estado']?.toString() ?? ''),
        TextCellValue(f['cufe']?.toString() ?? ''),
        TextCellValue(f['respuesta_dian']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaEmpleados(
    Excel excel,
    List<Map<String, dynamic>> empleados,
  ) {
    final hoja = excel['Empleados'];
    final encabezados = ['Nombre', 'Documento', 'Cargo', 'Salario', 'Auxilio'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final e in empleados) {
      hoja.appendRow([
        TextCellValue(e['nombre']?.toString() ?? ''),
        TextCellValue(e['documento']?.toString() ?? ''),
        TextCellValue(e['cargo']?.toString() ?? ''),
        DoubleCellValue((e['salario_base'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((e['auxilio_transporte'] as num?)?.toDouble() ?? 0),
      ]);
    }
  }

  static void _construirHojaNomina(
    Excel excel,
    List<Map<String, dynamic>> nomina,
  ) {
    final hoja = excel['Nomina'];
    final encabezados = [
      'Periodo',
      'Empleado',
      'Devengado',
      'Deducciones',
      'Neto',
      'Estado',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final n in nomina.reversed) {
      hoja.appendRow([
        TextCellValue(n['periodo']?.toString() ?? ''),
        TextCellValue(n['empleado']?.toString() ?? ''),
        DoubleCellValue((n['total_devengado'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((n['total_deducciones'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((n['neto_pagar'] as num?)?.toDouble() ?? 0),
        TextCellValue(n['estado']?.toString() ?? ''),
      ]);
    }
  }

  static void _construirHojaActivos(
    Excel excel,
    List<Map<String, dynamic>> activos,
  ) {
    final hoja = excel['Activos fijos'];
    final encabezados = [
      'Nombre',
      'Categoria',
      'Costo',
      'Vida meses',
      'Dep. mensual',
      'Dep. acumulada',
      'Valor libros',
    ];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final a in activos) {
      hoja.appendRow([
        TextCellValue(a['nombre']?.toString() ?? ''),
        TextCellValue(a['categoria']?.toString() ?? ''),
        DoubleCellValue((a['costo'] as num?)?.toDouble() ?? 0),
        IntCellValue((a['vida_util_meses'] as num?)?.toInt() ?? 0),
        DoubleCellValue((a['depreciacion_mensual'] as num?)?.toDouble() ?? 0),
        DoubleCellValue(
          (a['depreciacion_acumulada_calc'] as num?)?.toDouble() ?? 0,
        ),
        DoubleCellValue((a['valor_libros_calc'] as num?)?.toDouble() ?? 0),
      ]);
    }
  }

  static void _construirHojaExtractos(
    Excel excel,
    List<Map<String, dynamic>> extractos,
  ) {
    final hoja = excel['Extractos'];
    final encabezados = ['Fecha', 'Cuenta', 'Tipo', 'Descripcion', 'Valor'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final e in extractos.reversed) {
      hoja.appendRow([
        TextCellValue(e['fecha']?.toString() ?? ''),
        TextCellValue(e['cuenta']?.toString() ?? ''),
        TextCellValue(e['tipo']?.toString() ?? ''),
        TextCellValue(e['descripcion']?.toString() ?? ''),
        DoubleCellValue((e['valor'] as num?)?.toDouble() ?? 0),
      ]);
    }
  }

  static void _construirHojaAdjuntos(
    Excel excel,
    List<Map<String, dynamic>> adjuntos,
  ) {
    final hoja = excel['Adjuntos'];
    final encabezados = ['Fecha', 'Entidad', 'ID', 'Nombre', 'Ruta', 'Notas'];
    hoja.appendRow(encabezados.map((e) => TextCellValue(e)).toList());
    _negritaEncabezado(hoja, encabezados.length);
    for (final a in adjuntos.reversed) {
      hoja.appendRow([
        TextCellValue(_formatearFecha(a['fecha'].toString())),
        TextCellValue(a['entidad']?.toString() ?? ''),
        TextCellValue(a['entidad_id']?.toString() ?? ''),
        TextCellValue(a['nombre']?.toString() ?? ''),
        TextCellValue(a['ruta']?.toString() ?? ''),
        TextCellValue(a['notas']?.toString() ?? ''),
      ]);
    }
  }

  static void _escribirCelda(
    Sheet hoja,
    int col,
    int fila,
    String texto, {
    bool negrita = false,
    int tamano = 11,
  }) {
    final celda = hoja.cell(
      CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila),
    );
    celda.value = TextCellValue(texto);
    celda.cellStyle = CellStyle(bold: negrita, fontSize: tamano);
  }

  static void _negritaEncabezado(Sheet hoja, int columnas) {
    for (var col = 0; col < columnas; col++) {
      final celda = hoja.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
      );
      celda.cellStyle = CellStyle(bold: true);
    }
  }

  /// Muestra un diálogo de progreso no cancelable.
  static void _mostrarCargando(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Generando reporte…'),
          ],
        ),
      ),
    );
  }

  /// Formatea un número con dos decimales: 1234.50
  static String _fmt(double v) => v.toStringAsFixed(2);

  /// Rellena con cero a la izquierda si el número es de un dígito.
  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// Devuelve la fecha actual en formato dd/mm/aaaa.
  static String _fechaHoy() {
    final dt = DateTime.now();
    return '${_pad(dt.day)}/${_pad(dt.month)}/${dt.year}';
  }

  /// Convierte una fecha ISO 8601 a formato legible: 14/05/2026 10:30
  static String _formatearFecha(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${_pad(dt.day)}/${_pad(dt.month)}/${dt.year} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }
}
