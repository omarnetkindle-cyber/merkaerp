/// Modelo de Cuenta Contable del Catálogo General de Cuentas (CGC)
/// Implementa estructura PUC Público según Resolución 533/2015 CGN
library;

import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
enum NaturalezaCuenta {
  deudora,
  acreedora,
}

enum ClaseCuenta {
  activo, // Clase 1
  pasivo, // Clase 2
  patrimonio, // Clase 3
  ingresos, // Clase 4
  gastos, // Clase 5
  costoVentas, // Clase 6
  cuentasOrdenDeudoras, // Clase 8
  cuentasOrdenAcreedoras, // Clase 9
}

class CuentaContable {
  final String id;
  final String entidadId;
  final String codigo; // Código completo (ej. "1111")
  final String nombre;
  final ClaseCuenta clase;
  final String grupo; // Primer dígito
  final String subgrupo; // Primeros dos dígitos
  final String cuenta; // Primeros cuatro dígitos
  final String? subcuenta; // Primeros seis dígitos
  final String? auxiliar; // Código completo
  final NaturalezaCuenta naturaleza;
  final bool activa;
  final String? cuentaPadre; // Para estructura jerárquica
  final int nivel; // 1=grupo, 2=subgrupo, 3=cuenta, 4=subcuenta, 5=auxiliar
  final DateTime fechaCreacion;
  final String? observaciones;

  CuentaContable({
    required this.id,
    required this.entidadId,
    required this.codigo,
    required this.nombre,
    required this.clase,
    required this.grupo,
    required this.subgrupo,
    required this.cuenta,
    this.subcuenta,
    this.auxiliar,
    required this.naturaleza,
    required this.activa,
    this.cuentaPadre,
    required this.nivel,
    required this.fechaCreacion,
    this.observaciones,
  });

  factory CuentaContable.fromJson(Map<String, dynamic> json) {
    return CuentaContable(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      codigo: json['codigo'] as String,
      nombre: json['nombre'] as String,
      clase: ClaseCuenta.values.firstWhere(
        (e) => e.toString() == 'ClaseCuenta.${json['clase']}',
      ),
      grupo: json['grupo'] as String,
      subgrupo: json['subgrupo'] as String,
      cuenta: json['cuenta'] as String,
      subcuenta: json['subcuenta'] as String?,
      auxiliar: json['auxiliar'] as String?,
      naturaleza: NaturalezaCuenta.values.firstWhere(
        (e) => e.toString() == 'NaturalezaCuenta.${json['naturaleza']}',
      ),
      activa: json['activa'] as bool,
      cuentaPadre: json['cuenta_padre'] as String?,
      nivel: json['nivel'] as int,
      fechaCreacion: DateTime.parse(json['fecha_creacion'] as String),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'codigo': codigo,
      'nombre': nombre,
      'clase': clase.toString().split('.').last,
      'grupo': grupo,
      'subgrupo': subgrupo,
      'cuenta': cuenta,
      'subcuenta': subcuenta,
      'auxiliar': auxiliar,
      'naturaleza': naturaleza.toString().split('.').last,
      'activa': activa,
      'cuenta_padre': cuentaPadre,
      'nivel': nivel,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'observaciones': observaciones,
    };
  }

  /// Verifica si es cuenta de detalle (auxiliar)
  bool esCuentaDetalle() {
    return nivel == 5 && auxiliar != null;
  }

  /// Verifica si es cuenta de mayor
  bool esCuentaMayor() {
    return nivel < 5;
  }

  /// Verifica si es cuenta de orden
  bool esCuentaOrden() {
    return clase == ClaseCuenta.cuentasOrdenDeudoras ||
           clase == ClaseCuenta.cuentasOrdenAcreedoras;
  }

  /// Obtiene el nombre de la clase
  String get nombreClase {
    switch (clase) {
      case ClaseCuenta.activo:
        return 'Activo';
      case ClaseCuenta.pasivo:
        return 'Pasivo';
      case ClaseCuenta.patrimonio:
        return 'Patrimonio';
      case ClaseCuenta.ingresos:
        return 'Ingresos';
      case ClaseCuenta.gastos:
        return 'Gastos';
      case ClaseCuenta.costoVentas:
        return 'Costo de Ventas';
      case ClaseCuenta.cuentasOrdenDeudoras:
        return 'Cuentas de Orden Deudoras';
      case ClaseCuenta.cuentasOrdenAcreedoras:
        return 'Cuentas de Orden Acreedoras';
    }
  }

  CuentaContable copyWith({
    String? id,
    String? entidadId,
    String? codigo,
    String? nombre,
    ClaseCuenta? clase,
    String? grupo,
    String? subgrupo,
    String? cuenta,
    String? subcuenta,
    String? auxiliar,
    NaturalezaCuenta? naturaleza,
    bool? activa,
    String? cuentaPadre,
    int? nivel,
    DateTime? fechaCreacion,
    String? observaciones,
  }) {
    return CuentaContable(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      clase: clase ?? this.clase,
      grupo: grupo ?? this.grupo,
      subgrupo: subgrupo ?? this.subgrupo,
      cuenta: cuenta ?? this.cuenta,
      subcuenta: subcuenta ?? this.subcuenta,
      auxiliar: auxiliar ?? this.auxiliar,
      naturaleza: naturaleza ?? this.naturaleza,
      activa: activa ?? this.activa,
      cuentaPadre: cuentaPadre ?? this.cuentaPadre,
      nivel: nivel ?? this.nivel,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

/// Modelo de saldo de cuenta
class SaldoCuenta {
  final String cuentaId;
  final String cuentaCodigo;
  final String cuentaNombre;
  final MoneyValue saldoDeudor;
  final MoneyValue saldoAcreedor;
  final MoneyValue saldoNeto; // Positivo = deudor, Negativo = acreedor
  final DateTime fechaUltimoMovimiento;

  SaldoCuenta({
    required this.cuentaId,
    required this.cuentaCodigo,
    required this.cuentaNombre,
    required this.saldoDeudor,
    required this.saldoAcreedor,
    required this.saldoNeto,
    required this.fechaUltimoMovimiento,
  });

  factory SaldoCuenta.fromJson(Map<String, dynamic> json) {
    return SaldoCuenta(
      cuentaId: json['cuenta_id'] as String,
      cuentaCodigo: json['cuenta_codigo'] as String,
      cuentaNombre: json['cuenta_nombre'] as String,
      saldoDeudor: publicMoneyFromSql(json['saldo_deudor']),
      saldoAcreedor: publicMoneyFromSql(json['saldo_acreedor']),
      saldoNeto: publicMoneyFromSql(json['saldo_neto']),
      fechaUltimoMovimiento: DateTime.parse(json['fecha_ultimo_movimiento'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cuenta_id': cuentaId,
      'cuenta_codigo': cuentaCodigo,
      'cuenta_nombre': cuentaNombre,
      'saldo_deudor': saldoDeudor.toSql(),
      'saldo_acreedor': saldoAcreedor.toSql(),
      'saldo_neto': saldoNeto.toSql(),
      'fecha_ultimo_movimiento': fechaUltimoMovimiento.toIso8601String(),
    };
  }

  /// Obtiene el saldo según naturaleza
  MoneyValue getSaldoSegunNaturaleza(NaturalezaCuenta naturaleza) {
    if (naturaleza == NaturalezaCuenta.deudora) {
      return saldoDeudor - saldoAcreedor;
    } else {
      return saldoAcreedor - saldoDeudor;
    }
  }
}
