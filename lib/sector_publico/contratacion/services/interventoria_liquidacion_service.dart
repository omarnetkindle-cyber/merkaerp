/// Servicio de Interventoría/Supervisión y Liquidación de Contratos
/// Ley 80 de 1993 + Ley 1150 de 2007
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoInforme { inicial, mensual, finalInforme, especial }

enum TipoAlerta {
  retrasoEjecucion,
  incumplimientoEspecificaciones,
  problemasCalidad,
  retrasoPago,
  otro,
}

class InterventoriaLiquidacionService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  InterventoriaLiquidacionService({
    required this.db,
    required this.auditoriaService,
  });

  /// Registra un informe de supervisor/interventor
  Future<Map<String, dynamic>> registrarInformeSupervision({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required TipoInforme tipoInforme,
    required DateTime fechaInforme,
    required String contenido,
    required String elaboradoPor,
    double porcentajeEjecucion = 0,
    List<String>? observaciones,
    List<Map<String, dynamic>>? hallazgos,
  }) async {
    final id = _uuid.v4();

    // Verificar que el contrato existe
    final contrato = await db.query(
      'contratos',
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    if (contrato.isEmpty) {
      throw Exception('Contrato no encontrado');
    }

    await db.insert('informes_supervision', {
      'id': id,
      'entidad_id': entidadId,
      'contrato_id': contratoId,
      'numero_contrato': contrato.first['numero_contrato'],
      'tipo_informe': tipoInforme.toString().split('.').last,
      'fecha_informe': fechaInforme.toIso8601String(),
      'contenido': contenido,
      'elaborado_por': elaboradoPor,
      'porcentaje_ejecucion': porcentajeEjecucion,
      'observaciones': observaciones?.join('\n'),
      'hallazgos': hallazgos?.toString(),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'aprobado',
    });

    // Actualizar porcentaje de ejecución del contrato
    await db.update(
      'contratos',
      {'porcentaje_ejecucion': porcentajeEjecucion},
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'contratacion',
      accion: 'registro_informe_supervision',
      valorAnterior: {},
      valorNuevo: {
        'informe_id': id,
        'contrato_id': contratoId,
        'tipo_informe': tipoInforme.toString(),
        'porcentaje_ejecucion': porcentajeEjecucion,
      },
      referenciaId: id,
    );

    return {
      'informe_id': id,
      'contrato_id': contratoId,
      'tipo_informe': tipoInforme.toString(),
      'porcentaje_ejecucion': porcentajeEjecucion,
      'estado': 'aprobado',
    };
  }

  /// Registra una alerta de incumplimiento
  Future<Map<String, dynamic>> registrarAlertaIncumplimiento({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required TipoAlerta tipoAlerta,
    required String descripcion,
    required DateTime fechaDeteccion,
    required String detectadoPor,
    String? medidaCorrectiva,
    DateTime? fechaPlazoCorreccion,
    String? estado, // pendiente, en_correccion, resuelto, no_resuelto
  }) async {
    final id = _uuid.v4();

    await db.insert('alertas_incumplimiento', {
      'id': id,
      'entidad_id': entidadId,
      'contrato_id': contratoId,
      'tipo_alerta': tipoAlerta.toString().split('.').last,
      'descripcion': descripcion,
      'fecha_deteccion': fechaDeteccion.toIso8601String(),
      'detectado_por': detectadoPor,
      'medida_correctiva': medidaCorrectiva,
      'fecha_plazo_correccion': fechaPlazoCorreccion?.toIso8601String(),
      'estado': estado ?? 'pendiente',
      'fecha_registro': DateTime.now().toIso8601String(),
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'contratacion',
      accion: 'registro_alerta_incumplimiento',
      valorAnterior: {},
      valorNuevo: {
        'alerta_id': id,
        'contrato_id': contratoId,
        'tipo_alerta': tipoAlerta.toString(),
        'descripcion': descripcion,
      },
      referenciaId: id,
    );

    return {
      'alerta_id': id,
      'contrato_id': contratoId,
      'tipo_alerta': tipoAlerta.toString(),
      'estado': estado ?? 'pendiente',
    };
  }

  /// Genera acta de liquidación de contrato
  Future<Map<String, dynamic>> generarActaLiquidacion({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required DateTime fechaLiquidacion,
    required String elaboradoPor,
    required String revisadoPor,
    required MoneyValue valorContrato,
    required MoneyValue valorEjecutado,
    required MoneyValue saldoFavorContratista,
    required MoneyValue saldoFavorEntidad,
    required List<String> observaciones,
    required List<Map<String, dynamic>> saldosCuentas,
  }) async {
    final id = _uuid.v4();

    // Verificar que el contrato existe y está en estado apropiado
    final contrato = await db.query(
      'contratos',
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    if (contrato.isEmpty) {
      throw Exception('Contrato no encontrado');
    }

    final estadoContrato = contrato.first['estado'];
    if (estadoContrato != 'ejecucion' && estadoContrato != 'terminado') {
      throw Exception(
        'El contrato debe estar en ejecución o terminado para liquidar',
      );
    }

    // Verificar cuadre de saldos
    final cuadreSaldos =
        valorEjecutado - (saldoFavorContratista - saldoFavorEntidad);
    if ((cuadreSaldos - valorContrato).minorUnits.abs() > 100000) {
      // Tolerancia de $1,000 = 100,000 centavos.
      throw Exception('Los saldos no cuadran con el valor del contrato');
    }

    await db.insert('actas_liquidacion', {
      'id': id,
      'entidad_id': entidadId,
      'contrato_id': contratoId,
      'numero_contrato': contrato.first['numero_contrato'],
      'fecha_liquidacion': fechaLiquidacion.toIso8601String(),
      'elaborado_por': elaboradoPor,
      'revisado_por': revisadoPor,
      'valor_contrato': valorContrato.toSql(),
      'valor_ejecutado': valorEjecutado.toSql(),
      'saldo_favor_contratista': saldoFavorContratista.toSql(),
      'saldo_favor_entidad': saldoFavorEntidad.toSql(),
      'observaciones': observaciones.join('\n'),
      'saldos_cuentas': saldosCuentas.toString(),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'aprobado',
    });

    // Actualizar estado del contrato a liquidado
    await db.update(
      'contratos',
      {
        'estado': 'liquidado',
        'fecha_liquidacion': fechaLiquidacion.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'contratacion',
      accion: 'liquidacion_contrato',
      valorAnterior: {
        'estado_anterior': estadoContrato,
        'fecha_liquidacion_anterior': contrato.first['fecha_liquidacion'],
      },
      valorNuevo: {
        'estado_nuevo': 'liquidado',
        'fecha_liquidacion_nueva': fechaLiquidacion.toIso8601String(),
        'acta_liquidacion_id': id,
      },
      referenciaId: contratoId,
    );

    return {
      'acta_id': id,
      'contrato_id': contratoId,
      'fecha_liquidacion': fechaLiquidacion.toIso8601String(),
      'valor_ejecutado': publicMoneyForDisplay(valorEjecutado),
      'saldo_favor_contratista': publicMoneyForDisplay(saldoFavorContratista),
      'saldo_favor_entidad': publicMoneyForDisplay(saldoFavorEntidad),
      'estado': 'aprobado',
    };
  }

  /// Cierra el expediente contractual
  Future<Map<String, dynamic>> cerrarExpedienteContractual({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required String motivoCierre,
    required String responsableCierre,
    required DateTime fechaCierre,
    List<String>? documentosRequeridos,
    List<String>? documentosPendientes,
  }) async {
    // Verificar que el contrato está liquidado
    final contrato = await db.query(
      'contratos',
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    if (contrato.isEmpty) {
      throw Exception('Contrato no encontrado');
    }

    final estadoContrato = contrato.first['estado'];
    if (estadoContrato != 'liquidado') {
      throw Exception(
        'El contrato debe estar liquidado para cerrar el expediente',
      );
    }

    await db.update(
      'contratos',
      {
        'estado': 'expediente_cerrado',
        'fecha_cierre_expediente': fechaCierre.toIso8601String(),
        'motivo_cierre': motivoCierre,
        'responsable_cierre': responsableCierre,
        'documentos_requeridos': documentosRequeridos?.join(','),
        'documentos_pendientes': documentosPendientes?.join(','),
      },
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'contratacion',
      accion: 'cierre_expediente_contractual',
      valorAnterior: {'estado_anterior': estadoContrato},
      valorNuevo: {
        'estado_nuevo': 'expediente_cerrado',
        'fecha_cierre': fechaCierre.toIso8601String(),
        'motivo_cierre': motivoCierre,
      },
      referenciaId: contratoId,
    );

    return {
      'contrato_id': contratoId,
      'estado': 'expediente_cerrado',
      'fecha_cierre': fechaCierre.toIso8601String(),
    };
  }

  /// Consulta informes de supervisión de un contrato
  Future<List<Map<String, dynamic>>> consultarInformesSupervision({
    required String contratoId,
    TipoInforme? tipoInforme,
  }) async {
    String query = 'SELECT * FROM informes_supervision WHERE contrato_id = ?';
    List<dynamic> args = [contratoId];

    if (tipoInforme != null) {
      query += ' AND tipo_informe = ?';
      args.add(tipoInforme.toString().split('.').last);
    }

    query += ' ORDER BY fecha_informe DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta alertas de incumplimiento de un contrato
  Future<List<Map<String, dynamic>>> consultarAlertasIncumplimiento({
    required String contratoId,
    TipoAlerta? tipoAlerta,
    String? estado,
  }) async {
    String query = 'SELECT * FROM alertas_incumplimiento WHERE contrato_id = ?';
    List<dynamic> args = [contratoId];

    if (tipoAlerta != null) {
      query += ' AND tipo_alerta = ?';
      args.add(tipoAlerta.toString().split('.').last);
    }

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado);
    }

    query += ' ORDER BY fecha_deteccion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta acta de liquidación de un contrato
  Future<Map<String, dynamic>?> consultarActaLiquidacion({
    required String contratoId,
  }) async {
    final resultado = await db.query(
      'actas_liquidacion',
      where: 'contrato_id = ?',
      whereArgs: [contratoId],
    );

    if (resultado.isEmpty) return null;
    return resultado.first;
  }

  /// Genera resumen de supervisión de un contrato
  Future<Map<String, dynamic>> generarResumenSupervision({
    required String contratoId,
  }) async {
    // Total de informes
    final informes = await db.query(
      'informes_supervision',
      where: 'contrato_id = ?',
      whereArgs: [contratoId],
    );

    // Total de alertas
    final alertas = await db.query(
      'alertas_incumplimiento',
      where: 'contrato_id = ?',
      whereArgs: [contratoId],
    );

    // Alertas por estado
    final alertasPendientes = alertas
        .where((a) => a['estado'] == 'pendiente')
        .length;
    final alertasResueltas = alertas
        .where((a) => a['estado'] == 'resuelto')
        .length;

    // Porcentaje de ejecución actual
    final contrato = await db.query(
      'contratos',
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    final porcentajeEjecucion = contrato.isNotEmpty
        ? (contrato.first['porcentaje_ejecucion'] as num?)?.toDouble() ?? 0
        : 0;

    return {
      'contrato_id': contratoId,
      'total_informes': informes.length,
      'total_alertas': alertas.length,
      'alertas_pendientes': alertasPendientes,
      'alertas_resueltas': alertasResueltas,
      'porcentaje_ejecucion': porcentajeEjecucion,
      'estado_contrato': contrato.isNotEmpty
          ? contrato.first['estado']
          : 'no_encontrado',
    };
  }
}
