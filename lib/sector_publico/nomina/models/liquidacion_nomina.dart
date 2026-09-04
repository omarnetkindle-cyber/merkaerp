/// Modelo de Liquidación de Nómina
/// Con cálculo de aportes parafiscales y PILA
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoLiquidacion { generada, aprobada, pagada, anulada }

class LiquidacionNomina {
  final String id;
  final String entidadId;
  final String numeroLiquidacion; // Formato: LN-YYYY-MM-NNNNNN
  final String periodo; // Formato: YYYY-MM
  final String empleadoId;
  final String empleadoNombre;
  final String empleadoIdentificacion;
  final int diasTrabajados;
  final MoneyValue salarioBasico;
  final MoneyValue salarioDevengado;
  final MoneyValue auxilioTransporte;
  final MoneyValue auxilioAlimentacion;
  final MoneyValue horasExtra;
  final MoneyValue recargoNocturno;
  final MoneyValue totalDevengado;
  final MoneyValue salud; // 8.5%
  final MoneyValue pension; // 12%
  final MoneyValue fondoSolidaridad; // 1-2% según salario
  final MoneyValue riesgosLaborales; // 0.522% - 8.7%
  final MoneyValue cajaCompensacion; // 4%
  final MoneyValue sena; // 2%
  final MoneyValue icbf; // 3%
  final MoneyValue totalAportes;
  final MoneyValue netoPagar;
  final EstadoLiquidacion estado;
  final DateTime fechaLiquidacion;
  final DateTime? fechaPago;
  final String? pilaId; // ID en PILA
  final String? observaciones;

  LiquidacionNomina({
    required this.id,
    required this.entidadId,
    required this.numeroLiquidacion,
    required this.periodo,
    required this.empleadoId,
    required this.empleadoNombre,
    required this.empleadoIdentificacion,
    required this.diasTrabajados,
    required this.salarioBasico,
    required this.salarioDevengado,
    required this.auxilioTransporte,
    required this.auxilioAlimentacion,
    required this.horasExtra,
    required this.recargoNocturno,
    required this.totalDevengado,
    required this.salud,
    required this.pension,
    required this.fondoSolidaridad,
    required this.riesgosLaborales,
    required this.cajaCompensacion,
    required this.sena,
    required this.icbf,
    required this.totalAportes,
    required this.netoPagar,
    required this.estado,
    required this.fechaLiquidacion,
    this.fechaPago,
    this.pilaId,
    this.observaciones,
  });

  factory LiquidacionNomina.fromJson(Map<String, dynamic> json) {
    return LiquidacionNomina(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroLiquidacion: json['numero_liquidacion'] as String,
      periodo: json['periodo'] as String,
      empleadoId: json['empleado_id'] as String,
      empleadoNombre: json['empleado_nombre'] as String,
      empleadoIdentificacion: json['empleado_identificacion'] as String,
      diasTrabajados: json['dias_trabajados'] as int,
      salarioBasico: publicMoneyFromSql(json['salario_basico']),
      salarioDevengado: publicMoneyFromSql(json['salario_devengado']),
      auxilioTransporte: publicMoneyFromSql(json['auxilio_transporte']),
      auxilioAlimentacion: publicMoneyFromSql(json['auxilio_alimentacion']),
      horasExtra: publicMoneyFromSql(json['horas_extra']),
      recargoNocturno: publicMoneyFromSql(json['recargo_nocturno']),
      totalDevengado: publicMoneyFromSql(json['total_devengado']),
      salud: publicMoneyFromSql(json['salud']),
      pension: publicMoneyFromSql(json['pension']),
      fondoSolidaridad: publicMoneyFromSql(json['fondo_solidaridad']),
      riesgosLaborales: publicMoneyFromSql(json['riesgos_laborales']),
      cajaCompensacion: publicMoneyFromSql(json['caja_compensacion']),
      sena: publicMoneyFromSql(json['sena']),
      icbf: publicMoneyFromSql(json['icbf']),
      totalAportes: publicMoneyFromSql(json['total_aportes']),
      netoPagar: publicMoneyFromSql(json['neto_pagar']),
      estado: EstadoLiquidacion.values.firstWhere(
        (e) => e.toString() == 'EstadoLiquidacion.${json['estado']}',
      ),
      fechaLiquidacion: DateTime.parse(json['fecha_liquidacion'] as String),
      fechaPago: json['fecha_pago'] != null
          ? DateTime.parse(json['fecha_pago'] as String)
          : null,
      pilaId: json['pila_id'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_liquidacion': numeroLiquidacion,
      'periodo': periodo,
      'empleado_id': empleadoId,
      'empleado_nombre': empleadoNombre,
      'empleado_identificacion': empleadoIdentificacion,
      'dias_trabajados': diasTrabajados,
      'salario_basico': salarioBasico.toSql(),
      'salario_devengado': salarioDevengado.toSql(),
      'auxilio_transporte': auxilioTransporte.toSql(),
      'auxilio_alimentacion': auxilioAlimentacion.toSql(),
      'horas_extra': horasExtra.toSql(),
      'recargo_nocturno': recargoNocturno.toSql(),
      'total_devengado': totalDevengado.toSql(),
      'salud': salud.toSql(),
      'pension': pension.toSql(),
      'fondo_solidaridad': fondoSolidaridad.toSql(),
      'riesgos_laborales': riesgosLaborales.toSql(),
      'caja_compensacion': cajaCompensacion.toSql(),
      'sena': sena.toSql(),
      'icbf': icbf.toSql(),
      'total_aportes': totalAportes.toSql(),
      'neto_pagar': netoPagar.toSql(),
      'estado': estado.toString().split('.').last,
      'fecha_liquidacion': fechaLiquidacion.toIso8601String(),
      'fecha_pago': fechaPago?.toIso8601String(),
      'pila_id': pilaId,
      'observaciones': observaciones,
    };
  }

  bool estaPagada() {
    return estado == EstadoLiquidacion.pagada;
  }

  bool tienePILA() {
    return pilaId != null && pilaId!.isNotEmpty;
  }

  LiquidacionNomina copyWith({
    String? id,
    String? entidadId,
    String? numeroLiquidacion,
    String? periodo,
    String? empleadoId,
    String? empleadoNombre,
    String? empleadoIdentificacion,
    int? diasTrabajados,
    MoneyValue? salarioBasico,
    MoneyValue? salarioDevengado,
    MoneyValue? auxilioTransporte,
    MoneyValue? auxilioAlimentacion,
    MoneyValue? horasExtra,
    MoneyValue? recargoNocturno,
    MoneyValue? totalDevengado,
    MoneyValue? salud,
    MoneyValue? pension,
    MoneyValue? fondoSolidaridad,
    MoneyValue? riesgosLaborales,
    MoneyValue? cajaCompensacion,
    MoneyValue? sena,
    MoneyValue? icbf,
    MoneyValue? totalAportes,
    MoneyValue? netoPagar,
    EstadoLiquidacion? estado,
    DateTime? fechaLiquidacion,
    DateTime? fechaPago,
    String? pilaId,
    String? observaciones,
  }) {
    return LiquidacionNomina(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroLiquidacion: numeroLiquidacion ?? this.numeroLiquidacion,
      periodo: periodo ?? this.periodo,
      empleadoId: empleadoId ?? this.empleadoId,
      empleadoNombre: empleadoNombre ?? this.empleadoNombre,
      empleadoIdentificacion:
          empleadoIdentificacion ?? this.empleadoIdentificacion,
      diasTrabajados: diasTrabajados ?? this.diasTrabajados,
      salarioBasico: salarioBasico ?? this.salarioBasico,
      salarioDevengado: salarioDevengado ?? this.salarioDevengado,
      auxilioTransporte: auxilioTransporte ?? this.auxilioTransporte,
      auxilioAlimentacion: auxilioAlimentacion ?? this.auxilioAlimentacion,
      horasExtra: horasExtra ?? this.horasExtra,
      recargoNocturno: recargoNocturno ?? this.recargoNocturno,
      totalDevengado: totalDevengado ?? this.totalDevengado,
      salud: salud ?? this.salud,
      pension: pension ?? this.pension,
      fondoSolidaridad: fondoSolidaridad ?? this.fondoSolidaridad,
      riesgosLaborales: riesgosLaborales ?? this.riesgosLaborales,
      cajaCompensacion: cajaCompensacion ?? this.cajaCompensacion,
      sena: sena ?? this.sena,
      icbf: icbf ?? this.icbf,
      totalAportes: totalAportes ?? this.totalAportes,
      netoPagar: netoPagar ?? this.netoPagar,
      estado: estado ?? this.estado,
      fechaLiquidacion: fechaLiquidacion ?? this.fechaLiquidacion,
      fechaPago: fechaPago ?? this.fechaPago,
      pilaId: pilaId ?? this.pilaId,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
