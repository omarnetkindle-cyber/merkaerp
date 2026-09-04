/// Modelo de Contrato
/// Ley 80 de 1993 - Requiere CDP, RP, pólizas, legalización
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoContrato {
  enFirma,
  firmado,
  legalizado,
  enEjecucion,
  suspendido,
  terminado,
  liquidado,
  anulado,
}

enum TipoContrato {
  obra,
  consultoria,
  suministro,
  prestacionServicios,
  concesion,
  interadministrativo,
  otro,
}

class Contrato {
  final String id;
  final String entidadId;
  final String numeroContrato; // Formato: CT-YYYY-NNNNNN
  final String procesoId;
  final String numeroProceso;
  final String objetoContrato;
  final TipoContrato tipoContrato;
  final MoneyValue valorContrato;
  final String contratistaId;
  final String contratistaNombre;
  final String contratistaIdentificacion;
  final String cdpId;
  final String numeroCDP;
  final String? rpId;
  final String? numeroRP;
  final DateTime fechaFirma;
  final DateTime fechaInicioEjecucion;
  final DateTime fechaFinEjecucion;
  final int duracionDias;
  final EstadoContrato estado;
  final DateTime? fechaLegalizacion;
  final DateTime? fechaTerminacion;
  final DateTime? fechaLiquidacion;
  final String? supervisorId;
  final String? supervisorNombre;
  final String? interventorId;
  final String? interventorNombre;
  final String? observaciones;

  Contrato({
    required this.id,
    required this.entidadId,
    required this.numeroContrato,
    required this.procesoId,
    required this.numeroProceso,
    required this.objetoContrato,
    required this.tipoContrato,
    required this.valorContrato,
    required this.contratistaId,
    required this.contratistaNombre,
    required this.contratistaIdentificacion,
    required this.cdpId,
    required this.numeroCDP,
    this.rpId,
    this.numeroRP,
    required this.fechaFirma,
    required this.fechaInicioEjecucion,
    required this.fechaFinEjecucion,
    required this.duracionDias,
    required this.estado,
    this.fechaLegalizacion,
    this.fechaTerminacion,
    this.fechaLiquidacion,
    this.supervisorId,
    this.supervisorNombre,
    this.interventorId,
    this.interventorNombre,
    this.observaciones,
  });

  factory Contrato.fromJson(Map<String, dynamic> json) {
    return Contrato(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroContrato: json['numero_contrato'] as String,
      procesoId: json['proceso_id'] as String,
      numeroProceso: json['numero_proceso'] as String,
      objetoContrato: json['objeto_contrato'] as String,
      tipoContrato: TipoContrato.values.firstWhere(
        (e) => e.toString() == 'TipoContrato.${json['tipo_contrato']}',
      ),
      valorContrato: publicMoneyFromSql(json['valor_contrato']),
      contratistaId: json['contratista_id'] as String,
      contratistaNombre: json['contratista_nombre'] as String,
      contratistaIdentificacion: json['contratista_identificacion'] as String,
      cdpId: json['cdp_id'] as String,
      numeroCDP: json['numero_cdp'] as String,
      rpId: json['rp_id'] as String?,
      numeroRP: json['numero_rp'] as String?,
      fechaFirma: DateTime.parse(json['fecha_firma'] as String),
      fechaInicioEjecucion: DateTime.parse(
        json['fecha_inicio_ejecucion'] as String,
      ),
      fechaFinEjecucion: DateTime.parse(json['fecha_fin_ejecucion'] as String),
      duracionDias: json['duracion_dias'] as int,
      estado: EstadoContrato.values.firstWhere(
        (e) => e.toString() == 'EstadoContrato.${json['estado']}',
      ),
      fechaLegalizacion: json['fecha_legalizacion'] != null
          ? DateTime.parse(json['fecha_legalizacion'] as String)
          : null,
      fechaTerminacion: json['fecha_terminacion'] != null
          ? DateTime.parse(json['fecha_terminacion'] as String)
          : null,
      fechaLiquidacion: json['fecha_liquidacion'] != null
          ? DateTime.parse(json['fecha_liquidacion'] as String)
          : null,
      supervisorId: json['supervisor_id'] as String?,
      supervisorNombre: json['supervisor_nombre'] as String?,
      interventorId: json['interventor_id'] as String?,
      interventorNombre: json['interventor_nombre'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_contrato': numeroContrato,
      'proceso_id': procesoId,
      'numero_proceso': numeroProceso,
      'objeto_contrato': objetoContrato,
      'tipo_contrato': tipoContrato.toString().split('.').last,
      'valor_contrato': valorContrato.toSql(),
      'contratista_id': contratistaId,
      'contratista_nombre': contratistaNombre,
      'contratista_identificacion': contratistaIdentificacion,
      'cdp_id': cdpId,
      'numero_cdp': numeroCDP,
      'rp_id': rpId,
      'numero_rp': numeroRP,
      'fecha_firma': fechaFirma.toIso8601String(),
      'fecha_inicio_ejecucion': fechaInicioEjecucion.toIso8601String(),
      'fecha_fin_ejecucion': fechaFinEjecucion.toIso8601String(),
      'duracion_dias': duracionDias,
      'estado': estado.toString().split('.').last,
      'fecha_legalizacion': fechaLegalizacion?.toIso8601String(),
      'fecha_terminacion': fechaTerminacion?.toIso8601String(),
      'fecha_liquidacion': fechaLiquidacion?.toIso8601String(),
      'supervisor_id': supervisorId,
      'supervisor_nombre': supervisorNombre,
      'interventor_id': interventorId,
      'interventor_nombre': interventorNombre,
      'observaciones': observaciones,
    };
  }

  /// Verifica si tiene CDP y RP (requisito Ley 80/1993 Art. 41)
  bool tieneCDPyRP() {
    return cdpId.isNotEmpty && (rpId?.isNotEmpty ?? false);
  }

  /// Verifica si está en ejecución
  bool estaEnEjecucion() {
    return estado == EstadoContrato.enEjecucion;
  }

  /// Verifica si requiere legalización
  bool requiereLegalizacion() {
    return estado == EstadoContrato.firmado;
  }

  /// Verifica si puede liquidarse
  bool sePuedeLiquidar() {
    return estado == EstadoContrato.terminado;
  }

  /// Calcula el porcentaje de ejecución del contrato
  double calcularPorcentajeEjecucion() {
    final hoy = DateTime.now();
    final inicio = fechaInicioEjecucion;
    final fin = fechaFinEjecucion;

    if (hoy.isBefore(inicio)) return 0.0;
    if (hoy.isAfter(fin)) return 100.0;

    final totalDias = fin.difference(inicio).inDays;
    final diasTranscurridos = hoy.difference(inicio).inDays;

    return (diasTranscurridos / totalDias) * 100;
  }

  Contrato copyWith({
    String? id,
    String? entidadId,
    String? numeroContrato,
    String? procesoId,
    String? numeroProceso,
    String? objetoContrato,
    TipoContrato? tipoContrato,
    MoneyValue? valorContrato,
    String? contratistaId,
    String? contratistaNombre,
    String? contratistaIdentificacion,
    String? cdpId,
    String? numeroCDP,
    String? rpId,
    String? numeroRP,
    DateTime? fechaFirma,
    DateTime? fechaInicioEjecucion,
    DateTime? fechaFinEjecucion,
    int? duracionDias,
    EstadoContrato? estado,
    DateTime? fechaLegalizacion,
    DateTime? fechaTerminacion,
    DateTime? fechaLiquidacion,
    String? supervisorId,
    String? supervisorNombre,
    String? interventorId,
    String? interventorNombre,
    String? observaciones,
  }) {
    return Contrato(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroContrato: numeroContrato ?? this.numeroContrato,
      procesoId: procesoId ?? this.procesoId,
      numeroProceso: numeroProceso ?? this.numeroProceso,
      objetoContrato: objetoContrato ?? this.objetoContrato,
      tipoContrato: tipoContrato ?? this.tipoContrato,
      valorContrato: valorContrato ?? this.valorContrato,
      contratistaId: contratistaId ?? this.contratistaId,
      contratistaNombre: contratistaNombre ?? this.contratistaNombre,
      contratistaIdentificacion:
          contratistaIdentificacion ?? this.contratistaIdentificacion,
      cdpId: cdpId ?? this.cdpId,
      numeroCDP: numeroCDP ?? this.numeroCDP,
      rpId: rpId ?? this.rpId,
      numeroRP: numeroRP ?? this.numeroRP,
      fechaFirma: fechaFirma ?? this.fechaFirma,
      fechaInicioEjecucion: fechaInicioEjecucion ?? this.fechaInicioEjecucion,
      fechaFinEjecucion: fechaFinEjecucion ?? this.fechaFinEjecucion,
      duracionDias: duracionDias ?? this.duracionDias,
      estado: estado ?? this.estado,
      fechaLegalizacion: fechaLegalizacion ?? this.fechaLegalizacion,
      fechaTerminacion: fechaTerminacion ?? this.fechaTerminacion,
      fechaLiquidacion: fechaLiquidacion ?? this.fechaLiquidacion,
      supervisorId: supervisorId ?? this.supervisorId,
      supervisorNombre: supervisorNombre ?? this.supervisorNombre,
      interventorId: interventorId ?? this.interventorId,
      interventorNombre: interventorNombre ?? this.interventorNombre,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
