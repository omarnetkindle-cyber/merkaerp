import 'package:flutter/material.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../application/crm_opportunity_item_service.dart';
import '../domain/crm_opportunity.dart';
import '../domain/crm_opportunity_item.dart';

class CrmOpportunityPage extends StatefulWidget {
  const CrmOpportunityPage({super.key, required this.opportunity});

  final CrmOpportunity opportunity;

  @override
  State<CrmOpportunityPage> createState() => _CrmOpportunityPageState();
}

class _CrmOpportunityPageState extends State<CrmOpportunityPage> {
  late final CrmOpportunityItemService _items;
  late Future<List<CrmOpportunityItem>> _lines;
  late Future<Currency> _currency;

  @override
  void initState() {
    super.initState();
    _items = CrmOpportunityItemService();
    _lines = _items.listForOpportunity(widget.opportunity.id);
    _currency = _resolveCurrency();
  }

  Future<Currency> _resolveCurrency() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return MoneyCurrencyResolver.resolve(db, companyId: companyId);
  }

  void _reload() => setState(() {
    _lines = _items.listForOpportunity(widget.opportunity.id);
  });

  Future<void> _editLine({CrmOpportunityItem? line}) async {
    final currency = await _currency;
    if (!mounted) return;
    final productController = TextEditingController(
      text: line?.productId.toString() ?? '',
    );
    final quantityController = TextEditingController(
      text: line?.quantity.toString() ?? '1',
    );
    final priceController = TextEditingController(
      text: line == null ? '0' : line.unitPrice.toMajorUnitsString(),
    );
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(line == null ? 'Agregar producto' : 'Editar producto'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: productController,
                decoration: const InputDecoration(labelText: 'ID de producto'),
                keyboardType: TextInputType.number,
                validator: (value) => int.tryParse(value ?? '') == null
                    ? 'Ingrese un producto valido'
                    : null,
              ),
              TextFormField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Cantidad'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) => double.tryParse(value ?? '') == null
                    ? 'Ingrese una cantidad valida'
                    : null,
              ),
              TextFormField(
                controller: priceController,
                decoration: InputDecoration(
                  labelText: 'Precio unitario (${currency.code})',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        double.tryParse(value) == null
                    ? 'Ingrese un precio valido'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await _items.save(
        CrmOpportunityItem(
          id: line?.id,
          companyId: widget.opportunity.companyId,
          opportunityId: widget.opportunity.id,
          productId: int.parse(productController.text),
          quantity: double.parse(quantityController.text),
          unitPrice: MoneyValue.fromMajorUnits(
            priceController.text,
            currency: currency,
          ),
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la linea: $error')),
      );
    } finally {
      productController.dispose();
      quantityController.dispose();
      priceController.dispose();
    }
  }

  Future<void> _deleteLine(CrmOpportunityItem line) async {
    if (line.id == null) return;
    await _items.delete(line.id!);
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.opportunity.name)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _editLine,
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('Agregar producto'),
    ),
    body: FutureBuilder<List<CrmOpportunityItem>>(
      future: _lines,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('No se pudieron cargar las lineas: ${snapshot.error}'),
          );
        }
        final lines = snapshot.data ?? const <CrmOpportunityItem>[];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.opportunity.salesStage.value} - ${widget.opportunity.effectiveProbability}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Monto oportunidad: ${widget.opportunity.amount.format()}'),
            const SizedBox(height: 16),
            Text(
              'Productos de la oportunidad',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (lines.isEmpty)
              const ListTile(title: Text('Sin productos asociados'))
            else
              ...lines.map(
                (line) => ListTile(
                  title: Text(
                    'Producto ${line.productId} · ${line.quantity} ${line.uom}',
                  ),
                  subtitle: Text(
                    'Unitario: ${line.unitPrice.format()} · Total: ${line.amount.format()}',
                  ),
                  trailing: Wrap(
                    children: [
                      IconButton(
                        tooltip: 'Editar linea',
                        onPressed: () => _editLine(line: line),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Eliminar linea',
                        onPressed: () => _deleteLine(line),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
