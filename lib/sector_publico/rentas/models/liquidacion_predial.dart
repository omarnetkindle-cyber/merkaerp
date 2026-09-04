/// Modelo de Liquidación de Impuesto Predial
/// Ley 44 de 1990 - Cálculo: Avalúo × Tarifa (por mil)
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum EstadoLiquidacion {
  generada,
  notificada,
  pagada,
  enAcuerdo,
  vencida,
  enCobroCoactivo,
}

class LiquidacionPredial {
  final String id;
  final String entidadId;
  final String numeroLiquidacion; // Formato: LP-YYYY-NNNNNN
  final String vigencia;
  final String predioId;
  final String numeroPredial;
  final String contribuyenteId;
  final String contribuyenteNombre;
  final String contribuyenteIdentificacion;
  final MoneyValue avaluoCatastral;
  final double tarifa; // Por mil (ej. 5 = 5‰)
  final MoneyValue impuestoBase;
  final MoneyValue descuentoProntoPago; // Hasta 10% si paga en Q1
  final MoneyValue interesesMora;
  final MoneyValue totalPagar;
  final DateTime fechaLiquidacion;
  final DateTime fechaVencimiento; // Generalmente 6 meses
  final DateTime? fechaPago;
  final EstadoLiquidacion estado;
  final String? acuerdoPagoId;
  final String? observaciones;

  LiquidacionPredial({
    required this.id,
    required this.entidadId,
    required this.numeroLiquidacion,
    required this.vigencia,
    required this.predioId,
    required this.numeroPredial,
    required this.contribuyenteId,
    required this.contribuyenteNombre,
    required this.contribuyenteIdentificacion,
    required this.avaluoCatastral,
    required this.tarifa,
    required this.impuestoBase,
    required this.descuentoProntoPago,
    required this.interesesMora,
    required this.totalPagar,
    required this.fechaLiquidacion,
    required this.fechaVencimiento,
    this.fechaPago,
    required this.estado,
    this.acuerdoPagoId,
    this.observaciones,
  });

  factory LiquidacionPredial.fromJson(Map<String, dynamic> json) {
    return LiquidacionPredial(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroLiquidacion: json['numero_liquidacion'] as String,
      vigencia: json['vigencia'] as String,
      predioId: json['predio_id'] as String,
      numeroPredial: json['numero_predial'] as String,
      contribuyenteId: json['contribuyente_id'] as String,
      contribuyenteNombre: json['contribuyente_nombre'] as String,
      contribuyenteIdentificacion:
          json['contribuyente_identificacion'] as String,
      avaluoCatastral: publicMoneyFromSql(json['avaluo_catastral']),
      tarifa: (json['tarifa'] as num).toDouble(),
      impuestoBase: publicMoneyFromSql(json['impuesto_base']),
      descuentoProntoPago: publicMoneyFromSql(json['descuento_pronto_pago']),
      interesesMora: publicMoneyFromSql(json['intereses_mora']),
      totalPagar: publicMoneyFromSql(json['total_pagar']),
      fechaLiquidacion: DateTime.parse(json['fecha_liquidacion'] as String),
      fechaVencimiento: DateTime.parse(json['fecha_vencimiento'] as String),
      fechaPago: json['fecha_pago'] != null
          ? DateTime.parse(json['fecha_pago'] as String)
          : null,
      estado: EstadoLiquidacion.values.firstWhere(
        (e) => e.toString() == 'EstadoLiquidacion.${json['estado']}',
      ),
      acuerdoPagoId: json['acuerdo_pago_id'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_liquidacion': numeroLiquidacion,
      'vigencia': vigencia,
      'predio_id': predioId,
      'numero_predial': numeroPredial,
      'contribuyente_id': contribuyenteId,
      'contribuyente_nombre': contribuyenteNombre,
      'contribuyente_identificacion': contribuyenteIdentificacion,
      'avaluo_catastral': avaluoCatastral.toSql(),
      'tarifa': tarifa,
      'impuesto_base': impuestoBase.toSql(),
      'descuento_pronto_pago': descuentoProntoPago.toSql(),
      'intereses_mora': interesesMora.toSql(),
      'total_pagar': totalPagar.toSql(),
      'fecha_liquidacion': fechaLiquidacion.toIso8601String(),
      'fecha_vencimiento': fechaVencimiento.toIso8601String(),
      'fecha_pago': fechaPago?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'acuerdo_pago_id': acuerdoPagoId,
      'observaciones': observaciones,
    };
  }

  /// Verifica si está vencida
  bool estaVencida() {
    return DateTime.now().isAfter(fechaVencimiento) &&
        estado != EstadoLiquidacion.pagada;
  }

  /// Calcula los días de mora
  int calcularDiasMora() {
    if (!estaVencida()) return 0;
    return DateTime.now().difference(fechaVencimiento).inDays;
  }

  /// Verifica si aplica descuento por pronto pago (primer trimestre)
  bool aplicaDescuentoProntoPago() {
    final mesLiquidacion = fechaLiquidacion.month;
    return mesLiquidacion >= 1 &&
        mesLiquidacion <= 3 &&
        estado == EstadoLiquidacion.generada;
  }

  LiquidacionPredial copyWith({
    String? id,
    String? entidadId,
    String? numeroLiquidacion,
    String? vigencia,
    String? predioId,
    String? numeroPredial,
    String? contribuyenteId,
    String? contribuyenteNombre,
    String? contribuyenteIdentificacion,
    MoneyValue? avaluoCatastral,
    double? tarifa,
    MoneyValue? impuestoBase,
    MoneyValue? descuentoProntoPago,
    MoneyValue? interesesMora,
    MoneyValue? totalPagar,
    DateTime? fechaLiquidacion,
    DateTime? fechaVencimiento,
    DateTime? fechaPago,
    EstadoLiquidacion? estado,
    String? acuerdoPagoId,
    String? observaciones,
  }) {
    return LiquidacionPredial(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroLiquidacion: numeroLiquidacion ?? this.numeroLiquidacion,
      vigencia: vigencia ?? this.vigencia,
      predioId: predioId ?? this.predioId,
      numeroPredial: numeroPredial ?? this.numeroPredial,
      contribuyenteId: contribuyenteId ?? this.contribuyenteId,
      contribuyenteNombre: contribuyenteNombre ?? this.contribuyenteNombre,
      contribuyenteIdentificacion:
          contribuyenteIdentificacion ?? this.contribuyenteIdentificacion,
      avaluoCatastral: avaluoCatastral ?? this.avaluoCatastral,
      tarifa: tarifa ?? this.tarifa,
      impuestoBase: impuestoBase ?? this.impuestoBase,
      descuentoProntoPago: descuentoProntoPago ?? this.descuentoProntoPago,
      interesesMora: interesesMora ?? this.interesesMora,
      totalPagar: totalPagar ?? this.totalPagar,
      fechaLiquidacion: fechaLiquidacion ?? this.fechaLiquidacion,
      fechaVencimiento: fechaVencimiento ?? this.fechaVencimiento,
      fechaPago: fechaPago ?? this.fechaPago,
      estado: estado ?? this.estado,
      acuerdoPagoId: acuerdoPagoId ?? this.acuerdoPagoId,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
