/// Modelos de Reportes CHIP (Contaduría General de la Nación)
/// Formularios CGN 2015_001 a 005 y CGN 2016C01
library;

import 'dart:convert';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

enum TipoFormularioCHIP {
  cgn2015_001, // Información de la entidad
  cgn2015_002, // Ingresos y gastos
  cgn2015_003, // Situación financiera
  cgn2015_004, // Ejecución presupuestal
  cgn2015_005, // Deuda pública
  cgn2016C01, // Consolidado
}

class ReporteCHIP {
  final String id;
  final String entidadId;
  final TipoFormularioCHIP tipoFormulario;
  final String vigencia;
  final DateTime fechaGeneracion;
  final String usuarioGenero;
  final Map<String, dynamic> datos;
  final String estado; // generado, enviado, aceptado, rechazado
  final String? observaciones;

  ReporteCHIP({
    required this.id,
    required this.entidadId,
    required this.tipoFormulario,
    required this.vigencia,
    required this.fechaGeneracion,
    required this.usuarioGenero,
    required this.datos,
    required this.estado,
    this.observaciones,
  });

  factory ReporteCHIP.fromJson(Map<String, dynamic> json) {
    return ReporteCHIP(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      tipoFormulario: TipoFormularioCHIP.values.firstWhere(
        (e) => e.toString() == 'TipoFormularioCHIP.${json['tipo_formulario']}',
      ),
      vigencia: json['vigencia'] as String,
      fechaGeneracion: DateTime.parse(json['fecha_generacion'] as String),
      usuarioGenero: json['usuario_genero'] as String,
      datos: json['datos'] is String
          ? Map<String, dynamic>.from(
              jsonDecode(json['datos'] as String) as Map,
            )
          : Map<String, dynamic>.from(json['datos'] as Map),
      estado: json['estado'] as String,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'tipo_formulario': tipoFormulario.toString().split('.').last,
      'vigencia': vigencia,
      'fecha_generacion': fechaGeneracion.toIso8601String(),
      'usuario_genero': usuarioGenero,
      'datos': jsonEncode(datos),
      'estado': estado,
      'observaciones': observaciones,
    };
  }

  /// Obtiene el nombre del formulario
  String get nombreFormulario {
    switch (tipoFormulario) {
      case TipoFormularioCHIP.cgn2015_001:
        return 'CGN 2015_001 - Información de la Entidad';
      case TipoFormularioCHIP.cgn2015_002:
        return 'CGN 2015_002 - Ingresos y Gastos';
      case TipoFormularioCHIP.cgn2015_003:
        return 'CGN 2015_003 - Situación Financiera';
      case TipoFormularioCHIP.cgn2015_004:
        return 'CGN 2015_004 - Ejecución Presupuestal';
      case TipoFormularioCHIP.cgn2015_005:
        return 'CGN 2015_005 - Deuda Pública';
      case TipoFormularioCHIP.cgn2016C01:
        return 'CGN 2016C01 - Consolidado';
    }
  }
}

/// Datos específicos para formulario CGN 2015_001
class DatosCGN2015_001 {
  final String nit;
  final String razonSocial;
  final String tipoEntidad;
  final String departamento;
  final String municipio;
  final String direccion;
  final String telefono;
  final String email;
  final String representanteLegal;
  final String identificacionRepresentante;
  final String ordenadorGasto;
  final String identificacionOrdenador;
  final String contador;
  final String identificacionContador;
  final String tarjetaProfesionalContador;

  DatosCGN2015_001({
    required this.nit,
    required this.razonSocial,
    required this.tipoEntidad,
    required this.departamento,
    required this.municipio,
    required this.direccion,
    required this.telefono,
    required this.email,
    required this.representanteLegal,
    required this.identificacionRepresentante,
    required this.ordenadorGasto,
    required this.identificacionOrdenador,
    required this.contador,
    required this.identificacionContador,
    required this.tarjetaProfesionalContador,
  });

  Map<String, dynamic> toJson() {
    return {
      'nit': nit,
      'razon_social': razonSocial,
      'tipo_entidad': tipoEntidad,
      'departamento': departamento,
      'municipio': municipio,
      'direccion': direccion,
      'telefono': telefono,
      'email': email,
      'representante_legal': representanteLegal,
      'identificacion_representante': identificacionRepresentante,
      'ordenador_gasto': ordenadorGasto,
      'identificacion_ordenador': identificacionOrdenador,
      'contador': contador,
      'identificacion_contador': identificacionContador,
      'tarjeta_profesional_contador': tarjetaProfesionalContador,
    };
  }
}

/// Datos específicos para formulario CGN 2015_002 (Ingresos y Gastos)
class DatosCGN2015_002 {
  final MoneyValue ingresosTributarios;
  final MoneyValue ingresosNoTributarios;
  final MoneyValue transferenciasSGP;
  final MoneyValue regalias;
  final MoneyValue otrosIngresos;
  final MoneyValue totalIngresos;
  final MoneyValue gastosPersonal;
  final MoneyValue gastosGenerales;
  final MoneyValue transferencias;
  final MoneyValue gastosInversion;
  final MoneyValue otrosGastos;
  final MoneyValue totalGastos;
  final MoneyValue resultadoOperacional;

  DatosCGN2015_002({
    required this.ingresosTributarios,
    required this.ingresosNoTributarios,
    required this.transferenciasSGP,
    required this.regalias,
    required this.otrosIngresos,
    required this.totalIngresos,
    required this.gastosPersonal,
    required this.gastosGenerales,
    required this.transferencias,
    required this.gastosInversion,
    required this.otrosGastos,
    required this.totalGastos,
    required this.resultadoOperacional,
  });

  Map<String, dynamic> toJson() {
    return {
      'ingresos_tributarios': publicMoneyForDisplay(ingresosTributarios),
      'ingresos_no_tributarios': publicMoneyForDisplay(ingresosNoTributarios),
      'transferencias_sgp': publicMoneyForDisplay(transferenciasSGP),
      'regalias': publicMoneyForDisplay(regalias),
      'otros_ingresos': publicMoneyForDisplay(otrosIngresos),
      'total_ingresos': publicMoneyForDisplay(totalIngresos),
      'gastos_personal': publicMoneyForDisplay(gastosPersonal),
      'gastos_generales': publicMoneyForDisplay(gastosGenerales),
      'transferencias': publicMoneyForDisplay(transferencias),
      'gastos_inversion': publicMoneyForDisplay(gastosInversion),
      'otros_gastos': publicMoneyForDisplay(otrosGastos),
      'total_gastos': publicMoneyForDisplay(totalGastos),
      'resultado_operacional': publicMoneyForDisplay(resultadoOperacional),
    };
  }
}

/// Datos específicos para formulario CGN 2015_003 (Situación Financiera)
class DatosCGN2015_003 {
  final MoneyValue activoCorriente;
  final MoneyValue activoNoCorriente;
  final MoneyValue totalActivo;
  final MoneyValue pasivoCorriente;
  final MoneyValue pasivoNoCorriente;
  final MoneyValue totalPasivo;
  final MoneyValue patrimonio;
  final MoneyValue totalPasivoPatrimonio;

  DatosCGN2015_003({
    required this.activoCorriente,
    required this.activoNoCorriente,
    required this.totalActivo,
    required this.pasivoCorriente,
    required this.pasivoNoCorriente,
    required this.totalPasivo,
    required this.patrimonio,
    required this.totalPasivoPatrimonio,
  });

  Map<String, dynamic> toJson() {
    return {
      'activo_corriente': publicMoneyForDisplay(activoCorriente),
      'activo_no_corriente': publicMoneyForDisplay(activoNoCorriente),
      'total_activo': publicMoneyForDisplay(totalActivo),
      'pasivo_corriente': publicMoneyForDisplay(pasivoCorriente),
      'pasivo_no_corriente': publicMoneyForDisplay(pasivoNoCorriente),
      'total_pasivo': publicMoneyForDisplay(totalPasivo),
      'patrimonio': publicMoneyForDisplay(patrimonio),
      'total_pasivo_patrimonio': publicMoneyForDisplay(totalPasivoPatrimonio),
    };
  }
}

/// Datos específicos para formulario CGN 2015_004 (Ejecución Presupuestal)
class DatosCGN2015_004 {
  final MoneyValue apropiacionInicial;
  final MoneyValue adiciones;
  final MoneyValue reducciones;
  final MoneyValue credito;
  final MoneyValue contraCredito;
  final MoneyValue apropiacionDefinitiva;
  final MoneyValue compromisos;
  final MoneyValue obligaciones;
  final MoneyValue pagos;
  final MoneyValue saldoPorComprometer;

  DatosCGN2015_004({
    required this.apropiacionInicial,
    required this.adiciones,
    required this.reducciones,
    required this.credito,
    required this.contraCredito,
    required this.apropiacionDefinitiva,
    required this.compromisos,
    required this.obligaciones,
    required this.pagos,
    required this.saldoPorComprometer,
  });

  Map<String, dynamic> toJson() {
    return {
      'apropiacion_inicial': publicMoneyForDisplay(apropiacionInicial),
      'adiciones': publicMoneyForDisplay(adiciones),
      'reducciones': publicMoneyForDisplay(reducciones),
      'credito': publicMoneyForDisplay(credito),
      'contra_credito': publicMoneyForDisplay(contraCredito),
      'apropiacion_definitiva': publicMoneyForDisplay(apropiacionDefinitiva),
      'compromisos': publicMoneyForDisplay(compromisos),
      'obligaciones': publicMoneyForDisplay(obligaciones),
      'pagos': publicMoneyForDisplay(pagos),
      'saldo_por_comprometer': publicMoneyForDisplay(saldoPorComprometer),
    };
  }
}

/// Datos específicos para formulario CGN 2015_005 (Deuda Pública)
class DatosCGN2015_005 {
  final MoneyValue deudaInterna;
  final MoneyValue deudaExterna;
  final MoneyValue deudaTotal;
  final MoneyValue servicioDeuda;
  final MoneyValue cuotaAmortizacion;
  final MoneyValue intereses;
  final MoneyValue deudaVencida;

  DatosCGN2015_005({
    required this.deudaInterna,
    required this.deudaExterna,
    required this.deudaTotal,
    required this.servicioDeuda,
    required this.cuotaAmortizacion,
    required this.intereses,
    required this.deudaVencida,
  });

  Map<String, dynamic> toJson() {
    return {
      'deuda_interna': publicMoneyForDisplay(deudaInterna),
      'deuda_externa': publicMoneyForDisplay(deudaExterna),
      'deuda_total': publicMoneyForDisplay(deudaTotal),
      'servicio_deuda': publicMoneyForDisplay(servicioDeuda),
      'cuota_amortizacion': publicMoneyForDisplay(cuotaAmortizacion),
      'intereses': publicMoneyForDisplay(intereses),
      'deuda_vencida': publicMoneyForDisplay(deudaVencida),
    };
  }
}
