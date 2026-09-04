import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/currency/currency.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';
import '../services/merka_intelligence_service.dart';
import 'merka_theme_tokens.dart';

class OperationsModePanel extends StatefulWidget {
  const OperationsModePanel({
    super.key,
    required this.onOpenInventory,
    required this.onOpenPurchases,
    required this.onNotifications,
  });

  final VoidCallback onOpenInventory;
  final VoidCallback onOpenPurchases;
  final VoidCallback onNotifications;

  @override
  State<OperationsModePanel> createState() => _OperationsModePanelState();
}

class _OperationsModePanelState extends State<OperationsModePanel> {
  final MerkaIntelligenceService _intelligence = MerkaIntelligenceService();
  List<OperationalAlert> _criticalStock = [];
  List<OperationalAlert> _expiringProducts = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _pendingOrders = [];

  double _totalEntries = 0.0;
  double _totalExits = 0.0;
  bool _loading = true;
  Currency? _currency;

  @override
  void initState() {
    super.initState();
    _loadOperationsData();
  }

  Future<void> _loadOperationsData() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      _currency = currency;

      // Load alerts
      final alerts = await _intelligence.operationalAlerts();
      _criticalStock = alerts.where((a) => a.kind == 'critical_stock').toList();
      _expiringProducts = alerts
          .where((a) => a.kind == 'expiring_product')
          .toList();

      // Load suppliers
      _suppliers = await DatabaseHelper.instance.obtenerProveedores();

      // Load pending purchase orders
      _pendingOrders = await db.query(
        'compras',
        where: 'company_id = ? AND (estado = ? OR estado = ?)',
        whereArgs: [companyId, 'pendiente', 'borrador'],
        orderBy: 'fecha DESC',
        limit: 5,
      );

      // Sum entries and exits for month
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final monthEnd = DateTime(
        now.year,
        now.month + 1,
        0,
        23,
        59,
      ).toIso8601String();

      final entriesRows = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0) AS total FROM compras WHERE company_id = ? AND fecha BETWEEN ? AND ?",
        [companyId, monthStart, monthEnd],
      );
      final exitsRows = await db.rawQuery(
        "SELECT COALESCE(SUM(total), 0) AS total FROM ventas WHERE company_id = ? AND fecha BETWEEN ? AND ? AND COALESCE(estado, 'emitida') != 'anulada'",
        [companyId, monthStart, monthEnd],
      );

      _totalEntries = _major(entriesRows.first['total'], currency);
      _totalExits = _major(exitsRows.first['total'], currency);
    } catch (e) {
      debugPrint('Error loading operations mode data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: MerkaThemeTokens.navy800),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        final leftColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Widgets: Stock Crítico & Próximos a Vencer
            Row(
              children: [
                Expanded(
                  child: _WidgetCard(
                    title: 'Stock Crítico',
                    subtitle: '${_criticalStock.length} productos críticos',
                    icon: PhosphorIcons.warningCircle(),
                    iconColor: MerkaThemeTokens.danger,
                    child: _criticalStock.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Todo el stock está correcto.',
                              style: TextStyle(
                                fontSize: 12,
                                color: MerkaThemeTokens.graphite600,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._criticalStock
                                  .take(3)
                                  .map(
                                    (a) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        '• ${a.title} (${a.detail.split(" ").first} und)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: widget.onOpenPurchases,
                                icon: const Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Reabastecer en Compras',
                                  style: TextStyle(fontSize: 11),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: MerkaThemeTokens.navy600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _WidgetCard(
                    title: 'Próximos a Vencer',
                    subtitle: '${_expiringProducts.length} lotes por vencer',
                    icon: PhosphorIcons.timer(),
                    iconColor: MerkaThemeTokens.warning,
                    child: _expiringProducts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'Sin lotes próximos a vencer.',
                              style: TextStyle(
                                fontSize: 12,
                                color: MerkaThemeTokens.graphite600,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _expiringProducts
                                .take(3)
                                .map(
                                  (a) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '• ${a.title}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Short cuts
            Text(
              'Accesos Rápidos de Operación',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ShortcutButton(
                  label: 'Entrada Mercancía',
                  icon: PhosphorIcons.arrowDown(),
                  color: MerkaThemeTokens.success,
                  onTap: widget.onOpenPurchases,
                ),
                _ShortcutButton(
                  label: 'Salida / Despacho',
                  icon: PhosphorIcons.arrowUp(),
                  color: MerkaThemeTokens.danger,
                  onTap: widget.onOpenInventory,
                ),
                _ShortcutButton(
                  label: 'Traslados Bodega',
                  icon: PhosphorIcons.arrowsLeftRight(),
                  color: MerkaThemeTokens.navy800,
                  onTap: widget.onOpenInventory,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Bar chart entries vs exits
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MerkaThemeTokens.paper100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Movimiento de Inventario del Mes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: _ChartBar(
                          label: 'Entradas (Compras)',
                          value: _totalEntries,
                          color: MerkaThemeTokens.navy800,
                          max: _totalEntries > _totalExits
                              ? _totalEntries
                              : _totalExits,
                        ),
                      ),
                      const SizedBox(width: 40),
                      Expanded(
                        child: _ChartBar(
                          label: 'Salidas (Ventas)',
                          value: _totalExits,
                          color: MerkaThemeTokens.danger,
                          max: _totalEntries > _totalExits
                              ? _totalEntries
                              : _totalExits,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final rightColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pending purchase orders
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MerkaThemeTokens.paper100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Órdenes de Compra Pendientes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Icon(
                        Icons.history_outlined,
                        size: 16,
                        color: MerkaThemeTokens.graphite600,
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (_pendingOrders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No hay órdenes de compra pendientes.',
                          style: TextStyle(
                            fontSize: 12,
                            color: MerkaThemeTokens.graphite600,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._pendingOrders.map((ord) {
                      final val = _major(ord['total'], _currency!);
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.shopping_bag_outlined,
                          color: MerkaThemeTokens.navy800,
                        ),
                        title: Text('Orden #${ord['id']}'),
                        subtitle: Text(
                          'Fecha: ${ord['fecha'].toString().split("T").first}',
                        ),
                        trailing: Text(
                          '\$${val.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Recent suppliers
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MerkaThemeTokens.paper100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Proveedores Principales',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Divider(height: 24),
                  if (_suppliers.isEmpty)
                    const Center(
                      child: Text(
                        'No hay proveedores registrados.',
                        style: TextStyle(fontSize: 12),
                      ),
                    )
                  else
                    ..._suppliers
                        .take(4)
                        .map(
                          (sup) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.business,
                                  size: 16,
                                  color: MerkaThemeTokens.graphite600,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sup['nombre']?.toString() ?? 'Proveedor',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  sup['nit']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: MerkaThemeTokens.graphite600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ],
        );

        if (compact) {
          return SingleChildScrollView(
            child: Column(
              children: [leftColumn, const SizedBox(height: 16), rightColumn],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: leftColumn),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: rightColumn),
          ],
        );
      },
    );
  }

  double _major(Object? value, Currency currency) => MoneyValue.fromSql(
    value,
    currency: currency,
    nullableAsZero: true,
  ).toMajorUnitsDoubleForDisplay();
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MerkaThemeTokens.paper100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: MerkaThemeTokens.graphite600,
            ),
          ),
          const Divider(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color, size: 16),
      label: Text(
        label,
        style: const TextStyle(color: MerkaThemeTokens.graphite900),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: MerkaThemeTokens.paper100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
    required this.label,
    required this.value,
    required this.color,
    required this.max,
  });

  final String label;
  final double value;
  final Color color;
  final double max;

  @override
  Widget build(BuildContext context) {
    final pct = max == 0 ? 0.05 : (value / max).clamp(0.05, 1.0);
    return Column(
      children: [
        Text(
          '\$${value.toStringAsFixed(0)}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Container(
          height: 120 * pct,
          width: 48,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: MerkaThemeTokens.graphite600,
          ),
        ),
      ],
    );
  }
}
