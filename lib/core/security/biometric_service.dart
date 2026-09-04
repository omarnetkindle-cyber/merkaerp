// ============================================================
// biometric_service.dart
// Servicio de autenticación biométrica
// ============================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService {
  static final BiometricService instance = BiometricService._internal();
  
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricUserIdKey = 'biometric_user_id';
  
  BiometricService._internal();
  
  /// Verifica si el dispositivo soporta autenticación biométrica
  Future<bool> isDeviceSupported() async {
    final isSupported = await _localAuth.canCheckBiometrics;
    if (!isSupported) return false;
    
    // Verificar si hay biométricos disponibles
    final availableBiometrics = await _localAuth.getAvailableBiometrics();
    return availableBiometrics.isNotEmpty;
  }
  
  /// Obtiene los tipos de biometría disponibles
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Error getting available biometrics: $e');
      return [];
    }
  }
  
  /// Autentica al usuario usando biometría
  Future<bool> authenticate({
    String localizedReason = 'Por favor autentícate para continuar',
  }) async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: localizedReason,
      );
      return isAuthenticated;
    } catch (e) {
      debugPrint('Biometric authentication error: $e');
      return false;
    }
  }
  
  /// Habilita autenticación biométrica para un usuario
  Future<bool> enableBiometric(String userId) async {
    try {
      // Primero verificar que el dispositivo soporta biometría
      if (!await isDeviceSupported()) {
        return false;
      }
      
      // Solicitar autenticación inicial para confirmar
      final authenticated = await authenticate(
        localizedReason: 'Habilita autenticación biométrica para acceso rápido',
      );
      
      if (!authenticated) return false;
      
      // Guardar configuración
      await _secureStorage.write(key: _biometricEnabledKey, value: 'true');
      await _secureStorage.write(key: _biometricUserIdKey, value: userId);
      
      return true;
    } catch (e) {
      debugPrint('Error enabling biometric: $e');
      return false;
    }
  }
  
  /// Deshabilita autenticación biométrica
  Future<void> disableBiometric() async {
    try {
      await _secureStorage.delete(key: _biometricEnabledKey);
      await _secureStorage.delete(key: _biometricUserIdKey);
    } catch (e) {
      debugPrint('Error disabling biometric: $e');
    }
  }
  
  /// Verifica si la autenticación biométrica está habilitada
  Future<bool> isBiometricEnabled() async {
    try {
      final enabled = await _secureStorage.read(key: _biometricEnabledKey);
      return enabled == 'true';
    } catch (e) {
      debugPrint('Error checking biometric enabled: $e');
      return false;
    }
  }
  
  /// Obtiene el ID de usuario asociado a la biometría
  Future<String?> getBiometricUserId() async {
    try {
      return await _secureStorage.read(key: _biometricUserIdKey);
    } catch (e) {
      debugPrint('Error getting biometric user ID: $e');
      return null;
    }
  }
  
  /// Cancela autenticación en curso
  Future<void> cancelAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      debugPrint('Error cancelling authentication: $e');
    }
  }
  
  /// Verifica si es iOS (Face ID) o Android (fingerprint)
  bool get isIOS => Platform.isIOS;
  bool get isAndroid => Platform.isAndroid;
  
  /// Obtiene el mensaje apropiado según el tipo de biometría
  Future<String> getBiometricTypeMessage() async {
    final available = await getAvailableBiometrics();
    
    if (available.contains(BiometricType.face)) {
      return 'Usa Face ID para autenticarte';
    } else if (available.contains(BiometricType.fingerprint)) {
      return 'Usa tu huella digital para autenticarte';
    } else if (available.contains(BiometricType.iris)) {
      return 'Usa el escáner de iris para autenticarte';
    } else if (available.contains(BiometricType.strong)) {
      return 'Usa autenticación fuerte para continuar';
    } else {
      return 'Usa autenticación biométrica para continuar';
    }
  }
}
