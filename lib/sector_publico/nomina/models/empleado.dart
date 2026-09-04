/// Modelo de Empleado Público
/// Para nómina pública con cálculo de aportes parafiscales
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoContrato {
  indefinido,
  fijo,
  aprendizaje,
  practicas,
  docente,
  misional,
}

enum TipoVinculacion { carrera, libreNombramiento, provision, contrato }

/// Regimenes de vinculacion que requieren tratamiento salarial diferenciado.
/// Las escalas y componentes propios de cada entidad se cargan en sus actos
/// administrativos; el sistema no infiere primas o convenciones inexistentes.
enum RegimenNominaPublica {
  carreraAdministrativa,
  libreNombramientoRemocion,
  trabajadorOficial,
  docenteTerritorial,
  saludEse,
  judicialFiscalia,
}

class Empleado {
  final String id;
  final String entidadId;
  final String numeroIdentificacion;
  final String nombreCompleto;
  final String cargo;
  final String dependencia;
  final TipoContrato tipoContrato;
  final TipoVinculacion tipoVinculacion;
  final RegimenNominaPublica regimenNomina;
  final int claseRiesgoArl;
  final MoneyValue salarioBasico;
  final DateTime fechaIngreso;
  final DateTime? fechaRetiro;
  final bool activo;
  final String? cuentaBancaria;
  final String? tipoCuenta;
  final String? banco;
  final String? eps;
  final String? fondoPension;
  final String? fondoCesantias;
  final String? observaciones;
  final int? hrmEmployeeId;

  Empleado({
    required this.id,
    required this.entidadId,
    required this.numeroIdentificacion,
    required this.nombreCompleto,
    required this.cargo,
    required this.dependencia,
    required this.tipoContrato,
    required this.tipoVinculacion,
    required this.regimenNomina,
    required this.claseRiesgoArl,
    required this.salarioBasico,
    required this.fechaIngreso,
    this.fechaRetiro,
    required this.activo,
    this.cuentaBancaria,
    this.tipoCuenta,
    this.banco,
    this.eps,
    this.fondoPension,
    this.fondoCesantias,
    this.observaciones,
    this.hrmEmployeeId,
  });

  factory Empleado.fromJson(Map<String, dynamic> json) {
    return Empleado(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroIdentificacion: json['numero_identificacion'] as String,
      nombreCompleto: json['nombre_completo'] as String,
      cargo: json['cargo'] as String,
      dependencia: json['dependencia'] as String,
      tipoContrato: TipoContrato.values.firstWhere(
        (e) => e.toString() == 'TipoContrato.${json['tipo_contrato']}',
      ),
      tipoVinculacion: TipoVinculacion.values.firstWhere(
        (e) => e.toString() == 'TipoVinculacion.${json['tipo_vinculacion']}',
      ),
      regimenNomina: RegimenNominaPublica.values.firstWhere(
        (e) => e.name == json['regimen_nomina'],
        orElse: () =>
            _regimenPorVinculacion(json['tipo_vinculacion'] as String),
      ),
      claseRiesgoArl: (json['clase_riesgo_arl'] as num?)?.toInt() ?? 1,
      salarioBasico: publicMoneyFromSql(json['salario_basico']),
      fechaIngreso: DateTime.parse(json['fecha_ingreso'] as String),
      fechaRetiro: json['fecha_retiro'] != null
          ? DateTime.parse(json['fecha_retiro'] as String)
          : null,
      activo: json['activo'] == true || json['activo'] == 1,
      cuentaBancaria: json['cuenta_bancaria'] as String?,
      tipoCuenta: json['tipo_cuenta'] as String?,
      banco: json['banco'] as String?,
      eps: json['eps'] as String?,
      fondoPension: json['fondo_pension'] as String?,
      fondoCesantias: json['fondo_cesantias'] as String?,
      observaciones: json['observaciones'] as String?,
      hrmEmployeeId: (json['hrm_employee_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_identificacion': numeroIdentificacion,
      'nombre_completo': nombreCompleto,
      'cargo': cargo,
      'dependencia': dependencia,
      'tipo_contrato': tipoContrato.toString().split('.').last,
      'tipo_vinculacion': tipoVinculacion.toString().split('.').last,
      'regimen_nomina': regimenNomina.name,
      'clase_riesgo_arl': claseRiesgoArl,
      'salario_basico': salarioBasico.toSql(),
      'fecha_ingreso': fechaIngreso.toIso8601String(),
      'fecha_retiro': fechaRetiro?.toIso8601String(),
      'activo': activo,
      'cuenta_bancaria': cuentaBancaria,
      'tipo_cuenta': tipoCuenta,
      'banco': banco,
      'eps': eps,
      'fondo_pension': fondoPension,
      'fondo_cesantias': fondoCesantias,
      'observaciones': observaciones,
      'hrm_employee_id': hrmEmployeeId,
    };
  }

  /// Verifica si es docente (tiene cálculos especiales)
  bool esDocente() {
    return tipoContrato == TipoContrato.docente;
  }

  /// Calcula los días trabajados en un periodo
  int calcularDiasTrabajados(DateTime fechaInicio, DateTime fechaFin) {
    if (!activo && fechaRetiro != null) {
      fechaFin = fechaRetiro!;
    }
    return fechaFin.difference(fechaInicio).inDays + 1;
  }

  Empleado copyWith({
    String? id,
    String? entidadId,
    String? numeroIdentificacion,
    String? nombreCompleto,
    String? cargo,
    String? dependencia,
    TipoContrato? tipoContrato,
    TipoVinculacion? tipoVinculacion,
    RegimenNominaPublica? regimenNomina,
    int? claseRiesgoArl,
    MoneyValue? salarioBasico,
    DateTime? fechaIngreso,
    DateTime? fechaRetiro,
    bool? activo,
    String? cuentaBancaria,
    String? tipoCuenta,
    String? banco,
    String? eps,
    String? fondoPension,
    String? fondoCesantias,
    String? observaciones,
    int? hrmEmployeeId,
  }) {
    return Empleado(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroIdentificacion: numeroIdentificacion ?? this.numeroIdentificacion,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      cargo: cargo ?? this.cargo,
      dependencia: dependencia ?? this.dependencia,
      tipoContrato: tipoContrato ?? this.tipoContrato,
      tipoVinculacion: tipoVinculacion ?? this.tipoVinculacion,
      regimenNomina: regimenNomina ?? this.regimenNomina,
      claseRiesgoArl: claseRiesgoArl ?? this.claseRiesgoArl,
      salarioBasico: salarioBasico ?? this.salarioBasico,
      fechaIngreso: fechaIngreso ?? this.fechaIngreso,
      fechaRetiro: fechaRetiro ?? this.fechaRetiro,
      activo: activo ?? this.activo,
      cuentaBancaria: cuentaBancaria ?? this.cuentaBancaria,
      tipoCuenta: tipoCuenta ?? this.tipoCuenta,
      banco: banco ?? this.banco,
      eps: eps ?? this.eps,
      fondoPension: fondoPension ?? this.fondoPension,
      fondoCesantias: fondoCesantias ?? this.fondoCesantias,
      observaciones: observaciones ?? this.observaciones,
      hrmEmployeeId: hrmEmployeeId ?? this.hrmEmployeeId,
    );
  }

  static RegimenNominaPublica _regimenPorVinculacion(String vinculacion) {
    return vinculacion == TipoVinculacion.libreNombramiento.name
        ? RegimenNominaPublica.libreNombramientoRemocion
        : RegimenNominaPublica.carreraAdministrativa;
  }
}
