/// Modelo de Apropiación Presupuestal
/// Primera etapa del flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

class Apropiacion {
  final String id;
  final String entidadId;
  final String vigencia; // Año fiscal (ej. "2026")
  final String codigoRubro; // Código del rubro presupuestal
  final String nombreRubro;
  final MoneyValue valorInicial;
  MoneyValue valorApropiado;
  MoneyValue valorCDP;
  MoneyValue valorRP;
  MoneyValue valorObligado;
  MoneyValue valorPagado;
  MoneyValue saldoDisponible;
  final String fuenteFinanciacion;
  final String sector;
  final String programa;
  final String subprograma;
  final String proyecto; // Vinculado a Banco de Proyectos MGA
  final String actividad;
  final String objetoGasto;
  final DateTime fechaCreacion;
  final DateTime fechaAprobacionConcejo;
  final String actoAdministrativo; // Número del acuerdo/ordenanza
  final bool activo;
  final String? observaciones;

  Apropiacion({
    required this.id,
    required this.entidadId,
    required this.vigencia,
    required this.codigoRubro,
    required this.nombreRubro,
    required this.valorInicial,
    required this.valorApropiado,
    required this.valorCDP,
    required this.valorRP,
    required this.valorObligado,
    required this.valorPagado,
    required this.saldoDisponible,
    required this.fuenteFinanciacion,
    required this.sector,
    required this.programa,
    required this.subprograma,
    required this.proyecto,
    required this.actividad,
    required this.objetoGasto,
    required this.fechaCreacion,
    required this.fechaAprobacionConcejo,
    required this.actoAdministrativo,
    required this.activo,
    this.observaciones,
  });

  factory Apropiacion.fromJson(Map<String, dynamic> json) {
    return Apropiacion(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      codigoRubro: json['codigo_rubro'] as String,
      nombreRubro: json['nombre_rubro'] as String,
      valorInicial: publicMoneyFromSql(json['valor_inicial']),
      valorApropiado: publicMoneyFromSql(json['valor_apropiado']),
      valorCDP: publicMoneyFromSql(json['valor_cdp']),
      valorRP: publicMoneyFromSql(json['valor_rp']),
      valorObligado: publicMoneyFromSql(json['valor_obligado']),
      valorPagado: publicMoneyFromSql(json['valor_pagado']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      fuenteFinanciacion: json['fuente_financiacion'] as String,
      sector: json['sector'] as String,
      programa: json['programa'] as String,
      subprograma: json['subprograma'] as String,
      proyecto: json['proyecto'] as String,
      actividad: json['actividad'] as String,
      objetoGasto: json['objeto_gasto'] as String,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      fechaAprobacionConcejo: DateTime.parse(json['fecha_aprobacion_concejo'] as String),
      actoAdministrativo: json['acto_administrativo'] as String,
      activo: json['activo'] == true || json['activo'] == 1,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'codigo_rubro': codigoRubro,
      'nombre_rubro': nombreRubro,
      'valor_inicial': valorInicial.toSql(),
      'valor_apropiado': valorApropiado.toSql(),
      'valor_cdp': valorCDP.toSql(),
      'valor_rp': valorRP.toSql(),
      'valor_obligado': valorObligado.toSql(),
      'valor_pagado': valorPagado.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'fuente_financiacion': fuenteFinanciacion,
      'sector': sector,
      'programa': programa,
      'subprograma': subprograma,
      'proyecto': proyecto,
      'actividad': actividad,
      'objeto_gasto': objetoGasto,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_aprobacion_concejo': fechaAprobacionConcejo.toIso8601String(),
      'acto_administrativo': actoAdministrativo,
      'activo': activo ? 1 : 0,
      'observaciones': observaciones,
    };
  }

  /// Calcula el saldo disponible para expedir CDP
  /// Saldo = Valor Apropiado - Valor CDP - Valor RP
  MoneyValue calcularSaldoDisponibleCDP() {
    return valorApropiado - valorCDP - valorRP;
  }

  /// Verifica si hay disponibilidad para un monto específico
  bool tieneDisponibilidad(MoneyValue monto) {
    return calcularSaldoDisponibleCDP() >= monto;
  }

  /// Actualiza los valores después de una operación
  void actualizarValores({
    MoneyValue? valorCDPAdicional,
    MoneyValue? valorRPAdicional,
    MoneyValue? valorObligadoAdicional,
    MoneyValue? valorPagadoAdicional,
  }) {
    valorCDP += valorCDPAdicional ?? publicMoneyZero();
    valorRP += valorRPAdicional ?? publicMoneyZero();
    valorObligado += valorObligadoAdicional ?? publicMoneyZero();
    valorPagado += valorPagadoAdicional ?? publicMoneyZero();
    saldoDisponible = calcularSaldoDisponibleCDP();
  }

  Apropiacion copyWith({
    String? id,
    String? entidadId,
    String? vigencia,
    String? codigoRubro,
    String? nombreRubro,
    MoneyValue? valorInicial,
    MoneyValue? valorApropiado,
    MoneyValue? valorCDP,
    MoneyValue? valorRP,
    MoneyValue? valorObligado,
    MoneyValue? valorPagado,
    MoneyValue? saldoDisponible,
    String? fuenteFinanciacion,
    String? sector,
    String? programa,
    String? subprograma,
    String? proyecto,
    String? actividad,
    String? objetoGasto,
    DateTime? fechaCreacion,
    DateTime? fechaAprobacionConcejo,
    String? actoAdministrativo,
    bool? activo,
    String? observaciones,
  }) {
    return Apropiacion(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      vigencia: vigencia ?? this.vigencia,
      codigoRubro: codigoRubro ?? this.codigoRubro,
      nombreRubro: nombreRubro ?? this.nombreRubro,
      valorInicial: valorInicial ?? this.valorInicial,
      valorApropiado: valorApropiado ?? this.valorApropiado,
      valorCDP: valorCDP ?? this.valorCDP,
      valorRP: valorRP ?? this.valorRP,
      valorObligado: valorObligado ?? this.valorObligado,
      valorPagado: valorPagado ?? this.valorPagado,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      fuenteFinanciacion: fuenteFinanciacion ?? this.fuenteFinanciacion,
      sector: sector ?? this.sector,
      programa: programa ?? this.programa,
      subprograma: subprograma ?? this.subprograma,
      proyecto: proyecto ?? this.proyecto,
      actividad: actividad ?? this.actividad,
      objetoGasto: objetoGasto ?? this.objetoGasto,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaAprobacionConcejo: fechaAprobacionConcejo ?? this.fechaAprobacionConcejo,
      actoAdministrativo: actoAdministrativo ?? this.actoAdministrativo,
      activo: activo ?? this.activo,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
