/// Modelo de Retroactivo
/// Cálculo de retroactivos por ajustes salariales o sentencias
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoRetroactivo {
  ajusteSalarial,
  sentenciaJudicial,
  conciliacion,
  reconocimientoAntiguedad,
  otro,
}

enum EstadoRetroactivo { calculado, aprobado, enPago, pagado, anulado }

class Retroactivo {
  final String id;
  final String entidadId;
  final String numeroRetroactivo; // Formato: RT-YYYY-NNNNNN
  final String empleadoId;
  final String empleadoNombre;
  final String empleadoIdentificacion;
  final TipoRetroactivo tipoRetroactivo;
  final String motivo;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final int meses;
  final MoneyValue salarioAnterior;
  final MoneyValue salarioNuevo;
  final MoneyValue diferenciaMensual;
  final MoneyValue valorTotal;
  final MoneyValue valorPagado;
  final MoneyValue saldoPendiente;
  final EstadoRetroactivo estado;
  final DateTime fechaCalculo;
  final DateTime? fechaAprobacion;
  final String? actoAdministrativo;
  final String? observaciones;

  Retroactivo({
    required this.id,
    required this.entidadId,
    required this.numeroRetroactivo,
    required this.empleadoId,
    required this.empleadoNombre,
    required this.empleadoIdentificacion,
    required this.tipoRetroactivo,
    required this.motivo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.meses,
    required this.salarioAnterior,
    required this.salarioNuevo,
    required this.diferenciaMensual,
    required this.valorTotal,
    required this.valorPagado,
    required this.saldoPendiente,
    required this.estado,
    required this.fechaCalculo,
    this.fechaAprobacion,
    this.actoAdministrativo,
    this.observaciones,
  });

  factory Retroactivo.fromJson(Map<String, dynamic> json) {
    return Retroactivo(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroRetroactivo: json['numero_retroactivo'] as String,
      empleadoId: json['empleado_id'] as String,
      empleadoNombre: json['empleado_nombre'] as String,
      empleadoIdentificacion: json['empleado_identificacion'] as String,
      tipoRetroactivo: TipoRetroactivo.values.firstWhere(
        (e) => e.toString() == 'TipoRetroactivo.${json['tipo_retroactivo']}',
      ),
      motivo: json['motivo'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      meses: json['meses'] as int,
      salarioAnterior: publicMoneyFromSql(json['salario_anterior']),
      salarioNuevo: publicMoneyFromSql(json['salario_nuevo']),
      diferenciaMensual: publicMoneyFromSql(json['diferencia_mensual']),
      valorTotal: publicMoneyFromSql(json['valor_total']),
      valorPagado: publicMoneyFromSql(json['valor_pagado']),
      saldoPendiente: publicMoneyFromSql(json['saldo_pendiente']),
      estado: EstadoRetroactivo.values.firstWhere(
        (e) => e.toString() == 'EstadoRetroactivo.${json['estado']}',
      ),
      fechaCalculo: DateTime.parse(json['fecha_calculo'] as String),
      fechaAprobacion: json['fecha_aprobacion'] != null
          ? DateTime.parse(json['fecha_aprobacion'] as String)
          : null,
      actoAdministrativo: json['acto_administrativo'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_retroactivo': numeroRetroactivo,
      'empleado_id': empleadoId,
      'empleado_nombre': empleadoNombre,
      'empleado_identificacion': empleadoIdentificacion,
      'tipo_retroactivo': tipoRetroactivo.toString().split('.').last,
      'motivo': motivo,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'meses': meses,
      'salario_anterior': salarioAnterior.toSql(),
      'salario_nuevo': salarioNuevo.toSql(),
      'diferencia_mensual': diferenciaMensual.toSql(),
      'valor_total': valorTotal.toSql(),
      'valor_pagado': valorPagado.toSql(),
      'saldo_pendiente': saldoPendiente.toSql(),
      'estado': estado.toString().split('.').last,
      'fecha_calculo': fechaCalculo.toIso8601String(),
      'fecha_aprobacion': fechaAprobacion?.toIso8601String(),
      'acto_administrativo': actoAdministrativo,
      'observaciones': observaciones,
    };
  }

  bool estaPagado() {
    return estado == EstadoRetroactivo.pagado ||
        saldoPendiente == publicMoneyZero();
  }

  Retroactivo copyWith({
    String? id,
    String? entidadId,
    String? numeroRetroactivo,
    String? empleadoId,
    String? empleadoNombre,
    String? empleadoIdentificacion,
    TipoRetroactivo? tipoRetroactivo,
    String? motivo,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? meses,
    MoneyValue? salarioAnterior,
    MoneyValue? salarioNuevo,
    MoneyValue? diferenciaMensual,
    MoneyValue? valorTotal,
    MoneyValue? valorPagado,
    MoneyValue? saldoPendiente,
    EstadoRetroactivo? estado,
    DateTime? fechaCalculo,
    DateTime? fechaAprobacion,
    String? actoAdministrativo,
    String? observaciones,
  }) {
    return Retroactivo(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroRetroactivo: numeroRetroactivo ?? this.numeroRetroactivo,
      empleadoId: empleadoId ?? this.empleadoId,
      empleadoNombre: empleadoNombre ?? this.empleadoNombre,
      empleadoIdentificacion:
          empleadoIdentificacion ?? this.empleadoIdentificacion,
      tipoRetroactivo: tipoRetroactivo ?? this.tipoRetroactivo,
      motivo: motivo ?? this.motivo,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      meses: meses ?? this.meses,
      salarioAnterior: salarioAnterior ?? this.salarioAnterior,
      salarioNuevo: salarioNuevo ?? this.salarioNuevo,
      diferenciaMensual: diferenciaMensual ?? this.diferenciaMensual,
      valorTotal: valorTotal ?? this.valorTotal,
      valorPagado: valorPagado ?? this.valorPagado,
      saldoPendiente: saldoPendiente ?? this.saldoPendiente,
      estado: estado ?? this.estado,
      fechaCalculo: fechaCalculo ?? this.fechaCalculo,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      actoAdministrativo: actoAdministrativo ?? this.actoAdministrativo,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
