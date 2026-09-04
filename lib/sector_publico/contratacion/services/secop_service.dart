/// Servicio de Integración con SECOP II
/// Sistema Electrónico de Contratación Pública - Colombia Compra Eficiente
/// Integración configurable para interoperabilidad y consulta de datos abiertos
library;

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:dio/dio.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/proceso_contratacion.dart';
import '../models/contrato.dart';
import '../../security/auditoria_service.dart';
import '../../models/registro_auditoria.dart';
import '../../../integrations/application/integration_settings_service.dart';
import '../../../integrations/domain/integration_definition.dart';

class SECOPService {
  final Database db;
  final AuditoriaService auditoriaService;
  // Lectura pública de datos abiertos. Las operaciones de escritura usan
  // exclusivamente la configuración segura de Centro de Integraciones.
  static const String _soda3BaseUrl =
      'https://datos.gov.co/resource/p6dx-8zbt.json';
  static const Duration _timeout = Duration(seconds: 30);

  SECOPService({required this.db, required this.auditoriaService});

  Future<Dio> _secopDio() async {
    final settings = IntegrationSettingsService.instance;
    if (!await settings.isConfigured('secop_ii')) {
      throw StateError(
        'SECOP II no está configurado. Registra las credenciales y el contrato de API en Configuración > Integraciones.',
      );
    }
    final definition = IntegrationRegistry.byKey('secop_ii');
    final values = await settings.loadValues(definition);
    final rawBase = values['base_url']!.trim();
    final uri = Uri.tryParse(rawBase);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && !(uri.scheme == 'http' && const {'localhost','127.0.0.1','::1'}.contains(uri.host)))) {
      throw StateError('SECOP II exige un endpoint HTTPS válido.');
    }
    final servicePath = (values['service_path'] ?? '/contratacion').trim();
    final baseWithPath = uri.resolve(servicePath.endsWith('/') ? servicePath : '$servicePath/');
    final headers = <String, dynamic>{'Content-Type': 'application/json', 'Accept': 'application/json'};
    final auth = (values['auth_type'] ?? 'BEARER').toUpperCase();
    final credential = (values['credential'] ?? '').trim();
    final username = (values['username'] ?? '').trim();
    if (auth == 'BEARER' && credential.isNotEmpty) headers['Authorization'] = 'Bearer $credential';
    if (auth == 'API_KEY' && credential.isNotEmpty) headers[username.isEmpty ? 'X-API-Key' : username] = credential;
    if (auth == 'BASIC' && (username.isNotEmpty || credential.isNotEmpty)) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('$username:$credential'))}';
    }
    final xroad = (values['xroad_client_id'] ?? '').trim();
    if (xroad.isNotEmpty) headers['X-Road-Client'] = xroad;
    return Dio(BaseOptions(
      baseUrl: baseWithPath.toString(),
      connectTimeout: _timeout, receiveTimeout: _timeout,
      headers: headers,
      validateStatus: (status) => status != null && status < 500,
    ));
  }

  Future<Dio> _sodaDio() async {
    String appToken = '';
    try {
      final definition = IntegrationRegistry.byKey('secop_ii');
      final values = await IntegrationSettingsService.instance.loadValues(definition);
      appToken = (values['socrata_app_token'] ?? '').trim();
    } catch (_) {}
    return Dio(BaseOptions(
      connectTimeout: _timeout, receiveTimeout: _timeout,
      headers: {
        'Accept': 'application/json',
        if (appToken.isNotEmpty) 'X-App-Token': appToken,
      },
    ));
  }

  /// Publica un proceso mediante el canal SECOP configurado por la entidad
  Future<ProcesoContratacion> publicarEnSECOP({
    required String entidadId,
    required String usuarioId,
    required String procesoId,
    required String nitEntidad,
  }) async {
    final procesoResult = await db.query(
      'procesos_contratacion',
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    if (procesoResult.isEmpty) {
      throw Exception('Proceso no encontrado');
    }

    final proceso = ProcesoContratacion.fromJson(procesoResult.first);

    if (proceso.estado != EstadoProceso.estudioPrevio) {
      throw Exception('Solo se pueden publicar procesos en estudio previo');
    }

    try {
      // Preparar payload para SECOP II
      final payload = {
        'tipo_proceso': proceso.tipoContrato.toString().split('.').last,
        'modalidad_seleccion': proceso.modalidad.toString().split('.').last,
        'objeto_contrato': proceso.objetoContrato,
        'valor_estimado': publicMoneyForDisplay(proceso.valorEstimado),
        'fecha_inicio': proceso.fechaInicio.toIso8601String(),
        'fecha_fin': proceso.fechaCierre?.toIso8601String(),
        'nit_entidad': nitEntidad,
        'entidad': proceso.entidadId,
      };

      // Llamada al canal SECOP configurado por la entidad
      final dio = await _secopDio();
      final response = await dio.post(
        'procesos',
        data: payload,
      );

      if (response.statusCode != 201) {
        throw Exception(
          'Error al publicar en SECOP II: ${response.statusCode}',
        );
      }

      final secopId = response.data['id_proceso_secop'];
      final fechaPublicacion = DateTime.now();

      await db.update(
        'procesos_contratacion',
        {
          'estado': EstadoProceso.publicado.toString().split('.').last,
          'fecha_publicacion': fechaPublicacion.toIso8601String(),
          'secop_id': secopId,
        },
        where: 'id = ?',
        whereArgs: [procesoId],
      );

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'contratacion',
        accion: 'publicacion_secop_xroad',
        valorAnterior: {'estado_anterior': proceso.estado.toString()},
        valorNuevo: {
          'estado_nuevo': EstadoProceso.publicado.toString(),
          'secop_id': secopId,
          'respuesta_api': response.data,
        },
        referenciaId: procesoId,
      );

      return proceso.copyWith(
        estado: EstadoProceso.publicado,
        fechaPublicacion: fechaPublicacion,
        secopId: secopId,
      );
    } on DioException catch (e) {
      throw Exception('Error de conexión con SECOP II: ${e.message}');
    }
  }

  /// Recibe ofertas de SECOP II para un proceso
  Future<List<Map<String, dynamic>>> recibirOfertasSECOP({
    required String procesoId,
    required String secopId,
  }) async {
    try {
      final dio = await _secopDio();
      final response = await dio.get(
        'procesos/$secopId/ofertas',
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al recibir ofertas de SECOP II: ${response.statusCode}',
        );
      }

      return List<Map<String, dynamic>>.from(response.data['ofertas']);
    } on DioException catch (e) {
      throw Exception('Error de conexión con SECOP II: ${e.message}');
    }
  }

  /// Publica adjudicación en SECOP II
  Future<ProcesoContratacion> publicarAdjudicacionSECOP({
    required String entidadId,
    required String usuarioId,
    required String procesoId,
    required String secopId,
    required String proveedorId,
    required MoneyValue valorAdjudicacion,
  }) async {
    try {
      final payload = {
        'proveedor_id': proveedorId,
        'valor_adjudicacion': publicMoneyForDisplay(valorAdjudicacion),
        'fecha_adjudicacion': DateTime.now().toIso8601String(),
      };

      final dio = await _secopDio();
      final response = await dio.post(
        'procesos/$secopId/adjudicacion',
        data: payload,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al publicar adjudicación en SECOP II: ${response.statusCode}',
        );
      }

      final procesoResult = await db.query(
        'procesos_contratacion',
        where: 'id = ?',
        whereArgs: [procesoId],
      );

      final proceso = ProcesoContratacion.fromJson(procesoResult.first);

      await db.update(
        'procesos_contratacion',
        {'estado': EstadoProceso.adjudicado.toString().split('.').last},
        where: 'id = ?',
        whereArgs: [procesoId],
      );

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'contratacion',
        accion: 'adjudicacion_secop_xroad',
        valorAnterior: {'estado_anterior': proceso.estado.toString()},
        valorNuevo: {
          'estado_nuevo': EstadoProceso.adjudicado.toString(),
          'proveedor_id': proveedorId,
          'valor_adjudicacion': valorAdjudicacion.toWireMap(),
        },
        referenciaId: procesoId,
      );

      return proceso.copyWith(estado: EstadoProceso.adjudicado);
    } on DioException catch (e) {
      throw Exception('Error de conexión con SECOP II: ${e.message}');
    }
  }

  /// Sincroniza un contrato con SECOP II
  Future<Contrato> sincronizarContratoSECOP({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required String secopId,
  }) async {
    final contratoResult = await db.query(
      'contratos',
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    if (contratoResult.isEmpty) {
      throw Exception('Contrato no encontrado');
    }

    final contrato = Contrato.fromJson(contratoResult.first);

    try {
      final payload = {
        'numero_contrato': contrato.numeroContrato,
        'valor_contrato': publicMoneyForDisplay(contrato.valorContrato),
        'fecha_firma': contrato.fechaFirma.toIso8601String(),
        'fecha_inicio': contrato.fechaInicioEjecucion.toIso8601String(),
        'fecha_fin': contrato.fechaFinEjecucion.toIso8601String(),
      };

      final dio = await _secopDio();
      final response = await dio.post(
        'contratos',
        data: payload,
      );

      if (response.statusCode != 201) {
        throw Exception(
          'Error al sincronizar contrato con SECOP II: ${response.statusCode}',
        );
      }

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'contratacion',
        accion: 'sincronizacion_contrato_secop_xroad',
        valorAnterior: {'contrato_id': contratoId},
        valorNuevo: {'secop_id': secopId, 'respuesta_api': response.data},
        referenciaId: contratoId,
      );

      return contrato;
    } on DioException catch (e) {
      throw Exception('Error de conexión con SECOP II: ${e.message}');
    }
  }

  /// Consulta procesos publicados en SECOP II
  Future<List<ProcesoContratacion>> consultarProcesosSECOP({
    required String entidadId,
  }) async {
    final resultados = await db.query(
      'procesos_contratacion',
      where: 'entidad_id = ? AND secop_id IS NOT NULL',
      whereArgs: [entidadId],
      orderBy: 'fecha_publicacion DESC',
    );

    return resultados.map((r) => ProcesoContratacion.fromJson(r)).toList();
  }

  /// Genera reporte de contratación para SECOP II
  Future<Map<String, dynamic>> generarReporteSECOP({
    required String entidadId,
    required String vigencia,
  }) async {
    final procesos = await db.query(
      'procesos_contratacion',
      where: 'entidad_id = ? AND fecha_inicio LIKE ?',
      whereArgs: [entidadId, '$vigencia%'],
    );

    final contratos = await db.query(
      'contratos',
      where: 'entidad_id = ? AND fecha_firma LIKE ?',
      whereArgs: [entidadId, '$vigencia%'],
    );

    var valorTotalContratos = publicMoneyZero();
    for (final contrato in contratos) {
      valorTotalContratos += publicMoneyFromSql(contrato['valor_contrato']);
    }

    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'total_procesos': procesos.length,
      'total_contratos': contratos.length,
      'valor_total_contratos': publicMoneyForDisplay(valorTotalContratos),
      'procesos': procesos.map((r) => r['numero_proceso']).toList(),
      'contratos': contratos.map((r) => r['numero_contrato']).toList(),
    };
  }

  /// Consulta procesos de contratación vía API SODA3 de datos.gov.co
  /// Soporta paginación y filtros SoQL
  Future<List<Map<String, dynamic>>> consultarProcesosSODA3({
    String? nitEntidad,
    int? limit,
    int? offset,
    String? soqlFilter,
  }) async {
    try {
      // Construir parámetros de consulta
      final queryParams = <String, dynamic>{};

      if (nitEntidad != null) {
        queryParams['nit_entidad'] = nitEntidad;
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

      // Ordenar por fecha de publicación descendente
      queryParams['\$order'] = 'fecha_publicacion DESC';

      final sodaDio = await _sodaDio();
      final response = await sodaDio.get(
        _soda3BaseUrl,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar SECOP II vía SODA3: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3: ${e.message}');
    }
  }

  /// Consulta un contrato específico por ID de proceso vía SODA3
  Future<Map<String, dynamic>?> consultarContratoSODA3({
    required String idProceso,
  }) async {
    try {
      final sodaDio = await _sodaDio();
      final response = await sodaDio.get(
        _soda3BaseUrl,
        queryParameters: {'id_proceso': idProceso, '\$limit': 1},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar contrato vía SODA3: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      if (data.isEmpty) return null;
      return data.first as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3: ${e.message}');
    }
  }

  /// Consulta contratos por rango de fechas vía SODA3
  Future<List<Map<String, dynamic>>> consultarContratosPorFechaSODA3({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? nitEntidad,
    int? limit,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        '\$where':
            "fecha_publicacion >= '${fechaInicio.toIso8601String()}' AND fecha_publicacion <= '${fechaFin.toIso8601String()}'",
        '\$order': 'fecha_publicacion DESC',
      };

      if (nitEntidad != null) {
        queryParams['nit_entidad'] = nitEntidad;
      }

      if (limit != null) {
        queryParams['\$limit'] = limit;
      }

      final sodaDio = await _sodaDio();
      final response = await sodaDio.get(
        _soda3BaseUrl,
        queryParameters: queryParams,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar contratos por fecha vía SODA3: ${response.statusCode}',
        );
      }

      final List<dynamic> data = response.data;
      return data.cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      throw Exception('Error de conexión con API SODA3: ${e.message}');
    }
  }
}
