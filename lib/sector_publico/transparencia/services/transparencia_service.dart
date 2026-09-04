/// Servicio de Transparencia
/// Ley 1712 de 2014
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/reporte_transparencia.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../../../integrations/application/institutional_connector_service.dart';

class TransparenciaService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();
  final InstitutionalConnectorService _connector = InstitutionalConnectorService.instance;

  TransparenciaService({
    required this.db,
    required this.auditoriaService,
  });

  /// Crea un reporte de transparencia
  Future<ReporteTransparencia> crearReporteTransparencia({
    required String entidadId,
    required String usuarioId,
    required TipoReporteTransparencia tipoReporte,
    required String titulo,
    required String descripcion,
    required DateTime periodoInicio,
    required DateTime periodoFin,
  }) async {
    final id = _uuid.v4();
    final numeroReporte = 'RT-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaPublicacion = DateTime.now();

    final reporte = ReporteTransparencia(
      id: id,
      entidadId: entidadId,
      numeroReporte: numeroReporte,
      tipoReporte: tipoReporte,
      titulo: titulo,
      descripcion: descripcion,
      periodoInicio: periodoInicio,
      periodoFin: periodoFin,
      estado: EstadoReporte.borrador,
      fechaPublicacion: fechaPublicacion,
      usuarioPublico: usuarioId,
    );

    await db.insert('reportes_transparencia', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'transparencia',
      accion: 'creacion_reporte_transparencia',
      valorAnterior: {},
      valorNuevo: {
        'reporte_id': id,
        'numero_reporte': numeroReporte,
        'tipo_reporte': tipoReporte.toString(),
      },
      referenciaId: id,
    );

    return reporte;
  }

  /// Registra evidencia de una publicación realizada por fuera de MerkaERP.
  /// No representa una transmisión automática; exige una URL HTTPS verificable.
  Future<ReporteTransparencia> registrarPublicacionExterna({
    required String entidadId,
    required String usuarioId,
    required String reporteId,
    required String urlPublicacion,
  }) async {
    final uri = Uri.tryParse(urlPublicacion.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'https' || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      throw ArgumentError('La evidencia de publicación debe ser una URL HTTPS válida.');
    }
    final reporteResult = await db.query(
      'reportes_transparencia',
      where: 'id = ?',
      whereArgs: [reporteId],
    );

    if (reporteResult.isEmpty) {
      throw Exception('Reporte no encontrado');
    }

    final reporte = ReporteTransparencia.fromJson(reporteResult.first);

    if (reporte.estado != EstadoReporte.borrador) {
      throw Exception('Solo se pueden publicar reportes en estado borrador');
    }

    await db.update(
      'reportes_transparencia',
      {
        'estado': EstadoReporte.publicado.toString().split('.').last,
        'url_publicacion': urlPublicacion,
      },
      where: 'id = ?',
      whereArgs: [reporteId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'transparencia',
      accion: 'registro_publicacion_externa_transparencia',
      valorAnterior: {'estado_anterior': reporte.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoReporte.publicado.toString(),
        'url_publicacion': urlPublicacion,
      },
      referenciaId: reporteId,
    );

    return reporte.copyWith(
      estado: EstadoReporte.publicado,
      urlPublicacion: urlPublicacion,
    );
  }

  /// Transmite un reporte usando el portal configurado por la entidad.
  /// Solo cambia a PUBLICADO después de una respuesta HTTP 2xx real.
  Future<ReporteTransparencia> transmitirReporte({
    required String entidadId,
    required String usuarioId,
    required String reporteId,
  }) async {
    final rows = await db.query(
      'reportes_transparencia',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('Reporte no encontrado');
    final reporte = ReporteTransparencia.fromJson(rows.first);
    if (reporte.estado != EstadoReporte.borrador) {
      throw Exception('Solo se pueden transmitir reportes en estado borrador');
    }

    final response = await _connector.postJson(
      'transparency_portal',
      pathField: 'publication_path',
      payload: {
        'reporte_id': reporte.id,
        'numero_reporte': reporte.numeroReporte,
        'tipo': reporte.tipoReporte.toString().split('.').last,
        'titulo': reporte.titulo,
        'descripcion': reporte.descripcion,
        'periodo_inicio': reporte.periodoInicio.toUtc().toIso8601String(),
        'periodo_fin': reporte.periodoFin.toUtc().toIso8601String(),
        'entidad_id': entidadId,
      },
    );
    if (!response.ok) throw Exception(response.message);

    final data = response.data;
    final map = data is Map
        ? data.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
    final url = (map['url'] ?? map['url_publicacion'] ?? map['public_url'])
        ?.toString()
        .trim();
    final reference = (map['id'] ?? map['reference'] ?? map['referencia'])
        ?.toString()
        .trim();
    final now = DateTime.now().toUtc();
    await db.update(
      'reportes_transparencia',
      {
        'estado': EstadoReporte.publicado.toString().split('.').last,
        if (url != null && url.isNotEmpty) 'url_publicacion': url,
        'fecha_publicacion': now.toIso8601String(),
        'observaciones': reference == null || reference.isEmpty
            ? 'Transmisión aceptada por el portal configurado.'
            : 'Transmisión aceptada. Referencia externa: $reference',
      },
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
    );
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'transparencia',
      accion: 'transmision_portal_transparencia',
      valorAnterior: {'estado_anterior': reporte.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoReporte.publicado.toString(),
        'http_status': response.statusCode,
        if (reference != null && reference.isNotEmpty) 'referencia_externa': reference,
        if (url != null && url.isNotEmpty) 'url_publicacion': url,
      },
      referenciaId: reporteId,
    );
    return reporte.copyWith(
      estado: EstadoReporte.publicado,
      fechaPublicacion: now,
      urlPublicacion: url == null || url.isEmpty ? reporte.urlPublicacion : url,
      observaciones: reference == null || reference.isEmpty
          ? 'Transmisión aceptada por el portal configurado.'
          : 'Transmisión aceptada. Referencia externa: $reference',
    );
  }

  Future<List<ReporteTransparencia>> consultarReportes({
    required String entidadId,
    EstadoReporte? estado,
  }) async {
    String query = 'SELECT * FROM reportes_transparencia WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_publicacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => ReporteTransparencia.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}

