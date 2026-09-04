/// Modelo de Obligación Presupuestal
/// Cuarta etapa del flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoObligacion {
  pendiente,
  reconocida,
  pagadaParcialmente,
  pagadaTotalmente,
  anulada,
}

class Obligacion {
  final String id;
  final String entidadId;
  final String numeroObligacion; // Formato: OBL-YYYY-NNNNNN
  final String vigencia;
  final String rpId;
  final String numeroRP;
  final String contratoId;
  final String contratoNumero;
  final String terceroId; // Proveedor/contratista
  final String terceroNombre;
  final String codigoRubro;
  final MoneyValue valorObligacion;
  MoneyValue valorPagado;
  MoneyValue saldoPendiente;
  final DateTime fechaReconocimiento;
  final String funcionarioReconocio;
  final String objetoGasto;
  final String? actaReciboNumero; // Acta de recibo a satisfacción
  final DateTime? actaReciboFecha;
  final String? facturaNumero;
  final DateTime? facturaFecha;
  EstadoObligacion estado;
  final String? observaciones;

  Obligacion({
    required this.id,
    required this.entidadId,
    required this.numeroObligacion,
    required this.vigencia,
    required this.rpId,
    required this.numeroRP,
    required this.contratoId,
    required this.contratoNumero,
    required this.terceroId,
    required this.terceroNombre,
    required this.codigoRubro,
    required this.valorObligacion,
    required this.valorPagado,
    required this.saldoPendiente,
    required this.fechaReconocimiento,
    required this.funcionarioReconocio,
    required this.objetoGasto,
    this.actaReciboNumero,
    this.actaReciboFecha,
    this.facturaNumero,
    this.facturaFecha,
    required this.estado,
    this.observaciones,
  });

  factory Obligacion.fromJson(Map<String, dynamic> json) {
    return Obligacion(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroObligacion: json['numero_obligacion'] as String,
      vigencia: json['vigencia'] as String,
      rpId: json['rp_id'] as String,
      numeroRP: json['numero_rp'] as String,
      contratoId: json['contrato_id'] as String,
      contratoNumero: json['contrato_numero'] as String,
      terceroId: json['tercero_id'] as String,
      terceroNombre: json['tercero_nombre'] as String,
      codigoRubro: json['codigo_rubro'] as String,
      valorObligacion: publicMoneyFromSql(json['valor_obligacion']),
      valorPagado: publicMoneyFromSql(json['valor_pagado']),
      saldoPendiente: publicMoneyFromSql(json['saldo_pendiente']),
      fechaReconocimiento: DateTime.parse(json['fecha_reconocimiento'] as String),
      funcionarioReconocio: json['funcionario_reconocio'] as String,
      objetoGasto: json['objeto_gasto'] as String,
      actaReciboNumero: json['acta_recibo_numero'] as String?,
      actaReciboFecha: json['acta_recibo_fecha'] != null
          ? DateTime.parse(json['acta_recibo_fecha'] as String)
          : null,
      facturaNumero: json['factura_numero'] as String?,
      facturaFecha: json['factura_fecha'] != null
          ? DateTime.parse(json['factura_fecha'] as String)
          : null,
      estado: EstadoObligacion.values.firstWhere(
        (e) => e.toString() == 'EstadoObligacion.${json['estado']}',
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_obligacion': numeroObligacion,
      'vigencia': vigencia,
      'rp_id': rpId,
      'numero_rp': numeroRP,
      'contrato_id': contratoId,
      'contrato_numero': contratoNumero,
      'tercero_id': terceroId,
      'tercero_nombre': terceroNombre,
      'codigo_rubro': codigoRubro,
      'valor_obligacion': valorObligacion.toSql(),
      'valor_pagado': valorPagado.toSql(),
      'saldo_pendiente': saldoPendiente.toSql(),
      'fecha_reconocimiento': fechaReconocimiento.toIso8601String(),
      'funcionario_reconocio': funcionarioReconocio,
      'objeto_gasto': objetoGasto,
      'acta_recibo_numero': actaReciboNumero,
      'acta_recibo_fecha': actaReciboFecha?.toIso8601String(),
      'factura_numero': facturaNumero,
      'factura_fecha': facturaFecha?.toIso8601String(),
      'estado': estado.toString().split('.').last,
      'observaciones': observaciones,
    };
  }

  /// Verifica si tiene acta de recibo a satisfacción
  bool tieneActaRecibo() {
    return actaReciboNumero != null && actaReciboNumero!.isNotEmpty;
  }

  /// Verifica si tiene factura válida
  bool tieneFacturaValida() {
    return facturaNumero != null && facturaNumero!.isNotEmpty;
  }

  /// Verifica si se puede pagar (requiere acta de recibo o factura)
  bool sePuedePagar() {
    return (tieneActaRecibo() || tieneFacturaValida()) &&
           saldoPendiente > publicMoneyZero() &&
           (estado == EstadoObligacion.pendiente || estado == EstadoObligacion.pagadaParcialmente);
  }

  /// Actualiza el saldo después de un pago
  void actualizarSaldoPago(MoneyValue montoPago) {
    valorPagado += montoPago;
    saldoPendiente -= montoPago;

    if (saldoPendiente == publicMoneyZero()) {
      estado = EstadoObligacion.pagadaTotalmente;
    } else {
      estado = EstadoObligacion.pagadaParcialmente;
    }
  }

  Obligacion copyWith({
    String? id,
    String? entidadId,
    String? numeroObligacion,
    String? vigencia,
    String? rpId,
    String? numeroRP,
    String? contratoId,
    String? contratoNumero,
    String? terceroId,
    String? terceroNombre,
    String? codigoRubro,
    MoneyValue? valorObligacion,
    MoneyValue? valorPagado,
    MoneyValue? saldoPendiente,
    DateTime? fechaReconocimiento,
    String? funcionarioReconocio,
    String? objetoGasto,
    String? actaReciboNumero,
    DateTime? actaReciboFecha,
    String? facturaNumero,
    DateTime? facturaFecha,
    EstadoObligacion? estado,
    String? observaciones,
  }) {
    return Obligacion(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroObligacion: numeroObligacion ?? this.numeroObligacion,
      vigencia: vigencia ?? this.vigencia,
      rpId: rpId ?? this.rpId,
      numeroRP: numeroRP ?? this.numeroRP,
      contratoId: contratoId ?? this.contratoId,
      contratoNumero: contratoNumero ?? this.contratoNumero,
      terceroId: terceroId ?? this.terceroId,
      terceroNombre: terceroNombre ?? this.terceroNombre,
      codigoRubro: codigoRubro ?? this.codigoRubro,
      valorObligacion: valorObligacion ?? this.valorObligacion,
      valorPagado: valorPagado ?? this.valorPagado,
      saldoPendiente: saldoPendiente ?? this.saldoPendiente,
      fechaReconocimiento: fechaReconocimiento ?? this.fechaReconocimiento,
      funcionarioReconocio: funcionarioReconocio ?? this.funcionarioReconocio,
      objetoGasto: objetoGasto ?? this.objetoGasto,
      actaReciboNumero: actaReciboNumero ?? this.actaReciboNumero,
      actaReciboFecha: actaReciboFecha ?? this.actaReciboFecha,
      facturaNumero: facturaNumero ?? this.facturaNumero,
      facturaFecha: facturaFecha ?? this.facturaFecha,
      estado: estado ?? this.estado,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
