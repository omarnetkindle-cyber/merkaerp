/// Servicio de Cálculo de Intereses Moratorios
/// Fórmula exacta: I = K × T × t
/// Artículo 635 ET + Concepto Minhaciendo 032629 de 2026
/// Tasa de mora = Tasa de usura vigente - 2 puntos
/// Integración con API SODA3 de datos.gov.co para TIM
library;

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

class InteresesMoratoriosService {
  // ignore: unused_field — _dio reservado para llamadas directas futuras (actualmente usa _soda3Dio)
  final Dio _dio;
  final Dio _soda3Dio;

  /// Tasa de usura vigente (ejemplo para junio 2026: 28.79% EA)
  /// Este valor se actualiza automáticamente desde Superfinanciera vía SODA3
  double _tasaUsuraVigente = 28.79;

  // Configuración de API SODA3 (datos.gov.co - Superfinanciera)
  static const String _soda3BaseUrl =
      'https://datos.gov.co/resource/p63f-gtb6.json';
  static const Duration _timeout = Duration(seconds: 30);

  InteresesMoratoriosService({Dio? dio})
    : _dio =
          dio ??
          Dio(BaseOptions(connectTimeout: _timeout, receiveTimeout: _timeout)),
      _soda3Dio = Dio(
        BaseOptions(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          headers: {
            'Content-Type': 'application/json',
            'X-App-Token': _safeEnv('SOCRATA_APP_TOKEN'),
            'Authorization': _safeEnv('SOCRATA_AUTH_HEADER'),
          },
        ),
      );

  /// Lee una variable de entorno sin lanzar NotInitializedError si dotenv no cargó.
  static String _safeEnv(String key) {
    try {
      return dotenv.env[key] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Obtiene la tasa de mora actual (Usura - 2 puntos)
  double get tasaMoraMensual {
    final tasaAnual = tasaInteresMoratorio / 100;
    return (math.pow(1 + tasaAnual, 1 / 12) - 1) * 100;
  }

  /// Articulo 635 ET: tasa diaria equivalente a la tasa efectiva anual.
  double get tasaMoraDiaria {
    final tasaAnual = tasaInteresMoratorio / 100;
    return math.pow(1 + tasaAnual, 1 / 365) - 1;
  }

  /// Actualiza la tasa de usura desde Superfinanciera vía API SODA3
  /// Fórmula legal: TIM = Tasa de Usura - 2%
  Future<double> actualizarTasaUsuraDesdeSuperfinanciera() async {
    try {
      // Consultar la tasa de usura más reciente para Crédito de Consumo y Ordinario
      final response = await _soda3Dio.get(
        _soda3BaseUrl,
        queryParameters: {
          'modalidad': 'Crédito de Consumo y Ordinario',
          '\$order': 'fecha_publicacion DESC',
          '\$limit': 1,
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al obtener tasa de usura de Superfinanciera: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      if (data.isEmpty) {
        throw Exception('No se encontraron datos de tasa de usura');
      }

      final registro = data.first as Map<String, dynamic>;

      // Extraer la tasa efectiva anual del campo 'tasa_efectiva_anual'
      final tasaUsura = _parsearTasaUsuraSODA3(registro);

      _tasaUsuraVigente = tasaUsura;

      return tasaUsura;
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3: ${e.message}');
    }
  }

  /// Parsea la tasa de usura desde la respuesta SODA3 de Superfinanciera
  double _parsearTasaUsuraSODA3(Map<String, dynamic> registro) {
    // El campo puede venir como string o como número
    final tasaEfectivaAnual = registro['tasa_efectiva_anual'];

    if (tasaEfectivaAnual == null) {
      throw Exception(
        'Campo tasa_efectiva_anual no encontrado en la respuesta',
      );
    }

    // Convertir a double
    double tasa;
    if (tasaEfectivaAnual is String) {
      // Remover el símbolo % si está presente y convertir
      tasa = double.parse(tasaEfectivaAnual.replaceAll('%', '').trim());
    } else if (tasaEfectivaAnual is num) {
      tasa = tasaEfectivaAnual.toDouble();
    } else {
      throw Exception('Formato de tasa no válido');
    }

    return tasa;
  }

  /// Obtiene la Tasa de Interés Moratorio (TIM) actual
  /// Fórmula: TIM = Tasa de Usura - 2%
  double get tasaInteresMoratorio {
    return _tasaUsuraVigente - 2.0;
  }

  /// Ejecuta el cron job mensual de actualización de TIM
  /// Debe ejecutarse el primer día de cada mes
  Future<Map<String, dynamic>> ejecutarCronJobTIM() async {
    try {
      final tasaUsuraAnterior = _tasaUsuraVigente;
      final timAnterior = tasaInteresMoratorio;

      // Actualizar la tasa de usura desde Superfinanciera
      final nuevaTasaUsura = await actualizarTasaUsuraDesdeSuperfinanciera();
      final nuevoTIM = tasaInteresMoratorio;

      return {
        'fecha_ejecucion': DateTime.now().toIso8601String(),
        'tasa_usura_anterior': tasaUsuraAnterior,
        'tasa_usura_nueva': nuevaTasaUsura,
        'tim_anterior': timAnterior,
        'tim_nuevo': nuevoTIM,
        'estado': 'exitoso',
      };
    } catch (e) {
      return {
        'fecha_ejecucion': DateTime.now().toIso8601String(),
        'error': e.toString(),
        'estado': 'fallido',
      };
    }
  }

  /// Actualiza manualmente la tasa de usura (fallback)
  void actualizarTasaUsura(double nuevaTasa) {
    _tasaUsuraVigente = nuevaTasa;
  }

  /// Calcula intereses de mora según fórmula I = K × T × t
  /// K = Capital (valor adeudado)
  /// T = Tasa de mora (diaria)
  /// t = Tiempo (días de mora)
  MoneyValue calcularInteresesMora({
    required MoneyValue capital,
    required int diasMora,
    DateTime? fechaVencimiento,
  }) {
    if (diasMora <= 0) return publicMoneyZero();

    // Tasa de mora diaria = (Tasa mensual / 30)
    final tasaMoraDiaria = this.tasaMoraDiaria;

    // Fórmula: I = K × T × t
    final intereses = capital.multiplyDecimal(
      (tasaMoraDiaria * diasMora).toString(),
    );

    return intereses;
  }

  /// Calcula intereses de mora con fecha específica
  MoneyValue calcularInteresesMoraConFecha({
    required MoneyValue capital,
    required DateTime fechaVencimiento,
    required DateTime fechaCalculo,
  }) {
    final diasMora = fechaCalculo.difference(fechaVencimiento).inDays;
    return calcularInteresesMora(
      capital: capital,
      diasMora: diasMora > 0 ? diasMora : 0,
      fechaVencimiento: fechaVencimiento,
    );
  }

  /// Calcula el total a pagar con intereses
  MoneyValue calcularTotalConIntereses({
    required MoneyValue capital,
    required int diasMora,
  }) {
    final intereses = calcularInteresesMora(
      capital: capital,
      diasMora: diasMora,
    );
    return capital + intereses;
  }

  /// Genera tabla de amortización de intereses
  List<Map<String, dynamic>> generarTablaAmortizacion({
    required MoneyValue capital,
    required DateTime fechaVencimiento,
    required int numeroCuotas,
    required int periodicidadDias,
  }) {
    final tabla = <Map<String, dynamic>>[];
    var saldoPendiente = capital;
    DateTime fechaCuota = fechaVencimiento;

    for (int i = 1; i <= numeroCuotas; i++) {
      fechaCuota = fechaCuota.add(Duration(days: periodicidadDias));
      final diasMora = fechaCuota.difference(fechaVencimiento).inDays;

      final intereses = calcularInteresesMora(
        capital: saldoPendiente,
        diasMora: diasMora > 0 ? diasMora : 0,
      );

      final cuotaCapital = capital / numeroCuotas;
      final cuotaTotal = cuotaCapital + intereses;

      tabla.add({
        'cuota': i,
        'fecha': fechaCuota.toIso8601String(),
        'dias_mora': diasMora > 0 ? diasMora : 0,
        'saldo_pendiente': saldoPendiente,
        'intereses': intereses,
        'capital': cuotaCapital,
        'cuota_total': cuotaTotal,
      });

      saldoPendiente -= cuotaCapital;
    }

    return tabla;
  }

  /// Obtiene la tasa de usura actual
  double get tasaUsura => _tasaUsuraVigente;
}
