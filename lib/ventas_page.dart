import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_session.dart';
import 'catalog/application/catalog_service.dart';
import 'catalog/domain/master_catalog.dart';
import 'core/security/action_permission.dart';
import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'control_center_agent.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'numeric_input.dart';
import 'sales/application/create_sale_use_case.dart';
import 'sales/data/sale_repository.dart';
import 'sales/peripherals/pos_peripheral_service.dart';
import 'sales/peripherals/pos_peripherals_page.dart';
import 'sales/peripherals/pos_session_service.dart';
import 'services/merka_intelligence_service.dart';
import 'ui/enterprise_design_system.dart';
import 'ui/merka_theme_tokens.dart';

class VentasPage extends StatefulWidget {
  const VentasPage({super.key});

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> {
  final SaleRepository _ventasRepo = SqliteSaleRepository();
  final CreateSaleUseCase _crearVenta = CreateSaleUseCase();
  List<Map<String, dynamic>> _ventas = [];
  List<Map<String, dynamic>> _productos = [];
  List<TaxOption> _impuestosDisponibles = MasterCatalog.taxes;
  Map<int, String> _metodosPago = {};
  final Map<int, List<Map<String, dynamic>>> _detalles = {};
  final _busquedaController = TextEditingController();
  Currency? _currency;
  MoneyValue? _totalVentas;
  String _busqueda = '';
  String _filtroEstado = 'todos';
  String _filtroMetodo = 'todos';
  DateTime? _filtroDesde;
  DateTime? _filtroHasta;
  bool _datosCargados = false;
  Future<void>? _cargaEnCurso;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

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
    final enCurso = _cargaEnCurso;
    if (enCurso != null) return enCurso;

    final carga = _cargarDatosInterna();
    _cargaEnCurso = carga;
    try {
      await carga;
    } finally {
      if (identical(_cargaEnCurso, carga)) {
        _cargaEnCurso = null;
      }
    }
  }

  Future<void> _cargarDatosInterna() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final ventas = await _ventasRepo.findAll();
    final productos = await DatabaseHelper.instance.obtenerProductos();
    final metodos = await DatabaseHelper.instance.obtenerMetodosPago();
    final impuestos = await CatalogService.instance
        .taxOptionsForActiveCompany();
    final total = await _ventasRepo.totalSales();
    final detalles = <int, List<Map<String, dynamic>>>{};

    for (final venta in ventas) {
      final id = venta.id;
      if (id != null) {
        detalles[id] = (await _ventasRepo.findDetails(
          id,
        )).map((line) => line.toMap()).toList();
      }
    }

    if (!mounted) return;
    setState(() {
      _datosCargados = true;
      _currency = currency;
      _ventas = ventas.map((venta) => venta.toMap()).toList();
      _productos = productos;
      _impuestosDisponibles = impuestos;
      _totalVentas = total;
      _metodosPago = {
        for (final metodo in metodos)
          (metodo['id'] as num).toInt(): metodo['nombre'].toString(),
      };
      _detalles
        ..clear()
        ..addAll(detalles);
    });
  }

  Future<void> _asegurarDatosCargados() async {
    if (!_datosCargados || _productos.isEmpty) {
      await _cargarDatos();
    }
  }

  Future<void> _anularVenta(Map<String, dynamic> venta) async {
    if (!AppSession.puedeEjecutarAccion('sales', AppAction.cancel)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para anular ventas.')),
      );
      return;
    }
    final id = (venta['id'] as num).toInt();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Anular factura POS #$id'),
        content: const Text(
          'Se restaurara el inventario y se reversara el saldo relacionado.',
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
      await _ventasRepo.cancel(id);
      await ControlCenterAgent.reportEvent(
        event: 'sale.cancelled',
        module: 'sales',
        severity: 'warning',
      );
      await _cargarDatos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: MerkaThemeTokens.danger,
        ),
      );
    }
  }

  Future<void> _abrirFormulario() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!AppSession.puedeEjecutarAccion('sales', AppAction.create)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para crear ventas.'),
          backgroundColor: MerkaThemeTokens.warning,
        ),
      );
      return;
    }
    if (await DatabaseHelper.instance.operacionBloqueadaPorCierre()) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Operacion bloqueada por cierre de caja.'),
          backgroundColor: MerkaThemeTokens.warning,
        ),
      );
      return;
    }

    await _asegurarDatosCargados();
    if (!mounted) return;
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final zero = MoneyValue(minorUnits: 0, currency: currency);
    final posPeripheralConfig = await PosPeripheralService.instance.load();

    final disponibles = _productos
        .where((p) {
          final esServicio =
              (p['tipo_item']?.toString() ?? 'producto') == 'servicio';
          // Los servicios no tienen stock físico — siempre están disponibles.
          // Los productos físicos requieren stock > 0.
          return esServicio || ((p['stock'] as num?)?.toDouble() ?? 0) > 0;
        })
        .toList();

    if (disponibles.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No hay productos con stock disponible.'),
          backgroundColor: MerkaThemeTokens.warning,
        ),
      );
      return;
    }

    final metodosPago = await DatabaseHelper.instance.obtenerMetodosPago();
    final clientes = await DatabaseHelper.instance.obtenerClientes();
    if (!mounted) return;

    int productoSelId = (disponibles.first['id'] as num).toInt();
    final barcodeCtrl = TextEditingController();
    final barcodeFocus = FocusNode();
    final clienteFocus = FocusNode();
    final recibidoFocus = FocusNode();
    final cantidadCtrl = TextEditingController(text: '1');
    final intelligence = MerkaIntelligenceService();
    Timer? barcodeDebounce;
    var resolvingBarcode = false;
    int metodoPagoId = (metodosPago.first['id'] as num).toInt();
    bool esPagoMixto = false;
    final pagoCajaCtrl = TextEditingController();
    final pagoBancoCtrl = TextEditingController();
    final pagoCreditoCtrl = TextEditingController();
    // Convierte el precio del primer producto a major units para mostrarlo en
    // el campo editable del POS. El valor en BD es siempre int (minor units
    // post-v75) o puede ser MoneyValue si ya fue hidratado. En ambos casos
    // se normaliza aquí para que el cajero vea "10.00" y no "1000".
    final precioUnitarioCtrl = TextEditingController(
      text: _priceToDisplay(disponibles.first['precio'], currency),
    );
    final retefuenteCtrl = TextEditingController(text: '0');
    final reteivaCtrl = TextEditingController(text: '0');
    final reteicaCtrl = TextEditingController(text: '0');
    final montoRecibidoCtrl = TextEditingController();
    int? clienteId;
    String clienteNombre = 'Cliente general';
    double impuestoPct =
        (disponibles.first['impuesto_pct'] as num?)?.toDouble() ?? 0;
    final carrito = <Map<String, dynamic>>[];
    ({MoneyValue subtotal, MoneyValue impuestoTotal}) calcularValoresItem({
      required MoneyValue precio,
      required double cantidad,
      required double impuestoPct,
      required bool precioIncluyeIva,
      required Currency currency,
    }) {
      if (precioIncluyeIva && impuestoPct > 0) {
        final totalCobrado = precio.multiplyDecimal(cantidad.toString());
        final factor = 1.0 + (impuestoPct / 100.0);
        final baseMajor = totalCobrado.toMajorUnitsDoubleForDisplay() / factor;
        final subtotal = MoneyValue.fromMajorUnits(
          baseMajor.toStringAsFixed(currency.decimalPlaces),
          currency: currency,
        );
        final impuestoTotal = totalCobrado - subtotal;
        return (subtotal: subtotal, impuestoTotal: impuestoTotal);
      } else {
        final subtotal = precio.multiplyDecimal(cantidad.toString());
        final impuestoTotal = subtotal.percent(impuestoPct.toString());
        return (subtotal: subtotal, impuestoTotal: impuestoTotal);
      }
    }

    Map<String, dynamic>? productoPorId(int id) {
      for (final producto in disponibles) {
        if ((producto['id'] as num).toInt() == id) return producto;
      }
      return null;
    }

    MoneyValue subtotalCarrito() => carrito.fold<MoneyValue>(
      zero,
      (sum, item) => sum + (item['subtotal'] as MoneyValue),
    );

    MoneyValue impuestoCarrito() => carrito.fold<MoneyValue>(
      zero,
      (sum, item) => sum + (item['impuesto_total'] as MoneyValue),
    );

    MoneyValue totalCarrito() {
      return subtotalCarrito() + impuestoCarrito();
    }

    // Convierte cualquier representación de precio/costo a MoneyValue.
    // Acepta: int (minor units de BD post-v75), double (BD pre-v75 o REAL),
    // MoneyValue (ya hidratado, p.ej. precio editado por el cajero).
    // Nunca lanza StateError — fuente de silenciosos en llamadas previas.
    MoneyValue resolveMoneyValue(
      Object? value,
      Currency cur, {
      bool nullableAsZero = false,
    }) {
      if (value == null) {
        return MoneyValue(minorUnits: 0, currency: cur);
      }
      if (value is MoneyValue) return value;
      if (value is int) return MoneyValue(minorUnits: value, currency: cur);
      if (value is double) {
        // BD pre-v75: columna REAL → double. Tratamos como minor units
        // con truncamiento (equivalente a lo que fromSql haría si fuera int).
        return MoneyValue(minorUnits: value.round(), currency: cur);
      }
      if (nullableAsZero) return MoneyValue(minorUnits: 0, currency: cur);
      throw StateError(
        'No se puede convertir precio a MoneyValue: ${value.runtimeType} = $value',
      );
    }

    void agregarProducto(
      StateSetter setDlg,
      Map<String, dynamic> producto,
      double cantidad,
    ) {
      try {
        if (cantidad <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ingresa una cantidad mayor a cero.'),
              backgroundColor: MerkaThemeTokens.warning,
            ),
          );
          return;
        }
        final productoId = (producto['id'] as num).toInt();
        final esServicio =
            (producto['tipo_item']?.toString() ?? 'producto') == 'servicio';
        final stock = (producto['stock'] as num).toDouble();
        final yaAgregado = carrito
            .where((item) => item['producto_id'] == productoId)
            .fold<double>(
              0,
              (sum, item) => sum + (item['cantidad'] as num).toDouble(),
            );

        // Los servicios no descuentan stock — el check solo aplica a productos.
        if (!esServicio && yaAgregado + cantidad > stock) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Stock insuficiente para ${producto['nombre']}'),
              backgroundColor: MerkaThemeTokens.danger,
            ),
          );
          return;
        }

        // resolveMoneyValue acepta int (BD post-v75), double (BD pre-v75/REAL),
        // y MoneyValue (precio editado por el cajero). Ya no lanza StateError.
        final precio = resolveMoneyValue(producto['precio'], currency);
        final costo = resolveMoneyValue(
          producto['costo'],
          currency,
          nullableAsZero: true,
        );
      final bool precioIncluyeIva =
          (producto['precio_incluye_iva'] as num?)?.toInt() == 1 ||
          producto['precio_incluye_iva'] == true;

      final calcInicial = calcularValoresItem(
        precio: precio,
        cantidad: cantidad,
        impuestoPct: impuestoPct,
        precioIncluyeIva: precioIncluyeIva,
        currency: currency,
      );

      final existente = carrito.where((i) => i['producto_id'] == productoId);
      setDlg(() {
        if (existente.isNotEmpty) {
          final item = existente.first;
          final nuevaCantidad = (item['cantidad'] as num).toDouble() + cantidad;
          item['cantidad'] = nuevaCantidad;
          item['impuesto_pct'] = impuestoPct;

          final calcEdit = calcularValoresItem(
            precio: item['precio'] as MoneyValue,
            cantidad: nuevaCantidad,
            impuestoPct: impuestoPct,
            precioIncluyeIva: precioIncluyeIva,
            currency: currency,
          );
          item['subtotal'] = calcEdit.subtotal;
          item['impuesto_total'] = calcEdit.impuestoTotal;
        } else {
          carrito.add({
            'producto_id': productoId,
            'producto': producto['nombre'],
            'codigo_barras': producto['codigo_barras'] ?? '',
            'unidad': producto['unidad_base'] ?? 'unid.',
            'cantidad': cantidad,
            'precio': precio,
            'costo': costo,
            'subtotal': calcInicial.subtotal,
            'impuesto_pct': impuestoPct,
            'impuesto_total': calcInicial.impuestoTotal,
            'precio_incluye_iva': precioIncluyeIva,
            'ubicacion_codigo': producto['ubicacion_codigo'] ?? '',
            'ubicacion_pasillo': producto['ubicacion_pasillo'] ?? '',
            'ubicacion_estante': producto['ubicacion_estante'] ?? '',
            'ubicacion_nivel': producto['ubicacion_nivel'] ?? '',
            'codigo_lote': producto['codigo_lote'] ?? '',
            'fecha_vencimiento': producto['fecha_vencimiento'] ?? '',
          });
        }
        cantidadCtrl.text = '1';
        barcodeCtrl.clear();
        barcodeFocus.requestFocus();
      });
      } catch (e, st) {
        // Muestra el error real en pantalla — en release mode las excepciones
        // no capturadas en callbacks son silenciosas y el usuario no ve nada.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar al carrito: $e'),
            backgroundColor: MerkaThemeTokens.danger,
            duration: const Duration(seconds: 8),
          ),
        );
        assert(() {
          // En debug mode, relanza para que el devtools lo vea.
          // ignore: only_throw_errors
          Error.throwWithStackTrace(e, st);
        }());
      }
    }

    Map<String, dynamic>? buscarPorCodigo(String codigo) {
      final limpio = codigo.trim().toLowerCase();
      if (limpio.isEmpty) return null;
      for (final producto in disponibles) {
        final barras = (producto['codigo_barras'] ?? '')
            .toString()
            .toLowerCase();
        final id = producto['id'].toString();
        if (barras == limpio || id == limpio) return producto;
      }
      return null;
    }

    Future<void> resolverBusquedaAutomatica(
      StateSetter setDlg,
      String value,
    ) async {
      final query = value.trim();
      if (query.length < 3 || resolvingBarcode) return;
      resolvingBarcode = true;
      try {
        final local = buscarPorCodigo(query);
        final lookup = local == null
            ? await intelligence.findProduct(query)
            : null;
        final productoBase = local ?? lookup?.product;
        if (productoBase == null) {
          await SystemSound.play(SystemSoundType.alert);
          return;
        }
        final lote = lookup?.lot;
        final producto = {
          ...productoBase,
          if (lote != null) 'codigo_lote': lote['codigo_lote'],
          if (lote != null) 'fecha_vencimiento': lote['fecha_vencimiento'],
        };
        impuestoPct = (producto['impuesto_pct'] as num?)?.toDouble() ?? 0;
        agregarProducto(setDlg, producto, 1);
        await SystemSound.play(SystemSoundType.click);
        if (!mounted) return;
        final ubicacion = ProductLookupResult(
          product: producto,
          matchedBy: lookup?.matchedBy ?? 'codigo_barras',
          currency: lookup?.currency ?? _currency!,
          lot: lote,
          suggestions: lookup?.suggestions ?? const [],
        ).location;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              ubicacion.isEmpty
                  ? '${producto['nombre']} agregado'
                  : '${producto['nombre']} agregado | Ubicacion $ubicacion',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      } finally {
        resolvingBarcode = false;
      }
    }

    final posSessions = PosSessionService.instance;
    var favoriteIds = await posSessions.favoriteIds();
    var issuingInvoice = false;

    Future<void> issueInvoice(BuildContext dialogContext) async {
      if (issuingInvoice) return;
      if (carrito.isEmpty) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Agrega al menos un producto antes de finalizar.')),
        );
        return;
      }
      issuingInvoice = true;
      try {
        await _guardarVenta(
          carrito: carrito,
          metodoPagoId: metodoPagoId,
          clienteId: clienteId,
          clienteNombre: clienteNombre,
          metodosPago: metodosPago,
          pagoCaja: _moneyInput(pagoCajaCtrl.text, currency),
          pagoBanco: _moneyInput(pagoBancoCtrl.text, currency),
          pagoCredito: _moneyInput(pagoCreditoCtrl.text, currency),
          retefuente: _moneyInput(retefuenteCtrl.text, currency),
          reteiva: _moneyInput(reteivaCtrl.text, currency),
          reteica: _moneyInput(reteicaCtrl.text, currency),
        );
      } catch (e) {
        if (!dialogContext.mounted) return;
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: MerkaThemeTokens.danger),
        );
        issuingInvoice = false;
        return;
      }
      if (!dialogContext.mounted) return;
      Navigator.pop(dialogContext);
      await _cargarDatos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura emitida correctamente'), backgroundColor: MerkaThemeTokens.success),
      );
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.f2): () => barcodeFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.f4): () => clienteFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.f8): () => recibidoFocus.requestFocus(),
            const SingleActivator(LogicalKeyboardKey.f10): () => issueInvoice(ctx),
          },
          child: Focus(
            autofocus: true,
            child: Theme(
              data: posPeripheralConfig.touchMode
                  ? Theme.of(ctx).copyWith(
                      visualDensity: const VisualDensity(horizontal: 1, vertical: 1),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    )
                  : Theme.of(ctx),
              child: AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: posPeripheralConfig.touchMode ? 12 : 40,
            vertical: posPeripheralConfig.touchMode ? 12 : 24,
          ),
          title: Row(children: [
            const Expanded(child: Text('Nueva factura POS')),
            if (posPeripheralConfig.touchMode)
              const Chip(avatar: Icon(Icons.touch_app_outlined, size: 18), label: Text('Táctil')),
          ]),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Atajos: F2 producto/código · F4 cliente · F8 efectivo/cobro · F10 finalizar',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: barcodeCtrl,
                    focusNode: barcodeFocus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Codigo de barras',
                      prefixIcon: Icon(Icons.qr_code_scanner),
                      suffixIcon: Icon(Icons.camera_alt_outlined),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      barcodeDebounce?.cancel();
                      barcodeDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => resolverBusquedaAutomatica(setDlg, value),
                      );
                    },
                    onSubmitted: (value) {
                      final producto = buscarPorCodigo(value);
                      if (producto == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Producto no encontrado por codigo.'),
                            backgroundColor: MerkaThemeTokens.warning,
                          ),
                        );
                        return;
                      }
                      impuestoPct =
                          (producto['impuesto_pct'] as num?)?.toDouble() ?? 0;
                      agregarProducto(setDlg, producto, 1);
                    },
                  ),
                  const SizedBox(height: 10),
                  if (favoriteIds.isNotEmpty) ...[
                    Text('Favoritos', style: Theme.of(ctx).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final product in disponibles.where((p) => favoriteIds.contains((p['id'] as num).toInt())).take(10))
                          ActionChip(
                            avatar: const Icon(Icons.star, size: 16),
                            label: Text(product['nombre'].toString()),
                            tooltip: 'Agregar rápidamente al carrito',
                            onPressed: () => agregarProducto(setDlg, product, 1),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(children: [
                    Expanded(child: DropdownButtonFormField<int>(
                    initialValue: productoSelId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Producto',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: disponibles
                        .map(
                          (p) => DropdownMenuItem<int>(
                            value: (p['id'] as num).toInt(),
                            child: Text(
                              '${p['nombre']} | stock ${p['stock']} ${p['unidad_base']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      final producto = productoPorId(value);
                      setDlg(() {
                        productoSelId = value;
                        impuestoPct =
                            (producto?['impuesto_pct'] as num?)?.toDouble() ??
                            0;
                        if (producto != null && producto['precio'] != null) {
                          precioUnitarioCtrl.text =
                              _priceToDisplay(producto['precio'], currency);
                        }
                      });
                    },
                  )),
                    IconButton(
                      tooltip: favoriteIds.contains(productoSelId) ? 'Quitar de favoritos' : 'Agregar a favoritos',
                      onPressed: () async {
                        await posSessions.toggleFavorite(productoSelId);
                        final updated = await posSessions.favoriteIds();
                        setDlg(() => favoriteIds = updated);
                      },
                      icon: Icon(favoriteIds.contains(productoSelId) ? Icons.star : Icons.star_border),
                    ),
                  ]),
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
                          controller: precioUnitarioCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [NumericInput.decimal],
                          decoration: const InputDecoration(
                            labelText: 'Precio Unitario',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () {
                          try {
                            final cantidad =
                                double.tryParse(
                                  cantidadCtrl.text.replaceAll(',', '.'),
                                ) ??
                                0;
                            final producto = productoPorId(productoSelId);
                            if (producto == null) return;

                            final customPrecioStr =
                                precioUnitarioCtrl.text.trim().replaceAll(',', '.');
                            final customPrecio =
                                double.tryParse(customPrecioStr);

                            final Map<String, dynamic> prodParaAgregar;
                            if (customPrecio != null) {
                              // Precio editado por el cajero: se convierte a
                              // MoneyValue con fromMajorUnits para que
                              // resolveMoneyValue lo reciba ya tipado.
                              prodParaAgregar =
                                  Map<String, dynamic>.from(producto)
                                    ..['precio'] = MoneyValue.fromMajorUnits(
                                      customPrecioStr,
                                      currency: currency,
                                    );
                            } else {
                              prodParaAgregar = producto;
                            }

                            agregarProducto(setDlg, prodParaAgregar, cantidad);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: MerkaThemeTokens.danger,
                                duration: const Duration(seconds: 8),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
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
                        final nombre = metodosPago
                            .firstWhere(
                              (m) => (m['id'] as num).toInt() == value,
                            )['nombre']
                            .toString();
                        esPagoMixto = nombre.toUpperCase() == 'PAGO MIXTO';
                        if (!esPagoMixto) {
                          pagoCajaCtrl.clear();
                          pagoBancoCtrl.clear();
                          pagoCreditoCtrl.clear();
                        }
                      });
                    },
                  ),
                  if (esPagoMixto) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pagoCajaCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Efectivo (Caja)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: pagoBancoCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Transferencia',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: pagoCreditoCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Credito',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Campo para monto recibido en efectivo (para calcular cambio)
                  if (!esPagoMixto &&
                      _nombreMetodo(metodosPago, metodoPagoId) ==
                          'EFECTIVO') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: montoRecibidoCtrl,
                      focusNode: recibidoFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [NumericInput.decimal],
                      decoration: const InputDecoration(
                        labelText: 'Monto recibido (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        helperText: 'Para calcular el cambio',
                      ),
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
                        child: TextField(
                          controller: retefuenteCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [NumericInput.decimal],
                          decoration: const InputDecoration(
                            labelText: 'Retefuente',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: reteivaCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [NumericInput.decimal],
                          decoration: const InputDecoration(
                            labelText: 'ReteIVA',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: reteicaCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [NumericInput.decimal],
                          decoration: const InputDecoration(
                            labelText: 'ReteICA',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: clienteId,
                    focusNode: clienteFocus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Cliente general'),
                      ),
                      ...clientes.map(
                        (c) => DropdownMenuItem<int?>(
                          value: (c['id'] as num).toInt(),
                          child: Text(
                            c['nombre'].toString(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setDlg(() {
                        clienteId = value;
                        final cliente = clientes.where((c) => c['id'] == value);
                        clienteNombre = cliente.isEmpty
                            ? 'Cliente general'
                            : cliente.first['nombre'].toString();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<double>(
                    initialValue: _impuestoSeleccionado(impuestoPct),
                    decoration: const InputDecoration(
                      labelText: 'Impuesto del producto',
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
                        impuestoPct = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _CarritoVenta(
                    items: carrito,
                    moneda: _moneda,
                    onRemove: (index) => setDlg(() => carrito.removeAt(index)),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Total: ${_moneda(totalCarrito())}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: MerkaThemeTokens.success,
                      ),
                    ),
                  ),
                  // Mostrar cambio si se ingresó monto recibido (Mejora 14 - destacado)
                  if (!esPagoMixto &&
                      _nombreMetodo(metodosPago, metodoPagoId) ==
                          'EFECTIVO') ...[
                    const SizedBox(height: 8),
                    Builder(
                      builder: (context) {
                        final total = totalCarrito();
                        final recibido = _moneyInput(
                          montoRecibidoCtrl.text,
                          currency,
                        );
                        final cambio = recibido - total;
                        if (recibido.minorUnits > 0 && cambio.minorUnits > 0) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: MerkaThemeTokens.success.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: MerkaThemeTokens.success.withValues(
                                  alpha: 0.45,
                                ),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'CAMBIO A ENTREGAR',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: MerkaThemeTokens.success,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _moneda(cambio),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: MerkaThemeTokens.success,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.pause_circle_outline),
              label: const Text('Suspender'),
              onPressed: carrito.isEmpty ? null : () async {
                await posSessions.suspend(cart: carrito, customerId: clienteId, customerName: clienteNombre, paymentMethodId: metodoPagoId);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(const SnackBar(content: Text('Venta suspendida. Puedes recuperarla desde una nueva venta.')));
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('Recuperar'),
              onPressed: () async {
                final pending = await posSessions.list();
                if (!ctx.mounted) return;
                if (pending.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('No hay ventas suspendidas.'))); return; }
                final selected = await showDialog<int>(context: ctx, builder: (pickCtx) => SimpleDialog(
                  title: const Text('Ventas suspendidas'),
                  children: [for (final row in pending) SimpleDialogOption(
                    onPressed: () => Navigator.pop(pickCtx, (row['id'] as num).toInt()),
                    child: ListTile(title: Text('Venta #${row['id']} · ${row['customer_name'] ?? 'Cliente general'}'), subtitle: Text('${row['user_name']} · ${row['created_at']}')),
                  )],
                ));
                if (selected == null) return;
                final recovered = await posSessions.consume(selected, currency);
                setDlg(() {
                  carrito..clear()..addAll((recovered['cart'] as List).cast<Map<String,dynamic>>());
                  clienteId = recovered['customer_id'] as int?;
                  clienteNombre = recovered['customer_name'].toString();
                  metodoPagoId = recovered['payment_method_id'] as int? ?? metodoPagoId;
                });
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Emitir factura'),
              onPressed: carrito.isEmpty ? null : () => issueInvoice(ctx),
            ),
          ],
              ),
            ),
          ),
        ),
      ),
    );
    barcodeDebounce?.cancel();
    barcodeFocus.dispose();
    clienteFocus.dispose();
    recibidoFocus.dispose();
    barcodeCtrl.dispose();
    cantidadCtrl.dispose();
    precioUnitarioCtrl.dispose();
    montoRecibidoCtrl.dispose();
  }

  Future<void> _guardarVenta({
    required List<Map<String, dynamic>> carrito,
    required int metodoPagoId,
    required int? clienteId,
    required String clienteNombre,
    required List<Map<String, dynamic>> metodosPago,
    required MoneyValue pagoCaja,
    required MoneyValue pagoBanco,
    required MoneyValue pagoCredito,
    required MoneyValue retefuente,
    required MoneyValue reteiva,
    required MoneyValue reteica,
  }) async {
    final currency = pagoCaja.currency;
    final metodo = metodosPago.firstWhere(
      (m) => (m['id'] as num).toInt() == metodoPagoId,
      orElse: () => {'nombre': 'DESCONOCIDO'},
    );
    final result = await _crearVenta.execute(
      CreateSaleRequest(
        items: carrito
            .map((item) => SaleItemInput.fromCart(item, currency: currency))
            .toList(),
        paymentMethodId: metodoPagoId,
        paymentMethodName: metodo['nombre'].toString(),
        clientId: clienteId,
        clientName: clienteNombre,
        efectivo: pagoCaja,
        transferencia: pagoBanco,
        credito: pagoCredito,
        retefuente: retefuente,
        reteiva: reteiva,
        reteica: reteica,
      ),
    );
    await ControlCenterAgent.reportEvent(
      event: 'sale.created.${result.saleId}',
      module: 'sales',
    );
    try {
      await PosPeripheralService.instance.afterSale(result.saleId);
    } catch (error) {
      // Una falla del periférico jamás revierte una venta ya confirmada.
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'ERROR_PERIFERICO_POS', entidad: 'ventas', entidadId: result.saleId,
        detalle: 'La venta quedó registrada, pero el periférico reportó: $error',
      );
    }
  }

  void _mostrarDetalle(Map<String, dynamic> venta) {
    final id = (venta['id'] as num).toInt();
    final detalles = _detalles[id] ?? const <Map<String, dynamic>>[];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Factura POS #$id',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text('Cliente: ${venta['cliente'] ?? 'Cliente general'}'),
            Text('Fecha: ${_formatearFecha(venta['fecha']?.toString() ?? '')}'),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: detalles.length,
                itemBuilder: (_, index) {
                  final item = detalles[index];
                  final cantidad = (item['cantidad'] as num).toDouble();
                  final precio = item['precio_unitario'] as MoneyValue;
                  final subtotal = item['subtotal'] as MoneyValue;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['producto'].toString()),
                    subtitle: Text(
                      '${_cantidad(cantidad)} x ${_moneda(precio)}',
                    ),
                    trailing: Text(
                      _moneda(subtotal),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            // Mostrar desglose de métodos de pago (Bug 2)
            if (_positiveMoney(venta['efectivo']) ||
                _positiveMoney(venta['transferencia']) ||
                _positiveMoney(venta['credito'])) ...[
              const Text(
                'Formas de pago:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (_positiveMoney(venta['efectivo']))
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('Efectivo: ${_moneda(venta['efectivo']!)}'),
                ),
              if (_positiveMoney(venta['transferencia']))
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Transferencia: ${_moneda(venta['transferencia']!)}',
                  ),
                ),
              if (_positiveMoney(venta['credito']))
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('Crédito: ${_moneda(venta['credito']!)}'),
                ),
              const SizedBox(height: 8),
            ],
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${_moneda(venta['total']!)}',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resumenProductos(int ventaId) {
    final detalles = _detalles[ventaId] ?? const <Map<String, dynamic>>[];
    if (detalles.isEmpty) return 'Sin detalle de productos';
    final nombres = detalles
        .take(2)
        .map((item) => item['producto'].toString())
        .join(', ');
    final restantes = detalles.length - 2;
    return restantes > 0 ? '$nombres +$restantes mas' : nombres;
  }

  String _metodoPago(Map<String, dynamic> venta) {
    final id = (venta['metodo_pago_id'] as num?)?.toInt();
    if (id == null) return 'Metodo no registrado';
    return _metodosPago[id] ?? 'Metodo #$id';
  }

  String _nombreMetodo(List<Map<String, dynamic>> metodos, int id) {
    final metodo = metodos.firstWhere(
      (m) => (m['id'] as num).toInt() == id,
      orElse: () => {'nombre': 'DESCONOCIDO'},
    );
    return metodo['nombre'].toString();
  }

  String _moneda(Object valor) {
    if (valor is MoneyValue) return valor.format();
    final currency = _currency;
    if (currency == null) return 'Moneda no configurada';
    if (valor is int) {
      return MoneyValue.fromSql(valor, currency: currency).format();
    }
    return MoneyValue.fromMajorUnits(
      valor.toString(),
      currency: currency,
    ).format();
  }

  bool _positiveMoney(Object? value) {
    if (value is MoneyValue) return value.minorUnits > 0;
    if (value is int) return value > 0;
    return false;
  }

  String _cantidad(double valor) =>
      valor % 1 == 0 ? valor.toInt().toString() : valor.toString();

  double _impuestoSeleccionado(double value) {
    return _impuestosDisponibles.any((impuesto) => impuesto.rate == value)
        ? value
        : _impuestosDisponibles.first.rate;
  }

  String _formatearFecha(String iso) {
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
    if (!_datosCargados || _currency == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ventas')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final ventasVisibles = _ventas.where((venta) {
      final id = (venta['id'] as num).toInt();
      final texto =
          'factura pos $id ${venta['cliente'] ?? ''} ${_resumenProductos(id)} ${venta['fecha'] ?? ''}'
              .toLowerCase();
      if (!texto.contains(_busqueda.toLowerCase().trim())) return false;

      final estado = venta['estado']?.toString() ?? 'emitida';
      if (_filtroEstado == 'emitidas' && estado == 'anulada') return false;
      if (_filtroEstado == 'anuladas' && estado != 'anulada') return false;

      if (_filtroMetodo != 'todos') {
        final metodoId = (venta['metodo_pago_id'] as num?)?.toInt();
        final nombre = metodoId != null ? (_metodosPago[metodoId] ?? '') : '';
        if (!nombre.toLowerCase().contains(_filtroMetodo.toLowerCase())) {
          return false;
        }
      }

      final fechaStr = venta['fecha']?.toString() ?? '';
      if (fechaStr.isNotEmpty) {
        try {
          final fecha = DateTime.parse(fechaStr);
          if (_filtroDesde != null && fecha.isBefore(_filtroDesde!)) {
            return false;
          }
          if (_filtroHasta != null &&
              fecha.isAfter(_filtroHasta!.add(const Duration(days: 1)))) {
            return false;
          }
        } catch (_) {}
      }
      return true;
    }).toList();
    final zero = MoneyValue(minorUnits: 0, currency: _currency);
    final totalVisible = ventasVisibles.fold<MoneyValue>(
      zero,
      (sum, v) => sum + (v['total'] as MoneyValue),
    );
    final impuestoVisible = ventasVisibles.fold<MoneyValue>(
      zero,
      (sum, v) => sum + (v['impuesto_total'] as MoneyValue),
    );
    final anuladas = ventasVisibles
        .where(
          (venta) => (venta['estado']?.toString() ?? 'emitida') == 'anulada',
        )
        .length;
    final emitidas = ventasVisibles.length - anuladas;
    final ticketPromedio = emitidas == 0 ? zero : totalVisible / emitidas;
    final productosConStock = _productos
        .where((producto) => ((producto['stock'] as num?)?.toDouble() ?? 0) > 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventas'),
        actions: [
          IconButton(
            tooltip: 'Periféricos del POS',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PosPeripheralsPage())),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar ventas',
            onPressed: _cargarDatos,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: EnterpriseSpacing.sm),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewport = EnterpriseBreakpoints.fromWidth(
            constraints.maxWidth,
          );
          final padding = viewport.isMobile
              ? EnterpriseSpacing.md
              : EnterpriseSpacing.lg;

          return Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              children: [
                _VentasCommandPanel(
                  facturado: _moneda(
                    _busqueda.isEmpty ? (_totalVentas ?? zero) : totalVisible,
                  ),
                  impuesto: _moneda(impuestoVisible),
                  facturas: '${ventasVisibles.length}',
                  ticketPromedio: _moneda(ticketPromedio),
                  emitidas: emitidas,
                  anuladas: anuladas,
                  productosConStock: productosConStock,
                  cargado: _datosCargados,
                  onNewInvoice: _abrirFormulario,
                  onRefresh: _cargarDatos,
                ),
                const SizedBox(height: EnterpriseSpacing.md),
                _VentasToolbar(
                  controller: _busquedaController,
                  query: _busqueda,
                  onChanged: (value) => setState(() => _busqueda = value),
                  onClear: () {
                    _busquedaController.clear();
                    setState(() => _busqueda = '');
                  },
                  filtroEstado: _filtroEstado,
                  filtroMetodo: _filtroMetodo,
                  onEstado: (v) => setState(() => _filtroEstado = v),
                  onMetodo: (v) => setState(() => _filtroMetodo = v),
                  onFechaDesde: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _filtroDesde ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _filtroDesde = d);
                  },
                  onFechaHasta: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _filtroHasta ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (d != null) setState(() => _filtroHasta = d);
                  },
                  onLimpiarFiltros: () => setState(() {
                    _filtroEstado = 'todos';
                    _filtroMetodo = 'todos';
                    _filtroDesde = null;
                    _filtroHasta = null;
                  }),
                ),
                const SizedBox(height: EnterpriseSpacing.md),
                Expanded(
                  child: EnterprisePanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            EnterpriseSpacing.lg,
                            EnterpriseSpacing.md,
                            EnterpriseSpacing.lg,
                            EnterpriseSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.receipt_long,
                                color: AppBrand.warning,
                              ),
                              const SizedBox(width: EnterpriseSpacing.sm),
                              Expanded(
                                child: Text(
                                  'Facturas recientes',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              EnterpriseStatusPill(
                                icon: Icons.filter_list,
                                label: '${ventasVisibles.length} visibles',
                                color: AppBrand.info,
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        Expanded(
                          child: ventasVisibles.isEmpty
                              ? const _VentasEmptyState()
                              : ListView.separated(
                                  padding: const EdgeInsets.all(
                                    EnterpriseSpacing.md,
                                  ),
                                  itemCount: ventasVisibles.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(
                                        height: EnterpriseSpacing.sm,
                                      ),
                                  itemBuilder: (ctx, index) {
                                    final venta = ventasVisibles[index];
                                    final id = (venta['id'] as num).toInt();
                                    final totalRaw = venta['total'];
                                    final totalStr = totalRaw is MoneyValue
                                        ? totalRaw.format()
                                        : (totalRaw is num
                                            ? _moneda(totalRaw.toDouble())
                                            : totalRaw?.toString() ?? '$zero');
                                    final anulada =
                                        (venta['estado']?.toString() ??
                                            'emitida') ==
                                        'anulada';

                                    return _VentaTile(
                                      id: id,
                                      cliente:
                                          venta['cliente']?.toString() ??
                                          'Cliente general',
                                      fecha: _formatearFecha(
                                        venta['fecha']?.toString() ?? '',
                                      ),
                                      resumen: _resumenProductos(id),
                                      metodoPago: _metodoPago(venta),
                                      total: totalStr,
                                      anulada: anulada,
                                      onTap: () => _mostrarDetalle(venta),
                                      onCancel: anulada
                                          ? null
                                          : () => _anularVenta(venta),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _VentasCommandPanel extends StatelessWidget {
  const _VentasCommandPanel({
    required this.facturado,
    required this.impuesto,
    required this.facturas,
    required this.ticketPromedio,
    required this.emitidas,
    required this.anuladas,
    required this.productosConStock,
    required this.cargado,
    required this.onNewInvoice,
    required this.onRefresh,
  });

  final String facturado;
  final String impuesto;
  final String facturas;
  final String ticketPromedio;
  final int emitidas;
  final int anuladas;
  final int productosConStock;
  final bool cargado;
  final VoidCallback onNewInvoice;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return EnterprisePanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final isMobile = constraints.maxWidth < 600;

          // En móvil, mostrar menos métricas
          final metrics = isMobile
              ? [
                  _VentasMetric(
                    'Facturado',
                    facturado,
                    Icons.payments,
                    AppBrand.success,
                  ),
                  _VentasMetric(
                    'Facturas',
                    facturas,
                    Icons.receipt_long,
                    AppBrand.warning,
                  ),
                ]
              : [
                  _VentasMetric(
                    'Facturado',
                    facturado,
                    Icons.payments,
                    AppBrand.success,
                  ),
                  _VentasMetric(
                    'Impuesto',
                    impuesto,
                    Icons.percent,
                    AppBrand.info,
                  ),
                  _VentasMetric(
                    'Facturas',
                    facturas,
                    Icons.receipt_long,
                    AppBrand.warning,
                  ),
                  _VentasMetric(
                    'Ticket promedio',
                    ticketPromedio,
                    Icons.trending_up,
                    AppBrand.secondary,
                  ),
                ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppBrand.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
                      ),
                      child: const Icon(
                        Icons.point_of_sale,
                        color: AppBrand.warning,
                      ),
                    ),
                    const SizedBox(width: EnterpriseSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Punto de venta',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'Emision POS, anulaciones, impuestos y detalle por producto en una sola bandeja.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      IconButton(
                        tooltip: 'Actualizar ventas',
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      const SizedBox(width: EnterpriseSpacing.sm),
                      FilledButton.icon(
                        onPressed: onNewInvoice,
                        icon: const Icon(Icons.add_card),
                        label: const Text('Nueva factura'),
                      ),
                    ],
                  ],
                ),
              ],
              if (compact) ...[
                const SizedBox(height: EnterpriseSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onNewInvoice,
                        icon: const Icon(Icons.add_card, size: 18),
                        label: const Text(
                          'Nueva',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: EnterpriseSpacing.sm),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh, size: 20),
                      padding: const EdgeInsets.all(8),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: EnterpriseSpacing.sm),
              Wrap(
                spacing: EnterpriseSpacing.sm,
                runSpacing: EnterpriseSpacing.sm,
                children: [
                  EnterpriseStatusPill(
                    icon: Icons.receipt_long,
                    label: isMobile
                        ? '$emitidas emitidas'
                        : '$emitidas emitidas, $anuladas anuladas',
                    color: AppBrand.info,
                  ),
                  EnterpriseStatusPill(
                    icon: Icons.inventory,
                    label: isMobile
                        ? '$productosConStock productos'
                        : '$productosConStock productos con stock',
                    color: AppBrand.success,
                  ),
                  if (!isMobile)
                    EnterpriseStatusPill(
                      icon: Icons.trending_up,
                      label: 'Ticket promedio $ticketPromedio',
                      color: AppBrand.secondary,
                    ),
                ],
              ),
              const SizedBox(height: EnterpriseSpacing.sm),
              LayoutBuilder(
                builder: (context, grid) {
                  final columns = grid.maxWidth >= 1100
                      ? 4
                      : grid.maxWidth >= 800
                      ? 2
                      : isMobile
                      ? 2
                      : 3;
                  final width =
                      (grid.maxWidth - ((columns - 1) * EnterpriseSpacing.sm)) /
                      columns;
                  return Wrap(
                    spacing: EnterpriseSpacing.sm,
                    runSpacing: EnterpriseSpacing.sm,
                    children: [
                      for (final metric in metrics)
                        SizedBox(
                          width: width,
                          child: _VentasMetricTile(metric: metric),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VentasToolbar extends StatelessWidget {
  const _VentasToolbar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    required this.filtroEstado,
    required this.filtroMetodo,
    required this.onEstado,
    required this.onMetodo,
    required this.onFechaDesde,
    required this.onFechaHasta,
    required this.onLimpiarFiltros,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String filtroEstado;
  final String filtroMetodo;
  final ValueChanged<String> onEstado;
  final ValueChanged<String> onMetodo;
  final VoidCallback onFechaDesde;
  final VoidCallback onFechaHasta;
  final VoidCallback onLimpiarFiltros;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.manage_search),
            labelText: 'Buscar factura, cliente, producto o fecha',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar busqueda',
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('Emitidas'),
                selected: filtroEstado == 'emitidas',
                onSelected: (_) =>
                    onEstado(filtroEstado == 'emitidas' ? 'todos' : 'emitidas'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Anuladas'),
                selected: filtroEstado == 'anuladas',
                onSelected: (_) =>
                    onEstado(filtroEstado == 'anuladas' ? 'todos' : 'anuladas'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Efectivo'),
                selected: filtroMetodo == 'efectivo',
                onSelected: (_) =>
                    onMetodo(filtroMetodo == 'efectivo' ? 'todos' : 'efectivo'),
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Pago mixto'),
                selected: filtroMetodo == 'mixto',
                onSelected: (_) =>
                    onMetodo(filtroMetodo == 'mixto' ? 'todos' : 'mixto'),
              ),
              const SizedBox(width: 6),
              ActionChip(label: const Text('Desde'), onPressed: onFechaDesde),
              const SizedBox(width: 6),
              ActionChip(label: const Text('Hasta'), onPressed: onFechaHasta),
              const SizedBox(width: 6),
              ActionChip(
                label: const Text('Limpiar filtros'),
                onPressed: onLimpiarFiltros,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VentaTile extends StatelessWidget {
  const _VentaTile({
    required this.id,
    required this.cliente,
    required this.fecha,
    required this.resumen,
    required this.metodoPago,
    required this.total,
    required this.anulada,
    required this.onTap,
    required this.onCancel,
  });

  final int id;
  final String cliente;
  final String fecha;
  final String resumen;
  final String metodoPago;
  final String total;
  final bool anulada;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // En tema oscuro (navy) los tokens fijos de éxito/error son demasiado oscuros
    // y generan bajo contraste. Se usan versiones más brillantes adaptadas al tema.
    final successColor = isDark ? MerkaThemeTokens.success : AppBrand.success;
    final errorColor = isDark ? MerkaThemeTokens.danger : AppBrand.error;
    final warningColor = isDark ? MerkaThemeTokens.warning : AppBrand.warning;
    final accent = anulada ? errorColor : warningColor;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outline.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EnterpriseSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(EnterpriseRadii.md),
                ),
                child: Icon(Icons.receipt_long, color: accent),
              ),
              const SizedBox(width: EnterpriseSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: EnterpriseSpacing.sm,
                      runSpacing: EnterpriseSpacing.xs,
                      children: [
                        Text(
                          'Factura POS #$id',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        EnterpriseStatusPill(
                          icon: anulada ? Icons.block : Icons.check,
                          label: anulada ? 'Anulada' : 'Emitida',
                          color: anulada ? errorColor : successColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: EnterpriseSpacing.xs),
                    Text(
                      '$cliente | $fecha',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '$resumen | $metodoPago',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: EnterpriseSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 128),
                child: Text(
                  total,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: anulada ? errorColor : successColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.undo),
                color: errorColor,
                tooltip: 'Anular factura',
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VentasMetric {
  const _VentasMetric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _VentasMetricTile extends StatelessWidget {
  const _VentasMetricTile({required this.metric});

  final _VentasMetric metric;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(EnterpriseSpacing.md),
      decoration: BoxDecoration(
        color: metric.color.withValues(alpha: 0.08),
        border: Border.all(color: metric.color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: Row(
        children: [
          Icon(metric.icon, color: metric.color),
          const SizedBox(width: EnterpriseSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VentasEmptyState extends StatelessWidget {
  const _VentasEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EnterpriseSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long, size: 42, color: AppBrand.muted),
            const SizedBox(height: EnterpriseSpacing.sm),
            Text(
              'No hay facturas para mostrar.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              'Crea una factura o ajusta la busqueda para ver resultados.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

MoneyValue _moneyInput(String input, Currency currency) {
  final normalized = input.trim().isEmpty ? '0' : input.replaceAll(',', '.');
  return MoneyValue.fromMajorUnits(normalized, currency: currency);
}

/// Convierte cualquier representación de precio proveniente de un Map de BD
/// a un string de major units listo para mostrar en un [TextField].
///
/// - [MoneyValue]  → ya hidratado, usa [MoneyValue.toMajorUnitsString].
/// - [int]         → minor units post-v75 (ej. 1000 centavos → "10.00").
/// - [double]      → minor units con decimales de BD pre-v75 (truncado).
/// - cualquier otro → "0".
///
/// Esta función es el punto único de conversión entre la representación
/// de almacenamiento (centavos) y la representación de presentación (pesos)
/// en el campo de precio unitario editable del POS.
String _priceToDisplay(Object? value, Currency currency) {
  if (value == null) return '0';
  if (value is MoneyValue) return value.toMajorUnitsString();
  if (value is int) {
    return MoneyValue(minorUnits: value, currency: currency)
        .toMajorUnitsString();
  }
  if (value is double) {
    // BD pre-v75: columna REAL → double. Se trunca igual que fromSql.
    return MoneyValue(minorUnits: value.round(), currency: currency)
        .toMajorUnitsString();
  }
  return '0';
}

class _CarritoVenta extends StatelessWidget {
  const _CarritoVenta({
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
          color: MerkaThemeTokens.paper100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Agrega productos para emitir la factura.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detalle de la factura',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final cantidad = (item['cantidad'] as num).toDouble();
          final precio = item['precio'] as MoneyValue;
          final subtotal = item['subtotal'] as MoneyValue;
          final impuestoPct = (item['impuesto_pct'] as num?)?.toDouble() ?? 0;
          final ubicacion = _ubicacionProducto(item);
          final lote = item['codigo_lote']?.toString().trim() ?? '';
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
            subtitle: Text(
              [
                '$cant x ${moneda(precio)} | IVA ${_fmtPct(impuestoPct)}%',
                if (ubicacion.isNotEmpty) 'Ubicacion $ubicacion',
                if (lote.isNotEmpty) 'Lote $lote',
              ].join(' | '),
            ),
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

String _fmtPct(double value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();

String _ubicacionProducto(Map<String, dynamic> item) {
  final codigo = item['ubicacion_codigo']?.toString().trim() ?? '';
  if (codigo.isNotEmpty) return codigo;
  return [
    item['ubicacion_pasillo']?.toString() ?? '',
    item['ubicacion_estante']?.toString() ?? '',
    item['ubicacion_nivel']?.toString() ?? '',
  ].where((part) => part.trim().isNotEmpty).join('-');
}
