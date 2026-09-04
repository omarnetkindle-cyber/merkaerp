/// Modelo de Reporte de Transparencia
/// Ley 1712 de 2014 - Transparencia y Acceso a la Información Pública
library;


enum TipoReporteTransparencia {
  contratacion,
  presupuesto,
  personal,
  regalias,
  otros,
}

enum EstadoReporte {
  borrador,
  publicado,
  archivado,
}

class ReporteTransparencia {
  final String id;
  final String entidadId;
  final String numeroReporte; // Formato: RT-YYYY-NNNNNN
  final TipoReporteTransparencia tipoReporte;
  final String titulo;
  final String descripcion;
  final DateTime periodoInicio;
  final DateTime periodoFin;
  final String? urlPublicacion;
  final EstadoReporte estado;
  final DateTime fechaPublicacion;
  final String usuarioPublico;
  final String? observaciones;

  ReporteTransparencia({
    required this.id,
    required this.entidadId,
    required this.numeroReporte,
    required this.tipoReporte,
    required this.titulo,
    required this.descripcion,
    required this.periodoInicio,
    required this.periodoFin,
    this.urlPublicacion,
    required this.estado,
    required this.fechaPublicacion,
    required this.usuarioPublico,
    this.observaciones,
  });

  factory ReporteTransparencia.fromJson(Map<String, dynamic> json) {
    return ReporteTransparencia(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroReporte: json['numero_reporte'] as String,
      tipoReporte: TipoReporteTransparencia.values.firstWhere(
        (e) => e.toString() == 'TipoReporteTransparencia.${json['tipo_reporte']}',
      ),
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String,
      periodoInicio: DateTime.parse(json['periodo_inicio'] as String),
      periodoFin: DateTime.parse(json['periodo_fin'] as String),
      urlPublicacion: json['url_publicacion'] as String?,
      estado: EstadoReporte.values.firstWhere(
        (e) => e.toString() == 'EstadoReporte.${json['estado']}',
      ),
      fechaPublicacion: DateTime.parse(json['fecha_publicacion'] as String),
      usuarioPublico: json['usuario_publico'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_reporte': numeroReporte,
      'tipo_reporte': tipoReporte.toString().split('.').last,
      'titulo': titulo,
      'descripcion': descripcion,
      'periodo_inicio': periodoInicio.toIso8601String(),
      'periodo_fin': periodoFin.toIso8601String(),
      'url_publicacion': urlPublicacion,
      'estado': estado.toString().split('.').last,
      'fecha_publicacion': fechaPublicacion.toIso8601String(),
      'usuario_publico': usuarioPublico,
      'observaciones': observaciones,
    };
  }

  ReporteTransparencia copyWith({
    String? id,
    String? entidadId,
    String? numeroReporte,
    TipoReporteTransparencia? tipoReporte,
    String? titulo,
    String? descripcion,
    DateTime? periodoInicio,
    DateTime? periodoFin,
    String? urlPublicacion,
    EstadoReporte? estado,
    DateTime? fechaPublicacion,
    String? usuarioPublico,
    String? observaciones,
  }) {
    return ReporteTransparencia(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroReporte: numeroReporte ?? this.numeroReporte,
      tipoReporte: tipoReporte ?? this.tipoReporte,
      titulo: titulo ?? this.titulo,
      descripcion: descripcion ?? this.descripcion,
      periodoInicio: periodoInicio ?? this.periodoInicio,
      periodoFin: periodoFin ?? this.periodoFin,
      urlPublicacion: urlPublicacion ?? this.urlPublicacion,
      estado: estado ?? this.estado,
      fechaPublicacion: fechaPublicacion ?? this.fechaPublicacion,
      usuarioPublico: usuarioPublico ?? this.usuarioPublico,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
