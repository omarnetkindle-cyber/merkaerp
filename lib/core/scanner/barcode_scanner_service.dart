// ============================================================
// barcode_scanner_service.dart
// Servicio de escaneo de códigos de barras y QR
// ============================================================


class BarcodeScannerService {
  static final BarcodeScannerService instance = BarcodeScannerService._internal();
  
  BarcodeScannerService._internal();
  
  /// Valida si un código de barras es válido
  bool isValidBarcode(String barcode) {
    if (barcode.isEmpty) return false;
    
    // Validar EAN-13 (13 dígitos)
    if (barcode.length == 13 && _isValidEAN13(barcode)) {
      return true;
    }
    
    // Validar EAN-8 (8 dígitos)
    if (barcode.length == 8 && _isValidEAN8(barcode)) {
      return true;
    }
    
    // Validar UPC-A (12 dígitos)
    if (barcode.length == 12 && _isValidUPCA(barcode)) {
      return true;
    }
    
    // Validar Code 128 (alfanumérico)
    if (_isValidCode128(barcode)) {
      return true;
    }
    
    // Aceptar códigos QR (cualquier longitud)
    if (barcode.isNotEmpty) {
      return true;
    }
    
    return false;
  }
  
  /// Valida checksum de EAN-13
  bool _isValidEAN13(String barcode) {
    if (!RegExp(r'^\d{13}$').hasMatch(barcode)) return false;
    
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    
    final checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(barcode[12]);
  }
  
  /// Valida checksum de EAN-8
  bool _isValidEAN8(String barcode) {
    if (!RegExp(r'^\d{8}$').hasMatch(barcode)) return false;
    
    int sum = 0;
    for (int i = 0; i < 7; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }
    
    final checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(barcode[7]);
  }
  
  /// Valida checksum de UPC-A
  bool _isValidUPCA(String barcode) {
    if (!RegExp(r'^\d{12}$').hasMatch(barcode)) return false;
    
    int sum = 0;
    for (int i = 0; i < 11; i++) {
      final digit = int.parse(barcode[i]);
      sum += (i % 2 == 0) ? digit * 3 : digit;
    }
    
    final checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(barcode[11]);
  }
  
  /// Valida Code 128 (alfanumérico)
  bool _isValidCode128(String barcode) {
    return RegExp(r'^[A-Za-z0-9\s\-\.]+$').hasMatch(barcode) && barcode.isNotEmpty;
  }
  
  /// Determina el tipo de código de barras
  String getBarcodeType(String barcode) {
    if (barcode.length == 13 && _isValidEAN13(barcode)) {
      return 'EAN-13';
    } else if (barcode.length == 8 && _isValidEAN8(barcode)) {
      return 'EAN-8';
    } else if (barcode.length == 12 && _isValidUPCA(barcode)) {
      return 'UPC-A';
    } else if (_isValidCode128(barcode)) {
      return 'Code 128';
    } else if (barcode.startsWith('http://') || barcode.startsWith('https://')) {
      return 'QR URL';
    } else if (barcode.length > 20) {
      return 'QR Data';
    } else {
      return 'Unknown';
    }
  }
  
  /// Formatea el código de barras para visualización
  String formatBarcode(String barcode) {
    final type = getBarcodeType(barcode);
    
    switch (type) {
      case 'EAN-13':
        return '${barcode.substring(0, 1)} ${barcode.substring(1, 7)} ${barcode.substring(7)}';
      case 'EAN-8':
        return '${barcode.substring(0, 4)} ${barcode.substring(4)}';
      case 'UPC-A':
        return '${barcode.substring(0, 1)} ${barcode.substring(1, 6)} ${barcode.substring(6, 11)} ${barcode.substring(11)}';
      default:
        return barcode;
    }
  }
  
  /// Extrae información de un código QR
  Map<String, dynamic> parseQRCode(String qrData) {
    final result = <String, dynamic>{
      'raw': qrData,
      'type': 'unknown',
      'data': <String, dynamic>{},
    };
    
    // URL
    if (qrData.startsWith('http://') || qrData.startsWith('https://')) {
      result['type'] = 'url';
      result['data'] = {'url': qrData};
    }
    
    // JSON
    else if (qrData.startsWith('{') && qrData.endsWith('}')) {
      try {
        final jsonData = _parseJson(qrData);
        result['type'] = 'json';
        result['data'] = jsonData;
      } catch (e) {
        // No es JSON válido
      }
    }
    
    // Formato clave:valor
    else if (qrData.contains(':')) {
      final parts = qrData.split(':');
      if (parts.length == 2) {
        result['type'] = 'key_value';
        result['data'] = {
          'key': parts[0].trim(),
          'value': parts[1].trim(),
        };
      }
    }
    
    // Texto plano
    else {
      result['type'] = 'text';
      result['data'] = {'text': qrData};
    }
    
    return result;
  }
  
  /// Parsea JSON de forma segura
  Map<String, dynamic> _parseJson(String jsonString) {
    final parts = jsonString.split(',');
    final result = <String, dynamic>{};
    
    for (final part in parts) {
      final keyValue = part.split(':');
      if (keyValue.length == 2) {
        final key = keyValue[0].replaceAll(RegExp(r'[{}"]'), '').trim();
        final value = keyValue[1].replaceAll(RegExp(r'["}]'), '').trim();
        result[key] = value;
      }
    }
    
    return result;
  }
  
  /// Genera un código de barras para un producto
  String generateProductBarcode(int productId, {String prefix = 'PRD'}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = (timestamp % 10000).toString().padLeft(4, '0');
    return '$prefix${productId.toString().padLeft(6, '0')}$randomPart';
  }
}
