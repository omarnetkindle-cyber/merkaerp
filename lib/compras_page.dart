import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';

import 'app_session.dart';
import 'catalog/application/catalog_service.dart';
import 'catalog/domain/master_catalog.dart';
import 'core/security/action_permission.dart';
import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'detalle_compra_page.dart';
import 'features/feature_key.dart';
import 'numeric_input.dart';
import 'proveedores_page.dart';
import 'purchases/application/create_purchase_use_case.dart';
import 'purchases/data/purchase_repository.dart';
import 'purchases/pages/purchase_intelligence_page.dart';

class ComprasPage extends StatefulWidget {
  const ComprasPage({super.key});

  @override
  State<ComprasPage> createState() => _ComprasPageState();
}

class _ComprasPageState extends State<ComprasPage> {
  final PurchaseRepository _comprasRepo = SqlitePurchaseRepository();
  final CreatePurchaseUseCase _crearCompra = CreatePurchaseUseCase();
  List<Map<String, dynamic>> _compras = [];
  List<Map<String, dynamic>> _proveedores = [];
  List<Map<String, dynamic>> _productos = [];
  List<TaxOption> _impuestosDisponibles = MasterCatalog.taxes;
  Map<int, String> _metodosPago = {};
  final Map<int, List<Map<String, dynamic>>> _detalles = {};

  String _filtroEstado = 'todas';
  String _busqueda = '';
  bool _cargando = true;
  Currency? _currency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarDatos);
      }
    });
  }

  Future<void> _cargarDatos() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final compras = await _comprasRepo.findAll();
    final proveedores = await DatabaseHelper.instance.obtenerProveedores();
    final productos = await DatabaseHelper.instance.obtenerProductos();
    final metodos = await DatabaseHelper.instance.obtenerMetodosPago();
    final impuestos = await CatalogService.instance
        .taxOptionsForActiveCompany();
    final detalles = <int, List<Map<String, dynamic>>>{};

    for (final compra in compras) {
      final id = compra.id;
      if (id != null) {
        detalles[id] = (await _comprasRepo.findDetails(
          id,
        )).map((line) => line.toMap()).toList();
      }
    }

    if (!mounted) return;
    setState(() {
      _compras = compras.map((compra) => compra.toMap()).toList();
      _currency = currency;
      _proveedores = proveedores;
      _productos = productos;
      _impuestosDisponibles = impuestos;
      _metodosPago = {
        for (final metodo in metodos)
          (metodo['id'] as num).toInt(): metodo['nombre'].toString(),
      };
      _detalles
        ..clear()
        ..addAll(detalles);
      _cargando = false;
    });
  }

  Future<void> _abrirProveedores() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProveedoresPage()),
    );
    await _cargarDatos();
  }

  Future<void> _anularCompra(Map<String, dynamic> compra) async {
    if (!AppSession.puedeEjecutarAccion('purchases', AppAction.cancel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para anular compras.')),
      );
      return;
    }
    final id = (compra['id'] as num).toInt();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Anular compra #$id'),
        content: const Text(
          'Se revertira el inventario, el saldo pagado y la cuenta por pagar asociada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await _comprasRepo.cancel(id);
      await _cargarDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compra anulada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _abrirFormularioCompra({List<PurchaseSuggestionSelection> suggestedLines = const []}) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!AppSession.puedeEjecutarAccion('purchases', AppAction.create)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para crear compras.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await DatabaseHelper.instance.validarFeatureHabilitada(
        FeatureKey.purchases,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.orange),
      );
      return;
    }

    if (await DatabaseHelper.instance.operacionBloqueadaPorCierre()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Operacion bloqueada por cierre de caja.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_proveedores.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Primero registra un proveedor.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _abrirProveedores();
      return;
    }

    if (_productos.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Primero registra productos en inventario.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final metodosPago = await DatabaseHelper.instance.obtenerMetodosPago();
    if (!mounted) return;

    int proveedorId = (_proveedores.first['id'] as num).toInt();
    int productoSelId = (_productos.first['id'] as num).toInt();
    int metodoPagoId = (metodosPago.first['id'] as num).toInt();
    bool esPagoMixto = _nombreMetodo(metodosPago, metodoPagoId) == 'PAGO MIXTO';

    final facturaCtrl = TextEditingController();
    final observacionCtrl = TextEditingController();
    final cantidadCtrl = TextEditingController(text: '1');
    final costoCtrl = TextEditingController(
      text: _sqlMoney(
        _productoPorId(productoSelId)?['costo'],
      ).toMajorUnitsString(),
    );
    final impuestoCtrl = TextEditingController(
      text: _fmtNum(_productoPorId(productoSelId)?['impuesto_pct'] ?? 0),
    );
    final pagoCajaCtrl = TextEditingController();
    final pagoBancoCtrl = TextEditingController();
    final pagoCreditoCtrl = TextEditingController();
    final retefuenteCtrl = TextEditingController(text: '0');
    final reteivaCtrl = TextEditingController(text: '0');
    final reteicaCtrl = TextEditingController(text: '0');
    final carrito = <Map<String, dynamic>>[];
    bool precioIncluyeIva = false;

    double impuestoPct() => _parse(impuestoCtrl.text);
    final zero = MoneyValue(minorUnits: 0, currency: _currency);

    // Calcula subtotal (base) e IVA de una línea de compra.
    // Si precioIncluyeIva=true: desgrega el IVA del precio total.
    // Si precioIncluyeIva=false: precio es la base, IVA se suma aparte.
    ({MoneyValue subtotal, MoneyValue impuesto}) calcularValoresLineaCompra({
      required MoneyValue costo,
      required double cantidad,
      required double impuestoPct,
      required bool precioIncluyeIva,
    }) {
      if (precioIncluyeIva && impuestoPct > 0) {
        // Precio ingresado = total con IVA incluido (como viene en factura)
        final totalConIva = costo.multiplyDecimal(cantidad.toString());
        final factor = 1.0 + (impuestoPct / 100.0);
        final baseMajor = totalConIva.toMajorUnitsDoubleForDisplay() / factor;
        final subtotal = MoneyValue.fromMajorUnits(
          baseMajor.toStringAsFixed(_currency!.decimalPlaces),
          currency: _currency,
        );
        final impuesto = totalConIva - subtotal;
        return (subtotal: subtotal, impuesto: impuesto);
      } else {
        // Comportamiento tradicional: precio = base, IVA se suma aparte
        final subtotal = costo.multiplyDecimal(cantidad.toString());
        final impuesto = subtotal.percent(impuestoPct.toString());
        return (subtotal: subtotal, impuesto: impuesto);
      }
    }

    for (final suggestion in suggestedLines) {
      final product = _productoPorId(suggestion.productId);
      if (product == null || suggestion.quantity <= 0) continue;
      final cost = _sqlMoney(product['costo']);
      if (cost.minorUnits <= 0) continue;
      final tax = (product['impuesto_pct'] as num?)?.toDouble() ?? 0;
      final calc = calcularValoresLineaCompra(
        costo: cost,
        cantidad: suggestion.quantity,
        impuestoPct: tax,
        precioIncluyeIva: false,
      );
      carrito.add({
        'producto_id': suggestion.productId,
        'producto': product['nombre'],
        'unidad': product['unidad_base'] ?? 'unid.',
        'cantidad': suggestion.quantity,
        'costo': cost,
        'subtotal': calc.subtotal,
        'impuesto_linea': calc.impuesto,
        'precio_incluye_iva': false,
      });
    }

    MoneyValue subtotalCarrito() => carrito.fold<MoneyValue>(
      zero,
      (sum, item) => sum + (item['subtotal'] as MoneyValue),
    );
    MoneyValue impuestoCarrito() => carrito.fold<MoneyValue>(
      zero,
      (sum, item) => sum + (item['impuesto_linea'] as MoneyValue),
    );
    MoneyValue totalCarrito() => subtotalCarrito() + impuestoCarrito();

    void agregarProducto(StateSetter setDlg) {
      final cantidad = _parse(cantidadCtrl.text);
      final costo = _moneyInput(costoCtrl.text);
      if (cantidad <= 0 || costo.minorUnits <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cantidad y costo deben ser mayores que cero.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final productoSel = _productoPorId(productoSelId);
      if (productoSel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecciona un producto valido.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final calc = calcularValoresLineaCompra(
        costo: costo,
        cantidad: cantidad,
        impuestoPct: impuestoPct(),
        precioIncluyeIva: precioIncluyeIva,
      );

      final productoId = productoSelId;
      final existente = carrito.where(
        (item) => item['producto_id'] == productoId,
      );
      setDlg(() {
        if (existente.isNotEmpty) {
          final item = existente.first;
          final nuevaCantidad = (item['cantidad'] as num).toDouble() + cantidad;
          final calcActualizado = calcularValoresLineaCompra(
            costo: costo,
            cantidad: nuevaCantidad,
            impuestoPct: impuestoPct(),
            precioIncluyeIva: precioIncluyeIva,
          );
          item['cantidad'] = nuevaCantidad;
          item['costo'] = costo;
          item['subtotal'] = calcActualizado.subtotal;
          item['impuesto_linea'] = calcActualizado.impuesto;
          item['precio_incluye_iva'] = precioIncluyeIva;
        } else {
          carrito.add({
            'producto_id': productoId,
            'producto': productoSel['nombre'],
            'unidad': productoSel['unidad_base'] ?? 'unid.',
            'cantidad': cantidad,
            'costo': costo,
            'subtotal': calc.subtotal,
            'impuesto_linea': calc.impuesto,
            'precio_incluye_iva': precioIncluyeIva,
          });
        }
        cantidadCtrl.text = '1';
      });
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final total = totalCarrito();
          return AlertDialog(
            title: const Text('Nueva compra'),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: proveedorId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Proveedor',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _proveedores
                                .map(
                                  (p) => DropdownMenuItem<int>(
                                    value: (p['id'] as num).toInt(),
                                    child: Text(
                                      p['nombre'].toString(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDlg(() => proveedorId = value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            controller: facturaCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Factura',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: observacionCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observacion',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                      initialValue: productoSelId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Producto',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _productos
                          .map(
                            (p) => DropdownMenuItem<int>(
                              value: (p['id'] as num).toInt(),
                              child: Text(
                                '${p['nombre']} | stock ${_fmtNum(p['stock'])} ${p['unidad_base']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final producto = _productoPorId(value);
                        setDlg(() {
                          productoSelId = value;
                          costoCtrl.text = _sqlMoney(
                            producto?['costo'],
                          ).toMajorUnitsString();
                          impuestoCtrl.text = _fmtNum(
                            producto?['impuesto_pct'] ?? 0,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: cantidadCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: costoCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Costo unitario',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => agregarProducto(setDlg),
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: metodoPagoId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Metodo de pago',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: metodosPago
                                .map(
                                  (m) => DropdownMenuItem<int>(
                                    value: (m['id'] as num).toInt(),
                                    child: Text(m['nombre'].toString()),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setDlg(() {
                                metodoPagoId = value;
                                esPagoMixto =
                                    _nombreMetodo(metodosPago, value) ==
                                    'PAGO MIXTO';
                                if (!esPagoMixto) {
                                  pagoCajaCtrl.clear();
                                  pagoBancoCtrl.clear();
                                  pagoCreditoCtrl.clear();
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<double>(
                            initialValue: _impuestoSeleccionado(
                              impuestoCtrl.text,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Impuesto',
                              border: OutlineInputBorder(),
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
                              if (value == null) return;
                              setDlg(() {
                                impuestoCtrl.text = _fmtNum(value);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        'Precio incluye IVA (total factura proveedor)',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Activa si el costo ingresado ya tiene IVA incluido',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: precioIncluyeIva,
                      onChanged: (value) {
                        setDlg(() {
                          precioIncluyeIva = value ?? false;
                        });
                      },
                    ),
                    if (esPagoMixto) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _moneyField(pagoCajaCtrl, 'Caja', setDlg),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _moneyField(pagoBancoCtrl, 'Banco', setDlg),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _moneyField(
                              pagoCreditoCtrl,
                              'Credito',
                              setDlg,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Retenciones (opcional)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _moneyField(
                            retefuenteCtrl,
                            'Retefuente',
                            setDlg,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _moneyField(reteivaCtrl, 'ReteIVA', setDlg),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _moneyField(reteicaCtrl, 'ReteICA', setDlg),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _CarritoCompra(
                      items: carrito,
                      moneda: _moneda,
                      onRemove: (index) =>
                          setDlg(() => carrito.removeAt(index)),
                    ),
                    const SizedBox(height: 12),
                    _TotalesCompra(
                      subtotal: subtotalCarrito(),
                      impuesto: impuestoCarrito(),
                      total: total,
                      moneda: _moneda,
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
              FilledButton.icon(
                onPressed: carrito.isEmpty
                    ? null
                    : () async {
                        try {
                          await _guardarCompra(
                            proveedorId: proveedorId,
                            factura: facturaCtrl.text.trim(),
                            observacion: observacionCtrl.text.trim(),
                            metodoPagoId: metodoPagoId,
                            metodosPago: metodosPago,
                            impuestoPct: impuestoPct(),
                            pagoCajaManual: _moneyInput(pagoCajaCtrl.text),
                            pagoBancoManual: _moneyInput(pagoBancoCtrl.text),
                            pagoCreditoManual: _moneyInput(
                              pagoCreditoCtrl.text,
                            ),
                            retefuente: _moneyInput(retefuenteCtrl.text),
                            reteiva: _moneyInput(reteivaCtrl.text),
                            reteica: _moneyInput(reteicaCtrl.text),
                            carrito: carrito,
                          );
                        } catch (e) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(e.toString()),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        await _cargarDatos();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Compra registrada correctamente'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                icon: const Icon(Icons.check),
                label: const Text('Guardar compra'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _moneyField(
    TextEditingController controller,
    String label,
    StateSetter setDlg,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [NumericInput.decimal],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (_) => setDlg(() {}),
    );
  }

  Future<void> _guardarCompra({
    required int proveedorId,
    required String factura,
    required String observacion,
    required int metodoPagoId,
    required List<Map<String, dynamic>> metodosPago,
    required double impuestoPct,
    required MoneyValue pagoCajaManual,
    required MoneyValue pagoBancoManual,
    required MoneyValue pagoCreditoManual,
    required MoneyValue retefuente,
    required MoneyValue reteiva,
    required MoneyValue reteica,
    required List<Map<String, dynamic>> carrito,
  }) async {
    final metodo = _nombreMetodo(metodosPago, metodoPagoId);
    final proveedor = _proveedores.firstWhere(
      (p) => (p['id'] as num).toInt() == proveedorId,
      orElse: () => {'nombre': 'Sin proveedor'},
    );

    await _crearCompra.execute(
      CreatePurchaseRequest(
        supplierId: proveedorId,
        supplierName: proveedor['nombre']?.toString() ?? 'Sin proveedor',
        invoiceNumber: factura,
        observation: observacion,
        paymentMethodId: metodoPagoId,
        paymentMethodName: metodo,
        taxRate: impuestoPct,
        manualCash: pagoCajaManual,
        manualBank: pagoBancoManual,
        manualCredit: pagoCreditoManual,
        retefuente: retefuente,
        reteiva: reteiva,
        reteica: reteica,
        items: carrito
            .map(
              (item) => PurchaseItemInput.fromCart(item, currency: _currency!),
            )
            .toList(),
      ),
    );
  }

  void _mostrarDetalle(Map<String, dynamic> compra) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleCompraPage(compra: compra)),
    );
  }

  String _resumenProductos(int compraId) {
    final detalles = _detalles[compraId] ?? const <Map<String, dynamic>>[];
    if (detalles.isEmpty) return 'Sin detalle de productos';
    final nombres = detalles
        .take(2)
        .map((item) => item['producto'].toString())
        .join(', ');
    final restantes = detalles.length - 2;
    return restantes > 0 ? '$nombres +$restantes mas' : nombres;
  }

  String _metodoPago(Map<String, dynamic> compra) {
    final id = (compra['metodo_pago_id'] as num?)?.toInt();
    if (id == null) return 'Metodo no registrado';
    return _metodosPago[id] ?? 'Metodo #$id';
  }

  String _nombreMetodo(List<Map<String, dynamic>> metodos, int id) {
    final metodo = metodos.firstWhere(
      (m) => (m['id'] as num).toInt() == id,
      orElse: () => {'nombre': 'EFECTIVO'},
    );
    return metodo['nombre'].toString().trim().toUpperCase();
  }

  Map<String, dynamic>? _productoPorId(int id) {
    for (final producto in _productos) {
      if ((producto['id'] as num).toInt() == id) return producto;
    }
    return null;
  }

  double _impuestoSeleccionado(String value) {
    final parsed = _parse(value);
    return _impuestosDisponibles.any((impuesto) => impuesto.rate == parsed)
        ? parsed
        : _impuestosDisponibles.first.rate;
  }

  double _parse(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  String _fmtNum(dynamic value) {
    final d = (value as num?)?.toDouble() ?? 0;
    return d % 1 == 0 ? d.toInt().toString() : d.toString();
  }

  MoneyValue _moneyInput(String input) => MoneyValue.fromMajorUnits(
    input.trim().isEmpty ? '0' : input.trim().replaceAll(',', '.'),
    currency: _currency,
  );

  MoneyValue _sqlMoney(Object? value) =>
      MoneyValue.fromSql(value, currency: _currency, nullableAsZero: true);

  String _moneda(Object valor) {
    if (valor is MoneyValue) return valor.format();
    if (valor is int) return _sqlMoney(valor).format();
    return _moneyInput(valor.toString()).format();
  }

  String _fecha(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String pad(int n) => n.toString().padLeft(2, '0');
      return '${pad(dt.day)}/${pad(dt.month)}/${dt.year} ${pad(dt.hour)}:${pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || _currency == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Compras')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final comprasVisibles = _compras.where((compra) {
      final estado = compra['estado']?.toString() ?? 'pagada';
      if (_filtroEstado != 'todas' && estado != _filtroEstado) return false;
      final id = (compra['id'] as num).toInt();
      final texto =
          'compra $id ${compra['proveedor'] ?? ''} ${compra['numero_factura'] ?? ''} ${_resumenProductos(id)} ${compra['fecha'] ?? ''}'
              .toLowerCase();
      return texto.contains(_busqueda.toLowerCase().trim());
    }).toList();

    final zero = MoneyValue(minorUnits: 0, currency: _currency);
    final totalVisible = comprasVisibles.fold<MoneyValue>(
      zero,
      (sum, c) => sum + (c['total'] as MoneyValue),
    );
    final pendienteVisible = comprasVisibles.fold<MoneyValue>(
      zero,
      (sum, c) => sum + (c['credito'] as MoneyValue),
    );
    final productosComprados = comprasVisibles.fold<int>(
      0,
      (sum, c) => sum + (_detalles[(c['id'] as num).toInt()]?.length ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Compras'),
        actions: [
          IconButton(
            tooltip: '¿Qué debo comprar? · sugerencias automáticas',
            onPressed: () async {
              final suggestions = await Navigator.of(context).push<List<PurchaseSuggestionSelection>>(
                MaterialPageRoute(builder: (_) => const PurchaseIntelligencePage()),
              );
              if (!mounted || suggestions == null || suggestions.isEmpty) return;
              await _abrirFormularioCompra(suggestedLines: suggestions);
            },
            icon: const Icon(Icons.auto_graph),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _proveedores.isEmpty
            ? _abrirProveedores
            : _abrirFormularioCompra,
        icon: Icon(
          _proveedores.isEmpty ? Icons.business : Icons.add_shopping_cart,
        ),
        label: Text(_proveedores.isEmpty ? 'Crear proveedor' : 'Nueva compra'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Card(
                        color: MerkaThemeTokens.success,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: _MiniResumen(
                                  titulo: 'Comprado',
                                  valor: _moneda(totalVisible),
                                ),
                              ),
                              Expanded(
                                child: _MiniResumen(
                                  titulo: 'Credito',
                                  valor: _moneda(pendienteVisible),
                                ),
                              ),
                              Expanded(
                                child: _MiniResumen(
                                  titulo: 'Items',
                                  valor: '$productosComprados',
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
                          labelText:
                              'Buscar proveedor, factura, producto o fecha',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _busqueda.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpiar búsqueda',
                                  onPressed: () =>
                                      setState(() => _busqueda = ''),
                                  icon: const Icon(Icons.close),
                                ),
                        ),
                        onChanged: (value) => setState(() => _busqueda = value),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _estadoChip('Todas', 'todas'),
                            _estadoChip('Pagadas', 'pagada'),
                            _estadoChip('Pendientes', 'pendiente'),
                            _estadoChip('Anuladas', 'anulada'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: comprasVisibles.isEmpty
                      ? const Center(
                          child: Text('No hay compras para mostrar.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                          itemCount: comprasVisibles.length,
                          itemBuilder: (context, index) {
                            final compra = comprasVisibles[index];
                            final id = (compra['id'] as num).toInt();
                            final total = compra['total'] as MoneyValue;
                            final estado =
                                compra['estado']?.toString() ?? 'pagada';
                            final anulada = estado == 'anulada';

                            return Card(
                              child: ListTile(
                                onTap: () => _mostrarDetalle(compra),
                                leading: CircleAvatar(
                                  backgroundColor: anulada
                                      ? Colors.red.shade50
                                      : MerkaThemeTokens.success.withValues(alpha: 0.15),
                                  child: Icon(
                                    Icons.inventory_2,
                                    color: anulada
                                        ? Colors.red
                                        : MerkaThemeTokens.success,
                                  ),
                                ),
                                title: Text(
                                  'Compra #$id${anulada ? ' (anulada)' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${compra['proveedor'] ?? 'Sin proveedor'} | ${_fecha(compra['fecha']?.toString() ?? '')}\n${_resumenProductos(id)} | ${_metodoPago(compra)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 96,
                                      ),
                                      child: Text(
                                        _moneda(total),
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: anulada
                                              ? Colors.red
                                              : Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Anular compra',
                                      icon: const Icon(
                                        Icons.undo,
                                        color: Colors.red,
                                      ),
                                      onPressed: anulada
                                          ? null
                                          : () => _anularCompra(compra),
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

  Widget _estadoChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filtroEstado == value,
        onSelected: (_) => setState(() => _filtroEstado = value),
      ),
    );
  }
}

class _CarritoCompra extends StatelessWidget {
  const _CarritoCompra({
    required this.items,
    required this.moneda,
    required this.onRemove,
  });

  final List<Map<String, dynamic>> items;
  final String Function(Object) moneda;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Agrega productos para registrar la compra.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detalle de compra',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final cantidad = (item['cantidad'] as num).toDouble();
          final costo = item['costo'] as MoneyValue;
          final subtotal = item['subtotal'] as MoneyValue;
          final cant = cantidad % 1 == 0
              ? cantidad.toInt().toString()
              : cantidad.toString();

          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              item['producto'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('$cant ${item['unidad']} x ${moneda(costo)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  moneda(subtotal),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  onPressed: () => onRemove(index),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _TotalesCompra extends StatelessWidget {
  const _TotalesCompra({
    required this.subtotal,
    required this.impuesto,
    required this.total,
    required this.moneda,
  });

  final MoneyValue subtotal;
  final MoneyValue impuesto;
  final MoneyValue total;
  final String Function(Object) moneda;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Column(
          children: [
            _row('Subtotal', subtotal),
            _row('Impuesto', impuesto),
            const Divider(height: 14),
            _row('Total', total, destacado: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, MoneyValue value, {bool destacado = false}) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          moneda(value),
          style: TextStyle(
            fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
            fontSize: destacado ? 18 : 13,
          ),
        ),
      ],
    );
  }
}

class _MiniResumen extends StatelessWidget {
  const _MiniResumen({required this.titulo, required this.valor});

  final String titulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(color: Colors.white70)),
        Text(
          valor,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
