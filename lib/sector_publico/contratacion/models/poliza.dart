/// Modelo de Póliza de Garantía
/// Ley 80 de 1993 - Pólizas obligatorias según tipo de contrato
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoPoliza {
  cumplimiento,
  correctaEjecucion,
  calidad,
  estabilidad,
  anticipo,
  salarios,
  prestacionesSociales,
}

enum EstadoPoliza { vigente, reclamada, pagada, anulada, vencida }

class Poliza {
  final String id;
  final String entidadId;
  final String contratoId;
  final String numeroContrato;
  final String numeroPoliza;
  final TipoPoliza tipoPoliza;
  final String aseguradora;
  final MoneyValue valorAsegurado;
  final DateTime fechaEmision;
  final DateTime fechaInicioVigencia;
  final DateTime fechaFinVigencia;
  final EstadoPoliza estado;
  final DateTime? fechaReclamacion;
  final DateTime? fechaPago;
  final String? observaciones;

  Poliza({
    required this.id,
    required this.entidadId,
    required this.contratoId,
    required this.numeroContrato,
    required this.numeroPoliza,
    required this.tipoPoliza,
    required this.aseguradora,
    required this.valorAsegurado,
    required this.fechaEmision,
    required this.fechaInicioVigencia,
    required this.fechaFinVigencia,
    required this.estado,
    this.fechaReclamacion,
    this.fechaPago,
    this.observaciones,
  });

  factory Poliza.fromJson(Map<String, dynamic> json) {
    return Poliza(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      contratoId: json['contrato_id'] as String,
      numeroContrato: json['numero_contrato'] as String,
      numeroPoliza: json['numero_poliza'] as String,
      tipoPoliza: TipoPoliza.values.firstWhere(
        (e) => e.toString() == 'TipoPoliza.${json['tipo_poliza']}',
      ),
      aseguradora: json['aseguradora'] as String,
      valorAsegurado: publicMoneyFromSql(json['valor_asegurado']),
      fechaEmision: DateTime.parse(json['fecha_emision'] as String),
      fechaInicioVigencia: DateTime.parse(
        json['fecha_inicio_vigencia'] as String,
      ),
      fechaFinVigencia: DateTime.parse(json['fecha_fin_vigencia'] as String),
      estado: EstadoPoliza.values.firstWhere(
        (e) => e.toString() == 'EstadoPoliza.${json['estado']}',
      ),
      fechaReclamacion: json['fecha_reclamacion'] != null
          ? DateTime.parse(json['fecha_reclamacion'] as String)
          : null,
      fechaPago: json['fecha_pago'] != null
          ? DateTime.parse(json['fecha_pago'] as String)
          : null,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'contrato_id': contratoId,
      'numero_contrato': numeroContrato,
      'numero_poliza': numeroPoliza,
      'tipo_poliza': tipoPoliza.toString().split('.').last,
      'aseguradora': aseguradora,
      'valor_asegurado': valorAsegurado.toSql(),
      'fecha_emision': fechaEmision.toIso8601String(),
      'fecha_inicio_vigencia': fechaInicioVigencia.toIso8601String(),
      'fecha_fin_vigencia': fechaFinVigencia.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'fecha_reclamacion': fechaReclamacion?.toIso8601String(),
      'fecha_pago': fechaPago?.toIso8601String(),
      'observaciones': observaciones,
    };
  }

  /// Verifica si la póliza está vigente
  bool estaVigente() {
    return estado == EstadoPoliza.vigente &&
        DateTime.now().isBefore(fechaFinVigencia) &&
        DateTime.now().isAfter(fechaInicioVigencia);
  }

  /// Verifica si está vencida
  bool estaVencida() {
    return DateTime.now().isAfter(fechaFinVigencia) &&
        estado != EstadoPoliza.pagada;
  }

  /// Verifica si se puede reclamar
  bool sePuedeReclamar() {
    return estaVigente();
  }

  Poliza copyWith({
    String? id,
    String? entidadId,
    String? contratoId,
    String? numeroContrato,
    String? numeroPoliza,
    TipoPoliza? tipoPoliza,
    String? aseguradora,
    MoneyValue? valorAsegurado,
    DateTime? fechaEmision,
    DateTime? fechaInicioVigencia,
    DateTime? fechaFinVigencia,
    EstadoPoliza? estado,
    DateTime? fechaReclamacion,
    DateTime? fechaPago,
    String? observaciones,
  }) {
    return Poliza(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      contratoId: contratoId ?? this.contratoId,
      numeroContrato: numeroContrato ?? this.numeroContrato,
      numeroPoliza: numeroPoliza ?? this.numeroPoliza,
      tipoPoliza: tipoPoliza ?? this.tipoPoliza,
      aseguradora: aseguradora ?? this.aseguradora,
      valorAsegurado: valorAsegurado ?? this.valorAsegurado,
      fechaEmision: fechaEmision ?? this.fechaEmision,
      fechaInicioVigencia: fechaInicioVigencia ?? this.fechaInicioVigencia,
      fechaFinVigencia: fechaFinVigencia ?? this.fechaFinVigencia,
      estado: estado ?? this.estado,
      fechaReclamacion: fechaReclamacion ?? this.fechaReclamacion,
      fechaPago: fechaPago ?? this.fechaPago,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
