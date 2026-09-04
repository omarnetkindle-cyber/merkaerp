import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db_helper.dart';

class BarcodeScannerService {
  BarcodeScannerService._privateConstructor();
  
  static final BarcodeScannerService _instance = BarcodeScannerService._privateConstructor();
  factory BarcodeScannerService() => _instance;

  final _buffer = StringBuffer();
  DateTime? _lastKeystrokeTime;
  Timer? _bufferResetTimer;
  
  // Callback para cuando se detecta un código de barras
  Function(String barcode)? _onBarcodeDetected;

  // Configuración del escáner
  static const int _keystrokeTimeoutMs = 50; // Tiempo máximo entre teclas para considerar ráfaga
  static const int _bufferResetDelayMs = 100; // Tiempo para limpiar el buffer si no hay actividad

  /// Inicializa el escáner con un callback
  void initialize(Function(String barcode) onBarcodeDetected) {
    _onBarcodeDetected = onBarcodeDetected;
    RawKeyboard.instance.addListener(_handleKeyEvent);
  }

  /// Detiene el escáner
  void dispose() {
    RawKeyboard.instance.removeListener(_handleKeyEvent);
    _bufferResetTimer?.cancel();
    _buffer.clear();
  }

  void _handleKeyEvent(RawKeyEvent event) {
    // Solo procesar eventos de tecla presionada (no liberación)
    if (event is! RawKeyDownEvent) return;

    // Ignorar teclas de modificación (Ctrl, Alt, Shift, etc.)
    if (_isModifierKey(event.logicalKey)) return;

    final now = DateTime.now();
    final keystroke = event.logicalKey.keyLabel;

    // Verificar si es una ráfaga de teclas (escáner de códigos de barras)
    if (_lastKeystrokeTime != null) {
      final timeSinceLastKeystroke = now.difference(_lastKeystrokeTime!).inMilliseconds;
      
      // Si el tiempo entre teclas es mayor al timeout, limpiar el buffer
      if (timeSinceLastKeystroke > _keystrokeTimeoutMs) {
        _buffer.clear();
      }
    }

    _lastKeystrokeTime = now;

    // Reiniciar el timer de limpieza del buffer
    _bufferResetTimer?.cancel();
    _bufferResetTimer = Timer(const Duration(milliseconds: _bufferResetDelayMs), () {
      _buffer.clear();
      _lastKeystrokeTime = null;
    });

    // Si es Enter, procesar el código de barras
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.isNotEmpty) {
        final barcode = _buffer.toString();
        _buffer.clear();
        _lastKeystrokeTime = null;
        _bufferResetTimer?.cancel();
        
        // Invocar el callback con el código detectado
        if (_onBarcodeDetected != null) {
          _onBarcodeDetected!(barcode);
        }
      }
    } else {
      // Agregar la tecla al buffer
      if (keystroke.isNotEmpty) {
        _buffer.write(keystroke);
      }
    }
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.control ||
           key == LogicalKeyboardKey.alt ||
           key == LogicalKeyboardKey.shift ||
           key == LogicalKeyboardKey.meta ||
           key == LogicalKeyboardKey.capsLock ||
           key == LogicalKeyboardKey.numLock ||
           key == LogicalKeyboardKey.scrollLock;
  }

  /// Busca un producto por código de barras o SKU
  Future<Map<String, dynamic>?> buscarProductoPorBarcode(String barcode) async {
    try {
      final dbHelper = DatabaseHelper.instance;
      final db = await dbHelper.database;
      final companyId = await dbHelper.obtenerEmpresaActivaId();
      
      // Buscar por código de barras exacto
      final productos = await db.query(
        'productos',
        where: 'company_id = ? AND (codigo_barras = ? OR nombre = ?)',
        whereArgs: [companyId, barcode, barcode],
        limit: 1,
      );
      
      if (productos.isNotEmpty) {
        return productos.first;
      }
      
      return null;
    } catch (e) {
      print('Error al buscar producto: $e');
      return null;
    }
  }
}

/// Widget que integra el escáner de códigos de barras en el POS
class BarcodeScannerListener extends StatefulWidget {
  final Widget child;
  final Function(String barcode, Map<String, dynamic>? producto) onBarcodeScanned;

  const BarcodeScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
  });

  @override
  State<BarcodeScannerListener> createState() => _BarcodeScannerListenerState();
}

class _BarcodeScannerListenerState extends State<BarcodeScannerListener> {
  final BarcodeScannerService _scannerService = BarcodeScannerService();

  @override
  void initState() {
    super.initState();
    _scannerService.initialize(_handleBarcodeDetected);
  }

  @override
  void dispose() {
    _scannerService.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetected(String barcode) async {
    // Buscar el producto por código de barras
    final producto = await _scannerService.buscarProductoPorBarcode(barcode);
    
    // Invocar el callback con el código y el producto encontrado (o null)
    if (mounted) {
      widget.onBarcodeScanned(barcode, producto);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Mixin para agregar funcionalidad de escáner a cualquier widget
mixin BarcodeScannerMixin<T extends StatefulWidget> on State<T> {
  final BarcodeScannerService _scannerService = BarcodeScannerService();

  @override
  void initState() {
    super.initState();
    _scannerService.initialize(_handleBarcodeDetected);
  }

  @override
  void dispose() {
    _scannerService.dispose();
    super.dispose();
  }

  void handleBarcodeDetected(String barcode, Map<String, dynamic>? producto) {
    // Método para sobreescribir en el widget que usa el mixin
  }

  void _handleBarcodeDetected(String barcode) async {
    final producto = await _scannerService.buscarProductoPorBarcode(barcode);
    if (mounted) {
      handleBarcodeDetected(barcode, producto);
    }
  }
}
