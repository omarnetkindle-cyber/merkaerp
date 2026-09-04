/// Servicio de Job de Depreciación Automática
/// Ejecuta periódicamente (mensual) el cálculo de depreciación de activos
/// Genera asiento contable correspondiente sin intervención manual
/// NICSP 17 - Propiedades, Planta y Equipo
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class DepreciacionJobService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  DepreciacionJobService({required this.db, required this.auditoriaService});

  /// Ejecuta el job de depreciación mensual
  Future<Map<String, dynamic>> ejecutarDepreciacionMensual({
    required String entidadId,
    required String usuarioId,
    required String periodo, // Formato: '2024-06'
  }) async {
    // 1. Consultar activos activos
    final activos = await db.query(
      'activos_estado',
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, 'activo'],
    );

    if (activos.isEmpty) {
      return {
        'periodo': periodo,
        'total_activos': 0,
        'total_depreciacion': publicMoneyZero().toSql(),
        'asiento_id': null,
        'mensaje': 'No hay activos activos para depreciar',
      };
    }

    // 2. Consultar configuración de depreciación
    final configuraciones = await db.query(
      'configuracion_depreciacion',
      where: 'entidad_id = ? AND activo = 1',
      whereArgs: [entidadId],
    );

    final configMap = <String, Map<String, dynamic>>{};
    for (final config in configuraciones) {
      configMap[config['tipo_activo'] as String] = {
        'vida_util_anios': config['vida_util_anios'],
        'metodo_depreciacion': config['metodo_depreciacion'],
        'porcentaje_depreciacion': config['porcentaje_depreciacion'],
      };
    }

    // 3. Calcular depreciación por activo
    final detallesDepreciacion = <Map<String, dynamic>>[];
    var totalDepreciacion = publicMoneyZero();

    for (final activo in activos) {
      final tipoActivo = activo['tipo_activo'];
      final config = configMap[tipoActivo];

      if (config == null) continue;

      final valorAdquisicion = publicMoneyFromSql(activo['valor_adquisicion']);
      final valorResidual = publicMoneyFromSql(activo['valor_residual']);
      final vidaUtilAnios = config['vida_util_anios'] as int;
      final metodo = config['metodo_depreciacion'] as String;

      final depreciacionMensual = _calcularDepreciacionMensual(
        valorAdquisicion: valorAdquisicion,
        valorResidual: valorResidual,
        vidaUtilAnios: vidaUtilAnios,
        metodo: metodo,
      );

      if (depreciacionMensual > publicMoneyZero()) {
        detallesDepreciacion.add({
          'activo_id': activo['id'],
          'numero_inventario': activo['numero_inventario'],
          'tipo_activo': tipoActivo,
          'valor_adquisicion': valorAdquisicion.toSql(),
          'depreciacion_mensual': depreciacionMensual,
        });

        totalDepreciacion += depreciacionMensual;

        // Actualizar depreciación acumulada del activo
        final depreciacionAcumuladaActual = publicMoneyFromSql(
          activo['depreciacion_acumulada'],
        );
        await db.update(
          'activos_estado',
          {
            'depreciacion_acumulada':
                (depreciacionAcumuladaActual + depreciacionMensual).toSql(),
            'valor_neto':
                (valorAdquisicion -
                        (depreciacionAcumuladaActual + depreciacionMensual))
                    .toSql(),
          },
          where: 'id = ?',
          whereArgs: [activo['id']],
        );
      }
    }

    if (detallesDepreciacion.isEmpty) {
      return {
        'periodo': periodo,
        'total_activos': activos.length,
        'total_depreciacion': publicMoneyZero().toSql(),
        'asiento_id': null,
        'mensaje': 'No se generó depreciación para ningún activo',
      };
    }

    // 4. Generar asiento contable automático
    final asientoId = await _generarAsientoDepreciacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      periodo: periodo,
      totalDepreciacion: totalDepreciacion,
      detallesDepreciacion: detallesDepreciacion,
    );

    // 5. Registrar evento en auditoría
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'contabilidad',
      accion: 'job_depreciacion_mensual',
      valorAnterior: {},
      valorNuevo: {
        'periodo': periodo,
        'total_activos': activos.length,
        'total_depreciacion': totalDepreciacion.toSql(),
        'asiento_id': asientoId,
      },
    );

    return {
      'periodo': periodo,
      'total_activos': activos.length,
      'total_depreciacion': totalDepreciacion.toSql(),
      'asiento_id': asientoId,
      'detalles': detallesDepreciacion,
      'mensaje': 'Depreciación mensual ejecutada exitosamente',
    };
  }

  /// Calcula la depreciación mensual según el método
  MoneyValue _calcularDepreciacionMensual({
    required MoneyValue valorAdquisicion,
    required MoneyValue valorResidual,
    required int vidaUtilAnios,
    required String metodo,
  }) {
    final valorDepreciable = valorAdquisicion - valorResidual;

    switch (metodo) {
      case 'linea_recta':
        // Método de línea recta: (Valor depreciable / Vida útil) / 12
        return valorDepreciable / (vidaUtilAnios * 12);
      default:
        return valorDepreciable / (vidaUtilAnios * 12);
    }
  }

  /// Genera el asiento contable de depreciación
  Future<String> _generarAsientoDepreciacion({
    required String entidadId,
    required String usuarioId,
    required String periodo,
    required MoneyValue totalDepreciacion,
    required List<Map<String, dynamic>> detallesDepreciacion,
  }) async {
    final asientoId = _uuid.v4();
    final numeroAsiento = await _generarNumeroAsiento(entidadId);
    final fechaAsiento = DateTime.parse('$periodo-01');

    // Cuentas contables según NICSP 17
    // Débito: Gasto por depreciación (cuenta de resultado)
    // Crédito: Depreciación acumulada (cuenta de activo)
    final cuentaGastoDepreciacion = '620101'; // Gasto por depreciación
    final cuentaDepreciacionAcumulada = '160401'; // Depreciación acumulada

    // Crear asiento contable
    await db.insert('asientos_contables_sp', {
      'id': asientoId,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': 'Depreciación mensual de activos fijos - $periodo',
      'tipo_asiento': 'automatico',
      'estado': 'borrador',
      'total_debito': totalDepreciacion.toSql(),
      'total_credito': totalDepreciacion.toSql(),
      'usuario_creo': usuarioId,
      'usuario_reviso': usuarioId,
      'fecha_revision': DateTime.now().toIso8601String(),
      'referencia_origen': 'job_depreciacion',
      'tipo_documento_origen': 'job',
      'observaciones':
          'Asiento generado automáticamente por job de depreciación',
    });

    // Crear detalle de débito (gasto)
    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaGastoDepreciacion,
      'cuenta_nombre': 'Gasto por depreciación de propiedades, planta y equipo',
      'debito': totalDepreciacion.toSql(),
      'credito': publicMoneyZero().toSql(),
      'referencia_id': asientoId,
    });

    // Crear detalle de crédito (depreciación acumulada)
    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaDepreciacionAcumulada,
      'cuenta_nombre': 'Depreciación acumulada - Propiedades, planta y equipo',
      'debito': publicMoneyZero().toSql(),
      'credito': totalDepreciacion.toSql(),
      'referencia_id': asientoId,
    });

    await db.update(
      'asientos_contables_sp',
      {'estado': 'aprobado'},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    // Actualizar saldos de cuentas
    await _actualizarSaldosCuentas(
      entidadId: entidadId,
      periodo: periodo,
      cuentaCodigo: cuentaGastoDepreciacion,
      cuentaNombre: 'Gasto por depreciación de propiedades, planta y equipo',
      debito: totalDepreciacion,
      credito: publicMoneyZero(),
    );

    await _actualizarSaldosCuentas(
      entidadId: entidadId,
      periodo: periodo,
      cuentaCodigo: cuentaDepreciacionAcumulada,
      cuentaNombre: 'Depreciación acumulada - Propiedades, planta y equipo',
      debito: publicMoneyZero(),
      credito: totalDepreciacion,
    );

    return asientoId;
  }

  /// Genera el número de asiento siguiente
  Future<String> _generarNumeroAsiento(String entidadId) async {
    final resultado = await db.rawQuery(
      "SELECT MAX(numero_asiento) as max_numero FROM asientos_contables_sp WHERE entidad_id = ?",
      [entidadId],
    );

    final maxNumero = resultado.first['max_numero'];
    if (maxNumero == null) return 'AS-0001';

    final numeroActual = int.parse(maxNumero.toString().split('-')[1]);
    return 'AS-${(numeroActual + 1).toString().padLeft(4, '0')}';
  }

  /// Actualiza los saldos de las cuentas contables
  Future<void> _actualizarSaldosCuentas({
    required String entidadId,
    required String periodo,
    required String cuentaCodigo,
    required String cuentaNombre,
    required MoneyValue debito,
    required MoneyValue credito,
  }) async {
    final saldoExistente = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
      whereArgs: [entidadId, cuentaCodigo, periodo],
    );

    if (saldoExistente.isEmpty) {
      await db.insert('saldos_cuentas', {
        'id': _uuid.v4(),
        'entidad_id': entidadId,
        'cuenta_codigo': cuentaCodigo,
        'cuenta_nombre': cuentaNombre,
        'saldo_deudor': debito.toSql(),
        'saldo_acreedor': credito.toSql(),
        'saldo_neto': (debito - credito).toSql(),
        'fecha_ultimo_movimiento': DateTime.now().toIso8601String(),
        'vigencia': periodo,
      });
    } else {
      final saldoActual = saldoExistente.first;
      final nuevoSaldoDeudor =
          publicMoneyFromSql(saldoActual['saldo_deudor']) + debito;
      final nuevoSaldoAcreedor =
          publicMoneyFromSql(saldoActual['saldo_acreedor']) + credito;

      await db.update(
        'saldos_cuentas',
        {
          'saldo_deudor': nuevoSaldoDeudor.toSql(),
          'saldo_acreedor': nuevoSaldoAcreedor.toSql(),
          'saldo_neto': (nuevoSaldoDeudor - nuevoSaldoAcreedor).toSql(),
          'fecha_ultimo_movimiento': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [saldoActual['id']],
      );
    }
  }

  /// Verifica si el job ya se ejecutó para el periodo
  Future<bool> jobEjecutadoParaPeriodo({
    required String entidadId,
    required String periodo,
  }) async {
    final resultado = await db.query(
      'asientos_contables_sp',
      where:
          'entidad_id = ? AND tipo_documento_origen = ? AND referencia_origen = ? AND fecha_asiento LIKE ?',
      whereArgs: [entidadId, 'job', 'job_depreciacion', '$periodo%'],
    );

    return resultado.isNotEmpty;
  }
}
