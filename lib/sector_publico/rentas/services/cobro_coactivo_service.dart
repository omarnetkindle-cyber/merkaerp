/// Servicio de Cobro Coactivo
/// Las 6 etapas del cobro coactivo con sus plazos legales
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/proceso_cobro_coactivo.dart';
import '../models/liquidacion_predial.dart';
import 'intereses_moratorios_service.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class CobroCoactivoService {
  final Database db;
  final InteresesMoratoriosService interesesService;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  CobroCoactivoService({
    required this.db,
    required this.interesesService,
    required this.auditoriaService,
  });

  /// Inicia proceso de cobro coactivo
  Future<ProcesoCobroCoactivo> iniciarCobroCoactivo({
    required String entidadId,
    required String usuarioId,
    required String liquidacionId,
    required String numeroResolucion,
  }) async {
    // Obtener la liquidación
    final liquidacionResult = await db.query(
      'liquidaciones_prediales',
      where: 'id = ?',
      whereArgs: [liquidacionId],
    );

    if (liquidacionResult.isEmpty) {
      throw Exception('Liquidación no encontrada');
    }

    final liquidacionData = liquidacionResult.first;
    final liquidacion = LiquidacionPredial.fromJson(liquidacionData);

    if (liquidacion.estado != EstadoLiquidacion.vencida) {
      throw Exception(
        'Solo se puede iniciar cobro coactivo para liquidaciones vencidas',
      );
    }

    // Calcular intereses de mora
    final diasMora = liquidacion.calcularDiasMora();
    final interesesMora = interesesService.calcularInteresesMora(
      capital: liquidacion.totalPagar,
      diasMora: diasMora,
    );

    final valorDeuda = liquidacion.totalPagar + interesesMora;

    final id = _uuid.v4();
    final numeroProceso =
        'CC-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaInicio = DateTime.now();

    final proceso = ProcesoCobroCoactivo(
      id: id,
      entidadId: entidadId,
      numeroProceso: numeroProceso,
      liquidacionId: liquidacionId,
      numeroLiquidacion: liquidacion.numeroLiquidacion,
      deudorId: liquidacion.contribuyenteId,
      deudorNombre: liquidacion.contribuyenteNombre,
      valorDeuda: valorDeuda,
      valorRecuperado: publicMoneyZero(),
      saldoPendiente: valorDeuda,
      etapaActual: EtapaCobroCoactivo.mandamientoPago,
      estado: EstadoProceso.iniciado,
      fechaInicio: fechaInicio,
      numeroResolucion: numeroResolucion,
    );

    await db.insert('procesos_cobro_coactivo', proceso.toJson());

    // Actualizar estado de liquidación
    await db.update(
      'liquidaciones_prediales',
      {
        'estado': EstadoLiquidacion.enCobroCoactivo.toString().split('.').last,
        'intereses_mora': interesesMora.toSql(),
        'total_pagar': valorDeuda.toSql(),
      },
      where: 'id = ?',
      whereArgs: [liquidacionId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.inicioCobroCoactivo,
      modulo: 'rentas',
      accion: 'inicio_cobro_coactivo',
      valorAnterior: {'liquidacion_id': liquidacionId},
      valorNuevo: {
        'proceso_id': id,
        'numero_proceso': numeroProceso,
        'valor_deuda': valorDeuda.toSql(),
        'resolucion': numeroResolucion,
      },
      referenciaId: id,
    );

    return proceso;
  }

  /// Avanza a la siguiente etapa del cobro coactivo
  Future<ProcesoCobroCoactivo> avanzarEtapa({
    required String entidadId,
    required String usuarioId,
    required String procesoId,
    required EtapaCobroCoactivo nuevaEtapa,
    String? numeroResolucion,
  }) async {
    final procesoResult = await db.query(
      'procesos_cobro_coactivo',
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    if (procesoResult.isEmpty) {
      throw Exception('Proceso no encontrado');
    }

    final procesoData = procesoResult.first;
    final proceso = ProcesoCobroCoactivo.fromJson(procesoData);

    if (!proceso.puedeAvanzarA(nuevaEtapa)) {
      throw Exception(
        'Transicion de cobro coactivo no permitida: ${proceso.etapaActual.name} a ${nuevaEtapa.name}',
      );
    }

    if (proceso.estado == EstadoProceso.terminado ||
        proceso.estado == EstadoProceso.prescrito) {
      throw Exception('El proceso ya está terminado o prescrito');
    }

    // Actualizar fechas según la etapa
    Map<String, dynamic> actualizaciones = {
      'etapa_actual': nuevaEtapa.toString().split('.').last,
    };

    switch (nuevaEtapa) {
      case EtapaCobroCoactivo.mandamientoPago:
        actualizaciones['fecha_mandamiento_pago'] = DateTime.now()
            .toIso8601String();
        break;
      case EtapaCobroCoactivo.embargoSecuestro:
        actualizaciones['fecha_embargo'] = DateTime.now().toIso8601String();
        break;
      case EtapaCobroCoactivo.remate:
        actualizaciones['fecha_remate'] = DateTime.now().toIso8601String();
        break;
      case EtapaCobroCoactivo.archivo:
        actualizaciones['fecha_terminacion'] = DateTime.now().toIso8601String();
        actualizaciones['estado'] = EstadoProceso.terminado
            .toString()
            .split('.')
            .last;
        break;
      case EtapaCobroCoactivo.prescripcion:
        actualizaciones['fecha_terminacion'] = DateTime.now().toIso8601String();
        actualizaciones['estado'] = EstadoProceso.prescrito
            .toString()
            .split('.')
            .last;
        break;
      case EtapaCobroCoactivo.devolucion:
        actualizaciones['fecha_terminacion'] = DateTime.now().toIso8601String();
        break;
    }

    if (numeroResolucion != null) {
      actualizaciones['numero_resolucion'] = numeroResolucion;
    }

    await db.update(
      'procesos_cobro_coactivo',
      actualizaciones,
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'rentas',
      accion: 'avance_etapa_cobro_coactivo',
      valorAnterior: {'etapa_anterior': proceso.etapaActual.toString()},
      valorNuevo: {
        'etapa_nueva': nuevaEtapa.toString(),
        'resolucion': numeroResolucion,
      },
      referenciaId: procesoId,
    );

    return proceso.copyWith(
      etapaActual: nuevaEtapa,
      numeroResolucion: numeroResolucion ?? proceso.numeroResolucion,
    );
  }

  /// Registra un pago en el proceso de cobro coactivo
  Future<ProcesoCobroCoactivo> registrarPago({
    required String entidadId,
    required String usuarioId,
    required String procesoId,
    required MoneyValue montoPago,
  }) async {
    final procesoResult = await db.query(
      'procesos_cobro_coactivo',
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    if (procesoResult.isEmpty) {
      throw Exception('Proceso no encontrado');
    }

    final procesoData = procesoResult.first;
    final proceso = ProcesoCobroCoactivo.fromJson(procesoData);

    if (montoPago > proceso.saldoPendiente) {
      throw Exception('El pago excede el saldo pendiente');
    }

    final nuevoValorRecuperado = proceso.valorRecuperado + montoPago;
    final nuevoSaldoPendiente = proceso.saldoPendiente - montoPago;

    EstadoProceso nuevoEstado = proceso.estado;
    if (nuevoSaldoPendiente == publicMoneyZero()) {
      nuevoEstado = EstadoProceso.terminado;
    }

    await db.update(
      'procesos_cobro_coactivo',
      {
        'valor_recuperado': nuevoValorRecuperado.toSql(),
        'saldo_pendiente': nuevoSaldoPendiente.toSql(),
        'estado': nuevoEstado.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.pago,
      modulo: 'rentas',
      accion: 'pago_cobro_coactivo',
      valorAnterior: {
        'valor_recuperado_anterior': proceso.valorRecuperado.toSql(),
        'saldo_anterior': proceso.saldoPendiente.toSql(),
      },
      valorNuevo: {
        'monto_pago': montoPago.toSql(),
        'valor_recuperado_nuevo': nuevoValorRecuperado.toSql(),
        'saldo_nuevo': nuevoSaldoPendiente.toSql(),
      },
      referenciaId: procesoId,
    );

    return proceso.copyWith(
      valorRecuperado: nuevoValorRecuperado,
      saldoPendiente: nuevoSaldoPendiente,
      estado: nuevoEstado,
    );
  }

  /// Consulta procesos por entidad
  Future<List<ProcesoCobroCoactivo>> consultarProcesos({
    required String entidadId,
    EstadoProceso? estado,
    EtapaCobroCoactivo? etapa,
  }) async {
    String query = 'SELECT * FROM procesos_cobro_coactivo WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    if (etapa != null) {
      query += ' AND etapa_actual = ?';
      args.add(etapa.toString().split('.').last);
    }

    query += ' ORDER BY fecha_inicio DESC';

    final resultados = await db.rawQuery(query, args);

    return resultados.map((r) => ProcesoCobroCoactivo.fromJson(r)).toList();
  }

  /// Obtiene un proceso por ID
  Future<ProcesoCobroCoactivo?> obtenerProceso(String id) async {
    final resultado = await db.query(
      'procesos_cobro_coactivo',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return ProcesoCobroCoactivo.fromJson(resultado.first);
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
