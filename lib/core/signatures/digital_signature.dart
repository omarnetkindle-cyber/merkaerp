// ============================================================
// digital_signature.dart
// Servicio de firmas digitales de usuario
// ============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DigitalSignature {
  final String id;
  final String userId;
  final String userName;
  final Uint8List signatureData;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DigitalSignature({
    required this.id,
    required this.userId,
    required this.userName,
    required this.signatureData,
    required this.createdAt,
    this.updatedAt,
  });

  DigitalSignature copyWith({
    String? id,
    String? userId,
    String? userName,
    Uint8List? signatureData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DigitalSignature(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      signatureData: signatureData ?? this.signatureData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'signature_data': base64Encode(signatureData),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory DigitalSignature.fromMap(Map<String, dynamic> map) {
    return DigitalSignature(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      userName: map['user_name'] as String,
      signatureData: base64Decode(map['signature_data'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}

class DigitalSignatureService {
  static final DigitalSignatureService instance = DigitalSignatureService._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  DigitalSignatureService._internal();
  
  /// Guarda una firma digital
  Future<void> saveSignature(DigitalSignature signature) async {
    final key = 'signature_${signature.userId}';
    await _secureStorage.write(
      key: key,
      value: jsonEncode(signature.toMap()),
    );
  }
  
  /// Obtiene la firma de un usuario
  Future<DigitalSignature?> getSignature(String userId) async {
    final key = 'signature_$userId';
    final data = await _secureStorage.read(key: key);
    
    if (data == null) return null;
    
    try {
      final map = jsonDecode(data) as Map<String, dynamic>;
      return DigitalSignature.fromMap(map);
    } catch (e) {
      return null;
    }
  }
  
  /// Elimina la firma de un usuario
  Future<void> deleteSignature(String userId) async {
    final key = 'signature_$userId';
    await _secureStorage.delete(key: key);
  }
  
  /// Verifica si un usuario tiene firma guardada
  Future<bool> hasSignature(String userId) async {
    final signature = await getSignature(userId);
    return signature != null;
  }
  
  /// Convierte datos de firma a base64
  String signatureToBase64(Uint8List signatureData) {
    return base64Encode(signatureData);
  }
  
  /// Convierte base64 a datos de firma
  Uint8List base64ToSignature(String base64Data) {
    return base64Decode(base64Data);
  }
  
  /// Valida que los datos de firma no estén vacíos
  bool isValidSignatureData(Uint8List data) {
    return data.isNotEmpty && data.length > 100; // Mínimo de bytes razonable
  }
  
  /// Obtiene todas las firmas guardadas
  Future<List<String>> getAllSignatureUserIds() async {
    // Nota: FlutterSecureStorage no permite listar todas las claves
    // Esta es una implementación limitada
    return [];
  }
}
