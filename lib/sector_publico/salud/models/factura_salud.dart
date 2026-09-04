/// Modelo de Factura de Venta de Servicios de Salud (EPS / ADRES)
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

class FacturaSalud {
  final String id;
  final String entidadId;
  final String contratoId;
  final String numeroFactura;
  final String periodo;
  final MoneyValue montoTotal;
  final MoneyValue montoGlosado;
  final MoneyValue montoPagado;
  final DateTime fechaEmision;
  final String estado; // emitida, glosada, conciliada, pagada
  final String? observaciones;

  FacturaSalud({
    required this.id,
    required this.entidadId,
    required this.contratoId,
    required this.numeroFactura,
    required this.periodo,
    required this.montoTotal,
    required this.montoGlosado,
    required this.montoPagado,
    required this.fechaEmision,
    required this.estado,
    this.observaciones,
  });

  factory FacturaSalud.fromJson(Map<String, dynamic> json) {
    return FacturaSalud(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      contratoId: json['contrato_id'] as String,
      numeroFactura: json['numero_factura'] as String,
      periodo: json['periodo'] as String,
      montoTotal: publicMoneyFromSql(json['monto_total']),
      montoGlosado: publicMoneyFromSql(
        json['monto_glosado'],
        nullableAsZero: true,
      ),
      montoPagado: publicMoneyFromSql(
        json['monto_pagado'],
        nullableAsZero: true,
      ),
      fechaEmision: DateTime.parse(json['fecha_emision'] as String),
      estado: json['estado'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'contrato_id': contratoId,
      'numero_factura': numeroFactura,
      'periodo': periodo,
      'monto_total': montoTotal.toSql(),
      'monto_glosado': montoGlosado.toSql(),
      'monto_pagado': montoPagado.toSql(),
      'fecha_emision': fechaEmision.toIso8601String(),
      'estado': estado,
      'observaciones': observaciones,
    };
  }

  MoneyValue get saldoCobro => montoTotal - montoPagado;
}
