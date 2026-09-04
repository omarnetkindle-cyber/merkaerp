import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../app_session.dart';
import '../../core/predictive/predictive_analytics.dart';
import '../../core/security/action_permission.dart';
import '../../db_helper.dart';
import '../../ui/merka_theme_tokens.dart';
import '../application/inventory_movement_service.dart';
import '../application/warehouse_stock_service.dart';

/// Centro operativo del dominio Inventario.
///
/// No es un módulo independiente: expone capacidades que ya pertenecen a
/// Inventario (reposición, bodegas, conteos, variantes y series) reutilizando
/// las proyecciones/Kardex existentes.
class InventoryControlCenterPage extends StatefulWidget {
  const InventoryControlCenterPage({super.key});

  @override
  State<InventoryControlCenterPage> createState() =>
      _InventoryControlCenterPageState();
}

class _InventoryControlCenterPageState extends State<InventoryControlCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de control de inventario'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.auto_graph), text: 'Reposición'),
            Tab(icon: Icon(Icons.warehouse_outlined), text: 'Bodegas'),
            Tab(icon: Icon(Icons.fact_check_outlined), text: 'Conteos'),
            Tab(icon: Icon(Icons.tune), text: 'Variantes y series'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ReplenishmentTab(),
          _WarehousesTab(),
          _PhysicalCountsTab(),
          _VariantsSerialsTab(),
        ],
      ),
    );
  }
}

class _ReplenishmentTab extends StatefulWidget {
  const _ReplenishmentTab();

  @override
  State<_ReplenishmentTab> createState() => _ReplenishmentTabState();
}

class _ReplenishmentTabState extends State<_ReplenishmentTab> {
  Future<List<Map<String, dynamic>>>? _future;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return PredictiveAnalytics.instance.forecastStockRequirements(
      db,
      companyId,
      days: _days,
    );
  }


  Future<void> _editPolicy(Map<String, dynamic> row) async {
    if (!AppSession.puedeEjecutarAccion('inventory', AppAction.update)) {
      _message('No tienes permiso para modificar políticas de inventario.');
      return;
    }
    final minCtrl = TextEditingController(text: ((row['min_stock'] as num?)?.toDouble() ?? 0).toString());
    final maxCtrl = TextEditingController(text: ((row['max_stock'] as num?)?.toDouble() ?? 0).toString());
    final leadCtrl = TextEditingController(text: ((row['lead_time_days'] as num?)?.toInt() ?? 7).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Política · ${row['product_name'] ?? 'Producto'}'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: minCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock mínimo', helperText: 'Nivel de seguridad que no debería cruzarse.')),
            const SizedBox(height: 10),
            TextField(controller: maxCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stock máximo (0 = automático)', helperText: 'Meta de reposición. Si es 0, MerkaERP la calcula según consumo.')),
            const SizedBox(height: 10),
            TextField(controller: leadCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tiempo de reposición (días)', helperText: 'Días habituales desde pedir hasta recibir.')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final minimum = double.tryParse(minCtrl.text.replaceAll(',', '.'));
    final maximum = double.tryParse(maxCtrl.text.replaceAll(',', '.'));
    final lead = int.tryParse(leadCtrl.text.trim());
    if (minimum == null || maximum == null || lead == null || minimum < 0 || maximum < 0 || lead < 0 || lead > 365) {
      _message('Revisa los valores. Mínimo/máximo deben ser ≥ 0 y el tiempo entre 0 y 365 días.');
      return;
    }
    if (maximum > 0 && maximum < minimum) {
      _message('El stock máximo no puede ser menor que el mínimo.');
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.update(
      'productos',
      {'stock_minimo': minimum, 'stock_maximo': maximum, 'lead_time_days': lead},
      where: 'company_id = ? AND id = ?',
      whereArgs: [companyId, row['product_id']],
    );
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ACTUALIZAR_POLITICA_INVENTARIO',
      entidad: 'productos',
      entidadId: (row['product_id'] as num?)?.toInt(),
      detalle: 'Mínimo $minimum · máximo $maximum · reposición $lead día(s) · ${AppSession.nombre}',
    );
    if (mounted) setState(_reload);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'MerkaERP calcula qué conviene comprar usando consumo '
                      'histórico, existencias actuales y stock mínimo. La '
                      'sugerencia no crea compras sin confirmación del usuario.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _days,
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('7 días')),
                      DropdownMenuItem(value: 15, child: Text('15 días')),
                      DropdownMenuItem(value: 30, child: Text('30 días')),
                      DropdownMenuItem(value: 60, child: Text('60 días')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _days = value;
                        _reload();
                      });
                    },
                  ),
                  IconButton(
                    tooltip: 'Actualizar sugerencias',
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('No se pudo analizar: ${snapshot.error}'));
              }
              final rows = (snapshot.data ?? const <Map<String, dynamic>>[])
                  .where((row) => row['needs_reorder'] == true)
                  .toList();
              if (rows.isEmpty) {
                return const Center(
                  child: Text('No hay compras sugeridas para este horizonte.'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final current = (row['current_stock'] as num?)?.toDouble() ?? 0;
                  final recommended =
                      (row['recommended_order'] as num?)?.toDouble() ?? 0;
                  final daily =
                      (row['daily_consumption'] as num?)?.toDouble() ?? 0;
                  final days = (row['days_until_low'] as num?)?.toInt() ?? -1;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: MerkaThemeTokens.gold200,
                        child: const Icon(Icons.shopping_cart_checkout),
                      ),
                      title: Text(row['product_name']?.toString() ?? 'Producto'),
                      subtitle: Text(
                        'Stock actual: ${_qty(current)} · Consumo/día: ${_qty(daily)}\n'
                        '${days < 0 ? 'Sin consumo suficiente para estimar agotamiento' : 'Stock mínimo estimado en $days día(s)'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Comprar aprox.'),
                              Text(
                                _qty(recommended),
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text('Reposición: ${row['lead_time_days'] ?? 7} día(s)', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Configurar mínimo, máximo y tiempo de reposición',
                            onPressed: () => _editPolicy(row),
                            icon: const Icon(Icons.tune),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WarehousesTab extends StatefulWidget {
  const _WarehousesTab();

  @override
  State<_WarehousesTab> createState() => _WarehousesTabState();
}

class _WarehousesTabState extends State<_WarehousesTab> {
  Future<_WarehouseData>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_WarehouseData> _load() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final warehouses = await db.query(
      'bodegas',
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'activa DESC, codigo ASC',
    );
    final stock = await db.rawQuery(
      '''
      SELECT sb.*, p.nombre AS producto, b.nombre AS bodega
      FROM stock_bodega sb
      JOIN productos p ON p.id = sb.producto_id
      JOIN bodegas b ON b.id = sb.bodega_id
      WHERE sb.company_id = ?
      ORDER BY b.nombre, p.nombre
      ''',
      [companyId],
    );
    final products = await db.query(
      'productos',
      columns: ['id', 'nombre'],
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre',
    );
    return _WarehouseData(warehouses, stock, products);
  }

  Future<void> _newWarehouse() async {
    final code = TextEditingController();
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva bodega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              decoration: const InputDecoration(labelText: 'Código'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (ok != true || code.text.trim().isEmpty || name.text.trim().isEmpty) {
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.insert(
      'bodegas',
      {
        'company_id': companyId,
        'codigo': code.text.trim().toUpperCase(),
        'nombre': name.text.trim(),
        'activa': 1,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CREAR_BODEGA',
      entidad: 'bodegas',
      detalle: '${code.text.trim().toUpperCase()} · ${name.text.trim()}',
    );
    if (mounted) setState(_reload);
  }

  Future<void> _transfer(_WarehouseData data) async {
    if (data.warehouses.length < 2 || data.products.isEmpty) {
      _message('Necesitas al menos dos bodegas y un producto.');
      return;
    }
    int productId = (data.products.first['id'] as num).toInt();
    int fromId = (data.warehouses.first['id'] as num).toInt();
    int toId = (data.warehouses[1]['id'] as num).toInt();
    final quantity = TextEditingController();
    final reason = TextEditingController(text: 'Traslado entre bodegas');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Trasladar existencias'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: 'Producto'),
                  items: [
                    for (final p in data.products)
                      DropdownMenuItem(
                        value: (p['id'] as num).toInt(),
                        child: Text(p['nombre'].toString()),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => productId = v);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: fromId,
                        decoration: const InputDecoration(labelText: 'Origen'),
                        items: [
                          for (final w in data.warehouses)
                            DropdownMenuItem(
                              value: (w['id'] as num).toInt(),
                              child: Text(w['nombre'].toString()),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => fromId = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: toId,
                        decoration: const InputDecoration(labelText: 'Destino'),
                        items: [
                          for (final w in data.warehouses)
                            DropdownMenuItem(
                              value: (w['id'] as num).toInt(),
                              child: Text(w['nombre'].toString()),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => toId = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Trasladar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final qty = double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0;
    if (qty <= 0 || fromId == toId) {
      _message('Revisa cantidad, bodega origen y bodega destino.');
      return;
    }
    try {
      await WarehouseStockService().transfer(
        productId: productId,
        fromWarehouseId: fromId,
        toWarehouseId: toId,
        quantity: qty,
        reason: reason.text.trim().isEmpty ? 'Traslado entre bodegas' : reason.text.trim(),
      );
      if (mounted) setState(_reload);
    } catch (e) {
      _message(e.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WarehouseData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _newWarehouse,
                  icon: const Icon(Icons.add_business),
                  label: const Text('Nueva bodega'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _transfer(data),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Trasladar stock'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Bodegas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (data.warehouses.isEmpty)
              const Card(child: ListTile(title: Text('No hay bodegas configuradas.')))
            else
              ...data.warehouses.map(
                (w) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.warehouse_outlined),
                    title: Text(w['nombre'].toString()),
                    subtitle: Text('Código ${w['codigo']}'),
                    trailing: Text((w['activa'] as num?)?.toInt() == 1 ? 'Activa' : 'Inactiva'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Existencias por bodega', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (data.stock.isEmpty)
              const Card(child: ListTile(title: Text('Sin existencias por bodega todavía.')))
            else
              ...data.stock.map(
                (s) => Card(
                  child: ListTile(
                    title: Text(s['producto'].toString()),
                    subtitle: Text(s['bodega'].toString()),
                    trailing: Text(_qty((s['cantidad'] as num?)?.toDouble() ?? 0)),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PhysicalCountsTab extends StatefulWidget {
  const _PhysicalCountsTab();

  @override
  State<_PhysicalCountsTab> createState() => _PhysicalCountsTabState();
}

class _PhysicalCountsTabState extends State<_PhysicalCountsTab> {
  Future<List<Map<String, Object?>>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _InventoryAdvancedStore.counts();

  Future<void> _newCount() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final products = await db.query(
      'productos',
      columns: ['id', 'nombre', 'stock'],
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre',
    );
    if (products.isEmpty) {
      _message('No hay productos para contar.');
      return;
    }
    int productId = (products.first['id'] as num).toInt();
    final counted = TextEditingController();
    final note = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Registrar conteo físico'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: 'Producto'),
                  items: [
                    for (final p in products)
                      DropdownMenuItem(
                        value: (p['id'] as num).toInt(),
                        child: Text(p['nombre'].toString()),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => productId = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: counted,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad contada'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: 'Observación'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final qty = double.tryParse(counted.text.trim().replaceAll(',', '.'));
    if (qty == null || qty < 0) {
      _message('La cantidad contada no es válida.');
      return;
    }
    await _InventoryAdvancedStore.recordCount(
      productId: productId,
      counted: qty,
      note: note.text.trim(),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _apply(Map<String, Object?> row) async {
    if (!AppSession.puedeEjecutarAccion('inventory', AppAction.update)) {
      _message('No tienes permiso para aplicar ajustes de inventario.');
      return;
    }
    try {
      await _InventoryAdvancedStore.applyCount((row['id'] as num).toInt());
      if (mounted) setState(_reload);
    } catch (e) {
      _message(e.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conteo físico auditado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _newCount,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo conteo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
              final rows = snapshot.data ?? const <Map<String, Object?>>[];
              if (rows.isEmpty) {
                return const Center(child: Text('No hay conteos registrados.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final system = (row['system_qty'] as num?)?.toDouble() ?? 0;
                  final counted = (row['counted_qty'] as num?)?.toDouble() ?? 0;
                  final diff = counted - system;
                  final applied = row['status'] == 'applied';
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        diff.abs() < 0.000001 ? Icons.check_circle_outline : Icons.rule,
                        color: diff.abs() < 0.000001
                            ? MerkaThemeTokens.success
                            : MerkaThemeTokens.warning,
                      ),
                      title: Text(row['product_name']?.toString() ?? 'Producto'),
                      subtitle: Text(
                        'Sistema ${_qty(system)} · Contado ${_qty(counted)} · Diferencia ${_qty(diff)}\n'
                        '${row['created_at'] ?? ''}${(row['note']?.toString().isNotEmpty ?? false) ? ' · ${row['note']}' : ''}',
                      ),
                      trailing: applied
                          ? const Chip(label: Text('Aplicado'))
                          : TextButton(
                              onPressed: diff.abs() < 0.000001 ? null : () => _apply(row),
                              child: const Text('Aplicar ajuste'),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _VariantsSerialsTab extends StatefulWidget {
  const _VariantsSerialsTab();

  @override
  State<_VariantsSerialsTab> createState() => _VariantsSerialsTabState();
}

class _VariantsSerialsTabState extends State<_VariantsSerialsTab> {
  Future<_VariantData>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _InventoryAdvancedStore.variantsAndSerials();

  Future<void> _addVariant(_VariantData data) async {
    if (data.products.isEmpty) {
      _message('Primero crea un producto.');
      return;
    }
    int productId = (data.products.first['id'] as num).toInt();
    final sku = TextEditingController();
    final name = TextEditingController();
    final attributes = TextEditingController();
    final barcode = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Nueva variante'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  decoration: const InputDecoration(labelText: 'Producto base'),
                  items: [
                    for (final p in data.products)
                      DropdownMenuItem(
                        value: (p['id'] as num).toInt(),
                        child: Text(p['nombre'].toString()),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => productId = v);
                  },
                ),
                const SizedBox(height: 10),
                TextField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / referencia')), 
                const SizedBox(height: 10),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre de variante (ej. Azul / M)')),
                const SizedBox(height: 10),
                TextField(controller: attributes, decoration: const InputDecoration(labelText: 'Atributos (ej. color=azul; talla=M)')),
                const SizedBox(height: 10),
                TextField(controller: barcode, decoration: const InputDecoration(labelText: 'Código de barras (opcional)')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await _InventoryAdvancedStore.addVariant(
      productId: productId,
      sku: sku.text.trim(),
      name: name.text.trim(),
      attributes: attributes.text.trim(),
      barcode: barcode.text.trim(),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _addSerial(_VariantData data) async {
    if (data.products.isEmpty) {
      _message('Primero crea un producto.');
      return;
    }
    int productId = (data.products.first['id'] as num).toInt();
    int? variantId;
    final serial = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final variants = data.variants
              .where((v) => (v['product_id'] as num).toInt() == productId)
              .toList();
          if (variantId != null && !variants.any((v) => v['id'] == variantId)) {
            variantId = null;
          }
          return AlertDialog(
            title: const Text('Registrar número de serie'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Producto'),
                    items: [
                      for (final p in data.products)
                        DropdownMenuItem(
                          value: (p['id'] as num).toInt(),
                          child: Text(p['nombre'].toString()),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                        productId = v;
                        variantId = null;
                      });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: variantId,
                    decoration: const InputDecoration(labelText: 'Variante (opcional)'),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('Producto base')),
                      for (final v in variants)
                        DropdownMenuItem<int?>(
                          value: (v['id'] as num).toInt(),
                          child: Text(v['name'].toString()),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => variantId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: serial,
                    decoration: const InputDecoration(labelText: 'Número de serie'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Registrar')),
            ],
          );
        },
      ),
    );
    if (ok != true || serial.text.trim().isEmpty) return;
    try {
      await _InventoryAdvancedStore.addSerial(
        productId: productId,
        variantId: variantId,
        serial: serial.text.trim(),
      );
      if (mounted) setState(_reload);
    } catch (e) {
      _message(e.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VariantData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _addVariant(data),
                  icon: const Icon(Icons.tune),
                  label: const Text('Nueva variante'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _addSerial(data),
                  icon: const Icon(Icons.numbers),
                  label: const Text('Registrar serie'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Variantes', style: Theme.of(context).textTheme.titleMedium),
            if (data.variants.isEmpty)
              const Card(child: ListTile(title: Text('Sin variantes registradas.')))
            else
              ...data.variants.map(
                (v) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.style_outlined),
                    title: Text('${v['product_name']} · ${v['name']}'),
                    subtitle: Text(
                      [
                        if (v['sku']?.toString().isNotEmpty ?? false) 'SKU ${v['sku']}',
                        if (v['attributes_json']?.toString().isNotEmpty ?? false) v['attributes_json'].toString(),
                        if (v['barcode']?.toString().isNotEmpty ?? false) 'Código ${v['barcode']}',
                      ].join(' · '),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Números de serie', style: Theme.of(context).textTheme.titleMedium),
            if (data.serials.isEmpty)
              const Card(child: ListTile(title: Text('Sin números de serie registrados.')))
            else
              ...data.serials.map(
                (s) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.qr_code_2),
                    title: Text(s['serial_number'].toString()),
                    subtitle: Text('${s['product_name']}${s['variant_name'] == null ? '' : ' · ${s['variant_name']}'}'),
                    trailing: Chip(label: Text(s['status'].toString())),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WarehouseData {
  const _WarehouseData(this.warehouses, this.stock, this.products);

  final List<Map<String, Object?>> warehouses;
  final List<Map<String, Object?>> stock;
  final List<Map<String, Object?>> products;
}

class _VariantData {
  const _VariantData(this.products, this.variants, this.serials);

  final List<Map<String, Object?>> products;
  final List<Map<String, Object?>> variants;
  final List<Map<String, Object?>> serials;
}

class _InventoryAdvancedStore {
  static Future<Database> _db() => DatabaseHelper.instance.database;

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_physical_counts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        system_qty REAL NOT NULL,
        counted_qty REAL NOT NULL,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        created_by TEXT,
        created_at TEXT NOT NULL,
        applied_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_variants(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        sku TEXT,
        name TEXT NOT NULL,
        attributes_json TEXT,
        barcode TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        UNIQUE(company_id, product_id, sku)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_serials(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        variant_id INTEGER,
        serial_number TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'available',
        created_at TEXT NOT NULL,
        sold_at TEXT,
        UNIQUE(company_id, serial_number)
      )
    ''');
  }

  static Future<List<Map<String, Object?>>> counts() async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return db.rawQuery(
      '''
      SELECT c.*, p.nombre AS product_name
      FROM inventory_physical_counts c
      JOIN productos p ON p.id = c.product_id
      WHERE c.company_id = ?
      ORDER BY c.created_at DESC
      LIMIT 250
      ''',
      [companyId],
    );
  }

  static Future<void> recordCount({
    required int productId,
    required double counted,
    required String note,
  }) async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final rows = await db.query(
      'productos',
      columns: ['stock'],
      where: 'id = ? AND company_id = ?',
      whereArgs: [productId, companyId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('El producto ya no existe.');
    final systemQty = (rows.single['stock'] as num?)?.toDouble() ?? 0;
    final id = await db.insert('inventory_physical_counts', {
      'company_id': companyId,
      'product_id': productId,
      'system_qty': systemQty,
      'counted_qty': counted,
      'note': note,
      'status': 'pending',
      'created_by': AppSession.nombre,
      'created_at': DateTime.now().toIso8601String(),
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CONTEO_FISICO_INVENTARIO',
      entidad: 'inventory_physical_counts',
      entidadId: id,
      detalle: 'Producto $productId · sistema $systemQty · contado $counted',
    );
  }

  static Future<void> applyCount(int countId) async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_physical_counts',
        where: 'id = ? AND company_id = ? AND status = ?',
        whereArgs: [countId, companyId, 'pending'],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('El conteo no existe o ya fue aplicado.');
      final count = rows.single;
      final productId = (count['product_id'] as num).toInt();
      final products = await txn.query(
        'productos',
        columns: ['stock', 'costo'],
        where: 'id = ? AND company_id = ?',
        whereArgs: [productId, companyId],
        limit: 1,
      );
      if (products.isEmpty) throw StateError('El producto ya no existe.');

      final lotRows = await txn.rawQuery(
        "SELECT COUNT(*) AS total FROM lotes WHERE company_id = ? AND producto_id = ? AND cantidad > 0 AND (status IS NULL OR status != 'depleted')",
        [companyId, productId],
      );
      final activeLots = (lotRows.single['total'] as num?)?.toInt() ?? 0;
      if (activeLots > 0) {
        throw StateError(
          'Este producto está controlado por lotes. Ajusta primero sus lotes para no romper la trazabilidad FIFO.',
        );
      }

      final before = (products.single['stock'] as num?)?.toDouble() ?? 0;
      final counted = (count['counted_qty'] as num).toDouble();
      final delta = counted - before;
      if (delta.abs() > 0.000001) {
        await txn.update(
          'productos',
          {'stock': counted},
          where: 'id = ? AND company_id = ?',
          whereArgs: [productId, companyId],
        );
        await InventoryMovementService.record(
          db: txn,
          companyId: companyId,
          productId: productId,
          type: delta >= 0 ? 'entrada_ajuste_conteo' : 'salida_ajuste_conteo',
          quantity: delta.abs(),
          stockBefore: before,
          stockAfter: counted,
          reason: 'Conteo físico #$countId',
          date: DateTime.now().toIso8601String(),
          createdBy: AppSession.nombre,
          syncLots: false,
        );
      }
      await txn.update(
        'inventory_physical_counts',
        {'status': 'applied', 'applied_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND company_id = ?',
        whereArgs: [countId, companyId],
      );
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'APLICAR_CONTEO_FISICO',
      entidad: 'inventory_physical_counts',
      entidadId: countId,
      detalle: 'Ajuste aplicado por ${AppSession.nombre}',
    );
  }

  static Future<_VariantData> variantsAndSerials() async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final products = await db.query(
      'productos',
      columns: ['id', 'nombre'],
      where: 'company_id = ?',
      whereArgs: [companyId],
      orderBy: 'nombre',
    );
    final variants = await db.rawQuery(
      '''
      SELECT v.*, p.nombre AS product_name
      FROM product_variants v
      JOIN productos p ON p.id = v.product_id
      WHERE v.company_id = ? AND v.active = 1
      ORDER BY p.nombre, v.name
      ''',
      [companyId],
    );
    final serials = await db.rawQuery(
      '''
      SELECT s.*, p.nombre AS product_name, v.name AS variant_name
      FROM product_serials s
      JOIN productos p ON p.id = s.product_id
      LEFT JOIN product_variants v ON v.id = s.variant_id
      WHERE s.company_id = ?
      ORDER BY s.created_at DESC
      LIMIT 500
      ''',
      [companyId],
    );
    return _VariantData(products, variants, serials);
  }

  static Future<void> addVariant({
    required int productId,
    required String sku,
    required String name,
    required String attributes,
    required String barcode,
  }) async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final attrs = <String, String>{};
    for (final pair in attributes.split(';')) {
      final bits = pair.split('=');
      if (bits.length == 2 && bits[0].trim().isNotEmpty) {
        attrs[bits[0].trim()] = bits[1].trim();
      }
    }
    final id = await db.insert('product_variants', {
      'company_id': companyId,
      'product_id': productId,
      'sku': sku.isEmpty ? null : sku,
      'name': name,
      'attributes_json': attrs.isEmpty ? attributes : jsonEncode(attrs),
      'barcode': barcode.isEmpty ? null : barcode,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CREAR_VARIANTE_PRODUCTO',
      entidad: 'product_variants',
      entidadId: id,
      detalle: 'Producto $productId · $name',
    );
  }

  static Future<void> addSerial({
    required int productId,
    required int? variantId,
    required String serial,
  }) async {
    final db = await _db();
    await _ensureSchema(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final id = await db.insert('product_serials', {
      'company_id': companyId,
      'product_id': productId,
      'variant_id': variantId,
      'serial_number': serial,
      'status': 'available',
      'created_at': DateTime.now().toIso8601String(),
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'REGISTRAR_SERIE_PRODUCTO',
      entidad: 'product_serials',
      entidadId: id,
      detalle: 'Producto $productId · serie $serial',
    );
  }
}

String _qty(double value) {
  if (value.isNaN || value.isInfinite) return '0';
  return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
}
