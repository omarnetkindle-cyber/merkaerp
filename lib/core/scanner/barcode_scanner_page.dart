// ============================================================
// barcode_scanner_page.dart
// Página de escaneo de códigos de barras y QR
// ============================================================

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'barcode_scanner_service.dart';

class BarcodeScannerPage extends StatefulWidget {
  final Function(String barcode)? onBarcodeScanned;
  final String? title;

  const BarcodeScannerPage({
    super.key,
    this.onBarcodeScanned,
    this.title,
  });

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  final BarcodeScannerService _scannerService = BarcodeScannerService.instance;
  final MobileScannerController _controller = MobileScannerController();
  
  bool _isScanning = true;
  String? _lastScannedBarcode;
  String? _lastScannedType;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!;
    
    // Validar código
    if (_scannerService.isValidBarcode(rawValue)) {
      setState(() {
        _isScanning = false;
        _lastScannedBarcode = rawValue;
        _lastScannedType = _scannerService.getBarcodeType(rawValue);
      });

      // Vibración de feedback
      // HapticFeedback.lightImpact();

      if (widget.onBarcodeScanned != null) {
        widget.onBarcodeScanned!(rawValue);
      }

      // Reanudar escaneo después de 2 segundos
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isScanning = true;
          });
        }
      });
    }
  }

  void _toggleCamera() {
    _controller.switchCamera();
  }

  void _toggleFlash() {
    _controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Escáner de Códigos'),
        actions: [
          IconButton(
            tooltip: 'Cambiar cámara',
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: _toggleCamera,
          ),
          IconButton(
            tooltip: 'Encender o apagar flash',
            icon: const Icon(Icons.flash_on),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              overlay: _buildOverlay(),
            ),
          ),
          if (_lastScannedBarcode != null) _buildScannedResult(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return Stack(
      children: [
        // Marco de escaneo
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 2,
                  color: Colors.red,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Escanea el código',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Esquinas decorativas
        Positioned(
          top: MediaQuery.of(context).size.height * 0.3,
          left: 20,
          child: _buildCorner(),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.3,
          right: 20,
          child: _buildCorner(mirror: true),
        ),
        Positioned(
          bottom: MediaQuery.of(context).size.height * 0.3,
          left: 20,
          child: _buildCorner(vertical: true),
        ),
        Positioned(
          bottom: MediaQuery.of(context).size.height * 0.3,
          right: 20,
          child: _buildCorner(mirror: true, vertical: true),
        ),
      ],
    );
  }

  Widget _buildCorner({bool mirror = false, bool vertical = false}) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white, width: 3),
          left: BorderSide(color: Colors.white, width: 3),
          bottom: vertical ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
          right: mirror ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildScannedResult() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black87,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Código escaneado',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tipo: $_lastScannedType',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            _scannerService.formatBarcode(_lastScannedBarcode!),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isScanning = true;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Escanear otro'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context, _lastScannedBarcode);
                },
                icon: const Icon(Icons.check),
                label: const Text('Aceptar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
