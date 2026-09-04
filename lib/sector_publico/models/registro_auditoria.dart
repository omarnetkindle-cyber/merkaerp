/// Modelo de registro de auditoría append-only
/// Implementa hash encadenado para detectar manipulación
library;

import 'package:crypto/crypto.dart';
import 'dart:convert';

class RegistroAuditoria {
  final String id;
  final String entidadId;
  final String usuarioId;
  final String? usuarioNombre;
  final String? ipDireccion;
  final DateTime fechaHora;
  final TipoEventoAuditoria tipoEvento;
  final String modulo;
  final String accion;
  final Map<String, dynamic> valorAnterior;
  final Map<String, dynamic> valorNuevo;
  final String? hashAnterior; // Hash del registro anterior para encadenamiento
  final String hashActual; // Hash de este registro
  final String? referenciaId; // ID del registro afectado (ej. CDP, RP, etc.)
  final String? observaciones;

  RegistroAuditoria({
    required this.id,
    required this.entidadId,
    required this.usuarioId,
    this.usuarioNombre,
    this.ipDireccion,
    required this.fechaHora,
    required this.tipoEvento,
    required this.modulo,
    required this.accion,
    required this.valorAnterior,
    required this.valorNuevo,
    this.hashAnterior,
    required this.hashActual,
    this.referenciaId,
    this.observaciones,
  });

  static Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        // Los registros legados con Map.toString() se muestran como vacíos en
        // vez de provocar un cast inseguro. La verificación de integridad los
        // marca como no verificables.
      }
    }
    return <String, dynamic>{};
  }

  factory RegistroAuditoria.fromJson(Map<String, dynamic> json) {
    return RegistroAuditoria(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      usuarioId: json['usuario_id'] as String,
      usuarioNombre: json['usuario_nombre'] as String?,
      ipDireccion: json['ip_direccion'] as String?,
      fechaHora: DateTime.parse(json['fecha_hora'] as String),
      tipoEvento: TipoEventoAuditoria.values.firstWhere(
        (e) => e.toString() == 'TipoEventoAuditoria.${json['tipo_evento']}',
      ),
      modulo: json['modulo'] as String,
      accion: json['accion'] as String,
      valorAnterior: _mapValue(json['valor_anterior']),
      valorNuevo: _mapValue(json['valor_nuevo']),
      hashAnterior: json['hash_anterior'] as String?,
      hashActual: json['hash_actual'] as String,
      referenciaId: json['referencia_id'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'usuario_id': usuarioId,
      'usuario_nombre': usuarioNombre,
      'ip_direccion': ipDireccion,
      'fecha_hora': fechaHora.toIso8601String(),
      'tipo_evento': tipoEvento.toString().split('.').last,
      'modulo': modulo,
      'accion': accion,
      'valor_anterior': valorAnterior,
      'valor_nuevo': valorNuevo,
      'hash_anterior': hashAnterior,
      'hash_actual': hashActual,
      'referencia_id': referenciaId,
      'observaciones': observaciones,
    };
  }

  /// Calcula el hash SHA-256 de este registro para integridad
  static String calcularHash(Map<String, dynamic> datos) {
    final stringDatos = json.encode(datos);
    final bytes = utf8.encode(stringDatos);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  /// Verifica la integridad del encadenamiento de hashes
  bool verificarIntegridad(String? hashEsperadoAnterior) {
    return hashAnterior == hashEsperadoAnterior;
  }

  RegistroAuditoria copyWith({
    String? id,
    String? entidadId,
    String? usuarioId,
    String? usuarioNombre,
    String? ipDireccion,
    DateTime? fechaHora,
    TipoEventoAuditoria? tipoEvento,
    String? modulo,
    String? accion,
    Map<String, dynamic>? valorAnterior,
    Map<String, dynamic>? valorNuevo,
    String? hashAnterior,
    String? hashActual,
    String? referenciaId,
    String? observaciones,
  }) {
    return RegistroAuditoria(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      usuarioId: usuarioId ?? this.usuarioId,
      usuarioNombre: usuarioNombre ?? this.usuarioNombre,
      ipDireccion: ipDireccion ?? this.ipDireccion,
      fechaHora: fechaHora ?? this.fechaHora,
      tipoEvento: tipoEvento ?? this.tipoEvento,
      modulo: modulo ?? this.modulo,
      accion: accion ?? this.accion,
      valorAnterior: valorAnterior ?? this.valorAnterior,
      valorNuevo: valorNuevo ?? this.valorNuevo,
      hashAnterior: hashAnterior ?? this.hashAnterior,
      hashActual: hashActual ?? this.hashActual,
      referenciaId: referenciaId ?? this.referenciaId,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}

enum TipoEventoAuditoria {
  // Seguridad
  login,
  logout,
  cambioContrasena,
  cambioPermiso,

  // Presupuesto
  expedicionCDP,
  modificacionCDP,
  expedicionRP,
  modificacionRP,
  registroObligacion,
  pago,

  // Contabilidad
  asientoContable,
  reversaAsiento,
  cierreVigencia,

  // Nómina
  liquidacionNomina,
  pagoNomina,
  reliquidacion,

  // Rentas
  liquidacionTributo,
  recaudoTributo,
  inicioCobroCoactivo,

  // Contratación
  inicioProceso,
  adjudicacion,
  firmaContrato,
  liquidacionContrato,

  // General
  creacionRegistro,
  modificacionRegistro,
  intentoEliminacion, // CRÍTICO: nunca debe haber eliminación exitosa
}

/// Extension para obtener descripción legible del tipo de evento
extension TipoEventoAuditoriaExtension on TipoEventoAuditoria {
  String get descripcion {
    switch (this) {
      case TipoEventoAuditoria.login:
        return 'Inicio de sesión';
      case TipoEventoAuditoria.logout:
        return 'Cierre de sesión';
      case TipoEventoAuditoria.cambioContrasena:
        return 'Cambio de contraseña';
      case TipoEventoAuditoria.cambioPermiso:
        return 'Cambio de permisos';
      case TipoEventoAuditoria.expedicionCDP:
        return 'Expedición de CDP';
      case TipoEventoAuditoria.modificacionCDP:
        return 'Modificación de CDP';
      case TipoEventoAuditoria.expedicionRP:
        return 'Expedición de RP';
      case TipoEventoAuditoria.modificacionRP:
        return 'Modificación de RP';
      case TipoEventoAuditoria.registroObligacion:
        return 'Registro de obligación';
      case TipoEventoAuditoria.pago:
        return 'Pago';
      case TipoEventoAuditoria.asientoContable:
        return 'Asiento contable';
      case TipoEventoAuditoria.reversaAsiento:
        return 'Reversa de asiento';
      case TipoEventoAuditoria.cierreVigencia:
        return 'Cierre de vigencia';
      case TipoEventoAuditoria.liquidacionNomina:
        return 'Liquidación de nómina';
      case TipoEventoAuditoria.pagoNomina:
        return 'Pago de nómina';
      case TipoEventoAuditoria.reliquidacion:
        return 'Reliquidación';
      case TipoEventoAuditoria.liquidacionTributo:
        return 'Liquidación de tributo';
      case TipoEventoAuditoria.recaudoTributo:
        return 'Recaudo de tributo';
      case TipoEventoAuditoria.inicioCobroCoactivo:
        return 'Inicio de cobro coactivo';
      case TipoEventoAuditoria.inicioProceso:
        return 'Inicio de proceso contractual';
      case TipoEventoAuditoria.adjudicacion:
        return 'Adjudicación';
      case TipoEventoAuditoria.firmaContrato:
        return 'Firma de contrato';
      case TipoEventoAuditoria.liquidacionContrato:
        return 'Liquidación de contrato';
      case TipoEventoAuditoria.creacionRegistro:
        return 'Creación de registro';
      case TipoEventoAuditoria.modificacionRegistro:
        return 'Modificación de registro';
      case TipoEventoAuditoria.intentoEliminacion:
        return 'INTENTO DE ELIMINACIÓN - BLOQUEADO';
    }
  }

  /// La retención de auditoría no se fija por tipo de evento en el código.
  /// La entidad la parametriza de acuerdo con sus instrumentos archivísticos
  /// y actos institucionales vigentes.

}
