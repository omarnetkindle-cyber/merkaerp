/// Modelo de Reporte SPGR (Sistema de Presupuesto y Giro de Regalías - MHCP / DNP)
/// Reporte bienal de giros y avance de proyectos SGR OCAD
library;

import 'dart:convert';

class ReporteSPGR {
  final String id;
  final String entidadId;
  final String bienalidad; // ej. 2025-2026
  final DateTime fechaGeneracion;
  final String usuarioGenero;
  final Map<String, dynamic> datos;
  final String estado; // generado, enviado, validado
  final String? observaciones;

  ReporteSPGR({
    required this.id,
    required this.entidadId,
    required this.bienalidad,
    required this.fechaGeneracion,
    required this.usuarioGenero,
    required this.datos,
    required this.estado,
    this.observaciones,
  });

  factory ReporteSPGR.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> datosMap;
    if (json['datos'] is String) {
      datosMap = jsonDecode(json['datos'] as String) as Map<String, dynamic>;
    } else {
      datosMap = json['datos'] as Map<String, dynamic>;
    }

    return ReporteSPGR(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      bienalidad: json['bienalidad'] as String,
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
      'bienalidad': bienalidad,
      'fecha_generacion': fechaGeneracion.toIso8601String(),
      'usuario_genero': usuarioGenero,
      'datos': jsonEncode(datos),
      'estado': estado,
      'observaciones': observaciones,
    };
  }
}
