/// Modelo de Regalía
/// Sistema General de Regalías (SGR) - Ley 141 de 1993
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoRegalia { hidrocarburos, carbon, oro, niquel, otros }

enum EstadoRegalia {
  estimada,
  recibida,
  distribuida,
  asignada,
  ejecutada,
  devuelta,
}

class Regalia {
  final String id;
  final String entidadId;
  final String numeroRegalia; // Formato: RG-YYYY-NNNNNN
  final TipoRegalia tipoRegalia;
  final String proyecto;
  final String municipio;
  final String departamento;
  final MoneyValue valorEstimado;
  final MoneyValue valorRecibido;
  final MoneyValue valorDistribuido;
  final MoneyValue valorAsignado;
  final MoneyValue valorEjecutado;
  final DateTime vigencia;
  final DateTime fechaEstimacion;
  final DateTime? fechaRecepcion;
  final DateTime? fechaDistribucion;
  final EstadoRegalia estado;
  final String? observaciones;

  Regalia({
    required this.id,
    required this.entidadId,
    required this.numeroRegalia,
    required this.tipoRegalia,
    required this.proyecto,
    required this.municipio,
    required this.departamento,
    required this.valorEstimado,
    required this.valorRecibido,
    required this.valorDistribuido,
    required this.valorAsignado,
    required this.valorEjecutado,
    required this.vigencia,
    required this.fechaEstimacion,
    this.fechaRecepcion,
    this.fechaDistribucion,
    required this.estado,
    this.observaciones,
  });

  factory Regalia.fromJson(Map<String, dynamic> json) {
    return Regalia(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroRegalia: json['numero_regalia'] as String,
      tipoRegalia: TipoRegalia.values.firstWhere(
        (e) => e.toString() == 'TipoRegalia.${json['tipo_regalia']}',
      ),
      proyecto: json['proyecto'] as String,
      municipio: json['municipio'] as String,
      departamento: json['departamento'] as String,
      valorEstimado: publicMoneyFromSql(json['valor_estimado']),
      valorRecibido: publicMoneyFromSql(json['valor_recibido']),
      valorDistribuido: publicMoneyFromSql(json['valor_distribuido']),
      valorAsignado: publicMoneyFromSql(json['valor_asignado']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      vigencia: DateTime.parse(json['vigencia'] as String),
      fechaEstimacion: DateTime.parse(json['fecha_estimacion'] as String),
      fechaRecepcion: json['fecha_recepcion'] != null
          ? DateTime.parse(json['fecha_recepcion'] as String)
          : null,
      fechaDistribucion: json['fecha_distribucion'] != null
          ? DateTime.parse(json['fecha_distribucion'] as String)
          : null,
      estado: EstadoRegalia.values.firstWhere(
        (e) => e.toString() == 'EstadoRegalia.${json['estado']}',
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_regalia': numeroRegalia,
      'tipo_regalia': tipoRegalia.toString().split('.').last,
      'proyecto': proyecto,
      'municipio': municipio,
      'departamento': departamento,
      'valor_estimado': valorEstimado.toSql(),
      'valor_recibido': valorRecibido.toSql(),
      'valor_distribuido': valorDistribuido.toSql(),
      'valor_asignado': valorAsignado.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'vigencia': vigencia.toIso8601String(),
      'fecha_estimacion': fechaEstimacion.toIso8601String(),
      'fecha_recepcion': fechaRecepcion?.toIso8601String(),
      'fecha_distribucion': fechaDistribucion?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'observaciones': observaciones,
    };
  }

  double calcularPorcentajeEjecucion() {
    if (valorAsignado == publicMoneyZero()) return 0;
    return (valorEjecutado.minorUnits / valorAsignado.minorUnits) * 100;
  }

  Regalia copyWith({
    String? id,
    String? entidadId,
    String? numeroRegalia,
    TipoRegalia? tipoRegalia,
    String? proyecto,
    String? municipio,
    String? departamento,
    MoneyValue? valorEstimado,
    MoneyValue? valorRecibido,
    MoneyValue? valorDistribuido,
    MoneyValue? valorAsignado,
    MoneyValue? valorEjecutado,
    DateTime? vigencia,
    DateTime? fechaEstimacion,
    DateTime? fechaRecepcion,
    DateTime? fechaDistribucion,
    EstadoRegalia? estado,
    String? observaciones,
  }) {
    return Regalia(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroRegalia: numeroRegalia ?? this.numeroRegalia,
      tipoRegalia: tipoRegalia ?? this.tipoRegalia,
      proyecto: proyecto ?? this.proyecto,
      municipio: municipio ?? this.municipio,
      departamento: departamento ?? this.departamento,
      valorEstimado: valorEstimado ?? this.valorEstimado,
      valorRecibido: valorRecibido ?? this.valorRecibido,
      valorDistribuido: valorDistribuido ?? this.valorDistribuido,
      valorAsignado: valorAsignado ?? this.valorAsignado,
      valorEjecutado: valorEjecutado ?? this.valorEjecutado,
      vigencia: vigencia ?? this.vigencia,
      fechaEstimacion: fechaEstimacion ?? this.fechaEstimacion,
      fechaRecepcion: fechaRecepcion ?? this.fechaRecepcion,
      fechaDistribucion: fechaDistribucion ?? this.fechaDistribucion,
      estado: estado ?? this.estado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
