/// Modelo de Proceso Disciplinario
/// Control disciplinario - Código Disciplinario Único
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoProceso { investigacion, sancion, otro }

enum EstadoProcesoDisciplinario {
  iniciado,
  enInvestigacion,
  enDecision,
  sancionado,
  absuelto,
  archivado,
}

class ProcesoDisciplinario {
  final String id;
  final String entidadId;
  final String numeroProceso; // Formato: PD-YYYY-NNNNNN
  final TipoProceso tipoProceso;
  final String servidorPublico;
  final String identificacion;
  final String cargo;
  final String dependencia;
  final String descripcion;
  final DateTime fechaInicio;
  final DateTime? fechaDecision;
  final EstadoProcesoDisciplinario estado;
  final String? sancion;
  final MoneyValue? montoSancion;
  final String? observaciones;

  ProcesoDisciplinario({
    required this.id,
    required this.entidadId,
    required this.numeroProceso,
    required this.tipoProceso,
    required this.servidorPublico,
    required this.identificacion,
    required this.cargo,
    required this.dependencia,
    required this.descripcion,
    required this.fechaInicio,
    this.fechaDecision,
    required this.estado,
    this.sancion,
    this.montoSancion,
    this.observaciones,
  });

  factory ProcesoDisciplinario.fromJson(Map<String, dynamic> json) {
    return ProcesoDisciplinario(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroProceso: json['numero_proceso'] as String,
      tipoProceso: TipoProceso.values.firstWhere(
        (e) => e.toString() == 'TipoProceso.${json['tipo_proceso']}',
      ),
      servidorPublico: json['servidor_publico'] as String,
      identificacion: json['identificacion'] as String,
      cargo: json['cargo'] as String,
      dependencia: json['dependencia'] as String,
      descripcion: json['descripcion'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaDecision: json['fecha_decision'] != null
          ? DateTime.parse(json['fecha_decision'] as String)
          : null,
      estado: EstadoProcesoDisciplinario.values.firstWhere(
        (e) => e.toString() == 'EstadoProcesoDisciplinario.${json['estado']}',
      ),
      sancion: json['sancion'] as String?,
      montoSancion: json['monto_sancion'] != null
          ? publicMoneyFromSql(json['monto_sancion'])
          : null,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_proceso': numeroProceso,
      'tipo_proceso': tipoProceso.toString().split('.').last,
      'servidor_publico': servidorPublico,
      'identificacion': identificacion,
      'cargo': cargo,
      'dependencia': dependencia,
      'descripcion': descripcion,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_decision': fechaDecision?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'sancion': sancion,
      'monto_sancion': montoSancion?.toSql(),
      'observaciones': observaciones,
    };
  }

  ProcesoDisciplinario copyWith({
    String? id,
    String? entidadId,
    String? numeroProceso,
    TipoProceso? tipoProceso,
    String? servidorPublico,
    String? identificacion,
    String? cargo,
    String? dependencia,
    String? descripcion,
    DateTime? fechaInicio,
    DateTime? fechaDecision,
    EstadoProcesoDisciplinario? estado,
    String? sancion,
    MoneyValue? montoSancion,
    String? observaciones,
  }) {
    return ProcesoDisciplinario(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroProceso: numeroProceso ?? this.numeroProceso,
      tipoProceso: tipoProceso ?? this.tipoProceso,
      servidorPublico: servidorPublico ?? this.servidorPublico,
      identificacion: identificacion ?? this.identificacion,
      cargo: cargo ?? this.cargo,
      dependencia: dependencia ?? this.dependencia,
      descripcion: descripcion ?? this.descripcion,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaDecision: fechaDecision ?? this.fechaDecision,
      estado: estado ?? this.estado,
      sancion: sancion ?? this.sancion,
      montoSancion: montoSancion ?? this.montoSancion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
