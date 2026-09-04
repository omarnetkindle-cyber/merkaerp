// ============================================================
// inventario_page.dart
// Módulo de inventario: lista, agrega, edita y elimina
// productos con sus unidades, stock, costos y precios.
// Incluye soporte de Lotes y Vencimientos.
// ============================================================

import 'package:flutter/material.dart';
import 'catalog/application/catalog_service.dart';
import 'catalog/domain/master_catalog.dart';
import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'inventory/data/product_repository.dart';
import 'inventory/domain/inventory_summary.dart';
import 'inventory/domain/product.dart';
import 'inventory/pages/inventory_control_center_page.dart';
import 'numeric_input.dart';

class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

class _InventarioPageState extends State<InventarioPage> {
  final ProductRepository _productosRepo = SqliteProductRepository();
  List<Product> _productos = [];
  List<TaxOption> _impuestosDisponibles = MasterCatalog.taxes;
  Currency? _currency;
  String _busqueda = '';
  bool _soloStockBajo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarProductos);
      }
    });
  }

  // ── Carga de datos ───────────────────────────────────────

  /// Carga todos los productos desde la BD y actualiza el estado.
  Future<void> _cargarProductos() async {
    final data = await _productosRepo.findAll();
    final taxes = await CatalogService.instance.taxOptionsForActiveCompany();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    if (!mounted) return;
    setState(() {
      _productos = data;
      _impuestosDisponibles = taxes;
      _currency = currency;
    });
  }

  // ── Lógica CRUD ──────────────────────────────────────────

  /// Guarda un producto nuevo o actualiza uno existente.
  /// Si [id] es null se crea; si tiene valor se edita.
  Future<void> _guardarProducto({
    required int? id,
    required String nombre,
    required String unidad,
    required double stock,
    required double costo,
    required double precio,
    required double impuestoPct,
    required String codigoBarras,
    required String convNombre,
    required double convCantidad,
    String codigoLote = '',
    String fechaVencimiento = '',
    bool precioIncluyeIva = false,
  }) async {
    final currency = _currency;
    if (currency == null) {
      throw StateError('La moneda de la empresa aun no esta resuelta.');
    }
    final costoMoney = MoneyValue.fromMajorUnits(
      costo.toString(),
      currency: currency,
    );
    final generatedId = await _productosRepo.save(
      Product(
        id: id,
        name: nombre,
        unit: unidad,
        stock: stock,
        cost: costoMoney,
        price: MoneyValue.fromMajorUnits(precio.toString(), currency: currency),
        taxRate: impuestoPct,
        barcode: codigoBarras,
        conversionName: convNombre,
        conversionQuantity: convCantidad,
        precioIncluyeIva: precioIncluyeIva,
      ),
    );

    if (id == null && stock > 0 && codigoLote.isNotEmpty) {
      await DatabaseHelper.instance.registrarLote(
        productoId: generatedId,
        codigoLote: codigoLote,
        fechaVencimiento: fechaVencimiento.isNotEmpty
            ? fechaVencimiento
            : DateTime.now()
                  .add(const Duration(days: 365))
                  .toIso8601String()
                  .split('T')
                  .first,
        cantidad: stock,
        costo: costoMoney,
      );
    }

    await _cargarProductos();
  }

  Future<void> _verLotesProducto(int productoId, String productoNombre) async {
    final lotes = await DatabaseHelper.instance.obtenerLotesPorProducto(
      productoId,
    );
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lotes de "$productoNombre"'),
        content: lotes.isEmpty
            ? const Text('Este producto no tiene lotes registrados.')
            : SizedBox(
                width: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: lotes.length,
                  itemBuilder: (context, idx) {
                    final lote = lotes[idx];
                    final codigo = lote['codigo_lote'] ?? 'N/A';
                    final vencimiento = lote['fecha_vencimiento'] ?? 'N/A';
                    final cant = (lote['cantidad'] as num?)?.toDouble() ?? 0.0;
                    return ListTile(
                      title: Text('Lote: $codigo'),
                      subtitle: Text('Vence: $vencimiento'),
                      trailing: Text(
                        '${_fmtNum(cant)} ud.',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Muestra un diálogo de confirmación y elimina el producto si acepta.
  Future<void> _eliminarProducto(int id, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Deseas eliminar "$nombre" del inventario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await _productosRepo.delete(id);
        await _cargarProductos();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar producto: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    }
  }

  // ── Formulario (dialog) ──────────────────────────────────

  /// Abre un AlertDialog con el formulario de producto.
  /// Si [producto] no es null, lo precarga para edición.
  void _abrirFormulario({Product? producto}) {
    // Controladores de texto; se precargan si es edición
    final nombreCtrl = TextEditingController(text: producto?.name ?? '');
    final unidadCtrl = TextEditingController(text: producto?.unit ?? '');
    final stockCtrl = TextEditingController(
      text: producto != null ? _fmtNum(producto.stock) : '',
    );
    final costoCtrl = TextEditingController(
      text: producto != null ? producto.cost.toMajorUnitsString() : '',
    );
    final precioCtrl = TextEditingController(
      text: producto != null ? producto.price.toMajorUnitsString() : '',
    );
    final impuestoCtrl = TextEditingController(
      text: producto != null
          ? _fmtNum(producto.taxRate)
          : _fmtNum(_impuestosDisponibles.first.rate),
    );
    final codigoBarrasCtrl = TextEditingController(
      text: producto?.barcode ?? '',
    );
    final convNombreCtrl = TextEditingController(
      text: producto?.conversionName ?? '',
    );
    final convCantidadCtrl = TextEditingController(
      text: producto != null && producto.conversionQuantity > 0
          ? _fmtNum(producto.conversionQuantity)
          : '',
    );
    final codigoLoteCtrl = TextEditingController();
    final fechaVencimientoCtrl = TextEditingController();

    // Clave del formulario para validaciones
    final formKey = GlobalKey<FormState>();

    bool precioIncluyeIva = producto?.precioIncluyeIva ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Text(producto == null ? 'Nuevo producto' : 'Editar producto'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _campo(nombreCtrl, 'Nombre del producto', validar: true),
                  _campo(unidadCtrl, 'Unidad (kg, lb, und…)', validar: true),
                  _campo(
                    stockCtrl,
                    'Stock inicial',
                    numerico: true,
                    validar: true,
                  ),
                  _campo(
                    costoCtrl,
                    'Costo unitario',
                    numerico: true,
                    validar: true,
                  ),
                  _campo(
                    precioCtrl,
                    'Precio de venta',
                    numerico: true,
                    validar: true,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Este precio incluye IVA', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('El IVA se desglosará internamente del precio cargado', style: TextStyle(fontSize: 12)),
                    value: precioIncluyeIva,
                    onChanged: (val) => setDlgState(() => precioIncluyeIva = val),
                  ),
                  DropdownButtonFormField<double>(
                    initialValue: _parseImpuestoInicial(impuestoCtrl.text),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Impuesto sugerido',
                      isDense: true,
                    ),
                    items: _impuestosDisponibles
                        .map(
                          (imp) => DropdownMenuItem<double>(
                            value: imp.rate,
                            child: Text(imp.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) impuestoCtrl.text = _fmtNum(value);
                    },
                  ),
                  const SizedBox(height: 10),
                  _campo(codigoBarrasCtrl, 'Codigo de barras'),
                  if (producto == null) ...[
                    const Divider(),
                    const Text(
                      'Información de Lote inicial (Opcional)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _campo(codigoLoteCtrl, 'Código de lote (opcional)'),
                    TextFormField(
                      controller: fechaVencimientoCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Fecha de vencimiento (AAAA-MM-DD)',
                        isDense: true,
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (picked != null) {
                          fechaVencimientoCtrl.text = picked
                              .toIso8601String()
                              .split('T')
                              .first;
                        }
                      },
                    ),
                  ],
                  const Divider(),
                  const Text(
                    'Conversión (opcional)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _campo(convNombreCtrl, 'Nombre de conversión'),
                  _campo(
                    convCantidadCtrl,
                    'Cantidad equivalente',
                    numerico: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                Navigator.pop(ctx);

                try {
                  await _guardarProducto(
                    id: producto?.id,
                    nombre: nombreCtrl.text.trim(),
                    unidad: unidadCtrl.text.trim(),
                    stock: double.parse(stockCtrl.text.trim().replaceAll(',', '.')),
                    costo: double.parse(costoCtrl.text.trim().replaceAll(',', '.')),
                    precio: double.parse(
                      precioCtrl.text.trim().replaceAll(',', '.'),
                    ),
                    impuestoPct:
                        double.tryParse(
                          impuestoCtrl.text.trim().replaceAll(',', '.'),
                        ) ??
                        0,
                    codigoBarras: codigoBarrasCtrl.text.trim(),
                    convNombre: convNombreCtrl.text.trim(),
                    convCantidad:
                        double.tryParse(
                          convCantidadCtrl.text.trim().replaceAll(',', '.'),
                        ) ??
                        0,
                    codigoLote: codigoLoteCtrl.text.trim(),
                    fechaVencimiento: fechaVencimientoCtrl.text.trim(),
                    precioIncluyeIva: precioIncluyeIva,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al guardar producto: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 6),
                      ),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers de UI ────────────────────────────────────────

  Widget _campo(
    TextEditingController ctrl,
    String etiqueta, {
    bool numerico = false,
    bool validar = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: numerico
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: numerico ? [NumericInput.decimal] : null,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: etiqueta,
          isDense: true,
        ),
        validator: validar
            ? (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Campo requerido';
                }
                if (numerico) {
                  final n = double.tryParse(v.trim().replaceAll(',', '.'));
                  if (n == null) {
                    return 'Número inválido (ej: 1.5)';
                  }
                  if (n < 0) return 'El valor no puede ser negativo';
                }
                return null;
              }
            : null,
      ),
    );
  }

  String _fmtNum(dynamic v) {
    final d = (v as num).toDouble();
    return d % 1 == 0 ? d.toInt().toString() : d.toString();
  }

  double _parseImpuestoInicial(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
    return _impuestosDisponibles.any((impuesto) => impuesto.rate == parsed)
        ? parsed
        : _impuestosDisponibles.first.rate;
  }

  String _moneda(MoneyValue valor) => valor.format();

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_currency == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final resumen = _productos.isEmpty
        ? InventorySummary.empty(_currency!)
        : InventorySummary.fromProducts(_productos);
    final productosVisibles = _productos.where((p) {
      final texto = '${p.name} ${p.barcode}'.toLowerCase();
      final coincide = texto.contains(_busqueda.toLowerCase().trim());
      return coincide && (!_soloStockBajo || p.lowStock);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventario'),
        actions: [
          IconButton(
            tooltip: 'Centro de control: reposición, bodegas, conteos y variantes',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const InventoryControlCenterPage(),
                ),
              );
              await _cargarProductos();
            },
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Card(
                  color: Colors.green.shade700,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _resumenInventario(
                            'Costo',
                            _moneda(resumen.costValue),
                            Colors.white,
                          ),
                        ),
                        Expanded(
                          child: _resumenInventario(
                            'Venta',
                            _moneda(resumen.saleValue),
                            Colors.white,
                          ),
                        ),
                        Expanded(
                          child: _resumenInventario(
                            'Productos',
                            '${resumen.productCount}',
                            Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () => setState(() => _busqueda = ''),
                            icon: const Icon(Icons.close),
                          ),
                    labelText: 'Buscar producto',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _busqueda = value),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Solo stock bajo'),
                    selected: _soloStockBajo,
                    onSelected: (value) {
                      setState(() => _soloStockBajo = value);
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: productosVisibles.isEmpty
                ? const Center(
                    child: Text(
                      'Sin productos para mostrar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                    itemCount: productosVisibles.length,
                    itemBuilder: (ctx, i) {
                      final prod = productosVisibles[i];
                      final stockActual = prod.stock;
                      final precio = prod.price;
                      final stockBajo = prod.lowStock;

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: stockBajo
                                    ? Colors.red.shade100
                                    : Colors.green.shade100,
                                child: Icon(
                                  Icons.inventory_2,
                                  color: stockBajo ? Colors.red : Colors.green,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      prod.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Stock: ${_fmtNum(stockActual)} ${prod.unit}   |   Precio: ${_moneda(precio)}   |   IVA: ${_fmtNum(prod.taxRate)}%',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (prod.barcode.isNotEmpty)
                                      Text(
                                        'Codigo: ${prod.barcode}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (prod.conversionName.isNotEmpty)
                                      Text(
                                        '1 ${prod.conversionName} = ${_fmtNum(prod.conversionQuantity)} ${prod.unit}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    if (stockBajo)
                                      const Text(
                                        '⚠ Stock bajo',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Acciones',
                                onSelected: (value) {
                                  if (value == 'editar') {
                                    _abrirFormulario(producto: prod);
                                  } else if (value == 'lotes') {
                                    final id = prod.id;
                                    if (id != null) {
                                      _verLotesProducto(id, prod.name);
                                    }
                                  } else if (value == 'eliminar') {
                                    final id = prod.id;
                                    if (id != null) {
                                      _eliminarProducto(id, prod.name);
                                    }
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'lotes',
                                    child: Text('Ver lotes'),
                                  ),
                                  PopupMenuItem(
                                    value: 'eliminar',
                                    child: Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _resumenInventario(String titulo, String valor, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: TextStyle(color: color.withValues(alpha: 0.75))),
        Text(
          valor,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
