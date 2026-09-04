/// Modelos de Reporte FUT Territorial (Formulario Único Territorial - DNP / CHIP)
/// Reporte trimestral de Ingresos, Gastos, Deuda Pública y Regalías para el Departamento Nacional de Planeación
library;

import 'dart:convert';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoFormularioFUTTerritorial {
  futIngresos,
  futGastos,
  futDeuda,
  futRegalias,
}

class ReporteFUTTerritorial {
  final String id;
  final String entidadId;
  final TipoFormularioFUTTerritorial tipoFormulario;
  final String vigencia;
  final int trimestre; // 1, 2, 3, 4
  final DateTime fechaGeneracion;
  final String usuarioGenero;
  final Map<String, dynamic> datos;
  final String estado; // generado, enviado, aceptado
  final String? observaciones;

  ReporteFUTTerritorial({
    required this.id,
    required this.entidadId,
    required this.tipoFormulario,
    required this.vigencia,
    required this.trimestre,
    required this.fechaGeneracion,
    required this.usuarioGenero,
    required this.datos,
    required this.estado,
    this.observaciones,
  });

  factory ReporteFUTTerritorial.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> datosMap;
    if (json['datos'] is String) {
      datosMap = jsonDecode(json['datos'] as String) as Map<String, dynamic>;
    } else {
      datosMap = json['datos'] as Map<String, dynamic>;
    }

    return ReporteFUTTerritorial(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      tipoFormulario: TipoFormularioFUTTerritorial.values.firstWhere(
        (e) => e.name == json['tipo_formulario'],
        orElse: () => TipoFormularioFUTTerritorial.futIngresos,
      ),
      vigencia: json['vigencia'] as String,
      trimestre: json['trimestre'] is int
          ? json['trimestre'] as int
          : int.parse(json['trimestre'].toString()),
      fechaGeneracion: DateTime.parse(json['fecha_generacion'] as String),
      usuarioGenero: json['usuario_genero'] as String,
      datos: datosMap,
      estado: json['estado'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'tipo_formulario': tipoFormulario.name,
      'vigencia': vigencia,
      'trimestre': trimestre,
      'fecha_generacion': fechaGeneracion.toIso8601String(),
      'usuario_genero': usuarioGenero,
      'datos': jsonEncode(datos),
      'estado': estado,
      'observaciones': observaciones,
    };
  }

  String get nombreFormulario {
    switch (tipoFormulario) {
      case TipoFormularioFUTTerritorial.futIngresos:
        return 'FUT Ingresos (Recaudos y Transferencias SGP/FUT)';
      case TipoFormularioFUTTerritorial.futGastos:
        return 'FUT Gastos (Funcionamiento e Inversión DNP)';
      case TipoFormularioFUTTerritorial.futDeuda:
        return 'FUT Deuda Pública (Saldo y Amortización)';
      case TipoFormularioFUTTerritorial.futRegalias:
        return 'FUT Regalías (Sistema General de Regalías SGR)';
    }
  }
}

/// Datos de Ejecución de Ingresos FUT DNP
class DatosFUTIngresos {
  final MoneyValue ingresosCorrientes;
  final MoneyValue tributarios;
  final MoneyValue noTributarios;
  final MoneyValue transferenciasSGP;
  final MoneyValue regalias;
  final MoneyValue totalRecaudado;

  DatosFUTIngresos({
    required this.ingresosCorrientes,
    required this.tributarios,
    required this.noTributarios,
    required this.transferenciasSGP,
    required this.regalias,
    required this.totalRecaudado,
  });

  Map<String, dynamic> toJson() {
    return {
      'ingresos_corrientes': publicMoneyForDisplay(ingresosCorrientes),
      'tributarios': publicMoneyForDisplay(tributarios),
      'no_tributarios': publicMoneyForDisplay(noTributarios),
      'transferencias_sgp': publicMoneyForDisplay(transferenciasSGP),
      'regalias': publicMoneyForDisplay(regalias),
      'total_recaudado': publicMoneyForDisplay(totalRecaudado),
    };
  }
}

/// Datos de Ejecución de Gastos FUT DNP
class DatosFUTGastos {
  final MoneyValue funcionamiento;
  final MoneyValue serviciosPersonales;
  final MoneyValue gastosGenerales;
  final MoneyValue transferencias;
  final MoneyValue inversion;
  final MoneyValue servicioDeuda;
  final MoneyValue totalObligado;

  DatosFUTGastos({
    required this.funcionamiento,
    required this.serviciosPersonales,
    required this.gastosGenerales,
    required this.transferencias,
    required this.inversion,
    required this.servicioDeuda,
    required this.totalObligado,
  });

  Map<String, dynamic> toJson() {
    return {
      'funcionamiento': publicMoneyForDisplay(funcionamiento),
      'servicios_personales': publicMoneyForDisplay(serviciosPersonales),
      'gastos_generales': publicMoneyForDisplay(gastosGenerales),
      'transferencias': publicMoneyForDisplay(transferencias),
      'inversion': publicMoneyForDisplay(inversion),
      'servicio_deuda': publicMoneyForDisplay(servicioDeuda),
      'total_obligado': publicMoneyForDisplay(totalObligado),
    };
  }
}
