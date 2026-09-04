import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

class HardwareFingerprintService {
  static final HardwareFingerprintService _instance =
      HardwareFingerprintService._internal();
  factory HardwareFingerprintService() => _instance;
  HardwareFingerprintService._internal();

  String? _cachedFingerprint;

  /// Genera el fingerprint del hardware actual.
  ///
  /// El material crudo incluye hostname, SO, MAC y seriales/UUID locales cuando
  /// la plataforma los expone. Solo se retorna SHA-256; Control Center nunca
  /// recibe esos identificadores en claro.
  Future<String> generateFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    try {
      final deviceInfo = DeviceInfoPlugin();
      String fingerprintData = '';

      if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        fingerprintData = await _generateWindowsFingerprint(windowsInfo);
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        fingerprintData = _generateAndroidFingerprint(androidInfo);
      } else {
        // Fallback para otras plataformas
        fingerprintData = _generateGenericFingerprint();
      }

      // Generar hash SHA-256 del fingerprint
      final bytes = utf8.encode(fingerprintData);
      final hash = sha256.convert(bytes);

      _cachedFingerprint = hash.toString();
      return _cachedFingerprint!;
    } catch (e) {
      // Fallback en caso de error
      return _generateFallbackFingerprint();
    }
  }

  /// Genera fingerprint específico para Windows
  Future<String> _generateWindowsFingerprint(
    WindowsDeviceInfo windowsInfo,
  ) async {
    final windowsHardware = await _windowsHardwareIdentifiers();
    final macs = await _macAddresses();
    final components = [
      'os:${Platform.operatingSystem}',
      'version:${Platform.operatingSystemVersion}',
      'hostname:${Platform.localHostname}',
      windowsInfo.computerName,
      windowsInfo.numberOfCores.toString(),
      windowsInfo.systemMemoryInMegabytes.toString(),
      ...windowsHardware,
      ...macs,
    ];

    return _normalizeComponents(components).join('|');
  }

  /// Genera fingerprint específico para Android
  String _generateAndroidFingerprint(AndroidDeviceInfo androidInfo) {
    final components = [
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      Platform.localHostname,
      androidInfo.id,
      androidInfo.brand,
      androidInfo.model,
      androidInfo.board,
    ];

    return _normalizeComponents(components).join('|');
  }

  /// Genera fingerprint genérico para otras plataformas
  String _generateGenericFingerprint() {
    final components = [
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      Platform.localHostname,
      Platform.numberOfProcessors.toString(),
    ];

    return _normalizeComponents(components).join('|');
  }

  /// Genera fingerprint de fallback en caso de error
  String _generateFallbackFingerprint() {
    final components = [
      Platform.localHostname,
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      Platform.numberOfProcessors.toString(),
    ];

    final bytes = utf8.encode(components.join('|'));
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Valida si el fingerprint actual coincide con uno almacenado
  Future<bool> validateFingerprint(String storedFingerprint) async {
    final currentFingerprint = await generateFingerprint();
    return currentFingerprint == storedFingerprint;
  }

  /// Genera un UUID basado en el fingerprint (para compatibilidad con sistemas existentes)
  Future<String> generateUUID() async {
    final fingerprint = await generateFingerprint();
    // Convertir el hash a formato UUID-like
    final hash = fingerprint.substring(0, 32);
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-${hash.substring(12, 16)}-${hash.substring(16, 20)}-${hash.substring(20, 32)}'
        .toUpperCase();
  }

  /// Obtiene información del hardware para debugging
  Future<Map<String, dynamic>> getHardwareInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return {
        'platform': 'Windows',
        'computerName': windowsInfo.computerName,
        'numberOfCores': windowsInfo.numberOfCores,
        'systemMemoryInMegabytes': windowsInfo.systemMemoryInMegabytes,
        'productName': windowsInfo.productName,
        'userName': windowsInfo.userName,
      };
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return {
        'platform': 'Android',
        'brand': androidInfo.brand,
        'model': androidInfo.model,
        'board': androidInfo.board,
        'bootloader': androidInfo.bootloader,
        'supportedAbis': androidInfo.supportedAbis,
      };
    } else {
      return {
        'platform': Platform.operatingSystem,
        'hostname': Platform.localHostname,
        'numberOfProcessors': Platform.numberOfProcessors,
      };
    }
  }

  Future<List<String>> _windowsHardwareIdentifiers() async {
    if (!Platform.isWindows) return const [];
    const script = r'''
$ErrorActionPreference = "SilentlyContinue"
$bios = (Get-CimInstance Win32_BIOS).SerialNumber
$board = (Get-CimInstance Win32_BaseBoard).SerialNumber
$computer = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$disk = (Get-CimInstance Win32_DiskDrive | Select-Object -First 1).SerialNumber
$macs = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.MACAddress } | Select-Object -ExpandProperty MACAddress
@($bios, $board, $computer, $disk) + $macs | ForEach-Object { if ($_ -and $_.Trim()) { $_.Trim() } }
''';
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return const [];
      return LineSplitter.split(result.stdout.toString())
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) => 'hw:$line')
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _macAddresses() async => const [];

  List<String> _normalizeComponents(Iterable<String> components) {
    return components
        .map((component) => component.trim().toLowerCase())
        .where((component) => component.isNotEmpty)
        .toList();
  }
}
