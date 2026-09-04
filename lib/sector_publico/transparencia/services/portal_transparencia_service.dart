/// Servicio de Integración con Portal de Transparencia
/// Ley 1712/2014 y normas complementarias
/// Publicación automática de información en portal de transparencia
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoInformacion {
  presupuesto,
  contratacion,
  nomina,
  regalias,
  proyectos,
  otros,
}

class PortalTransparenciaService {
  final Dio dio;
  final Database database;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();
  final String portalUrl;
  final String apiKey;

  PortalTransparenciaService({
    required this.dio,
    required this.database,
    required this.auditoriaService,
    required this.portalUrl,
    required this.apiKey,
  }) {
    final uri = Uri.tryParse(portalUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.scheme != 'https') {
      throw ArgumentError.value(
        portalUrl,
        'portalUrl',
        'El portal de transparencia debe configurarse con una URL HTTPS real.',
      );
    }
    if (apiKey.trim().length < 8) {
      throw ArgumentError('La credencial del portal de transparencia no está configurada.');
    }
    dio.options.baseUrl = uri.toString().replaceFirst(RegExp(r'/$'), '');
    dio.options.headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiKey.trim()}',
    };
    dio.options.connectTimeout = const Duration(seconds: 15);
    dio.options.sendTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Future<void> _ensureTrackingTable() async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS publicaciones_portal (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id TEXT NOT NULL,
        tipo TEXT NOT NULL,
        portal_id TEXT,
        url_publicacion TEXT,
        referencia_interna TEXT,
        datos_json TEXT NOT NULL,
        fecha_publicacion TEXT NOT NULL,
        estado TEXT NOT NULL,
        error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_publicaciones_portal_entidad_estado ON publicaciones_portal(entidad_id, estado)',
    );
  }

  /// Publica información en el portal de transparencia
  Future<Map<String, dynamic>> publicarInformacion({
    required String entidadId,
    required String usuarioId,
    required TipoInformacion tipo,
    required Map<String, dynamic> datos,
    required DateTime fechaPublicacion,
    String? referenciaInterna,
    String? registroLocalId,
  }) async {
    await _ensureTrackingTable();
    final id = registroLocalId ?? _uuid.v4();

    try {
      // Validar datos según tipo
      _validarDatosTipo(tipo, datos);

      // Construir payload según especificación del portal
      final payload = _construirPayload(tipo, datos, entidadId, fechaPublicacion);

      // Enviar al portal
      final response = await dio.post(
        '/publicar',
        data: payload,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final portalId = response.data['id'] as String;
        final urlPublicacion = response.data['url'] as String;

        // Registrar publicación local
        await _registrarPublicacionLocal(
          id: id,
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipo: tipo,
          portalId: portalId,
          urlPublicacion: urlPublicacion,
          referenciaInterna: referenciaInterna,
          fechaPublicacion: fechaPublicacion,
          estado: 'publicado',
          datos: datos,
        );

        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.creacionRegistro,
          modulo: 'transparencia',
          accion: 'publicacion_portal_transparencia',
          valorAnterior: {},
          valorNuevo: {
            'publicacion_id': id,
            'portal_id': portalId,
            'tipo': tipo.toString(),
            'url_publicacion': urlPublicacion,
          },
          referenciaId: id,
        );

        return {
          'publicacion_id': id,
          'portal_id': portalId,
          'url_publicacion': urlPublicacion,
          'estado': 'publicado',
        };
      } else {
        throw Exception('Error al publicar: ${response.statusCode}');
      }
    } catch (e) {
      // Registrar error
      await _registrarPublicacionLocal(
        id: id,
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipo: tipo,
        portalId: '',
        urlPublicacion: '',
        referenciaInterna: referenciaInterna,
        fechaPublicacion: fechaPublicacion,
        estado: 'error',
        error: e.toString(),
        datos: datos,
      );

      throw Exception('Error al publicar en portal de transparencia: $e');
    }
  }

  /// Actualiza información publicada
  Future<Map<String, dynamic>> actualizarInformacion({
    required String entidadId,
    required String usuarioId,
    required String publicacionId,
    required String portalId,
    required Map<String, dynamic> nuevosDatos,
  }) async {
    await _ensureTrackingTable();
    try {
      final payload = {
        'id': portalId,
        'datos': nuevosDatos,
        'fecha_actualizacion': DateTime.now().toIso8601String(),
      };

      final response = await dio.put(
        '/actualizar/$portalId',
        data: payload,
      );

      if (response.statusCode == 200) {
        final nuevaUrl = response.data['url'] as String;

        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.modificacionRegistro,
          modulo: 'transparencia',
          accion: 'actualizacion_portal_transparencia',
          valorAnterior: {},
          valorNuevo: {
            'publicacion_id': publicacionId,
            'portal_id': portalId,
            'url_actualizada': nuevaUrl,
          },
          referenciaId: publicacionId,
        );

        await database.update(
          'publicaciones_portal',
          {
            'url_publicacion': nuevaUrl,
            'estado': 'actualizado',
            'error': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [publicacionId],
        );
        return {
          'publicacion_id': publicacionId,
          'portal_id': portalId,
          'url_actualizada': nuevaUrl,
          'estado': 'actualizado',
        };
      } else {
        throw Exception('Error al actualizar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al actualizar en portal de transparencia: $e');
    }
  }

  /// Elimina información del portal
  Future<Map<String, dynamic>> eliminarInformacion({
    required String entidadId,
    required String usuarioId,
    required String publicacionId,
    required String portalId,
    required String motivo,
  }) async {
    await _ensureTrackingTable();
    try {
      final response = await dio.delete(
        '/eliminar/$portalId',
        data: {
          'motivo': motivo,
          'fecha_eliminacion': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.intentoEliminacion,
          modulo: 'transparencia',
          accion: 'eliminacion_portal_transparencia',
          valorAnterior: {
            'portal_id': portalId,
          },
          valorNuevo: {
            'motivo': motivo,
          },
          referenciaId: publicacionId,
        );

        await database.update(
          'publicaciones_portal',
          {
            'estado': 'eliminado',
            'error': null,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [publicacionId],
        );
        return {
          'publicacion_id': publicacionId,
          'portal_id': portalId,
          'estado': 'eliminado',
        };
      } else {
        throw Exception('Error al eliminar: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al eliminar del portal de transparencia: $e');
    }
  }

  /// Consulta el estado de una publicación
  Future<Map<String, dynamic>> consultarEstadoPublicacion({
    required String portalId,
  }) async {
    try {
      final response = await dio.get(
        '/estado/$portalId',
      );

      if (response.statusCode == 200) {
        return response.data as Map<String, dynamic>;
      } else {
        throw Exception('Error al consultar estado: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al consultar estado en portal de transparencia: $e');
    }
  }

  /// Sincroniza automáticamente información pendiente
  Future<Map<String, dynamic>> sincronizarPendientes({
    required String entidadId,
    required String usuarioId,
  }) async {
    // Obtener publicaciones pendientes o con error
    final pendientes = await _obtenerPublicacionesPendientes(entidadId);

    int exitosas = 0;
    int fallidas = 0;
    final errores = <String>[];

    for (final pendiente in pendientes) {
      try {
        final tipo = TipoInformacion.values.firstWhere(
          (e) => e.toString().split('.').last == pendiente['tipo'],
        );

        final datos = pendiente['datos'] as Map<String, dynamic>;
        final referenciaInterna = pendiente['referencia_interna'];
        final fechaPublicacion = DateTime.parse(pendiente['fecha_publicacion']);

        await publicarInformacion(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipo: tipo,
          datos: datos,
          fechaPublicacion: fechaPublicacion,
          referenciaInterna: referenciaInterna,
          registroLocalId: pendiente['id']?.toString(),
        );

        exitosas++;
      } catch (e) {
        fallidas++;
        errores.add('${pendiente['id']}: $e');
      }
    }

    return {
      'total_pendientes': pendientes.length,
      'exitosas': exitosas,
      'fallidas': fallidas,
      'errores': errores,
    };
  }

  /// Valida los datos según el tipo de información
  void _validarDatosTipo(TipoInformacion tipo, Map<String, dynamic> datos) {
    switch (tipo) {
      case TipoInformacion.presupuesto:
        if (!datos.containsKey('vigencia') || !datos.containsKey('aprobado')) {
          throw Exception('Datos de presupuesto deben incluir vigencia y aprobado');
        }
        break;
      case TipoInformacion.contratacion:
        if (!datos.containsKey('numero_contrato') || !datos.containsKey('valor')) {
          throw Exception('Datos de contratación deben incluir número de contrato y valor');
        }
        break;
      case TipoInformacion.nomina:
        if (!datos.containsKey('periodo') || !datos.containsKey('total')) {
          throw Exception('Datos de nómina deben incluir periodo y total');
        }
        break;
      case TipoInformacion.regalias:
        if (!datos.containsKey('periodo') || !datos.containsKey('monto')) {
          throw Exception('Datos de regalías deben incluir periodo y monto');
        }
        break;
      case TipoInformacion.proyectos:
        if (!datos.containsKey('codigo_bpin') || !datos.containsKey('nombre')) {
          throw Exception('Datos de proyectos deben incluir código BPIN y nombre');
        }
        break;
      case TipoInformacion.otros:
        // No hay validación específica
        break;
    }
  }

  /// Construye el payload según especificación del portal
  Map<String, dynamic> _construirPayload(
    TipoInformacion tipo,
    Map<String, dynamic> datos,
    String entidadId,
    DateTime fechaPublicacion,
  ) {
    return {
      'tipo': tipo.toString().split('.').last,
      'entidad_id': entidadId,
      'datos': datos,
      'fecha_publicacion': fechaPublicacion.toIso8601String(),
      'formato': 'json',
      'version': '1.0',
    };
  }

  /// Registra o actualiza la trazabilidad local de la publicación.
  Future<void> _registrarPublicacionLocal({
    required String id,
    required String entidadId,
    required String usuarioId,
    required TipoInformacion tipo,
    required String portalId,
    required String urlPublicacion,
    required String? referenciaInterna,
    required DateTime fechaPublicacion,
    required String estado,
    required Map<String, dynamic> datos,
    String? error,
  }) async {
    await _ensureTrackingTable();
    final now = DateTime.now().toIso8601String();
    final existing = await database.query(
      'publicaciones_portal',
      columns: ['id', 'created_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final createdAt = existing.isEmpty
        ? now
        : existing.first['created_at']?.toString() ?? now;
    await database.insert(
      'publicaciones_portal',
      {
        'id': id,
        'entidad_id': entidadId,
        'usuario_id': usuarioId,
        'tipo': tipo.name,
        'portal_id': portalId.isEmpty ? null : portalId,
        'url_publicacion': urlPublicacion.isEmpty ? null : urlPublicacion,
        'referencia_interna': referenciaInterna,
        'datos_json': jsonEncode(datos),
        'fecha_publicacion': fechaPublicacion.toIso8601String(),
        'estado': estado,
        'error': error,
        'created_at': createdAt,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Obtiene publicaciones pendientes/error conservando el payload original
  /// para que el reintento sea idempotente sobre el mismo registro local.
  Future<List<Map<String, dynamic>>> _obtenerPublicacionesPendientes(
    String entidadId,
  ) async {
    await _ensureTrackingTable();
    final rows = await database.query(
      'publicaciones_portal',
      where: "entidad_id = ? AND estado IN ('pendiente', 'error')",
      whereArgs: [entidadId],
      orderBy: 'updated_at ASC',
    );
    return rows.map((row) {
      final copy = Map<String, dynamic>.from(row);
      final raw = row['datos_json']?.toString() ?? '{}';
      final decoded = jsonDecode(raw);
      copy['datos'] = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      copy['fecha_publicacion'] = row['fecha_publicacion']?.toString();
      copy['referencia_interna'] = row['referencia_interna']?.toString();
      return copy;
    }).toList();
  }
}

