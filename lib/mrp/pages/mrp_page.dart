import 'package:flutter/material.dart';

import '../../core/currency/money_value.dart';
import '../../core/commands/command_registry.dart';
import '../application/mrp_services.dart';
import '../domain/mrp_bom.dart';
import '../domain/mrp_bom_item.dart';
import '../domain/mrp_work_order.dart';
import '../domain/mrp_workstation.dart';
import '../data/mrp_repositories.dart';
import '../../ui/widgets/expandable_record_card.dart';
import '../../ui/widgets/semantic_zoom_record_list.dart';

class MrpPage extends StatefulWidget {
  const MrpPage({super.key});

  @override
  State<MrpPage> createState() => _MrpPageState();
}

class _MrpPageState extends State<MrpPage> with SingleTickerProviderStateMixin {
  final _bomService = MrpBomService();
  final _orderService = MrpWorkOrderService();
  final _workstationService = MrpWorkstationService();
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late Future<List<MrpBom>> _boms;
  late Future<List<MrpWorkOrder>> _orders;
  late Future<List<_MrpOrderViewData>> _orderViews;
  late Future<List<MrpWorkstation>> _workstations;
  late final String _commandOwner;

  @override
  void initState() {
    super.initState();
    _commandOwner = 'mrp.orders:${identityHashCode(this)}';
    _reload();
  }

  void _reload() {
    _boms = _bomService.list();
    _orders = _orderService.list();
    _orderViews = _orders.then(_loadOrderViews);
    _workstations = _workstationService.list();
  }

  @override
  void dispose() {
    CommandRegistry.instance.clearContext(_commandOwner);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Produccion MRP'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Editor BOM'),
          Tab(text: 'Ordenes de produccion'),
          Tab(text: 'Workstations'),
        ],
      ),
    ),
    body: TabBarView(
      controller: _tabs,
      children: [_buildBoms(), _buildOrders(), _buildWorkstations()],
    ),
  );

  Widget _buildBoms() => FutureBuilder<List<MrpBom>>(
    future: _boms,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text('No se pudieron cargar las BOM: ${snapshot.error}'),
        );
      }
      final boms = snapshot.data ?? const <MrpBom>[];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                'Listas de materiales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showBomEditor,
                icon: const Icon(Icons.add),
                label: const Text('Nueva BOM'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (boms.isEmpty) const Text('No hay BOM registradas.'),
          ...boms.map(
            (bom) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_tree),
                    title: Text('Producto #${bom.itemId}'),
                    subtitle: Text(
                      'Cantidad ${bom.quantity} ${bom.uom} - '
                      'Costo total ${bom.totalCost.toMajorUnitsString()}',
                    ),
                    trailing: Icon(
                      bom.isActive ? Icons.check_circle : Icons.pause_circle,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: bom.id == null
                          ? null
                          : () => _showBomStructure(bom),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Editar estructura'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _buildWorkstations() => FutureBuilder<List<MrpWorkstation>>(
    future: _workstations,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text('No se pudieron cargar workstations: ${snapshot.error}'),
        );
      }
      final workstations = snapshot.data ?? const <MrpWorkstation>[];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text(
                'Centros de trabajo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showWorkstationEditor,
                icon: const Icon(Icons.add),
                label: const Text('Nueva workstation'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (workstations.isEmpty)
            const Text('No hay workstations registradas.'),
          ...workstations.map(
            (workstation) => Card(
              child: ListTile(
                leading: const Icon(Icons.precision_manufacturing),
                title: Text(workstation.name),
                subtitle: Text(
                  'Costo/hora: ${workstation.hourRate.format()} - '
                  'Capacidad temporal: '
                  '${workstation.availableHoursPerDay?.toStringAsFixed(2) ?? 'No configurada'} '
                  'h/dia',
                ),
                trailing: Text(workstation.status),
              ),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _showWorkstationEditor() async {
    final name = TextEditingController();
    final rate = TextEditingController(text: '0');
    final hours = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nueva workstation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: rate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Costo por hora'),
            ),
            TextField(
              controller: hours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Horas disponibles por dia',
                hintText: 'Ej. 8',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final availableHours = double.tryParse(hours.text);
              if (name.text.trim().isEmpty ||
                  availableHours == null ||
                  availableHours <= 0) {
                return;
              }
              final currency = await MrpRepositoryContext().currency;
              await _workstationService.create(
                MrpWorkstation(
                  companyId: await MrpRepositoryContext().companyId,
                  name: name.text,
                  hourRate: MoneyValue.fromMajorUnits(
                    rate.text,
                    currency: currency,
                  ),
                  availableHoursPerDay: availableHours,
                ),
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    name.dispose();
    rate.dispose();
    hours.dispose();
    if (created == true && mounted) setState(_reload);
  }

  Future<List<_MrpOrderViewData>> _loadOrderViews(
    List<MrpWorkOrder> orders,
  ) async {
    return Future.wait(
      orders.map(
        (order) async => _MrpOrderViewData(
          order: order,
          stockOk: await _orderService.hasSufficientStock(order.id!),
        ),
      ),
    );
  }

  String _orderDisplayStatus(_MrpOrderViewData view) {
    final order = view.order;
    final canBeBlocked =
        order.status == MrpWorkOrderStatus.borrador ||
        order.status == MrpWorkOrderStatus.noIniciada;
    if (canBeBlocked && !view.stockOk) {
      return 'Bloqueada: stock insuficiente';
    }
    return _statusLabel(order.status);
  }

  Widget _buildOrders() => FutureBuilder<List<_MrpOrderViewData>>(
    future: _orderViews,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text('No se pudieron cargar ordenes: ${snapshot.error}'),
        );
      }
      final views = snapshot.data ?? const <_MrpOrderViewData>[];
      return Stack(
        children: [
          SemanticZoomRecordList<_MrpOrderViewData>(
            records: views,
            title: 'Zoom de órdenes de producción',
            statusOf: _orderDisplayStatus,
            itemBuilder: (context, view, {required initiallyExpanded}) =>
                _buildOrderTile(view, initiallyExpanded: initiallyExpanded),
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton.extended(
              heroTag: 'mrp_new_order',
              icon: const Icon(Icons.add),
              label: const Text('Nueva orden'),
              onPressed: _showNewOrderDialog,
            ),
          ),
        ],
      );
    },
  );

  Widget _buildOrderTile(
    _MrpOrderViewData view, {
    required bool initiallyExpanded,
  }) {
    final order = view.order;
    final stockOk = view.stockOk;
    final canBeBlocked =
        order.status == MrpWorkOrderStatus.borrador ||
        order.status == MrpWorkOrderStatus.noIniciada;
    final blocked = canBeBlocked && !stockOk;
    final actions = <RecordCardAction>[
      if (order.status == MrpWorkOrderStatus.noIniciada)
        RecordCardAction(
          id: 'start',
          label: 'Iniciar producción',
          icon: Icons.play_arrow,
          visible: !blocked,
          onPressed: (_) async {
            _activateOrderContext(context, order);
            await _orderService.transition(
              order.id!,
              MrpWorkOrderStatus.enProceso,
            );
            if (mounted) setState(_reload);
          },
        ),
      if (order.status == MrpWorkOrderStatus.enProceso)
        RecordCardAction(
          id: 'complete',
          label: 'Completar orden',
          icon: Icons.task_alt,
          onPressed: (_) async {
            _activateOrderContext(context, order);
            await _completeOrder(order);
            if (mounted) setState(_reload);
          },
        ),
      RecordCardAction(
        id: 'bom',
        label: 'Ver BOM',
        icon: Icons.account_tree,
        onPressed: (_) async {
          _activateOrderContext(context, order);
          final boms = await _bomService.list();
          MrpBom? matchingBom;
          for (final bom in boms) {
            if (bom.id == order.bomId) {
              matchingBom = bom;
              break;
            }
          }
          if (matchingBom != null && mounted) {
            _tabs.index = 0;
            await _showBomStructure(matchingBom);
          }
        },
      ),
    ];
    return ExpandableRecordCard(
      criticalFields: [
        RecordCardField(
          label: 'Orden',
          value: '#${order.id}',
          icon: blocked ? Icons.lock : Icons.precision_manufacturing,
          emphasized: true,
        ),
        RecordCardField(
          label: 'Producto',
          value: '#${order.productionItemId}',
          icon: Icons.inventory_2,
          emphasized: true,
        ),
        RecordCardField(
          label: 'Cantidad',
          value: order.qtyPlanned.toString(),
          icon: Icons.numbers,
        ),
        RecordCardField(
          label: 'Estado',
          value: blocked
              ? 'Bloqueada: stock insuficiente'
              : _statusLabel(order.status),
          icon: blocked ? Icons.warning : Icons.flag,
          emphasized: true,
        ),
      ],
      secondaryFields: [
        RecordCardField(label: 'BOM', value: '#${order.bomId}'),
        RecordCardField(
          label: 'Costo total',
          value: order.totalCost.toMajorUnitsString(),
        ),
        RecordCardField(
          label: 'Materia prima',
          value: order.rawMaterialCost.toMajorUnitsString(),
        ),
        RecordCardField(
          label: 'Operación',
          value: order.plannedOperatingCost.toMajorUnitsString(),
        ),
        RecordCardField(label: 'Bodega WIP', value: '${order.wipWarehouseId}'),
        RecordCardField(
          label: 'Bodega producto terminado',
          value: '${order.fgWarehouseId}',
        ),
        RecordCardField(
          label: 'Fecha límite',
          value: order.plannedEndDate?.toIso8601String() ?? 'Sin fecha',
        ),
      ],
      actions: actions,
      initiallyExpanded: initiallyExpanded,
    );
  }

  void _activateOrderContext(BuildContext context, MrpWorkOrder order) {
    final orderId = order.id;
    if (orderId == null) return;
    final actions = <String, CommandHandler>{
      'start': (commandContext, _) async {
        await _orderService.transition(orderId, MrpWorkOrderStatus.enProceso);
        if (mounted) setState(_reload);
      },
      'complete': (commandContext, _) async {
        await _orderService.transition(orderId, MrpWorkOrderStatus.completada);
        if (mounted) setState(_reload);
      },
      'bom': (commandContext, _) async {
        final boms = await _bomService.list();
        MrpBom? matchingBom;
        for (final bom in boms) {
          if (bom.id == order.bomId) {
            matchingBom = bom;
            break;
          }
        }
        if (matchingBom != null && mounted) {
          _tabs.index = 0;
          await _showBomStructure(matchingBom);
        }
      },
    };
    CommandRegistry.instance.setContext(
      CommandContext(
        moduleId: 'mrp',
        recordType: 'mrp_work_order',
        recordId: '$orderId',
        label: 'Orden #$orderId',
        ownerId: _commandOwner,
        actions: actions,
      ),
    );
  }

  Future<void> _completeOrder(MrpWorkOrder order) async {
    final quantity = TextEditingController(text: order.qtyPlanned.toString());
    final produced = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Completar orden'),
        content: TextField(
          controller: quantity,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Cantidad producida',
            helperText: 'Planeada: ${order.qtyPlanned}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(quantity.text);
              if (value == null || value <= 0 || value > order.qtyPlanned) {
                return;
              }
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    quantity.dispose();
    if (produced == null) return;
    await _orderService.transition(
      order.id!,
      MrpWorkOrderStatus.completada,
      producedQty: produced,
    );
  }

  Future<void> _showNewOrderDialog() async {
    final context2 = MrpRepositoryContext();
    final boms = await _bomService.list();
    if (!mounted) return;
    if (boms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Crea al menos una BOM antes de lanzar una orden de producción.',
          ),
        ),
      );
      return;
    }
    final companyId = await context2.companyId;
    if (!mounted) return;

    final qtyCtrl = TextEditingController(text: '1');
    var selectedBomId = boms.first.id!;
    DateTime? plannedEnd;

    final created = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Nueva orden de producción'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // BOM
                  DropdownButtonFormField<int>(
                    value: selectedBomId,
                    decoration: const InputDecoration(
                      labelText: 'Lista de materiales (BOM) *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    items: boms
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              'BOM #${b.id} — Producto #${b.itemId}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => selectedBomId = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  // Cantidad a producir
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad a producir *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Fecha límite
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(
                          const Duration(days: 7),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (d != null) setDlg(() => plannedEnd = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha límite (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        plannedEnd == null
                            ? 'Sin fecha'
                            : '${plannedEnd!.day.toString().padLeft(2, '0')}/'
                                  '${plannedEnd!.month.toString().padLeft(2, '0')}/'
                                  '${plannedEnd!.year}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.'));
                if (qty == null || qty <= 0) return;
                try {
                  final bom = boms.firstWhere((b) => b.id == selectedBomId);
                  await _orderService.create(
                    draft: MrpWorkOrder(
                      companyId: companyId,
                      bomId: selectedBomId,
                      productionItemId: bom.itemId,
                      qtyPlanned: qty,
                      status: MrpWorkOrderStatus.noIniciada,
                      wipWarehouseId: 1,
                      fgWarehouseId: 1,
                      totalCost: bom.totalCost.multiplyDecimal(qty.toString()),
                      rawMaterialCost: bom.rawMaterialCost.multiplyDecimal(
                        qty.toString(),
                      ),
                      plannedOperatingCost: bom.operatingCost.multiplyDecimal(
                        qty.toString(),
                      ),
                      actualOperatingCost: bom.totalCost.multiplyDecimal('0'),
                      plannedEndDate: plannedEnd,
                    ),
                  );
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx, true);
                } catch (e) {
                  if (dlgCtx.mounted) {
                    ScaffoldMessenger.of(
                      dlgCtx,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
              child: const Text('Crear orden'),
            ),
          ],
        ),
      ),
    );
    qtyCtrl.dispose();
    if (created == true && mounted) setState(_reload);
  }

  Future<void> _showBomEditor() async {
    final product = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva BOM'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: product,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ID producto terminado',
              ),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final productId = int.tryParse(product.text);
              final qty = double.tryParse(quantity.text);
              if (productId == null || qty == null || qty <= 0) return;
              await _bomService.createDraft(itemId: productId, quantity: qty);
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (created == true && mounted) setState(_reload);
  }

  Future<void> _showBomStructure(MrpBom bom) async {
    if (bom.id == null) return;
    var current = bom;
    var itemsFuture = _bomService.items(bom.id!);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Estructura BOM #${bom.id}'),
          content: SizedBox(
            width: 520,
            child: FutureBuilder<List<MrpBomItem>>(
              future: itemsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = snapshot.data!;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Costo total: ${current.totalCost.toMajorUnitsString()}',
                    ),
                    Text(
                      'Materiales: ${current.rawMaterialCost.toMajorUnitsString()} '
                      '- Operacion: ${current.operatingCost.toMajorUnitsString()}',
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Text('La BOM no tiene componentes.'),
                    ...items.map(
                      (item) => ListTile(
                        dense: true,
                        leading: Icon(
                          item.isSubAssemblyItem
                              ? Icons.account_tree
                              : Icons.inventory_2,
                        ),
                        title: Text('Producto #${item.itemId}'),
                        subtitle: Text(
                          'Cantidad ${item.qty} - '
                          '${item.isSubAssemblyItem ? 'Sub-ensamble' : 'Materia prima'}',
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final added = await _showAddBomItem(bom);
                          if (added != true) return;
                          current = await _bomService.recalculate(bom.id!);
                          itemsFuture = _bomService.items(bom.id!);
                          setDialogState(() {});
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar componente'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<bool?> _showAddBomItem(MrpBom bom) => showDialog<bool>(
    context: context,
    builder: (context) {
      final item = TextEditingController();
      final quantity = TextEditingController(text: '1');
      final rate = TextEditingController(text: '0');
      var isSubAssembly = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Agregar componente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: item,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ID producto'),
              ),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Costo unitario'),
              ),
              CheckboxListTile(
                value: isSubAssembly,
                onChanged: (value) =>
                    setState(() => isSubAssembly = value ?? false),
                title: const Text('Es sub-ensamble'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final itemId = int.tryParse(item.text);
                final qty = double.tryParse(quantity.text);
                final rateValue = double.tryParse(rate.text);
                if (itemId == null ||
                    qty == null ||
                    qty <= 0 ||
                    rateValue == null ||
                    rateValue < 0) {
                  return;
                }
                final rateMoney = MoneyValue.fromMajorUnits(
                  rate.text,
                  currency: bom.totalCost.currency,
                );
                await _bomService.addItem(
                  MrpBomItem(
                    companyId: bom.companyId,
                    bomId: bom.id!,
                    itemId: itemId,
                    qty: qty,
                    rate: rateMoney,
                    amount: rateMoney.multiplyDecimal(qty.toString()),
                    isSubAssemblyItem: isSubAssembly,
                  ),
                );
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      );
    },
  );

  String _statusLabel(MrpWorkOrderStatus status) => switch (status) {
    MrpWorkOrderStatus.borrador => 'Borrador',
    MrpWorkOrderStatus.noIniciada => 'No iniciada',
    MrpWorkOrderStatus.enProceso => 'En proceso',
    MrpWorkOrderStatus.completada => 'Completada',
    MrpWorkOrderStatus.cancelada => 'Cancelada',
  };
}

class _MrpOrderViewData {
  const _MrpOrderViewData({required this.order, required this.stockOk});

  final MrpWorkOrder order;
  final bool stockOk;
}
