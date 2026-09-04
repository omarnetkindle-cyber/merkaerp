/// Modelos de Estados Financieros según NICSP
/// NICSP 1: Estados Financieros
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoEstadoFinanciero {
  estadoSituacionFinanciera, // Balance General
  estadoResultadoOperacional, // PyG
  estadoCambiosPatrimonio, // Estado de Cambios en el Patrimonio
  estadoFlujosEfectivo, // NICSP 2
  estadoCuentasOrden, // Cuentas de Orden
}

class EstadoSituacionFinanciera {
  final String entidadId;
  final String vigencia;
  final DateTime fechaCorte;
  final MoneyValue totalActivo;
  final MoneyValue totalPasivo;
  final MoneyValue totalPatrimonio;
  final MoneyValue totalPasivoPatrimonio;
  final List<RenglonEstado> activos;
  final List<RenglonEstado> pasivos;
  final List<RenglonEstado> patrimonio;

  EstadoSituacionFinanciera({
    required this.entidadId,
    required this.vigencia,
    required this.fechaCorte,
    required this.totalActivo,
    required this.totalPasivo,
    required this.totalPatrimonio,
    required this.totalPasivoPatrimonio,
    required this.activos,
    required this.pasivos,
    required this.patrimonio,
  });

  factory EstadoSituacionFinanciera.fromJson(Map<String, dynamic> json) {
    return EstadoSituacionFinanciera(
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      fechaCorte: DateTime.parse(json['fecha_corte'] as String),
      totalActivo: publicMoneyFromSql(json['total_activo']),
      totalPasivo: publicMoneyFromSql(json['total_pasivo']),
      totalPatrimonio: publicMoneyFromSql(json['total_patrimonio']),
      totalPasivoPatrimonio: publicMoneyFromSql(json['total_pasivo_patrimonio']),
      activos: (json['activos'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
      pasivos: (json['pasivos'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
      patrimonio: (json['patrimonio'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'fecha_corte': fechaCorte.toIso8601String(),
      'total_activo': totalActivo.toSql(),
      'total_pasivo': totalPasivo.toSql(),
      'total_patrimonio': totalPatrimonio.toSql(),
      'total_pasivo_patrimonio': totalPasivoPatrimonio.toSql(),
      'activos': activos.map((r) => r.toJson()).toList(),
      'pasivos': pasivos.map((r) => r.toJson()).toList(),
      'patrimonio': patrimonio.map((r) => r.toJson()).toList(),
    };
  }

  /// Verifica que el estado esté cuadrado (Activo = Pasivo + Patrimonio)
  bool estaCuadrado() {
    return totalActivo == totalPasivoPatrimonio;
  }
}

class EstadoResultadoOperacional {
  final String entidadId;
  final String vigencia;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final MoneyValue totalIngresos;
  final MoneyValue totalGastos;
  final MoneyValue resultadoOperacional;
  final List<RenglonEstado> ingresos;
  final List<RenglonEstado> gastos;

  EstadoResultadoOperacional({
    required this.entidadId,
    required this.vigencia,
    required this.fechaInicio,
    required this.fechaFin,
    required this.totalIngresos,
    required this.totalGastos,
    required this.resultadoOperacional,
    required this.ingresos,
    required this.gastos,
  });

  factory EstadoResultadoOperacional.fromJson(Map<String, dynamic> json) {
    return EstadoResultadoOperacional(
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      totalIngresos: publicMoneyFromSql(json['total_ingresos']),
      totalGastos: publicMoneyFromSql(json['total_gastos']),
      resultadoOperacional: publicMoneyFromSql(json['resultado_operacional']),
      ingresos: (json['ingresos'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
      gastos: (json['gastos'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'total_ingresos': totalIngresos.toSql(),
      'total_gastos': totalGastos.toSql(),
      'resultado_operacional': resultadoOperacional.toSql(),
      'ingresos': ingresos.map((r) => r.toJson()).toList(),
      'gastos': gastos.map((r) => r.toJson()).toList(),
    };
  }
}

class EstadoFlujosEfectivo {
  final String entidadId;
  final String vigencia;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final MoneyValue totalActividadesOperacion;
  final MoneyValue totalActividadesInversion;
  final MoneyValue totalActividadesFinanciacion;
  final MoneyValue variacionNetaEfectivo;
  final MoneyValue efectivoAlInicio;
  final MoneyValue efectivoAlFinal;
  final List<RenglonEstado> actividadesOperacion;
  final List<RenglonEstado> actividadesInversion;
  final List<RenglonEstado> actividadesFinanciacion;

  EstadoFlujosEfectivo({
    required this.entidadId,
    required this.vigencia,
    required this.fechaInicio,
    required this.fechaFin,
    required this.totalActividadesOperacion,
    required this.totalActividadesInversion,
    required this.totalActividadesFinanciacion,
    required this.variacionNetaEfectivo,
    required this.efectivoAlInicio,
    required this.efectivoAlFinal,
    required this.actividadesOperacion,
    required this.actividadesInversion,
    required this.actividadesFinanciacion,
  });

  factory EstadoFlujosEfectivo.fromJson(Map<String, dynamic> json) {
    return EstadoFlujosEfectivo(
      entidadId: json['entidad_id'] as String,
      vigencia: json['vigencia'] as String,
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaFin: DateTime.parse(json['fecha_fin'] as String),
      totalActividadesOperacion: publicMoneyFromSql(json['total_actividades_operacion']),
      totalActividadesInversion: publicMoneyFromSql(json['total_actividades_inversion']),
      totalActividadesFinanciacion: publicMoneyFromSql(json['total_actividades_financiacion']),
      variacionNetaEfectivo: publicMoneyFromSql(json['variacion_neta_efectivo']),
      efectivoAlInicio: publicMoneyFromSql(json['efectivo_al_inicio']),
      efectivoAlFinal: publicMoneyFromSql(json['efectivo_al_final']),
      actividadesOperacion: (json['actividades_operacion'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
      actividadesInversion: (json['actividades_inversion'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
      actividadesFinanciacion: (json['actividades_financiacion'] as List)
          .map((r) => RenglonEstado.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'total_actividades_operacion': totalActividadesOperacion.toSql(),
      'total_actividades_inversion': totalActividadesInversion.toSql(),
      'total_actividades_financiacion': totalActividadesFinanciacion.toSql(),
      'variacion_neta_efectivo': variacionNetaEfectivo.toSql(),
      'efectivo_al_inicio': efectivoAlInicio.toSql(),
      'efectivo_al_final': efectivoAlFinal.toSql(),
      'actividades_operacion': actividadesOperacion.map((r) => r.toJson()).toList(),
      'actividades_inversion': actividadesInversion.map((r) => r.toJson()).toList(),
      'actividades_financiacion': actividadesFinanciacion.map((r) => r.toJson()).toList(),
    };
  }

  /// Verifica que el estado esté cuadrado
  bool estaCuadrado() {
    final calculadoFinal = efectivoAlInicio + variacionNetaEfectivo;
    return efectivoAlFinal == calculadoFinal;
  }
}

class RenglonEstado {
  final String codigoCuenta;
  final String nombreCuenta;
  final MoneyValue valor;
  final int nivel; // Para indentación en reportes
  final bool esTotal; // Si es un renglón de subtotal

  RenglonEstado({
    required this.codigoCuenta,
    required this.nombreCuenta,
    required this.valor,
    required this.nivel,
    this.esTotal = false,
  });

  factory RenglonEstado.fromJson(Map<String, dynamic> json) {
    return RenglonEstado(
      codigoCuenta: json['codigo_cuenta'] as String,
      nombreCuenta: json['nombre_cuenta'] as String,
      valor: publicMoneyFromSql(json['valor']),
      nivel: json['nivel'] as int,
      esTotal: json['es_total'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codigo_cuenta': codigoCuenta,
      'nombre_cuenta': nombreCuenta,
      'valor': valor.toSql(),
      'nivel': nivel,
      'es_total': esTotal,
    };
  }
}
