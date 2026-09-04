/// Modelo de Proceso de Cobro Coactivo
/// Las 6 etapas del cobro coactivo con sus plazos legales
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum EtapaCobroCoactivo {
  mandamientoPago, // Etapa 1: Mandamiento de pago
  embargoSecuestro, // Etapa 2: Embargo y secuestro
  remate, // Etapa 3: Remate de bienes
  devolucion, // Etapa 4: Devolución
  archivo, // Etapa 5: Archivo del expediente
  prescripcion, // Etapa 6: Prescripción (si aplica)
}

enum EstadoProceso { iniciado, enTramite, suspendido, terminado, prescrito }

class ProcesoCobroCoactivo {
  final String id;
  final String entidadId;
  final String numeroProceso; // Formato: CC-YYYY-NNNNNN
  final String liquidacionId;
  final String numeroLiquidacion;
  final String deudorId;
  final String deudorNombre;
  final MoneyValue valorDeuda;
  final MoneyValue valorRecuperado;
  final MoneyValue saldoPendiente;
  final EtapaCobroCoactivo etapaActual;
  final EstadoProceso estado;
  final DateTime fechaInicio;
  final DateTime? fechaMandamientoPago;
  final DateTime? fechaEmbargo;
  final DateTime? fechaRemate;
  final DateTime? fechaTerminacion;
  final String? numeroResolucion;
  final String? observaciones;

  ProcesoCobroCoactivo({
    required this.id,
    required this.entidadId,
    required this.numeroProceso,
    required this.liquidacionId,
    required this.numeroLiquidacion,
    required this.deudorId,
    required this.deudorNombre,
    required this.valorDeuda,
    required this.valorRecuperado,
    required this.saldoPendiente,
    required this.etapaActual,
    required this.estado,
    required this.fechaInicio,
    this.fechaMandamientoPago,
    this.fechaEmbargo,
    this.fechaRemate,
    this.fechaTerminacion,
    this.numeroResolucion,
    this.observaciones,
  });

  factory ProcesoCobroCoactivo.fromJson(Map<String, dynamic> json) {
    return ProcesoCobroCoactivo(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroProceso: json['numero_proceso'] as String,
      liquidacionId: json['liquidacion_id'] as String,
      numeroLiquidacion: json['numero_liquidacion'] as String,
      deudorId: json['deudor_id'] as String,
      deudorNombre: json['deudor_nombre'] as String,
      valorDeuda: publicMoneyFromSql(json['valor_deuda']),
      valorRecuperado: publicMoneyFromSql(json['valor_recuperado']),
      saldoPendiente: publicMoneyFromSql(json['saldo_pendiente']),
      etapaActual: EtapaCobroCoactivo.values.firstWhere(
        (e) => e.toString() == 'EtapaCobroCoactivo.${json['etapa_actual']}',
      ),
      estado: EstadoProceso.values.firstWhere(
        (e) => e.toString() == 'EstadoProceso.${json['estado']}',
      ),
      fechaInicio: DateTime.parse(json['fecha_inicio'] as String),
      fechaMandamientoPago: json['fecha_mandamiento_pago'] != null
          ? DateTime.parse(json['fecha_mandamiento_pago'] as String)
          : null,
      fechaEmbargo: json['fecha_embargo'] != null
          ? DateTime.parse(json['fecha_embargo'] as String)
          : null,
      fechaRemate: json['fecha_remate'] != null
          ? DateTime.parse(json['fecha_remate'] as String)
          : null,
      fechaTerminacion: json['fecha_terminacion'] != null
          ? DateTime.parse(json['fecha_terminacion'] as String)
          : null,
      numeroResolucion: json['numero_resolucion'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_proceso': numeroProceso,
      'liquidacion_id': liquidacionId,
      'numero_liquidacion': numeroLiquidacion,
      'deudor_id': deudorId,
      'deudor_nombre': deudorNombre,
      'valor_deuda': valorDeuda.toSql(),
      'valor_recuperado': valorRecuperado.toSql(),
      'saldo_pendiente': saldoPendiente.toSql(),
      'etapa_actual': etapaActual.toString().split('.').last,
      'estado': estado.toString().split('.').last,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_mandamiento_pago': fechaMandamientoPago?.toIso8601String(),
      'fecha_embargo': fechaEmbargo?.toIso8601String(),
      'fecha_remate': fechaRemate?.toIso8601String(),
      'fecha_terminacion': fechaTerminacion?.toIso8601String(),
      'numero_resolucion': numeroResolucion,
      'observaciones': observaciones,
    };
  }

  /// Avanza a la siguiente etapa del cobro coactivo
  ProcesoCobroCoactivo avanzarEtapa(EtapaCobroCoactivo nuevaEtapa) {
    if (!puedeAvanzarA(nuevaEtapa)) {
      throw StateError(
        'Transicion no permitida de ${etapaActual.name} a ${nuevaEtapa.name}',
      );
    }
    return copyWith(etapaActual: nuevaEtapa);
  }

  /// El cierre por prescripcion es excepcional; la ruta ordinaria no admite saltos.
  bool puedeAvanzarA(EtapaCobroCoactivo nuevaEtapa) {
    if (nuevaEtapa == EtapaCobroCoactivo.prescripcion) {
      return saldoPendiente > publicMoneyZero();
    }
    return switch (etapaActual) {
      EtapaCobroCoactivo.mandamientoPago =>
        nuevaEtapa == EtapaCobroCoactivo.embargoSecuestro,
      EtapaCobroCoactivo.embargoSecuestro =>
        nuevaEtapa == EtapaCobroCoactivo.remate,
      EtapaCobroCoactivo.remate => nuevaEtapa == EtapaCobroCoactivo.devolucion,
      EtapaCobroCoactivo.devolucion => nuevaEtapa == EtapaCobroCoactivo.archivo,
      EtapaCobroCoactivo.archivo || EtapaCobroCoactivo.prescripcion => false,
    };
  }

  /// Verifica si el proceso está prescrito (5 años)
  bool estaPrescrito() {
    final cincoAnios = DateTime.now().subtract(const Duration(days: 365 * 5));
    return fechaInicio.isBefore(cincoAnios) &&
        saldoPendiente > publicMoneyZero();
  }

  /// Obtiene descripción de la etapa actual
  String get descripcionEtapa {
    switch (etapaActual) {
      case EtapaCobroCoactivo.mandamientoPago:
        return 'Mandamiento de Pago - Notificación al deudor';
      case EtapaCobroCoactivo.embargoSecuestro:
        return 'Embargo y Secuestro - Medidas cautelares';
      case EtapaCobroCoactivo.remate:
        return 'Remate de Bienes - Venta pública';
      case EtapaCobroCoactivo.devolucion:
        return 'Devolución - Entrega de remanente';
      case EtapaCobroCoactivo.archivo:
        return 'Archivo - Cierre del expediente';
      case EtapaCobroCoactivo.prescripcion:
        return 'Prescripción - Extinción de la obligación';
    }
  }

  /// Obtiene el plazo legal para la etapa actual (en días)
  int get plazoLegalEtapa {
    switch (etapaActual) {
      case EtapaCobroCoactivo.mandamientoPago:
        return 30; // 30 días para pagar
      case EtapaCobroCoactivo.embargoSecuestro:
        return 60; // 60 días para ejecutar embargo
      case EtapaCobroCoactivo.remate:
        return 90; // 90 días para remate
      case EtapaCobroCoactivo.devolucion:
        return 30; // 30 días para devolución
      case EtapaCobroCoactivo.archivo:
        return 0; // Inmediato
      case EtapaCobroCoactivo.prescripcion:
        return 0; // No aplica
    }
  }

  ProcesoCobroCoactivo copyWith({
    String? id,
    String? entidadId,
    String? numeroProceso,
    String? liquidacionId,
    String? numeroLiquidacion,
    String? deudorId,
    String? deudorNombre,
    MoneyValue? valorDeuda,
    MoneyValue? valorRecuperado,
    MoneyValue? saldoPendiente,
    EtapaCobroCoactivo? etapaActual,
    EstadoProceso? estado,
    DateTime? fechaInicio,
    DateTime? fechaMandamientoPago,
    DateTime? fechaEmbargo,
    DateTime? fechaRemate,
    DateTime? fechaTerminacion,
    String? numeroResolucion,
    String? observaciones,
  }) {
    return ProcesoCobroCoactivo(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroProceso: numeroProceso ?? this.numeroProceso,
      liquidacionId: liquidacionId ?? this.liquidacionId,
      numeroLiquidacion: numeroLiquidacion ?? this.numeroLiquidacion,
      deudorId: deudorId ?? this.deudorId,
      deudorNombre: deudorNombre ?? this.deudorNombre,
      valorDeuda: valorDeuda ?? this.valorDeuda,
      valorRecuperado: valorRecuperado ?? this.valorRecuperado,
      saldoPendiente: saldoPendiente ?? this.saldoPendiente,
      etapaActual: etapaActual ?? this.etapaActual,
      estado: estado ?? this.estado,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaMandamientoPago: fechaMandamientoPago ?? this.fechaMandamientoPago,
      fechaEmbargo: fechaEmbargo ?? this.fechaEmbargo,
      fechaRemate: fechaRemate ?? this.fechaRemate,
      fechaTerminacion: fechaTerminacion ?? this.fechaTerminacion,
      numeroResolucion: numeroResolucion ?? this.numeroResolucion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
