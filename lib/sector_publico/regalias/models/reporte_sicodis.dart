/// Modelo de Reporte y Certificación SICODIS SGP (DNP Colombia)
/// Sistema de Información para la Captura de Datos de la Inversión Social (Ley 1176 de 2007)
library;

import 'dart:convert';

class ReporteSICODIS {
  final String id;
  final String entidadId;
  final String vigencia;
  final String sectorParticipacion; // Educación, Salud, Agua Potable, Propósito General
  final DateTime fechaGeneracion;
  final String usuarioGenero;
  final Map<String, dynamic> datos;
  final String estado; // generado, enviado, certificado
  final String? observaciones;

  ReporteSICODIS({
    required this.id,
    required this.entidadId,
    required this.vigencia,
    required this.sectorParticipacion,
    required this.fechaGeneracion,
    required this.usuarioGenero,
    required this.datos,
    required this.estado,
    this.observaciones,
  });

  factory ReporteSICODIS.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> datosMap;
    if (json['datos'] is String) {
      datosMap = jsonDecode(json['datos'] as String) as Map<String, dynamic>;
    } else {
      datosMap = json['datos'] as Map<String, dynamic>;
    }

    return ReporteSICODIS(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      sectorParticipacion: json['sector_participacion'] as String,
      fechaGeneracion: DateTime.parse(json['fecha_generacion'] as String),
      usuarioGenero: json['usuario_genero'] as String,
      datos: datosMap,
      estado: json['estado'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'sector_participacion': sectorParticipacion,
      'fecha_generacion': fechaGeneracion.toIso8601String(),
      'usuario_genero': usuarioGenero,
      'datos': jsonEncode(datos),
      'estado': estado,
      'observaciones': observaciones,
    };
  }
}
