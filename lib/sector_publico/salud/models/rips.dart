/// Modelo de RIPS (Registros Individuales de Prestación de Servicios)
/// Ministerio de Salud - Formatos RIPS
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoRIPS {
  ac, // Consulta
  ap, // Procedimiento
  am, // Medicamentos
  at, // Otros servicios
  ah, // Hospitalización
  an, // Recién nacido
  au, // Urgencias
  af, // Factura
}

class RIPS {
  final String id;
  final String entidadId;
  final TipoRIPS tipoRIPS;
  final String codigoPrestador;
  final String nombrePrestador;
  final String numeroFactura;
  final DateTime fechaFactura;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String codigoPaciente;
  final String nombrePaciente;
  final String tipoIdentificacion;
  final String numeroIdentificacion;
  final String codigoServicio;
  final String nombreServicio;
  final MoneyValue valorServicio;
  final MoneyValue valorCopago;
  final MoneyValue valorModera;
  final MoneyValue valorNeto;
  final String? diagnosticoPrincipal;
  final String? diagnosticoRelacionado;
  final String? observaciones;

  RIPS({
    required this.id,
    required this.entidadId,
    required this.tipoRIPS,
    required this.codigoPrestador,
    required this.nombrePrestador,
    required this.numeroFactura,
    required this.fechaFactura,
    required this.fechaInicio,
    required this.fechaFin,
    required this.codigoPaciente,
    required this.nombrePaciente,
    required this.tipoIdentificacion,
    required this.numeroIdentificacion,
    required this.codigoServicio,
    required this.nombreServicio,
    required this.valorServicio,
    required this.valorCopago,
    required this.valorModera,
    required this.valorNeto,
    this.diagnosticoPrincipal,
    this.diagnosticoRelacionado,
    this.observaciones,
  });

  factory RIPS.fromJson(Map<String, dynamic> json) {
    return RIPS(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      tipoRIPS: TipoRIPS.values.firstWhere(
        (e) => e.toString() == 'TipoRIPS.${json['tipo_rips']}',
      ),
      codigoPrestador: json['codigo_prestador'] as String,
      nombrePrestador: json['nombre_prestador'] as String,
      numeroFactura: json['numero_factura'] as String,
      fechaFactura: DateTime.parse(json['fecha_factura'] as String),
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      codigoPaciente: json['codigo_paciente'] as String,
      nombrePaciente: json['nombre_paciente'] as String,
      tipoIdentificacion: json['tipo_identificacion'] as String,
      numeroIdentificacion: json['numero_identificacion'] as String,
      codigoServicio: json['codigo_servicio'] as String,
      nombreServicio: json['nombre_servicio'] as String,
      valorServicio: publicMoneyFromSql(json['valor_servicio']),
      valorCopago: publicMoneyFromSql(json['valor_copago']),
      valorModera: publicMoneyFromSql(json['valor_modera']),
      valorNeto: publicMoneyFromSql(json['valor_neto']),
      diagnosticoPrincipal: json['diagnostico_principal'] as String?,
      diagnosticoRelacionado: json['diagnostico_relacionado'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'tipo_rips': tipoRIPS.toString().split('.').last,
      'codigo_prestador': codigoPrestador,
      'nombre_prestador': nombrePrestador,
      'numero_factura': numeroFactura,
      'fecha_factura': fechaFactura.toIso8601String(),
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'codigo_paciente': codigoPaciente,
      'nombre_paciente': nombrePaciente,
      'tipo_identificacion': tipoIdentificacion,
      'numero_identificacion': numeroIdentificacion,
      'codigo_servicio': codigoServicio,
      'nombre_servicio': nombreServicio,
      'valor_servicio': valorServicio.toSql(),
      'valor_copago': valorCopago.toSql(),
      'valor_modera': valorModera.toSql(),
      'valor_neto': valorNeto.toSql(),
      'diagnostico_principal': diagnosticoPrincipal,
      'diagnostico_relacionado': diagnosticoRelacionado,
      'observaciones': observaciones,
    };
  }

  RIPS copyWith({
    String? id,
    String? entidadId,
    TipoRIPS? tipoRIPS,
    String? codigoPrestador,
    String? nombrePrestador,
    String? numeroFactura,
    DateTime? fechaFactura,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? codigoPaciente,
    String? nombrePaciente,
    String? tipoIdentificacion,
    String? numeroIdentificacion,
    String? codigoServicio,
    String? nombreServicio,
    MoneyValue? valorServicio,
    MoneyValue? valorCopago,
    MoneyValue? valorModera,
    MoneyValue? valorNeto,
    String? diagnosticoPrincipal,
    String? diagnosticoRelacionado,
    String? observaciones,
  }) {
    return RIPS(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      tipoRIPS: tipoRIPS ?? this.tipoRIPS,
      codigoPrestador: codigoPrestador ?? this.codigoPrestador,
      nombrePrestador: nombrePrestador ?? this.nombrePrestador,
      numeroFactura: numeroFactura ?? this.numeroFactura,
      fechaFactura: fechaFactura ?? this.fechaFactura,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      codigoPaciente: codigoPaciente ?? this.codigoPaciente,
      nombrePaciente: nombrePaciente ?? this.nombrePaciente,
      tipoIdentificacion: tipoIdentificacion ?? this.tipoIdentificacion,
      numeroIdentificacion: numeroIdentificacion ?? this.numeroIdentificacion,
      codigoServicio: codigoServicio ?? this.codigoServicio,
      nombreServicio: nombreServicio ?? this.nombreServicio,
      valorServicio: valorServicio ?? this.valorServicio,
      valorCopago: valorCopago ?? this.valorCopago,
      valorModera: valorModera ?? this.valorModera,
      valorNeto: valorNeto ?? this.valorNeto,
      diagnosticoPrincipal: diagnosticoPrincipal ?? this.diagnosticoPrincipal,
      diagnosticoRelacionado:
          diagnosticoRelacionado ?? this.diagnosticoRelacionado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
