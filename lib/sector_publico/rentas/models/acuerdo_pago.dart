/// Modelo de Acuerdo de Pago
/// ET Art. 814 - Acuerdos para deudores morosos. Al firmar, pierde derecho a prescripción
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum EstadoAcuerdo { activo, cumplido, incumplido, cancelado }

class AcuerdoPago {
  final String id;
  final String entidadId;
  final String numeroAcuerdo; // Formato: AP-YYYY-NNNNNN
  final String liquidacionId;
  final String numeroLiquidacion;
  final String contribuyenteId;
  final String contribuyenteNombre;
  final MoneyValue valorOriginal;
  final MoneyValue valorPagado;
  final MoneyValue saldoPendiente;
  final int numeroCuotas;
  final MoneyValue valorCuota;
  final DateTime fechaFirma;
  final DateTime fechaPrimeraCuota;
  final int periodicidadDias; // Días entre cuotas (ej. 30)
  final EstadoAcuerdo estado;
  final String? observaciones;

  AcuerdoPago({
    required this.id,
    required this.entidadId,
    required this.numeroAcuerdo,
    required this.liquidacionId,
    required this.numeroLiquidacion,
    required this.contribuyenteId,
    required this.contribuyenteNombre,
    required this.valorOriginal,
    required this.valorPagado,
    required this.saldoPendiente,
    required this.numeroCuotas,
    required this.valorCuota,
    required this.fechaFirma,
    required this.fechaPrimeraCuota,
    required this.periodicidadDias,
    required this.estado,
    this.observaciones,
  });

  factory AcuerdoPago.fromJson(Map<String, dynamic> json) {
    return AcuerdoPago(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroAcuerdo: json['numero_acuerdo'] as String,
      liquidacionId: json['liquidacion_id'] as String,
      numeroLiquidacion: json['numero_liquidacion'] as String,
      contribuyenteId: json['contribuyente_id'] as String,
      contribuyenteNombre: json['contribuyente_nombre'] as String,
      valorOriginal: publicMoneyFromSql(json['valor_original']),
      valorPagado: publicMoneyFromSql(json['valor_pagado']),
      saldoPendiente: publicMoneyFromSql(json['saldo_pendiente']),
      numeroCuotas: json['numero_cuotas'] as int,
      valorCuota: publicMoneyFromSql(json['valor_cuota']),
      fechaFirma: DateTime.parse(json['fecha_firma'] as String),
      fechaPrimeraCuota: DateTime.parse(json['fecha_primera_cuota'] as String),
      periodicidadDias: json['periodicidad_dias'] as int,
      estado: EstadoAcuerdo.values.firstWhere(
        (e) => e.toString() == 'EstadoAcuerdo.${json['estado']}',
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_acuerdo': numeroAcuerdo,
      'liquidacion_id': liquidacionId,
      'numero_liquidacion': numeroLiquidacion,
      'contribuyente_id': contribuyenteId,
      'contribuyente_nombre': contribuyenteNombre,
      'valor_original': valorOriginal.toSql(),
      'valor_pagado': valorPagado.toSql(),
      'saldo_pendiente': saldoPendiente.toSql(),
      'numero_cuotas': numeroCuotas,
      'valor_cuota': valorCuota.toSql(),
      'fecha_firma': fechaFirma.toIso8601String(),
      'fecha_primera_cuota': fechaPrimeraCuota.toIso8601String(),
      'periodicidad_dias': periodicidadDias,
      'estado': estado.toString().split('.').last,
      'observaciones': observaciones,
    };
  }

  /// Verifica si el acuerdo está vigente
  bool estaVigente() {
    return estado == EstadoAcuerdo.activo && saldoPendiente > publicMoneyZero();
  }

  /// Calcula el número de cuotas pagadas
  int calcularCuotasPagadas() {
    return (valorOriginal - saldoPendiente).minorUnits ~/ valorCuota.minorUnits;
  }

  /// Calcula el número de cuotas pendientes
  int calcularCuotasPendientes() {
    return saldoPendiente.minorUnits ~/ valorCuota.minorUnits;
  }

  /// Verifica si hay cuota vencida
  bool tieneCuotaVencida() {
    if (!estaVigente()) return false;

    final cuotasPagadas = calcularCuotasPagadas();
    final fechaUltimaCuotaPagada = fechaPrimeraCuota.add(
      Duration(days: periodicidadDias * cuotasPagadas),
    );
    final fechaProximaCuota = fechaUltimaCuotaPagada.add(
      Duration(days: periodicidadDias),
    );

    return DateTime.now().isAfter(fechaProximaCuota);
  }

  AcuerdoPago copyWith({
    String? id,
    String? entidadId,
    String? numeroAcuerdo,
    String? liquidacionId,
    String? numeroLiquidacion,
    String? contribuyenteId,
    String? contribuyenteNombre,
    MoneyValue? valorOriginal,
    MoneyValue? valorPagado,
    MoneyValue? saldoPendiente,
    int? numeroCuotas,
    MoneyValue? valorCuota,
    DateTime? fechaFirma,
    DateTime? fechaPrimeraCuota,
    int? periodicidadDias,
    EstadoAcuerdo? estado,
    String? observaciones,
  }) {
    return AcuerdoPago(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroAcuerdo: numeroAcuerdo ?? this.numeroAcuerdo,
      liquidacionId: liquidacionId ?? this.liquidacionId,
      numeroLiquidacion: numeroLiquidacion ?? this.numeroLiquidacion,
      contribuyenteId: contribuyenteId ?? this.contribuyenteId,
      contribuyenteNombre: contribuyenteNombre ?? this.contribuyenteNombre,
      valorOriginal: valorOriginal ?? this.valorOriginal,
      valorPagado: valorPagado ?? this.valorPagado,
      saldoPendiente: saldoPendiente ?? this.saldoPendiente,
      numeroCuotas: numeroCuotas ?? this.numeroCuotas,
      valorCuota: valorCuota ?? this.valorCuota,
      fechaFirma: fechaFirma ?? this.fechaFirma,
      fechaPrimeraCuota: fechaPrimeraCuota ?? this.fechaPrimeraCuota,
      periodicidadDias: periodicidadDias ?? this.periodicidadDias,
      estado: estado ?? this.estado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
