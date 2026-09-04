/// Modelo de Contrato EPS / ADRES para servicios de Salud Pública / ESE Hospital
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum RegimenSalud { subsidiado, contributivo, vinculado, especial }

class ContratoEPS {
  final String id;
  final String entidadId;
  final String numeroContrato;
  final String epsAdresNombre;
  final String epsAdresNit;
  final RegimenSalud regimen;
  final MoneyValue montoContrato;
  final MoneyValue montoFacturado;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String estado; // activo, terminado, enConciliacion
  final String? observaciones;

  ContratoEPS({
    required this.id,
    required this.entidadId,
    required this.numeroContrato,
    required this.epsAdresNombre,
    required this.epsAdresNit,
    required this.regimen,
    required this.montoContrato,
    required this.montoFacturado,
    required this.fechaInicio,
    required this.fechaFin,
    required this.estado,
    this.observaciones,
  });

  factory ContratoEPS.fromJson(Map<String, dynamic> json) {
    return ContratoEPS(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroContrato: json['numero_contrato'] as String,
      epsAdresNombre: json['eps_adres_nombre'] as String,
      epsAdresNit: json['eps_adres_nit'] as String,
      regimen: RegimenSalud.values.firstWhere(
        (e) => e.name == json['regimen'],
        orElse: () => RegimenSalud.subsidiado,
      ),
      montoContrato: publicMoneyFromSql(json['monto_contrato']),
      montoFacturado: publicMoneyFromSql(
        json['monto_facturado'],
        nullableAsZero: true,
      ),
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      estado: json['estado'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_contrato': numeroContrato,
      'eps_adres_nombre': epsAdresNombre,
      'eps_adres_nit': epsAdresNit,
      'regimen': regimen.name,
      'monto_contrato': montoContrato.toSql(),
      'monto_facturado': montoFacturado.toSql(),
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'estado': estado,
      'observaciones': observaciones,
    };
  }

  MoneyValue get saldoDisponibleFacturacion => montoContrato - montoFacturado;
}
