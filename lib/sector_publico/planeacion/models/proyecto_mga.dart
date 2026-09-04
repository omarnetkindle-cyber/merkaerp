/// Modelo de Proyecto MGA (Metodología General Ajustada)
/// Banco de Proyectos de Inversión Pública - DNP
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoProyecto {
  perfil,
  preformulacion,
  formulado,
  registradoBPIN,
  viabilizado,
  enEjecucion,
  suspendido,
  terminado,
  cancelado,
}

enum TipoProyecto { obra, estudio, consultoria, adquisicion, otro }

class ProyectoMGA {
  final String id;
  final String entidadId;
  final String codigoBPIN; // Código en BPIN
  final String nombreProyecto;
  final TipoProyecto tipoProyecto;
  final String sector;
  final String programa;
  final String subprograma;
  final MoneyValue valorTotal;
  final MoneyValue valorEjecutado;
  final MoneyValue saldoPorEjecutar;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String responsable;
  final String dependencia;
  final EstadoProyecto estado;
  final String? codigoCDP;
  final String? codigoRP;
  final String? observaciones;

  ProyectoMGA({
    required this.id,
    required this.entidadId,
    required this.codigoBPIN,
    required this.nombreProyecto,
    required this.tipoProyecto,
    required this.sector,
    required this.programa,
    required this.subprograma,
    required this.valorTotal,
    required this.valorEjecutado,
    required this.saldoPorEjecutar,
    required this.fechaInicio,
    required this.fechaFin,
    required this.responsable,
    required this.dependencia,
    required this.estado,
    this.codigoCDP,
    this.codigoRP,
    this.observaciones,
  });

  factory ProyectoMGA.fromJson(Map<String, dynamic> json) {
    return ProyectoMGA(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      codigoBPIN: json['codigo_bpin'] as String,
      nombreProyecto: json['nombre_proyecto'] as String,
      tipoProyecto: TipoProyecto.values.firstWhere(
        (e) => e.toString() == 'TipoProyecto.${json['tipo_proyecto']}',
      ),
      sector: json['sector'] as String,
      programa: json['programa'] as String,
      subprograma: json['subprograma'] as String,
      valorTotal: publicMoneyFromSql(json['valor_total']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      saldoPorEjecutar: publicMoneyFromSql(json['saldo_por_ejecutar']),
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      responsable: json['responsable'] as String,
      dependencia: json['dependencia'] as String,
      estado: EstadoProyecto.values.firstWhere(
        (e) => e.toString() == 'EstadoProyecto.${json['estado']}',
      ),
      codigoCDP: json['codigo_cdp'] as String?,
      codigoRP: json['codigo_rp'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'codigo_bpin': codigoBPIN,
      'nombre_proyecto': nombreProyecto,
      'tipo_proyecto': tipoProyecto.toString().split('.').last,
      'sector': sector,
      'programa': programa,
      'subprograma': subprograma,
      'valor_total': valorTotal.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'saldo_por_ejecutar': saldoPorEjecutar.toSql(),
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'responsable': responsable,
      'dependencia': dependencia,
      'estado': estado.toString().split('.').last,
      'codigo_cdp': codigoCDP,
      'codigo_rp': codigoRP,
      'observaciones': observaciones,
    };
  }

  /// Verifica si tiene CDP y RP asociados
  bool tieneCDPyRP() {
    return codigoCDP != null &&
        codigoCDP!.isNotEmpty &&
        codigoRP != null &&
        codigoRP!.isNotEmpty;
  }

  /// Calcula el porcentaje de ejecución
  double calcularPorcentajeEjecucion() {
    if (valorTotal == publicMoneyZero()) return 0;
    return (valorEjecutado.minorUnits / valorTotal.minorUnits) * 100;
  }

  /// Verifica si está en ejecución
  bool estaEnEjecucion() {
    return estado == EstadoProyecto.enEjecucion;
  }

  ProyectoMGA copyWith({
    String? id,
    String? entidadId,
    String? codigoBPIN,
    String? nombreProyecto,
    TipoProyecto? tipoProyecto,
    String? sector,
    String? programa,
    String? subprograma,
    MoneyValue? valorTotal,
    MoneyValue? valorEjecutado,
    MoneyValue? saldoPorEjecutar,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? responsable,
    String? dependencia,
    EstadoProyecto? estado,
    String? codigoCDP,
    String? codigoRP,
    String? observaciones,
  }) {
    return ProyectoMGA(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      codigoBPIN: codigoBPIN ?? this.codigoBPIN,
      nombreProyecto: nombreProyecto ?? this.nombreProyecto,
      tipoProyecto: tipoProyecto ?? this.tipoProyecto,
      sector: sector ?? this.sector,
      programa: programa ?? this.programa,
      subprograma: subprograma ?? this.subprograma,
      valorTotal: valorTotal ?? this.valorTotal,
      valorEjecutado: valorEjecutado ?? this.valorEjecutado,
      saldoPorEjecutar: saldoPorEjecutar ?? this.saldoPorEjecutar,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      responsable: responsable ?? this.responsable,
      dependencia: dependencia ?? this.dependencia,
      estado: estado ?? this.estado,
      codigoCDP: codigoCDP ?? this.codigoCDP,
      codigoRP: codigoRP ?? this.codigoRP,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
