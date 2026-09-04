/// Modelo de Fondo de Unidad de Tesorería (FUT Local / Recursos de Terceros)
/// Fondo de Unidad de Tesorería - Manejo de recursos de terceros
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoFondoUnidadTesoreria {
  contrato,
  convenio,
  donacion,
  fiducia,
  otro,
}

enum EstadoFondoUnidadTesoreria {
  activo,
  enEjecucion,
  suspendido,
  terminado,
  liquidado,
  cancelado,
}

class FondoUnidadTesoreria {
  final String id;
  final String entidadId;
  final String numeroFUT; // Formato: FUT-YYYY-NNNNNN
  final String nombreFUT;
  final TipoFondoUnidadTesoreria tipoFUT;
  final String? numeroContrato;
  final String? numeroConvenio;
  final String terceroId;
  final String terceroNombre;
  final String terceroIdentificacion;
  final MoneyValue valorInicial;
  final MoneyValue valorEjecutado;
  final MoneyValue saldoDisponible;
  final DateTime fechaApertura;
  final DateTime? fechaCierre;
  final EstadoFondoUnidadTesoreria estado;
  final String? responsable;
  final String? observaciones;

  FondoUnidadTesoreria({
    required this.id,
    required this.entidadId,
    required this.numeroFUT,
    required this.nombreFUT,
    required this.tipoFUT,
    this.numeroContrato,
    this.numeroConvenio,
    required this.terceroId,
    required this.terceroNombre,
    required this.terceroIdentificacion,
    required this.valorInicial,
    required this.valorEjecutado,
    required this.saldoDisponible,
    required this.fechaApertura,
    this.fechaCierre,
    required this.estado,
    this.responsable,
    this.observaciones,
  });

  factory FondoUnidadTesoreria.fromJson(Map<String, dynamic> json) {
    return FondoUnidadTesoreria(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroFUT: json['numero_fut'] as String,
      nombreFUT: json['nombre_fut'] as String,
      tipoFUT: TipoFondoUnidadTesoreria.values.firstWhere(
        (e) => e.name == json['tipo_fut'] || e.toString() == 'TipoFUT.${json['tipo_fut']}',
        orElse: () => TipoFondoUnidadTesoreria.convenio,
      ),
      numeroContrato: json['numero_contrato'] as String?,
      numeroConvenio: json['numero_convenio'] as String?,
      terceroId: json['tercero_id'] as String,
      terceroNombre: json['tercero_nombre'] as String,
      terceroIdentificacion: json['tercero_identificacion'] as String,
      valorInicial: publicMoneyFromSql(json['valor_inicial']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      fechaApertura: DateTime.parse(json['fecha_apertura'] as String),
      fechaCierre: json['fecha_cierre'] != null
          ? DateTime.parse(json['fecha_cierre'] as String)
          : null,
      estado: EstadoFondoUnidadTesoreria.values.firstWhere(
        (e) => e.name == json['estado'] || e.toString() == 'EstadoFUT.${json['estado']}',
        orElse: () => EstadoFondoUnidadTesoreria.activo,
      ),
      responsable: json['responsable'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_fut': numeroFUT,
      'nombre_fut': nombreFUT,
      'tipo_fut': tipoFUT.name,
      'numero_contrato': numeroContrato,
      'numero_convenio': numeroConvenio,
      'tercero_id': terceroId,
      'tercero_nombre': terceroNombre,
      'tercero_identificacion': terceroIdentificacion,
      'valor_inicial': valorInicial.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'fecha_apertura': fechaApertura.toIso8601String(),
      'fecha_cierre': fechaCierre?.toIso8601String(),
      'estado': estado.name,
      'responsable': responsable,
      'observaciones': observaciones,
    };
  }

  /// Calcula el porcentaje de ejecución
  double calcularPorcentajeEjecucion() {
    if (valorInicial == publicMoneyZero()) return 0;
    return (valorEjecutado.minorUnits / valorInicial.minorUnits) * 100;
  }

  /// Verifica si está activo
  bool estaActivo() {
    return estado == EstadoFondoUnidadTesoreria.activo || estado == EstadoFondoUnidadTesoreria.enEjecucion;
  }

  /// Verifica si tiene saldo disponible
  bool tieneSaldo() {
    return saldoDisponible > publicMoneyZero();
  }
}
