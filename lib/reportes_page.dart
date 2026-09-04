// ============================================================
// reportes_page.dart
// Módulo de reportes: análisis de ventas, rentabilidad,
// estado del inventario y flujo de caja.
// ============================================================

import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'reporting/configurable_report_page.dart';

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  // Estado de carga
  bool _cargando = true;

  // Métricas calculadas
  double _totalVentas = 0;
  double _totalIngresos = 0;
  double _totalEgresos = 0;
  double _saldoCaja = 0;
  double _valorInventarioCosto = 0;
  double _valorInventarioPrecio = 0;
  double _gananciaBruta = 0;
  double _ticketPromedio = 0;
  double _margenBrutoPct = 0;
  double ingresosTotales = 0;
  double egresosTotales = 0;

  // Datos de listas
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _ventas = [];

  // Top 5 productos por ingreso generado
  List<Map<String, dynamic>> _topProductos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarDatos);
      }
    });
  }

  // ── Carga y cálculo ──────────────────────────────────────

  /// Obtiene todos los datos y calcula las métricas de reporte.
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    final productos = await DatabaseHelper.instance.obtenerProductos();
    final ventas = await DatabaseHelper.instance.obtenerVentasActivas();
    final movimientos = await DatabaseHelper.instance.obtenerMovimientos();
    final saldoCaja = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'caja',
    );
    final totalVentas = await DatabaseHelper.instance.obtenerTotalVentas();
    double amount(Object? value) => MoneyValue.fromSql(
      value,
      currency: saldoCaja.currency,
      nullableAsZero: true,
    ).toMajorUnitsDoubleForDisplay();

    // Separar ingresos y egresos de caja
    double totalIngresos = 0;
    double totalEgresos = 0;
    ingresosTotales = 0;
    egresosTotales = 0;
    for (final m in movimientos) {
      if (m['tipo'] == 'ingreso') {
        totalIngresos += amount(m['monto']);
      } else if (m['tipo'] == 'egreso') {
        totalEgresos += amount(m['monto']);
      }
    }
    ingresosTotales = totalIngresos;
    egresosTotales = totalEgresos;
    // Valor del inventario al costo y al precio de venta
    double valorCosto = 0;
    double valorPrecio = 0;
    for (final p in productos) {
      valorCosto += (p['stock'] as num) * amount(p['costo']);
      valorPrecio += (p['stock'] as num) * amount(p['precio']);
    }

    // Ganancia bruta = suma de (precio_unitario - costo_unitario) × cantidad
    double gananciaBruta = 0;
    final Map<String, double> ventasCant = {};
    final Map<String, double> ventasTotal = {};
    for (final v in ventas) {
      final detalle = await DatabaseHelper.instance.obtenerDetalleVenta(
        (v['id'] as num).toInt(),
      );
      for (final item in detalle) {
        final nombre = item['producto'] as String;
        final cantidad = (item['cantidad'] as num).toDouble();
        final precio = amount(item['precio_unitario']);
        final subtotal = amount(item['subtotal']);
        final producto = productos.where((p) => p['id'] == item['producto_id']);
        final costo = producto.isEmpty ? 0.0 : amount(producto.first['costo']);
        gananciaBruta += (precio - costo) * cantidad;
        ventasCant[nombre] = (ventasCant[nombre] ?? 0) + cantidad;
        ventasTotal[nombre] = (ventasTotal[nombre] ?? 0) + subtotal;
      }
    }

    // Ordenar por total generado descendente y tomar top 5
    final topProductos =
        ventasTotal.entries
            .map(
              (e) => {
                'nombre': e.key,
                'total': e.value,
                'cantidad': ventasCant[e.key] ?? 0.0,
              },
            )
            .toList()
          ..sort(
            (a, b) => (b['total'] as double).compareTo(a['total'] as double),
          );

    setState(() {
      _productos = productos;
      _ventas = ventas;
      _saldoCaja = saldoCaja.toMajorUnitsDoubleForDisplay();
      _totalVentas = totalVentas.toMajorUnitsDoubleForDisplay();
      _totalIngresos = totalIngresos;
      _totalEgresos = totalEgresos;
      _valorInventarioCosto = valorCosto;
      _valorInventarioPrecio = valorPrecio;
      _gananciaBruta = gananciaBruta;
      _ticketPromedio = ventas.isEmpty
          ? 0
          : totalVentas.toMajorUnitsDoubleForDisplay() / ventas.length;
      _margenBrutoPct = totalVentas.minorUnits <= 0
          ? 0
          : (gananciaBruta / totalVentas.toMajorUnitsDoubleForDisplay()) * 100;
      _topProductos = topProductos.take(5).toList();
      _cargando = false;
    });
  }

  // ── Helpers ──────────────────────────────────────────────

  /// Formatea un número como moneda: $1,234.50
  String _moneda(double valor) =>
      '\$${valor.toStringAsFixed(2).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          // Botón para recargar los datos manualmente
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Diseñar reporte configurable',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConfigurableReportPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargarDatos,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // ── Resumen general ──────────────────────
                  _encabezadoSeccion('Resumen general'),
                  _tarjetaMetrica(
                    icono: Icons.point_of_sale,
                    color: Colors.orange,
                    titulo: 'Total ventas',
                    valor: _moneda(_totalVentas),
                    subtitulo: '${_ventas.length} transacciones',
                  ),
                  _tarjetaMetrica(
                    icono: Icons.trending_up,
                    color: Colors.green.shade700,
                    titulo: 'Ganancia bruta',
                    valor: _moneda(_gananciaBruta),
                    subtitulo: 'Ventas − costo de mercadería',
                  ),
                  _tarjetaMetrica(
                    icono: Icons.account_balance_wallet,
                    color: _saldoCaja >= 0 ? MerkaThemeTokens.success : MerkaThemeTokens.danger,
                    titulo: 'Saldo en caja',
                    valor: _moneda(_saldoCaja),
                    subtitulo: 'Ingresos − egresos acumulados',
                  ),
                  const SizedBox(height: 8),

                  // ── Flujo de caja ────────────────────────
                  _encabezadoSeccion('Flujo de caja'),
                  Row(
                    children: [
                      Expanded(
                        child: _tarjetaMetrica(
                          icono: Icons.south_west,
                          color: Colors.green,
                          titulo: 'Ingresos',
                          valor: _moneda(_totalIngresos),
                          subtitulo: '',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _tarjetaMetrica(
                          icono: Icons.north_east,
                          color: Colors.red,
                          titulo: 'Egresos',
                          valor: _moneda(_totalEgresos),
                          subtitulo: '',
                        ),
                      ),
                    ],
                  ),
                  _graficoFlujo(),
                  const SizedBox(height: 8),

                  // ── Inventario ───────────────────────────
                  _encabezadoSeccion('Estado del inventario'),
                  _tarjetaMetrica(
                    icono: Icons.inventory_2,
                    color: MerkaThemeTokens.navy600,
                    titulo: 'Valor al costo',
                    valor: _moneda(_valorInventarioCosto),
                    subtitulo: '${_productos.length} productos registrados',
                  ),
                  _tarjetaMetrica(
                    icono: Icons.sell,
                    color: MerkaThemeTokens.navy700,
                    titulo: 'Valor a precio de venta',
                    valor: _moneda(_valorInventarioPrecio),
                    subtitulo:
                        'Ganancia potencial: ${_moneda(_valorInventarioPrecio - _valorInventarioCosto)}',
                  ),
                  const SizedBox(height: 8),

                  // ── Top productos ────────────────────────
                  if (_topProductos.isNotEmpty) ...[
                    _encabezadoSeccion('Top productos (por ventas)'),
                    ..._topProductos.asMap().entries.map(
                      (e) => _filaTopProducto(e.key + 1, e.value),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ── Alertas de stock bajo ────────────────
                  if (_productos.any((p) => (p['stock'] as num) <= 5)) ...[
                    _encabezadoSeccion('⚠ Stock bajo'),
                    ..._productos
                        .where((p) => (p['stock'] as num) <= 5)
                        .map(
                          (p) => Card(
                            elevation: 1,
                            color: Colors.red.shade50,
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.warning_amber,
                                color: Colors.red.shade600,
                              ),
                              title: Text(p['nombre'] as String),
                              trailing: Text(
                                'Stock: ${p['stock']} ${p['unidad_base']}',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  // ── Widgets de construcción ──────────────────────────────

  /// Encabezado de sección con texto en mayúsculas y color gris.
  Widget _encabezadoSeccion(String titulo) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      titulo.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey,
        letterSpacing: 0.8,
      ),
    ),
  );

  /// Tarjeta de métrica con ícono, título, valor y subtítulo.
  Widget _tarjetaMetrica({
    required IconData icono,
    required Color color,
    required String titulo,
    required String valor,
    required String subtitulo,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icono, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  if (subtitulo.isNotEmpty)
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fila de top producto con número de posición y barra de progreso.
  Widget _filaTopProducto(int pos, Map<String, dynamic> p) {
    final maxTotal = _topProductos.isEmpty
        ? 1.0
        : (_topProductos.first['total'] as double);
    final total = p['total'] as double;
    final progreso = maxTotal > 0 ? total / maxTotal : 0.0;
    final cantidad = p['cantidad'] as double;
    final cantStr = cantidad % 1 == 0
        ? cantidad.toInt().toString()
        : cantidad.toString();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            // Número de posición
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.orange.shade100,
              child: Text(
                '$pos',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Nombre y barra de progreso proporcional
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['nombre'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  _tarjetaMetrica(
                    icono: Icons.percent,
                    color: MerkaThemeTokens.navy700,
                    titulo: 'Margen bruto',
                    valor: '${_margenBrutoPct.toStringAsFixed(1)}%',
                    subtitulo: 'Ganancia bruta / ventas',
                  ),
                  _tarjetaMetrica(
                    icono: Icons.shopping_cart_checkout,
                    color: MerkaThemeTokens.gold500,
                    titulo: 'Ticket promedio',
                    valor: _moneda(_ticketPromedio),
                    subtitulo: 'Promedio por factura emitida',
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progreso,
                      minHeight: 6,
                      backgroundColor: Colors.orange.shade50,
                      valueColor: AlwaysStoppedAnimation(
                        Colors.orange.shade400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$cantStr unid. vendidas',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Total en dinero
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 96),
              child: Text(
                _moneda(total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _graficoFlujo() {
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [
                BarChartRodData(toY: ingresosTotales, color: Colors.green),
              ],
            ),
            BarChartGroupData(
              x: 1,
              barRods: [
                BarChartRodData(toY: egresosTotales, color: Colors.red),
              ],
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  switch (value.toInt()) {
                    case 0:
                      return const Text('Ingresos');
                    case 1:
                      return const Text('Egresos');
                  }
                  return const Text('');
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
