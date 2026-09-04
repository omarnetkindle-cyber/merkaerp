/// Modelo de Proceso de Contratación
/// Ley 80 de 1993 + Ley 1150 de 2007 + Decreto 1082 de 2015
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum ModalidadSeleccion {
  licitacionPublica,
  seleccionAbreviada,
  contratacionDirecta,
  concursoMeritos,
  minimaCuantia,
}

enum EstadoProceso {
  estudioPrevio,
  publicado,
  enEvaluacion,
  adjudicado,
  enFirma,
  firmado,
  legalizado,
  ejecucion,
  terminado,
  anulado,
}

class ProcesoContratacion {
  final String id;
  final String entidadId;
  final String numeroProceso; // Formato: PC-YYYY-NNNNNN
  final String objetoContrato;
  final ModalidadSeleccion modalidad;
  final MoneyValue valorEstimado;
  final String tipoContrato;
  final String dependenciaSolicitante;
  final String responsableProceso;
  final DateTime fechaInicio;
  final DateTime? fechaPublicacion;
  final DateTime? fechaCierre;
  final EstadoProceso estado;
  final String? cdpId;
  final String? numeroCDP;
  final String? secopId; // ID en SECOP II
  final String? observaciones;

  ProcesoContratacion({
    required this.id,
    required this.entidadId,
    required this.numeroProceso,
    required this.objetoContrato,
    required this.modalidad,
    required this.valorEstimado,
    required this.tipoContrato,
    required this.dependenciaSolicitante,
    required this.responsableProceso,
    required this.fechaInicio,
    this.fechaPublicacion,
    this.fechaCierre,
    required this.estado,
    this.cdpId,
    this.numeroCDP,
    this.secopId,
    this.observaciones,
  });

  factory ProcesoContratacion.fromJson(Map<String, dynamic> json) {
    return ProcesoContratacion(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroProceso: json['numero_proceso'] as String,
      objetoContrato: json['objeto_contrato'] as String,
      modalidad: ModalidadSeleccion.values.firstWhere(
        (e) => e.toString() == 'ModalidadSeleccion.${json['modalidad']}',
      ),
      valorEstimado: publicMoneyFromSql(json['valor_estimado']),
      tipoContrato: json['tipo_contrato'] as String,
      dependenciaSolicitante: json['dependencia_solicitante'] as String,
      responsableProceso: json['responsable_proceso'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaPublicacion: json['fecha_publicacion'] != null
          ? DateTime.parse(json['fecha_publicacion'] as String)
          : null,
      fechaCierre: json['fecha_cierre'] != null
          ? DateTime.parse(json['fecha_cierre'] as String)
          : null,
      estado: EstadoProceso.values.firstWhere(
        (e) => e.toString() == 'EstadoProceso.${json['estado']}',
      ),
      cdpId: json['cdp_id'] as String?,
      numeroCDP: json['numero_cdp'] as String?,
      secopId: json['secop_id'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_proceso': numeroProceso,
      'objeto_contrato': objetoContrato,
      'modalidad': modalidad.toString().split('.').last,
      'valor_estimado': valorEstimado.toSql(),
      'tipo_contrato': tipoContrato,
      'dependencia_solicitante': dependenciaSolicitante,
      'responsable_proceso': responsableProceso,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_publicacion': fechaPublicacion?.toIso8601String(),
      'fecha_cierre': fechaCierre?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'cdp_id': cdpId,
      'numero_cdp': numeroCDP,
      'secop_id': secopId,
      'observaciones': observaciones,
    };
  }

  /// Regla de flujo para publicación/interoperabilidad SECOP.
  ///
  /// La obligación concreta depende del régimen, tipo de entidad/proceso y
  /// configuración institucional; el modelo no la presume universalmente.
  bool requierePublicacionSECOP({bool sujetoARegimenDePublicacion = true}) =>
      sujetoARegimenDePublicacion;

  /// Verifica si tiene CDP asociado
  bool tieneCDP() {
    return cdpId != null && cdpId!.isNotEmpty;
  }

  /// Verifica si puede ser adjudicado
  bool sePuedeAdjudicar() {
    return estado == EstadoProceso.enEvaluacion && tieneCDP();
  }

  ProcesoContratacion copyWith({
    String? id,
    String? entidadId,
    String? numeroProceso,
    String? objetoContrato,
    ModalidadSeleccion? modalidad,
    MoneyValue? valorEstimado,
    String? tipoContrato,
    String? dependenciaSolicitante,
    String? responsableProceso,
    DateTime? fechaInicio,
    DateTime? fechaPublicacion,
    DateTime? fechaCierre,
    EstadoProceso? estado,
    String? cdpId,
    String? numeroCDP,
    String? secopId,
    String? observaciones,
  }) {
    return ProcesoContratacion(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroProceso: numeroProceso ?? this.numeroProceso,
      objetoContrato: objetoContrato ?? this.objetoContrato,
      modalidad: modalidad ?? this.modalidad,
      valorEstimado: valorEstimado ?? this.valorEstimado,
      tipoContrato: tipoContrato ?? this.tipoContrato,
      dependenciaSolicitante:
          dependenciaSolicitante ?? this.dependenciaSolicitante,
      responsableProceso: responsableProceso ?? this.responsableProceso,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaPublicacion: fechaPublicacion ?? this.fechaPublicacion,
      fechaCierre: fechaCierre ?? this.fechaCierre,
      estado: estado ?? this.estado,
      cdpId: cdpId ?? this.cdpId,
      numeroCDP: numeroCDP ?? this.numeroCDP,
      secopId: secopId ?? this.secopId,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
