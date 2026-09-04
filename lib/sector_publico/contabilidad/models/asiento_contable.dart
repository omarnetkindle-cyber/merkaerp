/// Modelo de Asiento Contable NICSP
/// Implementa asientos automáticos desde el flujo presupuestal
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoAsiento {
  manual,
  automaticoPresupuestal, // Generado desde presupuesto
  automaticoNomina, // Generado desde nómina
  automaticoTributario, // Generado desde rentas
  automaticoCierre, // Generado en cierre de vigencia
  reversa, // Reversa de asiento
  ajuste, // Ajuste contable
}

enum EstadoAsiento {
  borrador,
  registrado,
  cuadrado,
  reversado,
}

class DetalleAsiento {
  final String id;
  final String cuentaCodigo;
  final String cuentaNombre;
  final MoneyValue debito;
  final MoneyValue credito;
  final String? referenciaId; // ID del documento origen (CDP, RP, etc.)

  DetalleAsiento({
    required this.id,
    required this.cuentaCodigo,
    required this.cuentaNombre,
    required this.debito,
    required this.credito,
    this.referenciaId,
  });

  factory DetalleAsiento.fromJson(Map<String, dynamic> json) {
    return DetalleAsiento(
      id: json['id'] as String,
      cuentaCodigo: json['cuenta_codigo'] as String,
      cuentaNombre: json['cuenta_nombre'] as String,
      debito: publicMoneyFromSql(json['debito']),
      credito: publicMoneyFromSql(json['credito']),
      referenciaId: json['referencia_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cuenta_codigo': cuentaCodigo,
      'cuenta_nombre': cuentaNombre,
      'debito': debito.toSql(),
      'credito': credito.toSql(),
      'referencia_id': referenciaId,
    };
  }

  DetalleAsiento copyWith({
    String? id,
    String? cuentaCodigo,
    String? cuentaNombre,
    MoneyValue? debito,
    MoneyValue? credito,
    String? referenciaId,
  }) {
    return DetalleAsiento(
      id: id ?? this.id,
      cuentaCodigo: cuentaCodigo ?? this.cuentaCodigo,
      cuentaNombre: cuentaNombre ?? this.cuentaNombre,
      debito: debito ?? this.debito,
      credito: credito ?? this.credito,
      referenciaId: referenciaId ?? this.referenciaId,
    );
  }
}

class AsientoContable {
  final String id;
  final String entidadId;
  final String numeroAsiento; // Formato: AS-YYYY-NNNNNN
  final DateTime fechaAsiento;
  final String descripcion;
  final TipoAsiento tipoAsiento;
  final EstadoAsiento estado;
  final List<DetalleAsiento> detalles;
  final MoneyValue totalDebito;
  final MoneyValue totalCredito;
  final String usuarioCreo;
  final String? usuarioReviso;
  final DateTime? fechaRevision;
  final String? referenciaOrigen; // ID del documento origen
  final String? tipoDocumentoOrigen; // CDP, RP, OBLIGACION, PAGO, etc.
  final String? observaciones;

  AsientoContable({
    required this.id,
    required this.entidadId,
    required this.numeroAsiento,
    required this.fechaAsiento,
    required this.descripcion,
    required this.tipoAsiento,
    required this.estado,
    required this.detalles,
    required this.totalDebito,
    required this.totalCredito,
    required this.usuarioCreo,
    this.usuarioReviso,
    this.fechaRevision,
    this.referenciaOrigen,
    this.tipoDocumentoOrigen,
    this.observaciones,
  });

  factory AsientoContable.fromJson(Map<String, dynamic> json) {
    final detallesJson = json['detalles'] as List;
    final detalles = detallesJson
        .map((d) => DetalleAsiento.fromJson(d as Map<String, dynamic>))
        .toList();

    return AsientoContable(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroAsiento: json['numero_asiento'] as String,
      fechaAsiento: DateTime.parse(json['fecha_asiento'] as String),
      descripcion: json['descripcion'] as String,
      tipoAsiento: TipoAsiento.values.firstWhere(
        (e) => e.toString() == 'TipoAsiento.${json['tipo_asiento']}',
      ),
      estado: EstadoAsiento.values.firstWhere(
        (e) => e.toString() == 'EstadoAsiento.${json['estado']}',
      ),
      detalles: detalles,
      totalDebito: publicMoneyFromSql(json['total_debito']),
      totalCredito: publicMoneyFromSql(json['total_credito']),
      usuarioCreo: json['usuario_creo'] as String,
      usuarioReviso: json['usuario_reviso'] as String?,
      fechaRevision: json['fecha_revision'] != null
          ? DateTime.parse(json['fecha_revision'] as String)
          : null,
      referenciaOrigen: json['referencia_origen'] as String?,
      tipoDocumentoOrigen: json['tipo_documento_origen'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': descripcion,
      'tipo_asiento': tipoAsiento.toString().split('.').last,
      'estado': estado.toString().split('.').last,
      'detalles': detalles.map((d) => d.toJson()).toList(),
      'total_debito': totalDebito.toSql(),
      'total_credito': totalCredito.toSql(),
      'usuario_creo': usuarioCreo,
      'usuario_reviso': usuarioReviso,
      'fecha_revision': fechaRevision?.toIso8601String(),
      'referencia_origen': referenciaOrigen,
      'tipo_documento_origen': tipoDocumentoOrigen,
      'observaciones': observaciones,
    };
  }

  /// Verifica si el asiento está cuadrado (débito = crédito)
  bool estaCuadrado() {
    return totalDebito == totalCredito;
  }

  /// Verifica si el asiento puede ser registrado
  bool sePuedeRegistrar() {
    return estado == EstadoAsiento.borrador && estaCuadrado() && detalles.isNotEmpty;
  }

  /// Verifica si el asiento puede ser reversado
  bool sePuedeReversar() {
    return estado == EstadoAsiento.registrado || estado == EstadoAsiento.cuadrado;
  }

  AsientoContable copyWith({
    String? id,
    String? entidadId,
    String? numeroAsiento,
    DateTime? fechaAsiento,
    String? descripcion,
    TipoAsiento? tipoAsiento,
    EstadoAsiento? estado,
    List<DetalleAsiento>? detalles,
    MoneyValue? totalDebito,
    MoneyValue? totalCredito,
    String? usuarioCreo,
    String? usuarioReviso,
    DateTime? fechaRevision,
    String? referenciaOrigen,
    String? tipoDocumentoOrigen,
    String? observaciones,
  }) {
    return AsientoContable(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroAsiento: numeroAsiento ?? this.numeroAsiento,
      fechaAsiento: fechaAsiento ?? this.fechaAsiento,
      descripcion: descripcion ?? this.descripcion,
      tipoAsiento: tipoAsiento ?? this.tipoAsiento,
      estado: estado ?? this.estado,
      detalles: detalles ?? this.detalles,
      totalDebito: totalDebito ?? this.totalDebito,
      totalCredito: totalCredito ?? this.totalCredito,
      usuarioCreo: usuarioCreo ?? this.usuarioCreo,
      usuarioReviso: usuarioReviso ?? this.usuarioReviso,
      fechaRevision: fechaRevision ?? this.fechaRevision,
      referenciaOrigen: referenciaOrigen ?? this.referenciaOrigen,
      tipoDocumentoOrigen: tipoDocumentoOrigen ?? this.tipoDocumentoOrigen,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
