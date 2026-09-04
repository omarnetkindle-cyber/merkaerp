/// Modelo de Consolidación NICSP 40
/// NICSP 40 - Información a revelar sobre transferencias
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoTransferencia { subsidio, transferencia, donacion, otro }

class ConsolidacionNICSP40 {
  final String id;
  final String entidadId;
  final String numeroConsolidacion; // Formato: CN-YYYY-NNNNNN
  final String vigencia;
  final String entidadOrigen;
  final String entidadDestino;
  final TipoTransferencia tipoTransferencia;
  final String descripcion;
  final MoneyValue valorTransferido;
  final MoneyValue valorEjecutado;
  final MoneyValue valorNoEjecutado;
  final DateTime fechaTransferencia;
  final String? proyecto;
  final String? observaciones;

  ConsolidacionNICSP40({
    required this.id,
    required this.entidadId,
    required this.numeroConsolidacion,
    required this.vigencia,
    required this.entidadOrigen,
    required this.entidadDestino,
    required this.tipoTransferencia,
    required this.descripcion,
    required this.valorTransferido,
    required this.valorEjecutado,
    required this.valorNoEjecutado,
    required this.fechaTransferencia,
    this.proyecto,
    this.observaciones,
  });

  factory ConsolidacionNICSP40.fromJson(Map<String, dynamic> json) {
    return ConsolidacionNICSP40(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroConsolidacion: json['numero_consolidacion'] as String,
      vigencia: json['vigencia'] as String,
      entidadOrigen: json['entidad_origen'] as String,
      entidadDestino: json['entidad_destino'] as String,
      tipoTransferencia: TipoTransferencia.values.firstWhere(
        (e) =>
            e.toString() == 'TipoTransferencia.${json['tipo_transferencia']}',
      ),
      descripcion: json['descripcion'] as String,
      valorTransferido: publicMoneyFromSql(json['valor_transferido']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      valorNoEjecutado: publicMoneyFromSql(json['valor_no_ejecutado']),
      fechaTransferencia: DateTime.parse(json['fecha_transferencia'] as String),
      proyecto: json['proyecto'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_consolidacion': numeroConsolidacion,
      'vigencia': vigencia,
      'entidad_origen': entidadOrigen,
      'entidad_destino': entidadDestino,
      'tipo_transferencia': tipoTransferencia.toString().split('.').last,
      'descripcion': descripcion,
      'valor_transferido': valorTransferido.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'valor_no_ejecutado': valorNoEjecutado.toSql(),
      'fecha_transferencia': fechaTransferencia.toIso8601String(),
      'proyecto': proyecto,
      'observaciones': observaciones,
    };
  }

  double calcularPorcentajeEjecucion() {
    if (valorTransferido == publicMoneyZero()) return 0;
    return (valorEjecutado.minorUnits / valorTransferido.minorUnits) * 100;
  }

  ConsolidacionNICSP40 copyWith({
    String? id,
    String? entidadId,
    String? numeroConsolidacion,
    String? vigencia,
    String? entidadOrigen,
    String? entidadDestino,
    TipoTransferencia? tipoTransferencia,
    String? descripcion,
    MoneyValue? valorTransferido,
    MoneyValue? valorEjecutado,
    MoneyValue? valorNoEjecutado,
    DateTime? fechaTransferencia,
    String? proyecto,
    String? observaciones,
  }) {
    return ConsolidacionNICSP40(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroConsolidacion: numeroConsolidacion ?? this.numeroConsolidacion,
      vigencia: vigencia ?? this.vigencia,
      entidadOrigen: entidadOrigen ?? this.entidadOrigen,
      entidadDestino: entidadDestino ?? this.entidadDestino,
      tipoTransferencia: tipoTransferencia ?? this.tipoTransferencia,
      descripcion: descripcion ?? this.descripcion,
      valorTransferido: valorTransferido ?? this.valorTransferido,
      valorEjecutado: valorEjecutado ?? this.valorEjecutado,
      valorNoEjecutado: valorNoEjecutado ?? this.valorNoEjecutado,
      fechaTransferencia: fechaTransferencia ?? this.fechaTransferencia,
      proyecto: proyecto ?? this.proyecto,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
