/// Modelos de Reportes SIA Observa (Contraloría General de la República - CGR)
/// Consolidación anual de Contratación, Presupuesto y Nómina para Plan de Mejoramiento
library;

import 'dart:convert';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoReporteSIAObserva {
  planMejoramiento,
  contratacionAnual,
  ejecucionNominaPresupuesto,
}

class ReporteSIAObserva {
  final String id;
  final String entidadId;
  final TipoReporteSIAObserva tipoReporte;
  final String vigencia;
  final DateTime fechaGeneracion;
  final String usuarioGenero;
  final Map<String, dynamic> datos;
  final String estado; // generado, rendido, aprobado
  final String? observaciones;

  ReporteSIAObserva({
    required this.id,
    required this.entidadId,
    required this.tipoReporte,
    required this.vigencia,
    required this.fechaGeneracion,
    required this.usuarioGenero,
    required this.datos,
    required this.estado,
    this.observaciones,
  });

  factory ReporteSIAObserva.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> datosMap;
    if (json['datos'] is String) {
      datosMap = jsonDecode(json['datos'] as String) as Map<String, dynamic>;
    } else {
      datosMap = json['datos'] as Map<String, dynamic>;
    }

    return ReporteSIAObserva(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      tipoReporte: TipoReporteSIAObserva.values.firstWhere(
        (e) => e.name == json['tipo_reporte'],
        orElse: () => TipoReporteSIAObserva.planMejoramiento,
      ),
      vigencia: json['vigencia'] as String,
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
      'tipo_reporte': tipoReporte.name,
      'vigencia': vigencia,
      'fecha_generacion': fechaGeneracion.toIso8601String(),
      'usuario_genero': usuarioGenero,
      'datos': jsonEncode(datos),
      'estado': estado,
      'observaciones': observaciones,
    };
  }

  String get nombreReporte {
    switch (tipoReporte) {
      case TipoReporteSIAObserva.planMejoramiento:
        return 'SIA Observa - Plan de Mejoramiento Anual (CGR)';
      case TipoReporteSIAObserva.contratacionAnual:
        return 'SIA Observa - Rendición Anual de Contratación';
      case TipoReporteSIAObserva.ejecucionNominaPresupuesto:
        return 'SIA Observa - Consolidado Nómina vs Presupuesto';
    }
  }
}

/// Datos consolidados para Plan de Mejoramiento SIA Observa
class DatosSIAObservaPlan {
  final int totalHallazgosAtendidos;
  final int totalAccionesImplementadas;
  final int totalContratosAuditados;
  final MoneyValue valorTotalContratado;
  final MoneyValue valorTotalEjecutadoPresupuesto;
  final MoneyValue valorTotalNominaLiquidada;
  final double cumplimientoPorcentaje;

  DatosSIAObservaPlan({
    required this.totalHallazgosAtendidos,
    required this.totalAccionesImplementadas,
    required this.totalContratosAuditados,
    required this.valorTotalContratado,
    required this.valorTotalEjecutadoPresupuesto,
    required this.valorTotalNominaLiquidada,
    required this.cumplimientoPorcentaje,
  });

  Map<String, dynamic> toJson() {
    return {
      'total_hallazgos_atendidos': totalHallazgosAtendidos,
      'total_acciones_implementadas': totalAccionesImplementadas,
      'total_contratos_auditados': totalContratosAuditados,
      'valor_total_contratado': publicMoneyForDisplay(valorTotalContratado),
      'valor_total_ejecutado_presupuesto': publicMoneyForDisplay(
        valorTotalEjecutadoPresupuesto,
      ),
      'valor_total_nomina_liquidada': publicMoneyForDisplay(
        valorTotalNominaLiquidada,
      ),
      'cumplimiento_porcentaje': cumplimientoPorcentaje,
    };
  }
}
