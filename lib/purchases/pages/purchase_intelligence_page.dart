import 'package:flutter/material.dart';

import '../../core/predictive/predictive_analytics.dart';
import '../../db_helper.dart';
import '../../ui/merka_theme_tokens.dart';

class PurchaseSuggestionSelection {
  const PurchaseSuggestionSelection({
    required this.productId,
    required this.productName,
    required this.quantity,
  });

  final int productId;
  final String productName;
  final double quantity;
}

/// Asistente de compra basado en el consumo real de inventario.
///
/// Solo prepara líneas sugeridas. La compra sigue pasando por el formulario
/// normal de Compras, donde el usuario selecciona proveedor, costos, impuestos
/// y confirma la transacción.
class PurchaseIntelligencePage extends StatefulWidget {
  const PurchaseIntelligencePage({super.key});

  @override
  State<PurchaseIntelligencePage> createState() =>
      _PurchaseIntelligencePageState();
}

class _PurchaseIntelligencePageState extends State<PurchaseIntelligencePage> {
  Future<List<Map<String, dynamic>>>? _future;
  final Set<int> _selected = <int>{};
  final Map<int, TextEditingController> _quantityControllers = {};
  int _horizon = 30;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _reload() {
    _selected.clear();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await PredictiveAnalytics.instance.forecastStockRequirements(
      db,
      companyId,
      days: _horizon,
    );
    final urgent = rows
        .where((row) => row['needs_reorder'] == true)
        .toList(growable: false);
    for (final row in urgent) {
      final id = (row['product_id'] as num).toInt();
      final qty = (row['recommended_order'] as num?)?.toDouble() ?? 0;
      _selected.add(id);
      _quantityControllers[id] = TextEditingController(text: _qty(qty));
    }
    return urgent;
  }

  void _useSuggestions(List<Map<String, dynamic>> rows) {
    final result = <PurchaseSuggestionSelection>[];
    for (final row in rows) {
      final id = (row['product_id'] as num).toInt();
      if (!_selected.contains(id)) continue;
      final qty = double.tryParse(
            (_quantityControllers[id]?.text ?? '').trim().replaceAll(',', '.'),
          ) ??
          0;
      if (qty <= 0) continue;
      result.add(
        PurchaseSuggestionSelection(
          productId: id,
          productName: row['product_name']?.toString() ?? 'Producto',
          quantity: qty,
        ),
      );
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras inteligentes')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('No se pudo generar la sugerencia: ${snapshot.error}'));
          }
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¿Qué debo comprar?',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'La recomendación usa ventas recientes, consumo diario, '
                          'existencias y stock mínimo. Puedes cambiar las cantidades '
                          'antes de pasarlas al formulario normal de compra.',
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Horizonte: '),
                            DropdownButton<int>(
                              value: _horizon,
                              items: const [
                                DropdownMenuItem(value: 7, child: Text('7 días')),
                                DropdownMenuItem(value: 15, child: Text('15 días')),
                                DropdownMenuItem(value: 30, child: Text('30 días')),
                                DropdownMenuItem(value: 60, child: Text('60 días')),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _horizon = value;
                                  _reload();
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Text('No hay productos que requieran reposición.'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          final id = (row['product_id'] as num).toInt();
                          final selected = _selected.contains(id);
                          final stock = (row['current_stock'] as num?)?.toDouble() ?? 0;
                          final consumption =
                              (row['daily_consumption'] as num?)?.toDouble() ?? 0;
                          final days = (row['days_until_low'] as num?)?.toInt() ?? -1;
                          return Card(
                            child: CheckboxListTile(
                              value: selected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selected.add(id);
                                  } else {
                                    _selected.remove(id);
                                  }
                                });
                              },
                              secondary: const Icon(
                                Icons.inventory_2_outlined,
                                color: MerkaThemeTokens.navy700,
                              ),
                              title: Text(row['product_name']?.toString() ?? 'Producto'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Stock ${_qty(stock)} · Consumo/día ${_qty(consumption)}'
                                    '${days < 0 ? '' : ' · mínimo en $days día(s)'}',
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 180,
                                    child: TextField(
                                      enabled: selected,
                                      controller: _quantityControllers[id],
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Cantidad a comprar',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: rows.isEmpty ? null : () => _useSuggestions(rows),
                      icon: const Icon(Icons.shopping_cart_checkout),
                      label: Text('Usar ${_selected.length} sugerencia(s) en una compra'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _qty(double value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
