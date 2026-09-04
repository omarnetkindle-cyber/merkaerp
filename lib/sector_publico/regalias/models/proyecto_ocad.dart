/// Modelo de Proyecto OCAD (Órgano Colegiado de Administración y Decisión - SGR Colombia)
/// Ley 2056 de 2020 - Sistema General de Regalías (SGR)
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoOCAD {
  municipal,
  departamental,
  regional,
  paz,
  ctei, // Ciencia, Tecnología e Innovación
}

enum EstadoOCAD {
  formulado,
  viabilizado,
  priorizado,
  aprobado,
  ejecucion,
  cerrado,
}

class ProyectoOCAD {
  final String id;
  final String entidadId;
  final String? proyectoMgaId; // FK opcional a proyectos_mga
  final String? bienioId; // FK opcional a bienios_sgr
  final String
  codigoBPIN; // Código del Banco de Proyectos de Inversión Nacional DNP
  final String nombreProyecto;
  final String bienalidad; // Formato bienal: 2025-2026
  final TipoOCAD tipoOCAD;
  final MoneyValue montoAprobado;
  final MoneyValue montoGiroSPGR;
  final EstadoOCAD estadoOCAD;
  final DateTime fechaAprobacion;
  final String? actaAprobacion;
  final String? fuenteFinanciacion;
  final String? entidadEjecutora;
  final String? observaciones;

  ProyectoOCAD({
    required this.id,
    required this.entidadId,
    this.proyectoMgaId,
    this.bienioId,
    required this.codigoBPIN,
    required this.nombreProyecto,
    required this.bienalidad,
    required this.tipoOCAD,
    required this.montoAprobado,
    required this.montoGiroSPGR,
    required this.estadoOCAD,
    required this.fechaAprobacion,
    this.actaAprobacion,
    this.fuenteFinanciacion,
    this.entidadEjecutora,
    this.observaciones,
  });

  factory ProyectoOCAD.fromJson(Map<String, dynamic> json) {
    return ProyectoOCAD(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      proyectoMgaId: json['proyecto_mga_id'] as String?,
      bienioId: json['bienio_id'] as String?,
      codigoBPIN: json['codigo_bpin'] as String,
      nombreProyecto: json['nombre_proyecto'] as String,
      bienalidad: json['bienalidad'] as String,
      tipoOCAD: TipoOCAD.values.firstWhere(
        (e) => e.name == json['tipo_ocad'],
        orElse: () => TipoOCAD.municipal,
      ),
      montoAprobado: publicMoneyFromSql(json['monto_aprobado']),
      montoGiroSPGR: publicMoneyFromSql(json['monto_giro_spgr']),
      estadoOCAD: EstadoOCAD.values.firstWhere(
        (e) => e.name == json['estado_ocad'],
        orElse: () => EstadoOCAD.aprobado,
      ),
      fechaAprobacion: DateTime.parse(json['fecha_aprobacion'] as String),
      actaAprobacion: json['acta_aprobacion'] as String?,
      fuenteFinanciacion: json['fuente_financiacion'] as String?,
      entidadEjecutora: json['entidad_ejecutora'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'proyecto_mga_id': proyectoMgaId,
      'bienio_id': bienioId,
      'codigo_bpin': codigoBPIN,
      'nombre_proyecto': nombreProyecto,
      'bienalidad': bienalidad,
      'tipo_ocad': tipoOCAD.name,
      'monto_aprobado': montoAprobado.toSql(),
      'monto_giro_spgr': montoGiroSPGR.toSql(),
      'estado_ocad': estadoOCAD.name,
      'fecha_aprobacion': fechaAprobacion.toIso8601String(),
      'acta_aprobacion': actaAprobacion,
      'fuente_financiacion': fuenteFinanciacion,
      'entidad_ejecutora': entidadEjecutora,
      'observaciones': observaciones,
    };
  }

  MoneyValue get saldoPendienteGiro => montoAprobado - montoGiroSPGR;
}
