/// Modelo de Pago
/// Quinta y última etapa del flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoPago {
  programado,
  aprobado,
  rechazado,
  enProceso,
  pagado,
  anulado,
}

enum TipoPago {
  transferenciaBancaria,
  cheque,
  electronico,
  compensacion,
}

class Pago {
  final String id;
  final String entidadId;
  final String numeroPago; // Formato: PAG-YYYY-NNNNNN
  final String vigencia;
  final String obligacionId;
  final String numeroObligacion;
  final String rpId;
  final String numeroRP;
  final String terceroId;
  final String terceroNombre;
  final String bancoDestino;
  final String cuentaDestino;
  final String tipoCuenta; // Ahorros, Corriente
  final MoneyValue valorPago;
  final int mesPAC;
  final DateTime fechaProgramacion;
  final DateTime? fechaAprobacion;
  final DateTime? fechaEjecucion;
  final String funcionarioAprobo;
  final String funcionarioProgramo;
  final TipoPago tipoPago;
  final EstadoPago estado;
  final String? numeroCheque;
  final String? numeroReferencia;
  final String? observaciones;
  final String? rechazoMotivo;

  Pago({
    required this.id,
    required this.entidadId,
    required this.numeroPago,
    required this.vigencia,
    required this.obligacionId,
    required this.numeroObligacion,
    required this.rpId,
    required this.numeroRP,
    required this.terceroId,
    required this.terceroNombre,
    required this.bancoDestino,
    required this.cuentaDestino,
    required this.tipoCuenta,
    required this.valorPago,
    required this.mesPAC,
    required this.fechaProgramacion,
    this.fechaAprobacion,
    this.fechaEjecucion,
    required this.funcionarioAprobo,
    required this.funcionarioProgramo,
    required this.tipoPago,
    required this.estado,
    this.numeroCheque,
    this.numeroReferencia,
    this.observaciones,
    this.rechazoMotivo,
  });

  factory Pago.fromJson(Map<String, dynamic> json) {
    return Pago(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroPago: json['numero_pago'] as String,
      vigencia: json['vigencia'] as String,
      obligacionId: json['obligacion_id'] as String,
      numeroObligacion: json['numero_obligacion'] as String,
      rpId: json['rp_id'] as String,
      numeroRP: json['numero_rp'] as String,
      terceroId: json['tercero_id'] as String,
      terceroNombre: json['tercero_nombre'] as String,
      bancoDestino: json['banco_destino'] as String,
      cuentaDestino: json['cuenta_destino'] as String,
      tipoCuenta: json['tipo_cuenta'] as String,
      valorPago: publicMoneyFromSql(json['valor_pago']),
      mesPAC: (json['mes_pac'] as num?)?.toInt() ?? 0,
      fechaProgramacion: DateTime.parse(json['fecha_programacion'] as String),
      fechaAprobacion: json['fecha_aprobacion'] != null
          ? DateTime.parse(json['fecha_aprobacion'] as String)
          : null,
      fechaEjecucion: json['fecha_ejecucion'] != null
          ? DateTime.parse(json['fecha_ejecucion'] as String)
          : null,
      funcionarioAprobo: json['funcionario_aprobo'] as String,
      funcionarioProgramo: json['funcionario_programo'] as String,
      tipoPago: TipoPago.values.firstWhere(
        (e) => e.toString() == 'TipoPago.${json['tipo_pago']}',
      ),
      estado: EstadoPago.values.firstWhere(
        (e) => e.toString() == 'EstadoPago.${json['estado']}',
      ),
      numeroCheque: json['numero_cheque'] as String?,
      numeroReferencia: json['numero_referencia'] as String?,
      observaciones: json['observaciones'] as String?,
      rechazoMotivo: json['rechazo_motivo'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_pago': numeroPago,
      'vigencia': vigencia,
      'obligacion_id': obligacionId,
      'numero_obligacion': numeroObligacion,
      'rp_id': rpId,
      'numero_rp': numeroRP,
      'tercero_id': terceroId,
      'tercero_nombre': terceroNombre,
      'banco_destino': bancoDestino,
      'cuenta_destino': cuentaDestino,
      'tipo_cuenta': tipoCuenta,
      'valor_pago': valorPago.toSql(),
      'mes_pac': mesPAC,
      'fecha_programacion': fechaProgramacion.toIso8601String(),
      'fecha_aprobacion': fechaAprobacion?.toIso8601String(),
      'fecha_ejecucion': fechaEjecucion?.toIso8601String(),
      'funcionario_aprobo': funcionarioAprobo,
      'funcionario_programo': funcionarioProgramo,
      'tipo_pago': tipoPago.toString().split('.').last,
      'estado': estado.toString().split('.').last,
      'numero_cheque': numeroCheque,
      'numero_referencia': numeroReferencia,
      'observaciones': observaciones,
      'rechazo_motivo': rechazoMotivo,
    };
  }

  /// Verifica si el pago está aprobado
  bool estaAprobado() {
    return estado == EstadoPago.aprobado ||
           estado == EstadoPago.enProceso ||
           estado == EstadoPago.pagado;
  }

  /// Verifica si el pago está ejecutado
  bool estaPagado() {
    return estado == EstadoPago.pagado && fechaEjecucion != null;
  }

  /// Verifica si se puede ejecutar el pago
  bool sePuedeEjecutar() {
    return estado == EstadoPago.aprobado &&
           fechaEjecucion == null;
  }

  Pago copyWith({
    String? id,
    String? entidadId,
    String? numeroPago,
    String? vigencia,
    String? obligacionId,
    String? numeroObligacion,
    String? rpId,
    String? numeroRP,
    String? terceroId,
    String? terceroNombre,
    String? bancoDestino,
    String? cuentaDestino,
    String? tipoCuenta,
    MoneyValue? valorPago,
    int? mesPAC,
    DateTime? fechaProgramacion,
    DateTime? fechaAprobacion,
    DateTime? fechaEjecucion,
    String? funcionarioAprobo,
    String? funcionarioProgramo,
    TipoPago? tipoPago,
    EstadoPago? estado,
    String? numeroCheque,
    String? numeroReferencia,
    String? observaciones,
    String? rechazoMotivo,
  }) {
    return Pago(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroPago: numeroPago ?? this.numeroPago,
      vigencia: vigencia ?? this.vigencia,
      obligacionId: obligacionId ?? this.obligacionId,
      numeroObligacion: numeroObligacion ?? this.numeroObligacion,
      rpId: rpId ?? this.rpId,
      numeroRP: numeroRP ?? this.numeroRP,
      terceroId: terceroId ?? this.terceroId,
      terceroNombre: terceroNombre ?? this.terceroNombre,
      bancoDestino: bancoDestino ?? this.bancoDestino,
      cuentaDestino: cuentaDestino ?? this.cuentaDestino,
      tipoCuenta: tipoCuenta ?? this.tipoCuenta,
      valorPago: valorPago ?? this.valorPago,
      mesPAC: mesPAC ?? this.mesPAC,
      fechaProgramacion: fechaProgramacion ?? this.fechaProgramacion,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      fechaEjecucion: fechaEjecucion ?? this.fechaEjecucion,
      funcionarioAprobo: funcionarioAprobo ?? this.funcionarioAprobo,
      funcionarioProgramo: funcionarioProgramo ?? this.funcionarioProgramo,
      tipoPago: tipoPago ?? this.tipoPago,
      estado: estado ?? this.estado,
      numeroCheque: numeroCheque ?? this.numeroCheque,
      numeroReferencia: numeroReferencia ?? this.numeroReferencia,
      observaciones: observaciones ?? this.observaciones,
      rechazoMotivo: rechazoMotivo ?? this.rechazoMotivo,
    );
  }
}
