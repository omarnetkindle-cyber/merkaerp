/// Modelo de Programa Anual Mensualizado de Caja (PAC)
/// Define el monto máximo mensual de fondos disponibles para pagos
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum EstadoPAC {
  borrador,
  aprobado,
  modificado,
  ejecutado,
  cerrado,
}

class PAC {
  final String id;
  final String entidadId;
  final String vigencia;
  final int mes; // 1-12
  final String codigoRubro;
  final MoneyValue valorProgramado;
  MoneyValue valorEjecutado;
  MoneyValue saldoDisponible;
  final DateTime fechaCreacion;
  final DateTime? fechaAprobacion;
  final String? funcionarioAprobo;
  final EstadoPAC estado;
  final String? actoAdministrativo; // Resolución de aprobación
  final String? observaciones;

  PAC({
    required this.id,
    required this.entidadId,
    required this.vigencia,
    required this.mes,
    required this.codigoRubro,
    required this.valorProgramado,
    required this.valorEjecutado,
    required this.saldoDisponible,
    required this.fechaCreacion,
    this.fechaAprobacion,
    this.funcionarioAprobo,
    required this.estado,
    this.actoAdministrativo,
    this.observaciones,
  });

  factory PAC.fromJson(Map<String, dynamic> json) {
    return PAC(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      mes: json['mes'] as int,
      codigoRubro: json['codigo_rubro'] as String,
      valorProgramado: publicMoneyFromSql(json['valor_programado']),
      valorEjecutado: publicMoneyFromSql(json['valor_ejecutado']),
      saldoDisponible: publicMoneyFromSql(json['saldo_disponible']),
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      fechaAprobacion: json['fecha_aprobacion'] != null
          ? DateTime.parse(json['fecha_aprobacion'] as String)
          : null,
      funcionarioAprobo: json['funcionario_aprobo'] as String?,
      estado: EstadoPAC.values.firstWhere(
        (e) => e.toString() == 'EstadoPAC.${json['estado']}',
      ),
      actoAdministrativo: json['acto_administrativo'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'mes': mes,
      'codigo_rubro': codigoRubro,
      'valor_programado': valorProgramado.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'saldo_disponible': saldoDisponible.toSql(),
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_aprobacion': fechaAprobacion?.toIso8601String(),
      'funcionario_aprobo': funcionarioAprobo,
      'estado': estado.toString().split('.').last,
      'acto_administrativo': actoAdministrativo,
      'observaciones': observaciones,
    };
  }

  /// Verifica si el PAC está aprobado
  bool estaAprobado() {
    return estado == EstadoPAC.aprobado ||
           estado == EstadoPAC.modificado ||
           estado == EstadoPAC.ejecutado ||
           estado == EstadoPAC.cerrado;
  }

  /// Verifica si hay cupo PAC para un pago
  bool tieneCupoParaPago(MoneyValue montoPago) {
    return estaAprobado() && saldoDisponible >= montoPago;
  }

  /// Actualiza el saldo después de un pago
  void actualizarSaldoPago(MoneyValue montoPago) {
    valorEjecutado += montoPago;
    saldoDisponible -= montoPago;
  }

  /// Obtiene el nombre del mes
  String get nombreMes {
    final nombres = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return nombres[mes - 1];
  }

  PAC copyWith({
    String? id,
    String? entidadId,
    String? vigencia,
    int? mes,
    String? codigoRubro,
    MoneyValue? valorProgramado,
    MoneyValue? valorEjecutado,
    MoneyValue? saldoDisponible,
    DateTime? fechaCreacion,
    DateTime? fechaAprobacion,
    String? funcionarioAprobo,
    EstadoPAC? estado,
    String? actoAdministrativo,
    String? observaciones,
  }) {
    return PAC(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      vigencia: vigencia ?? this.vigencia,
      mes: mes ?? this.mes,
      codigoRubro: codigoRubro ?? this.codigoRubro,
      valorProgramado: valorProgramado ?? this.valorProgramado,
      valorEjecutado: valorEjecutado ?? this.valorEjecutado,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaAprobacion: fechaAprobacion ?? this.fechaAprobacion,
      funcionarioAprobo: funcionarioAprobo ?? this.funcionarioAprobo,
      estado: estado ?? this.estado,
      actoAdministrativo: actoAdministrativo ?? this.actoAdministrativo,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

/// Modelo para registro de embargos judiciales (informativo, por inembargabilidad)
class EmbargoJudicial {
  final String id;
  final String entidadId;
  final String numeroProceso;
  final String juzgado;
  final String? terceroId;
  final String terceroNombre;
  final MoneyValue valorEmbargo;
  final DateTime fechaRegistro;
  final DateTime? fechaLevantamiento;
  final bool activo;
  final String? observaciones;

  EmbargoJudicial({
    required this.id,
    required this.entidadId,
    required this.numeroProceso,
    required this.juzgado,
    this.terceroId,
    required this.terceroNombre,
    required this.valorEmbargo,
    required this.fechaRegistro,
    this.fechaLevantamiento,
    required this.activo,
    this.observaciones,
  });

  factory EmbargoJudicial.fromJson(Map<String, dynamic> json) {
    return EmbargoJudicial(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroProceso: json['numero_proceso'] as String,
      juzgado: json['juzgado'] as String,
      terceroId: json['tercero_id'] as String?,
      terceroNombre: json['tercero_nombre'] as String,
      valorEmbargo: publicMoneyFromSql(json['valor_embargo']),
      fechaRegistro: DateTime.parse(json['fecha_registro'] as String),
      fechaLevantamiento: json['fecha_levantamiento'] != null
          ? DateTime.parse(json['fecha_levantamiento'] as String)
          : null,
      activo: json['activo'] as bool,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_proceso': numeroProceso,
      'juzgado': juzgado,
      'tercero_id': terceroId,
      'tercero_nombre': terceroNombre,
      'valor_embargo': valorEmbargo.toSql(),
      'fecha_registro': fechaRegistro.toIso8601String(),
      'fecha_levantamiento': fechaLevantamiento?.toIso8601String(),
      'activo': activo,
      'observaciones': observaciones,
    };
  }
}

/// Modelo para estampillas parafiscales
class EstampillaParafiscal {
  final String id;
  final String entidadId;
  final String nombreEstampilla;
  final double tarifa; // Porcentaje (ej. 0.5%)
  final String baseLegal; // Ordenanza/ley habilitante
  final DateTime fechaCreacion;
  final bool activo;
  final String? observaciones;

  EstampillaParafiscal({
    required this.id,
    required this.entidadId,
    required this.nombreEstampilla,
    required this.tarifa,
    required this.baseLegal,
    required this.fechaCreacion,
    required this.activo,
    this.observaciones,
  });

  factory EstampillaParafiscal.fromJson(Map<String, dynamic> json) {
    return EstampillaParafiscal(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      nombreEstampilla: json['nombre_estampilla'] as String,
      tarifa: (json['tarifa'] as num).toDouble(),
      baseLegal: json['base_legal'] as String,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      activo: json['activo'] as bool,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'nombre_estampilla': nombreEstampilla,
      'tarifa': tarifa,
      'base_legal': baseLegal,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'activo': activo,
      'observaciones': observaciones,
    };
  }

  /// Calcula el valor de la estampilla
  double calcularValor(double baseGravable) {
    return baseGravable * (tarifa / 100);
  }
}
