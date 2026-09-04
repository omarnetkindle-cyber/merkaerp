/// Modelo de PDT (Plan de Desarrollo Territorial)
/// Plan de Desarrollo Territorial - 4 años
library;


enum EstadoPDT {
  borrador,
  aprobadoConcejo,
  aprobadoDepartamental,
  vigente,
  archivado,
}

class PDT {
  final String id;
  final String entidadId;
  final String vigencia; // 4 años (ej. 2024-2027)
  final String nombrePDT;
  final String vision;
  final String mision;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final EstadoPDT estado;
  final String? actoAdministrativo; // Acuerdo/Ordenanza de aprobación
  final DateTime? fechaAprobacion;
  final String? observaciones;

  PDT({
    required this.id,
    required this.entidadId,
    required this.vigencia,
    required this.nombrePDT,
    required this.vision,
    required this.mision,
    required this.fechaInicio,
    required this.fechaFin,
    required this.estado,
    this.actoAdministrativo,
    this.fechaAprobacion,
    this.observaciones,
  });

  factory PDT.fromJson(Map<String, dynamic> json) {
    return PDT(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      nombrePDT: json['nombre_pdt'] as String,
      vision: json['vision'] as String,
      mision: json['mision'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      estado: EstadoPDT.values.firstWhere(
        (e) => e.toString() == 'EstadoPDT.${json['estado']}',
      ),
      actoAdministrativo: json['acto_administrativo'] as String?,
      fechaAprobacion: json['fecha_aprobacion'] != null
          ? DateTime.parse(json['fecha_aprobacion'] as String)
          : null,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'nombre_pdt': nombrePDT,
      'vision': vision,
      'mision': mision,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'acto_administrativo': actoAdministrativo,
      'fecha_aprobacion': fechaAprobacion?.toIso8601String(),
      'observaciones': observaciones,
    };
  }

  /// Verifica si está vigente
  bool estaVigente() {
    return estado == EstadoPDT.vigente &&
           DateTime.now().isAfter(fechaInicio) &&
           DateTime.now().isBefore(fechaFin);
  }

  /// Verifica si requiere aprobación departamental
  bool requiereAprobacionDepartamental() {
    return estado == EstadoPDT.aprobadoConcejo;
  }

  PDT copyWith({
    String? id,
    String? entidadId,
    String? vigencia,
    String? nombrePDT,
    String? vision,
    String? mision,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    EstadoPDT? estado,
    String? actoAdministrativo,
    DateTime? fechaAprobacion,
    String? observaciones,
  }) {
    return PDT(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      vigencia: vigencia ?? this.vigencia,
      nombrePDT: nombrePDT ?? this.nombrePDT,
      vision: vision ?? this.vision,
      mision: mision ?? this.mision,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      estado: estado ?? this.estado,
      actoAdministrativo: actoAdministrativo ?? this.actoAdministrativo,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
