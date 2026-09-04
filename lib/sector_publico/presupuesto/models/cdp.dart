/// Modelo de Certificado de Disponibilidad Presupuestal (CDP)
/// Segunda etapa del flujo: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoCDP {
  vigente,
  modificado,
  reducido,
  anulado,
  totalmenteComprometido,
}

class CDP {
  final String id;
  final String entidadId;
  final String numeroCDP; // Formato: CDP-YYYY-NNNNNN
  final String vigencia;
  final String apropiacionId;
  final String codigoRubro;
  final MoneyValue valorCDP;
  MoneyValue valorComprometidoRP;
  MoneyValue saldoDisponible;
  final DateTime fechaExpedicion;
  final DateTime fechaVigencia; // Generalmente 6 meses desde expedición
  final String funcionarioExpedidor;
  final String funcionarioSolicitante;
  final String objetoGasto;
  final String? contratoNumero; // Si ya está vinculado a un contrato
  EstadoCDP estado;
  final String? actoAdministrativoModificacion; // Si fue modificado
  final DateTime? fechaModificacion;
  final String? observaciones;

  CDP({
    required this.id,
    required this.entidadId,
    required this.numeroCDP,
    required this.vigencia,
    required this.apropiacionId,
    required this.codigoRubro,
    required this.valorCDP,
    required this.valorComprometidoRP,
    required this.saldoDisponible,
    required this.fechaExpedicion,
    required this.fechaVigencia,
    required this.funcionarioExpedidor,
    required this.funcionarioSolicitante,
    required this.objetoGasto,
    this.contratoNumero,
    required this.estado,
    this.actoAdministrativoModificacion,
    this.fechaModificacion,
    this.observaciones,
  });

  factory CDP.fromJson(Map<String, dynamic> json) {
    return CDP(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroCDP: json['numero_cdp'] as String,
      vigencia: json['vigencia'] as String,
      apropiacionId: json['apropiacion_id'] as String,
      codigoRubro: json['codigo_rubro'] as String,
      valorCDP: publicMoneyFromSql(json['valor_cdp']),
      valorComprometidoRP: publicMoneyFromSql(json['valor_comprometido_rp']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      fechaExpedicion: DateTime.parse(json['fecha_expedicion'] as String),
      fechaVigencia: DateTime.parse(json['fecha_vigencia'] as String),
      funcionarioExpedidor: json['funcionario_expedidor'] as String,
      funcionarioSolicitante: json['funcionario_solicitante'] as String,
      objetoGasto: json['objeto_gasto'] as String,
      contratoNumero: json['contrato_numero'] as String?,
      estado: EstadoCDP.values.firstWhere(
        (e) => e.toString() == 'EstadoCDP.${json['estado']}',
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
      'numero_cdp': numeroCDP,
      'vigencia': vigencia,
      'apropiacion_id': apropiacionId,
      'codigo_rubro': codigoRubro,
      'valor_cdp': valorCDP.toSql(),
      'valor_comprometido_rp': valorComprometidoRP.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'fecha_expedicion': fechaExpedicion.toIso8601String(),
      'fecha_vigencia': fechaVigencia.toIso8601String(),
      'funcionario_expedidor': funcionarioExpedidor,
      'funcionario_solicitante': funcionarioSolicitante,
      'objeto_gasto': objetoGasto,
      'contrato_numero': contratoNumero,
      'estado': estado.toString().split('.').last,
      'acto_administrativo_modificacion': actoAdministrativoModificacion,
      'fecha_modificacion': fechaModificacion?.toIso8601String(),
      'observaciones': observaciones,
    };
  }

  /// Verifica si el CDP está vigente
  bool estaVigente() {
    return estado == EstadoCDP.vigente &&
           DateTime.now().isBefore(fechaVigencia) &&
           saldoDisponible > publicMoneyZero();
  }

  /// Verifica si hay saldo disponible para un RP
  bool tieneSaldoParaRP(MoneyValue montoRP) {
    return saldoDisponible >= montoRP && estaVigente();
  }

  /// Actualiza el saldo después de un RP
  void actualizarSaldoRP(MoneyValue montoRP) {
    valorComprometidoRP += montoRP;
    saldoDisponible -= montoRP;
    
    if (saldoDisponible == publicMoneyZero()) {
      estado = EstadoCDP.totalmenteComprometido;
    }
  }

  /// Verifica si está vinculado a contrato
  bool estaVinculadoAContrato() {
    return contratoNumero != null && contratoNumero!.isNotEmpty;
  }

  CDP copyWith({
    String? id,
    String? entidadId,
    String? numeroCDP,
    String? vigencia,
    String? apropiacionId,
    String? codigoRubro,
    MoneyValue? valorCDP,
    MoneyValue? valorComprometidoRP,
    MoneyValue? saldoDisponible,
    DateTime? fechaExpedicion,
    DateTime? fechaVigencia,
    String? funcionarioExpedidor,
    String? funcionarioSolicitante,
    String? objetoGasto,
    String? contratoNumero,
    EstadoCDP? estado,
    String? actoAdministrativoModificacion,
    DateTime? fechaModificacion,
    String? observaciones,
  }) {
    return CDP(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroCDP: numeroCDP ?? this.numeroCDP,
      vigencia: vigencia ?? this.vigencia,
      apropiacionId: apropiacionId ?? this.apropiacionId,
      codigoRubro: codigoRubro ?? this.codigoRubro,
      valorCDP: valorCDP ?? this.valorCDP,
      valorComprometidoRP: valorComprometidoRP ?? this.valorComprometidoRP,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      fechaExpedicion: fechaExpedicion ?? this.fechaExpedicion,
      fechaVigencia: fechaVigencia ?? this.fechaVigencia,
      funcionarioExpedidor: funcionarioExpedidor ?? this.funcionarioExpedidor,
      funcionarioSolicitante: funcionarioSolicitante ?? this.funcionarioSolicitante,
      objetoGasto: objetoGasto ?? this.objetoGasto,
      contratoNumero: contratoNumero ?? this.contratoNumero,
      estado: estado ?? this.estado,
      actoAdministrativoModificacion: actoAdministrativoModificacion ?? this.actoAdministrativoModificacion,
      fechaModificacion: fechaModificacion ?? this.fechaModificacion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
