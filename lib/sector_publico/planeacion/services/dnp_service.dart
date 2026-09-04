/// Servicio de Integración con DNP (Departamento Nacional de Planeación)
/// Integración con APIs SODA3 de datos.gov.co
/// Datasets: Sisbén, SGR, Tipologías Municipales
library;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

class DNPService {
  final Dio _soda3Dio;
  static const Duration _timeout = Duration(seconds: 30);

  // Endpoints SODA3 del DNP
  static const String _sisbenUrl =
      'https://datos.gov.co/resource/hq2v-5umk.json';
  static const String _sgrUrl = 'https://datos.gov.co/resource/p54v-f343.json';
  static const String _tipologiasUrl =
      'https://datos.gov.co/resource/66v2-w4r9.json';

  DNPService({Dio? dio})
    : _soda3Dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: _timeout,
              receiveTimeout: _timeout,
              headers: {
                'Content-Type': 'application/json',
                'X-App-Token': dotenv.env['SOCRATA_APP_TOKEN'] ?? '',
                'Authorization': dotenv.env['SOCRATA_AUTH_HEADER'] ?? '',
              },
            ),
          );

  /// Consulta datos del Sisbén (muestras de población)
  /// Uso: Caracterización socioeconómica y estadísticas de ciudadanos
  Future<List<Map<String, dynamic>>> consultarSisben({
    String? codigoMunicipio,
    String? departamento,
    int? limit,
    int? offset,
    String? soqlFilter,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (codigoMunicipio != null) {
        queryParams['codigo_municipio'] = codigoMunicipio;
      }

      if (departamento != null) {
        queryParams['departamento'] = departamento;
      }

      if (limit != null) {
        queryParams['\$limit'] = limit;
      }

      if (offset != null) {
        queryParams['\$offset'] = offset;
      }

      if (soqlFilter != null) {
        queryParams['\$where'] = soqlFilter;
      }

      queryParams['\$order'] = 'fecha_registro DESC';

      final response = await _soda3Dio.get(
        _sisbenUrl,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw Exception('Error al consultar Sisbén: ${response.statusCode}');
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3 (Sisbén): ${e.message}');
    }
  }

  /// Consulta estadísticas agregadas del Sisbén por municipio
  Future<Map<String, dynamic>> consultarEstadisticasSisbenMunicipio({
    required String codigoMunicipio,
  }) async {
    try {
      final response = await _soda3Dio.get(
        _sisbenUrl,
        queryParameters: {
          'codigo_municipio': codigoMunicipio,
          '\$select': 'grupo_sisben, COUNT(*) as total',
          '\$group': 'grupo_sisben',
          '\$order': 'grupo_sisben',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar estadísticas Sisbén: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;

      // Calcular totales
      int totalPoblacion = data.fold<int>(
        0,
        (sum, r) => sum + int.parse(r['total'].toString()),
      );

      return {
        'codigo_municipio': codigoMunicipio,
        'total_poblacion': totalPoblacion,
        'distribucion_por_grupo': data,
      };
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3 (Sisbén): ${e.message}');
    }
  }

  /// Consulta proyectos del Sistema General de Regalías (SGR)
  /// Uso: Seguimiento a ejecución presupuestal de proyectos de inversión
  Future<List<Map<String, dynamic>>> consultarProyectosSGR({
    String? codigoDepartamento,
    String? codigoMunicipio,
    String? bpin,
    String? estado,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (codigoDepartamento != null) {
        queryParams['codigo_departamento'] = codigoDepartamento;
      }

      if (codigoMunicipio != null) {
        queryParams['codigo_municipio'] = codigoMunicipio;
      }

      if (bpin != null) {
        queryParams['codigo_bpin'] = bpin;
      }

      if (estado != null) {
        queryParams['estado'] = estado;
      }

      if (limit != null) {
        queryParams['\$limit'] = limit;
      }

      if (offset != null) {
        queryParams['\$offset'] = offset;
      }

      queryParams['\$order'] = 'fecha_registro DESC';

      final response = await _soda3Dio.get(
        _sgrUrl,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar proyectos SGR: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3 (SGR): ${e.message}');
    }
  }

  /// Consulta un proyecto SGR específico por BPIN
  Future<Map<String, dynamic>?> consultarProyectoSGR({
    required String bpin,
  }) async {
    try {
      final response = await _soda3Dio.get(
        _sgrUrl,
        queryParameters: {'codigo_bpin': bpin, '\$limit': 1},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar proyecto SGR: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      if (data.isEmpty) return null;
      return data.first as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3 (SGR): ${e.message}');
    }
  }

  /// Consulta ejecución presupuestal de proyectos SGR
  Future<Map<String, dynamic>> consultarEjecucionPresupuestalSGR({
    required String codigoMunicipio,
    required int anio,
  }) async {
    try {
      final response = await _soda3Dio.get(
        _sgrUrl,
        queryParameters: {
          'codigo_municipio': codigoMunicipio,
          '\$where': "anio_vigencia = '$anio'",
          '\$select':
              'SUM(valor_asignado) as total_asignado, SUM(valor_ejecutado) as total_ejecutado, COUNT(*) as total_proyectos',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar ejecución SGR: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      if (data.isEmpty) {
        return {
          'codigo_municipio': codigoMunicipio,
          'anio': anio,
          'total_asignado': 0,
          'total_ejecutado': 0,
          'total_proyectos': 0,
          'porcentaje_ejecucion': 0,
        };
      }

      final resultado = data.first;
      final totalAsignado = publicMoneyFromMajor(
        resultado['total_asignado'].toString(),
      );
      final totalEjecutado = publicMoneyFromMajor(
        resultado['total_ejecutado'].toString(),
      );
      final porcentajeEjecucion = totalAsignado > publicMoneyZero()
          ? (totalEjecutado.minorUnits / totalAsignado.minorUnits) * 100
          : 0;

      return {
        'codigo_municipio': codigoMunicipio,
        'anio': anio,
        'total_asignado': publicMoneyForDisplay(totalAsignado),
        'total_ejecutado': publicMoneyForDisplay(totalEjecutado),
        'total_proyectos': int.parse(resultado['total_proyectos'].toString()),
        'porcentaje_ejecucion': porcentajeEjecucion,
      };
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3 (SGR): ${e.message}');
    }
  }

  /// Consulta clasificación y tipologías municipales del DNP
  /// Uso: Validar entorno de desarrollo territorial y categorías de descentralización
  Future<List<Map<String, dynamic>>> consultarTipologiasMunicipales({
    String? codigoMunicipio,
    String? departamento,
    String? categoria,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{};

      if (codigoMunicipio != null) {
        queryParams['codigo_municipio'] = codigoMunicipio;
      }

      if (departamento != null) {
        queryParams['departamento'] = departamento;
      }

      if (categoria != null) {
        queryParams['categoria_municipal'] = categoria;
      }

      if (limit != null) {
        queryParams['\$limit'] = limit;
      }

      queryParams['\$order'] = 'nombre_municipio ASC';

      final response = await _soda3Dio.get(
        _tipologiasUrl,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar tipologías municipales: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception(
        'Error de conexión con API SODA3 (Tipologías): ${e.message}',
      );
    }
  }

  /// Consulta la tipología específica de un municipio
  Future<Map<String, dynamic>?> consultarTipologiaMunicipio({
    required String codigoMunicipio,
  }) async {
    try {
      final response = await _soda3Dio.get(
        _tipologiasUrl,
        queryParameters: {'codigo_municipio': codigoMunicipio, '\$limit': 1},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar tipología municipal: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      if (data.isEmpty) return null;
      return data.first as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception(
        'Error de conexión con API SODA3 (Tipologías): ${e.message}',
      );
    }
  }

  /// Calcula transferencias según tipología municipal
  /// Basado en categorías de descentralización del DNP
  Future<Map<String, dynamic>> calcularTransferencias({
    required String codigoMunicipio,
    required MoneyValue baseCalculo,
  }) async {
    try {
      final tipologia = await consultarTipologiaMunicipio(
        codigoMunicipio: codigoMunicipio,
      );

      if (tipologia == null) {
        throw Exception('No se encontró tipología para el municipio');
      }

      final categoria = tipologia['categoria_municipal'] as String;

      // Porcentajes de transferencia según categoría (ejemplo)
      final porcentajesTransferencia = <String, double>{
        'Especial': 1.0,
        'Primera': 0.95,
        'Segunda': 0.90,
        'Tercera': 0.85,
        'Cuarta': 0.80,
        'Quinta': 0.75,
        'Sexta': 0.70,
      };

      final porcentaje = porcentajesTransferencia[categoria] ?? 0.70;
      final transferencia = baseCalculo.multiplyDecimal(porcentaje.toString());

      return {
        'codigo_municipio': codigoMunicipio,
        'categoria': categoria,
        'base_calculo': publicMoneyForDisplay(baseCalculo),
        'porcentaje_transferencia': porcentaje,
        'transferencia_calculada': publicMoneyForDisplay(transferencia),
        'tipologia_completa': tipologia,
      };
    } on DioException catch (e) {
      throw Exception(
        'Error de conexión con API SODA3 (Tipologías): ${e.message}',
      );
    }
  }

  /// Consulta todos los municipios de un departamento con su tipología
  Future<List<Map<String, dynamic>>> consultarMunicipiosPorDepartamento({
    required String codigoDepartamento,
  }) async {
    try {
      final response = await _soda3Dio.get(
        _tipologiasUrl,
        queryParameters: {
          'codigo_departamento': codigoDepartamento,
          '\$order': 'categoria_municipal ASC, nombre_municipio ASC',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar municipios por departamento: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception(
        'Error de conexión con API SODA3 (Tipologías): ${e.message}',
      );
    }
  }
}
