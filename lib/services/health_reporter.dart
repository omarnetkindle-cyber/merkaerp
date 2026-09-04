import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../db_helper.dart';
import '../core/backup/full_backup_service.dart';
import '../core/app/app_version.dart';
import 'licencia_service.dart';

enum NivelAlerta { info, advertencia, critico }

class AlertaSalud {
  const AlertaSalud({
    required this.nivel,
    required this.tipo,
    required this.mensaje,
    required this.timestamp,
    this.metrica,
    this.valorActual,
    this.valorLimite,
  });

  final NivelAlerta nivel;
  final String tipo;
  final String mensaje;
  final DateTime timestamp;
  final String? metrica;
  final double? valorActual;
  final double? valorLimite;

  Map<String, dynamic> toJson() {
    return {
      'nivel': nivel.name,
      'tipo': tipo,
      'mensaje': mensaje,
      'timestamp': timestamp.toIso8601String(),
      'metrica': metrica,
      'valor_actual': valorActual,
      'valor_limite': valorLimite,
    };
  }
}

class MetricasSalud {
  const MetricasSalud({
    required this.timestamp,
    required this.dbResponseMs,
    required this.memoryRssMb,
    required this.dbSizeMb,
    required this.ultimaVersion,
    required this.ultimoRespaldo,
    this.heartbeatOk = true,
    this.erroresCriticos = 0,
  });

  final DateTime timestamp;
  final int dbResponseMs;
  final int memoryRssMb;
  final double dbSizeMb;
  final String ultimaVersion;
  final DateTime? ultimoRespaldo;
  final bool heartbeatOk;
  final int erroresCriticos;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'db_response_ms': dbResponseMs,
      'memory_rss_mb': memoryRssMb,
      'db_size_mb': dbSizeMb,
      'ultima_version': ultimaVersion,
      'ultimo_respaldo': ultimoRespaldo?.toIso8601String(),
      'heartbeat_ok': heartbeatOk,
      'errores_criticos': erroresCriticos,
    };
  }
}

class HealthReporter {
  HealthReporter._();

  static final HealthReporter instance = HealthReporter._();

  static const int _heartbeatIntervalMin = 5;
  static const int _heartbeatTimeoutMin = 15;
  static const int _memoryThresholdPct = 85;
  static const int _respaldoMaxHoras = 48;

  Timer? _heartbeatTimer;
  Timer? _dbSizeTimer;
  Timer? _memoryTimer;
  DateTime? _ultimoHeartbeat;
  final List<AlertaSalud> _alertasActivas = [];
  final List<void Function(AlertaSalud)> _alertaListeners = [];

  bool get isRunning => _heartbeatTimer != null;

  List<AlertaSalud> get alertasActivas => List.unmodifiable(_alertasActivas);

  void iniciar() {
    if (isRunning) return;

    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: _heartbeatIntervalMin),
      (_) => _enviarHeartbeat(),
    );

    _dbSizeTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _verificarTamanoDb(),
    );

    _memoryTimer = Timer.periodic(
      const Duration(minutes: _heartbeatIntervalMin),
      (_) => _verificarMemoria(),
    );

    _ultimoHeartbeat = DateTime.now();
  }

  void detener() {
    _heartbeatTimer?.cancel();
    _dbSizeTimer?.cancel();
    _memoryTimer?.cancel();
    _heartbeatTimer = null;
    _dbSizeTimer = null;
    _memoryTimer = null;
  }

  Future<MetricasSalud> recolectarMetricas() async {
    final db = await DatabaseHelper.instance.database;
    final sw = Stopwatch()..start();
    await db.rawQuery('SELECT 1');
    sw.stop();

    final dbPath = await DatabaseHelper.instance.obtenerRutaBaseDatos();
    final dbFile = File(dbPath);
    final dbSizeBytes = await dbFile.length();
    final dbSizeMb = dbSizeBytes / (1024 * 1024);

    final respaldos = await FullBackupService.instance.listBackups();
    final ultimoRespaldo = respaldos.isNotEmpty
        ? await respaldos.first.lastModified()
        : null;

    return MetricasSalud(
      timestamp: DateTime.now(),
      dbResponseMs: sw.elapsedMilliseconds,
      memoryRssMb: (ProcessInfo.currentRss / (1024 * 1024)).round(),
      dbSizeMb: dbSizeMb,
      ultimaVersion: AppVersion.version,
      ultimoRespaldo: ultimoRespaldo,
      heartbeatOk: _verificarHeartbeat(),
      erroresCriticos: _contarErroresCriticos(),
    );
  }

  Future<void> reportarErrorCritico(String error, {String? stackTrace}) async {
    final alerta = AlertaSalud(
      nivel: NivelAlerta.critico,
      tipo: 'error_critico',
      mensaje: error,
      timestamp: DateTime.now(),
    );

    _agregarAlerta(alerta);

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'SALUD_ERROR_CRITICO',
      entidad: 'health_reporter',
      detalle: '$error\n$stackTrace',
    );
  }

  void agregarAlertaListener(void Function(AlertaSalud) listener) {
    _alertaListeners.add(listener);
  }

  void removerAlertaListener(void Function(AlertaSalud) listener) {
    _alertaListeners.remove(listener);
  }

  Future<void> _enviarHeartbeat() async {
    try {
      _ultimoHeartbeat = DateTime.now();
      
      final metricas = await recolectarMetricas();
      
      final licencia = await LicenciaService.instance.obtenerLicencia();
      if (licencia != null) {
        await _verificarLimiteDb(metricas.dbSizeMb, licencia);
      }

      await _verificarRespaldoReciente(metricas.ultimoRespaldo);
      await _verificarVersionActualizada();
    } catch (e) {
      debugPrint('Error en heartbeat: $e');
    }
  }

  Future<void> _verificarTamanoDb() async {
    try {
      final metricas = await recolectarMetricas();
      final licencia = await LicenciaService.instance.obtenerLicencia();
      
      if (licencia != null) {
        await _verificarLimiteDb(metricas.dbSizeMb, licencia);
      }
    } catch (e) {
      debugPrint('Error al verificar tamaño DB: $e');
    }
  }

  Future<void> _verificarMemoria() async {
    try {
      final metricas = await recolectarMetricas();
      // En Windows, asumimos 4GB como referencia para el cálculo de porcentaje
      final memoriaTotalMb = 4096.0;
      final porcentajeUso = (metricas.memoryRssMb / memoriaTotalMb) * 100;

      if (porcentajeUso > _memoryThresholdPct) {
        final alerta = AlertaSalud(
          nivel: NivelAlerta.advertencia,
          tipo: 'memoria_alta',
          mensaje: 'Uso de memoria alto: ${porcentajeUso.toStringAsFixed(1)}%',
          timestamp: DateTime.now(),
          metrica: 'memory_pct',
          valorActual: porcentajeUso,
          valorLimite: _memoryThresholdPct.toDouble(),
        );
        _agregarAlerta(alerta);
      }
    } catch (e) {
      debugPrint('Error al verificar memoria: $e');
    }
  }

  Future<void> _verificarLimiteDb(double dbSizeMb, LicenciaInfo licencia) async {
    if (licencia.limiteDbMb == null) return;

    if (dbSizeMb > licencia.limiteDbMb!) {
      final alerta = AlertaSalud(
        nivel: NivelAlerta.critico,
        tipo: 'db_excede_limite',
        mensaje: 'Base de datos excede límite del plan: ${dbSizeMb.toStringAsFixed(2)}MB / ${licencia.limiteDbMb}MB',
        timestamp: DateTime.now(),
        metrica: 'db_size_mb',
        valorActual: dbSizeMb,
        valorLimite: licencia.limiteDbMb!.toDouble(),
      );
      _agregarAlerta(alerta);
    }
  }

  Future<void> _verificarRespaldoReciente(DateTime? ultimoRespaldo) async {
    if (ultimoRespaldo == null) {
      final alerta = AlertaSalud(
        nivel: NivelAlerta.advertencia,
        tipo: 'sin_respaldo',
        mensaje: 'No hay respaldos de base de datos',
        timestamp: DateTime.now(),
      );
      _agregarAlerta(alerta);
      return;
    }

    final horasSinRespaldo = DateTime.now().difference(ultimoRespaldo).inHours;
    if (horasSinRespaldo > _respaldoMaxHoras) {
      final alerta = AlertaSalud(
        nivel: NivelAlerta.advertencia,
        tipo: 'respaldo_antiguo',
        mensaje: 'Último respaldo hace $horasSinRespaldo horas (máximo: $_respaldoMaxHoras)',
        timestamp: DateTime.now(),
        metrica: 'horas_sin_respaldo',
        valorActual: horasSinRespaldo.toDouble(),
        valorLimite: _respaldoMaxHoras.toDouble(),
      );
      _agregarAlerta(alerta);
    }
  }

  Future<void> _verificarVersionActualizada() async {
    // Esta verificación se hará contra el Control Center
    // Por ahora, solo registramos la versión actual
    // Si la versión local es diferente a la última conocida, generar alerta
    // Esto se implementará cuando se integre con UpdateService
  }

  bool _verificarHeartbeat() {
    if (_ultimoHeartbeat == null) return false;
    
    final minutosDesdeUltimo = DateTime.now().difference(_ultimoHeartbeat!).inMinutes;
    return minutosDesdeUltimo < _heartbeatTimeoutMin;
  }

  int _contarErroresCriticos() {
    return _alertasActivas
        .where((a) => a.nivel == NivelAlerta.critico && a.tipo == 'error_critico')
        .length;
  }

  void _agregarAlerta(AlertaSalud alerta) {
    // Evitar duplicados recientes del mismo tipo
    final existeSimilar = _alertasActivas.any((a) =>
        a.tipo == alerta.tipo &&
        DateTime.now().difference(a.timestamp).inMinutes < 30);

    if (!existeSimilar) {
      _alertasActivas.add(alerta);
      _notificarAlerta(alerta);

      // Limpiar alertas viejas
      _alertasActivas.removeWhere((a) =>
          DateTime.now().difference(a.timestamp).inHours > 24);
    }
  }

  void _notificarAlerta(AlertaSalud alerta) {
    for (final listener in _alertaListeners) {
      try {
        listener(alerta);
      } catch (e) {
        debugPrint('Error en listener de alerta: $e');
      }
    }
  }

  Future<void> limpiarAlertasAntiguas() async {
    _alertasActivas.removeWhere((a) =>
        DateTime.now().difference(a.timestamp).inHours > 24);
  }

  Future<Map<String, dynamic>> obtenerReporteCompleto() async {
    final metricas = await recolectarMetricas();
    
    return {
      'metricas': metricas.toJson(),
      'alertas': _alertasActivas.map((a) => a.toJson()).toList(),
      'heartbeat_ok': _verificarHeartbeat(),
      'servicio_activo': isRunning,
    };
  }
}
