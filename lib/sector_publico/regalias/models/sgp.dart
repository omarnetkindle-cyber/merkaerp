/// Modelo de SGP (Sistema General de Participaciones)
/// Ley 1176 de 2007
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoParticipacion { salud, educacion, agua, saneamiento, otros }

enum EstadoSGP {
  asignado,
  transferido,
  recibido,
  enEjecucion,
  ejecutado,
  devuelto,
}

class SGP {
  final String id;
  final String entidadId;
  final String numeroSGP; // Formato: SGP-YYYY-NNNNNN
  final TipoParticipacion tipoParticipacion;
  final String programa;
  final String municipio;
  final String departamento;
  final MoneyValue valorAsignado;
  final MoneyValue valorTransferido;
  final MoneyValue valorRecibido;
  final MoneyValue valorEjecutado;
  final MoneyValue saldoDisponible;
  final DateTime vigencia;
  final DateTime fechaAsignacion;
  final DateTime? fechaTransferencia;
  final DateTime? fechaRecepcion;
  final EstadoSGP estado;
  final String? observaciones;

  SGP({
    required this.id,
    required this.entidadId,
    required this.numeroSGP,
    required this.tipoParticipacion,
    required this.programa,
    required this.municipio,
    required this.departamento,
    required this.valorAsignado,
    required this.valorTransferido,
    required this.valorRecibido,
    required this.valorEjecutado,
    required this.saldoDisponible,
    required this.vigencia,
    required this.fechaAsignacion,
    this.fechaTransferencia,
    this.fechaRecepcion,
    required this.estado,
    this.observaciones,
  });

  factory SGP.fromJson(Map<String, dynamic> json) {
    return SGP(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroSGP: json['numero_sgp'] as String,
      tipoParticipacion: TipoParticipacion.values.firstWhere(
        (e) =>
            e.toString() == 'TipoParticipacion.${json['tipo_participacion']}',
      ),
      programa: json['programa'] as String,
      municipio: json['municipio'] as String,
      departamento: json['departamento'] as String,
      valorAsignado: publicMoneyFromSql(json['valor_asignado']),
      valorTransferido: publicMoneyFromSql(json['valor_transferido']),
      valorRecibido: publicMoneyFromSql(json['valor_recibido']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      vigencia: DateTime.parse(json['vigencia'] as String),
      fechaAsignacion: DateTime.parse(json['fecha_asignacion'] as String),
      fechaTransferencia: json['fecha_transferencia'] != null
          ? DateTime.parse(json['fecha_transferencia'] as String)
          : null,
      fechaRecepcion: json['fecha_recepcion'] != null
          ? DateTime.parse(json['fecha_recepcion'] as String)
          : null,
      estado: EstadoSGP.values.firstWhere(
        (e) => e.toString() == 'EstadoSGP.${json['estado']}',
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_sgp': numeroSGP,
      'tipo_participacion': tipoParticipacion.toString().split('.').last,
      'programa': programa,
      'municipio': municipio,
      'departamento': departamento,
      'valor_asignado': valorAsignado.toSql(),
      'valor_transferido': valorTransferido.toSql(),
      'valor_recibido': valorRecibido.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'vigencia': vigencia.toIso8601String(),
      'fecha_asignacion': fechaAsignacion.toIso8601String(),
      'fecha_transferencia': fechaTransferencia?.toIso8601String(),
      'fecha_recepcion': fechaRecepcion?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'observaciones': observaciones,
    };
  }

  double calcularPorcentajeEjecucion() {
    if (valorRecibido == publicMoneyZero()) return 0;
    return (valorEjecutado.minorUnits / valorRecibido.minorUnits) * 100;
  }

  bool tieneSaldo() {
    return saldoDisponible > publicMoneyZero();
  }

  SGP copyWith({
    String? id,
    String? entidadId,
    String? numeroSGP,
    TipoParticipacion? tipoParticipacion,
    String? programa,
    String? municipio,
    String? departamento,
    MoneyValue? valorAsignado,
    MoneyValue? valorTransferido,
    MoneyValue? valorRecibido,
    MoneyValue? valorEjecutado,
    MoneyValue? saldoDisponible,
    DateTime? vigencia,
    DateTime? fechaAsignacion,
    DateTime? fechaTransferencia,
    DateTime? fechaRecepcion,
    EstadoSGP? estado,
    String? observaciones,
  }) {
    return SGP(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroSGP: numeroSGP ?? this.numeroSGP,
      tipoParticipacion: tipoParticipacion ?? this.tipoParticipacion,
      programa: programa ?? this.programa,
      municipio: municipio ?? this.municipio,
      departamento: departamento ?? this.departamento,
      valorAsignado: valorAsignado ?? this.valorAsignado,
      valorTransferido: valorTransferido ?? this.valorTransferido,
      valorRecibido: valorRecibido ?? this.valorRecibido,
      valorEjecutado: valorEjecutado ?? this.valorEjecutado,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      vigencia: vigencia ?? this.vigencia,
      fechaAsignacion: fechaAsignacion ?? this.fechaAsignacion,
      fechaTransferencia: fechaTransferencia ?? this.fechaTransferencia,
      fechaRecepcion: fechaRecepcion ?? this.fechaRecepcion,
      estado: estado ?? this.estado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
