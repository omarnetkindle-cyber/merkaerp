/// Modelo de Registro Presupuestal (RP)
/// Tercera etapa del flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoRP {
  vigente,
  modificado,
  reducido,
  anulado,
  totalmenteObligado,
}

class RP {
  final String id;
  final String entidadId;
  final String numeroRP; // Formato: RP-YYYY-NNNNNN
  final String vigencia;
  final String cdpId;
  final String numeroCDP;
  final String contratoId; // Requisito: contrato firmado
  final String contratoNumero;
  final String codigoRubro;
  final MoneyValue valorRP;
  MoneyValue valorObligado;
  MoneyValue saldoDisponible;
  final DateTime fechaExpedicion;
  final DateTime fechaVigencia;
  final String funcionarioExpedidor;
  final String funcionarioSolicitante;
  final String objetoGasto;
  EstadoRP estado;
  final String? actoAdministrativoModificacion;
  final DateTime? fechaModificacion;
  final String? observaciones;

  RP({
    required this.id,
    required this.entidadId,
    required this.numeroRP,
    required this.vigencia,
    required this.cdpId,
    required this.numeroCDP,
    required this.contratoId,
    required this.contratoNumero,
    required this.codigoRubro,
    required this.valorRP,
    required this.valorObligado,
    required this.saldoDisponible,
    required this.fechaExpedicion,
    required this.fechaVigencia,
    required this.funcionarioExpedidor,
    required this.funcionarioSolicitante,
    required this.objetoGasto,
    required this.estado,
    this.actoAdministrativoModificacion,
    this.fechaModificacion,
    this.observaciones,
  });

  factory RP.fromJson(Map<String, dynamic> json) {
    return RP(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroRP: json['numero_rp'] as String,
      vigencia: json['vigencia'] as String,
      cdpId: json['cdp_id'] as String,
      numeroCDP: json['numero_cdp'] as String,
      contratoId: json['contrato_id'] as String,
      contratoNumero: json['contrato_numero'] as String,
      codigoRubro: json['codigo_rubro'] as String,
      valorRP: publicMoneyFromSql(json['valor_rp']),
      valorObligado: publicMoneyFromSql(json['valor_obligado']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      fechaExpedicion: DateTime.parse(json['fecha_expedicion'] as String),
      fechaVigencia: DateTime.parse(json['fecha_vigencia'] as String),
      funcionarioExpedidor: json['funcionario_expedidor'] as String,
      funcionarioSolicitante: json['funcionario_solicitante'] as String,
      objetoGasto: json['objeto_gasto'] as String,
      estado: EstadoRP.values.firstWhere(
        (e) => e.toString() == 'EstadoRP.${json['estado']}',
      ),
      actoAdministrativoModificacion: json['acto_administrativo_modificacion'] as String?,
      fechaModificacion: json['fecha_modificacion'] != null
          ? DateTime.parse(json['fecha_modificacion'] as String)
          : null,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_rp': numeroRP,
      'vigencia': vigencia,
      'cdp_id': cdpId,
      'numero_cdp': numeroCDP,
      'contrato_id': contratoId,
      'contrato_numero': contratoNumero,
      'codigo_rubro': codigoRubro,
      'valor_rp': valorRP.toSql(),
      'valor_obligado': valorObligado.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'fecha_expedicion': fechaExpedicion.toIso8601String(),
      'fecha_vigencia': fechaVigencia.toIso8601String(),
      'funcionario_expedidor': funcionarioExpedidor,
      'funcionario_solicitante': funcionarioSolicitante,
      'objeto_gasto': objetoGasto,
      'estado': estado.toString().split('.').last,
      'acto_administrativo_modificacion': actoAdministrativoModificacion,
      'fecha_modificacion': fechaModificacion?.toIso8601String(),
      'observaciones': observaciones,
    };
  }

  /// Verifica si el RP está vigente
  bool estaVigente() {
    return estado == EstadoRP.vigente &&
           DateTime.now().isBefore(fechaVigencia) &&
           saldoDisponible > publicMoneyZero();
  }

  /// Verifica si hay saldo disponible para una obligación
  bool tieneSaldoParaObligacion(MoneyValue montoObligacion) {
    return saldoDisponible >= montoObligacion && estaVigente();
  }

  /// Actualiza el saldo después de una obligación
  void actualizarSaldoObligacion(MoneyValue montoObligacion) {
    valorObligado += montoObligacion;
    saldoDisponible -= montoObligacion;
    
    if (saldoDisponible == publicMoneyZero()) {
      estado = EstadoRP.totalmenteObligado;
    }
  }

  RP copyWith({
    String? id,
    String? entidadId,
    String? numeroRP,
    String? vigencia,
    String? cdpId,
    String? numeroCDP,
    String? contratoId,
    String? contratoNumero,
    String? codigoRubro,
    MoneyValue? valorRP,
    MoneyValue? valorObligado,
    MoneyValue? saldoDisponible,
    DateTime? fechaExpedicion,
    DateTime? fechaVigencia,
    String? funcionarioExpedidor,
    String? funcionarioSolicitante,
    String? objetoGasto,
    EstadoRP? estado,
    String? actoAdministrativoModificacion,
    DateTime? fechaModificacion,
    String? observaciones,
  }) {
    return RP(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroRP: numeroRP ?? this.numeroRP,
      vigencia: vigencia ?? this.vigencia,
      cdpId: cdpId ?? this.cdpId,
      numeroCDP: numeroCDP ?? this.numeroCDP,
      contratoId: contratoId ?? this.contratoId,
      contratoNumero: contratoNumero ?? this.contratoNumero,
      codigoRubro: codigoRubro ?? this.codigoRubro,
      valorRP: valorRP ?? this.valorRP,
      valorObligado: valorObligado ?? this.valorObligado,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      fechaExpedicion: fechaExpedicion ?? this.fechaExpedicion,
      fechaVigencia: fechaVigencia ?? this.fechaVigencia,
      funcionarioExpedidor: funcionarioExpedidor ?? this.funcionarioExpedidor,
      funcionarioSolicitante: funcionarioSolicitante ?? this.funcionarioSolicitante,
      objetoGasto: objetoGasto ?? this.objetoGasto,
      estado: estado ?? this.estado,
      actoAdministrativoModificacion: actoAdministrativoModificacion ?? this.actoAdministrativoModificacion,
      fechaModificacion: fechaModificacion ?? this.fechaModificacion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
