/// Modelo de Bienio Presupuestal SGR (Sistema General de Regalías - Colombia)
/// Ley 2056 de 2020 - Ciclo presupuestal bienal (2 años)
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum EstadoBienioSGR { vigente, cerrado }

class BienioSGR {
  final String id;
  final String entidadId;
  final String codigoBienio; // Formato bienal: 2025-2026
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final MoneyValue montoPresupuestadoBienio;
  final MoneyValue montoEjecutadoBienio;
  final EstadoBienioSGR estado;
  final String? observaciones;

  BienioSGR({
    required this.id,
    required this.entidadId,
    required this.codigoBienio,
    required this.fechaInicio,
    required this.fechaFin,
    required this.montoPresupuestadoBienio,
    required this.montoEjecutadoBienio,
    required this.estado,
    this.observaciones,
  });

  factory BienioSGR.fromJson(Map<String, dynamic> json) {
    return BienioSGR(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      codigoBienio: json['codigo_bienio'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      montoPresupuestadoBienio: publicMoneyFromSql(
        json['monto_presupuestado_bienio'],
      ),
      montoEjecutadoBienio: publicMoneyFromSql(json['monto_ejecutado_bienio']),
      estado: EstadoBienioSGR.values.firstWhere(
        (e) => e.name == json['estado'],
        orElse: () => EstadoBienioSGR.vigente,
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'codigo_bienio': codigoBienio,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'monto_presupuestado_bienio': montoPresupuestadoBienio.toSql(),
      'monto_ejecutado_bienio': montoEjecutadoBienio.toSql(),
      'estado': estado.name,
      'observaciones': observaciones,
    };
  }

  bool get estaVigente => estado == EstadoBienioSGR.vigente;
}
