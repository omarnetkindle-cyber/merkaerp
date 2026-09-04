/// Servicio de Cierre de Vigencia
/// Implementa cierre anual según Art. 89 EOP y NICSP
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import '../models/asiento_contable.dart';
import '../models/estado_financiero.dart';
import 'contabilidad_nicsp_service.dart';
import '../../security/auditoria_service.dart';
import '../../models/registro_auditoria.dart';

class CierreVigenciaService {
  final Database db;
  final ContabilidadNICSPService contabilidadService;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  CierreVigenciaService({
    required this.db,
    required this.contabilidadService,
    required this.auditoriaService,
  });

  /// Ejecuta el cierre de vigencia
  /// Cálculo de reservas y cuentas por pagar al 31-dic (Art. 89 EOP)
  Future<Map<String, dynamic>> ejecutarCierreVigencia({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String motivo,
  }) async {
    // Verificar que no exista un cierre previo
    final cierreExistente = await db.query(
      'cierres_vigencia',
      where: 'entidad_id = ? AND vigencia = ?',
      whereArgs: [entidadId, vigencia],
    );

    if (cierreExistente.isNotEmpty) {
      throw Exception('Ya existe un cierre de vigencia para el año $vigencia');
    }

    final fechaCierre = DateTime(int.parse(vigencia), 12, 31);
    final fechaApertura = DateTime(int.parse(vigencia) + 1, 1, 1);

    // 1. Generar asiento de cierre de cuentas de resultado
    final asientoCierre = await _generarAsientoCierreResultados(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      fechaCierre: fechaCierre,
    );

    // 2. Calcular reservas y cuentas por pagar
    final reservas = await _calcularReservas(
      entidadId: entidadId,
      vigencia: vigencia,
    );

    // 3. Generar asiento de apertura del siguiente año
    final asientoApertura = await _generarAsientoApertura(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigenciaSiguiente: (int.parse(vigencia) + 1).toString(),
      fechaApertura: fechaApertura,
    );

    // 4. Registrar el cierre
    final cierreId = _uuid.v4();
    await db.insert('cierres_vigencia', {
      'id': cierreId,
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'fecha_cierre': fechaCierre.toIso8601String(),
      'asiento_cierre_id': asientoCierre.id,
      'asiento_apertura_id': asientoApertura.id,
      'usuario_cerro': usuarioId,
      'estado': 'completado',
      'observaciones': motivo,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.cierreVigencia,
      modulo: 'contabilidad',
      accion: 'cierre_vigencia',
      valorAnterior: {'vigencia': vigencia},
      valorNuevo: {
        'cierre_id': cierreId,
        'asiento_cierre': asientoCierre.id,
        'asiento_apertura': asientoApertura.id,
        'reservas': reservas,
      },
      referenciaId: cierreId,
    );

    return {
      'cierre_id': cierreId,
      'vigencia': vigencia,
      'fecha_cierre': fechaCierre.toIso8601String(),
      'asiento_cierre_id': asientoCierre.id,
      'asiento_apertura_id': asientoApertura.id,
      'reservas': reservas,
      'estado': 'completado',
    };
  }

  /// Genera asiento de cierre de cuentas de resultado (ingresos y gastos)
  Future<AsientoContable> _generarAsientoCierreResultados({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DateTime fechaCierre,
  }) async {
    // Obtener saldos de cuentas de ingreso (Clase 4)
    final ingresos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '4%'],
    );

    // Obtener saldos de cuentas de gasto (Clase 5)
    final gastos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '5%'],
    );

    final detalles = <DetalleAsiento>[];

    // Cerrar ingresos (crédito)
    for (final ingreso in ingresos) {
      final saldoNeto = publicMoneyFromSql(ingreso['saldo_neto']);
      if (saldoNeto > publicMoneyZero()) {
        detalles.add(DetalleAsiento(
          id: _uuid.v4(),
          cuentaCodigo: ingreso['cuenta_codigo'] as String,
          cuentaNombre: ingreso['cuenta_nombre'] as String,
          debito: saldoNeto,
          credito: publicMoneyZero(),
        ));
      }
    }

    // Cerrar gastos (débito)
    for (final gasto in gastos) {
      final saldoNeto = publicMoneyFromSql(gasto['saldo_neto']);
      if (saldoNeto > publicMoneyZero()) {
        detalles.add(DetalleAsiento(
          id: _uuid.v4(),
          cuentaCodigo: gasto['cuenta_codigo'] as String,
          cuentaNombre: gasto['cuenta_nombre'] as String,
          debito: publicMoneyZero(),
          credito: saldoNeto,
        ));
      }
    }

    // Si hay resultado, llevarlo a resultado del ejercicio
    final totalIngresos = ingresos.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['saldo_neto']),
    );
    final totalGastos = gastos.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['saldo_neto']),
    );
    final resultado = totalIngresos - totalGastos;

    if (resultado != publicMoneyZero()) {
      detalles.add(DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: '3115',
        cuentaNombre: 'Resultado del ejercicio',
        debito: resultado > publicMoneyZero() ? resultado : publicMoneyZero(),
        credito: resultado < publicMoneyZero() ? resultado.abs() : publicMoneyZero(),
      ));
    }

    return await contabilidadService.crearAsientoManual(
      entidadId: entidadId,
      usuarioId: usuarioId,
      fechaAsiento: fechaCierre,
      descripcion: 'Cierre de cuentas de resultado - Vigencia $vigencia',
      detalles: detalles,
    );
  }

  /// Genera asiento de apertura del siguiente año
  Future<AsientoContable> _generarAsientoApertura({
    required String entidadId,
    required String usuarioId,
    required String vigenciaSiguiente,
    required DateTime fechaApertura,
  }) async {
    // Obtener saldos de cuentas de balance (Clases 1, 2, 3) al cierre
    final saldosBalance = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND (cuenta_codigo LIKE ? OR cuenta_codigo LIKE ? OR cuenta_codigo LIKE ?)',
      whereArgs: [entidadId, (int.parse(vigenciaSiguiente) - 1).toString(), '1%', '2%', '3%'],
    );

    final detalles = <DetalleAsiento>[];

    for (final saldo in saldosBalance) {
      final saldoNeto = publicMoneyFromSql(saldo['saldo_neto']);
      if (saldoNeto != publicMoneyZero()) {
        detalles.add(DetalleAsiento(
          id: _uuid.v4(),
          cuentaCodigo: saldo['cuenta_codigo'] as String,
          cuentaNombre: saldo['cuenta_nombre'] as String,
          debito: saldoNeto > publicMoneyZero() ? saldoNeto : publicMoneyZero(),
          credito: saldoNeto < publicMoneyZero() ? saldoNeto.abs() : publicMoneyZero(),
        ));
      }
    }

    return await contabilidadService.crearAsientoManual(
      entidadId: entidadId,
      usuarioId: usuarioId,
      fechaAsiento: fechaApertura,
      descripcion: 'Apertura de cuentas de balance - Vigencia $vigenciaSiguiente',
      detalles: detalles,
    );
  }

  /// Calcula reservas y cuentas por pagar al cierre
  Future<Map<String, dynamic>> _calcularReservas({
    required String entidadId,
    required String vigencia,
  }) async {
    // Cuentas por pagar pendientes (Clase 2)
    final cuentasPagar = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '24%'],
    );

    // Provisiones (NICSP 19)
    final provisiones = await db.query(
      'provisiones',
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, 'activa'],
    );

    final totalCuentasPagar = cuentasPagar.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['saldo_neto']),
    );
    final totalProvisiones = provisiones.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum + publicMoneyFromSql(r['valor_provision']),
    );

    return {
      'cuentas_por_pagar': totalCuentasPagar,
      'provisiones': totalProvisiones,
      'total_reservas': totalCuentasPagar + totalProvisiones,
    };
  }

  /// Genera Estado de Situación Financiera (Balance General)
  Future<EstadoSituacionFinanciera> generarEstadoSituacionFinanciera({
    required String entidadId,
    required String vigencia,
    required DateTime fechaCorte,
  }) async {
    // Activos (Clase 1)
    final activos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '1%'],
    );

    // Pasivos (Clase 2)
    final pasivos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '2%'],
    );

    // Patrimonio (Clase 3)
    final patrimonio = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '3%'],
    );

    // saldos_cuentas almacena debito - credito. El CGC semilla define las
    // clases 2, 3 y 4 como acreedoras, por lo que se invierten al presentar.
    final totalActivo = _sumarSaldos(activos);
    final totalPasivo = _sumarSaldos(pasivos, naturalezaAcreedora: true);
    final patrimonioBase = _sumarSaldos(patrimonio, naturalezaAcreedora: true);
    final resultadoPeriodo = await _calcularResultadoPeriodo(entidadId, vigencia);
    final totalPatrimonio = patrimonioBase + resultadoPeriodo;
    final renglonesPatrimonio = [
      ..._renglonesEstado(patrimonio, naturalezaAcreedora: true),
      RenglonEstado(
        codigoCuenta: 'RESULTADO-PERIODO',
        nombreCuenta: 'Resultado del periodo',
        valor: resultadoPeriodo,
        nivel: 1,
      ),
    ];

    return EstadoSituacionFinanciera(
      entidadId: entidadId,
      vigencia: vigencia,
      fechaCorte: fechaCorte,
      totalActivo: totalActivo,
      totalPasivo: totalPasivo,
      totalPatrimonio: totalPatrimonio,
      totalPasivoPatrimonio: totalPasivo + totalPatrimonio,
      activos: _renglonesEstado(activos),
      pasivos: _renglonesEstado(pasivos, naturalezaAcreedora: true),
      patrimonio: renglonesPatrimonio,
    );
  }

  /// Genera Estado de Resultado Operacional (PyG)
  Future<EstadoResultadoOperacional> generarEstadoResultado({
    required String entidadId,
    required String vigencia,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    // Ingresos (Clase 4)
    final ingresos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '4%'],
    );

    // Gastos y costos (Clases 5, 6 y 7)
    final gastos = await db.query(
      'saldos_cuentas',
      where: '''entidad_id = ? AND vigencia = ? AND
          (cuenta_codigo LIKE ? OR cuenta_codigo LIKE ? OR cuenta_codigo LIKE ?)''',
      whereArgs: [entidadId, vigencia, '5%', '6%', '7%'],
    );

    final totalIngresos = _sumarSaldos(ingresos, naturalezaAcreedora: true);
    final totalGastos = _sumarSaldos(gastos);
    final resultadoOperacional = totalIngresos - totalGastos;

    return EstadoResultadoOperacional(
      entidadId: entidadId,
      vigencia: vigencia,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      totalIngresos: totalIngresos,
      totalGastos: totalGastos,
      resultadoOperacional: resultadoOperacional,
      ingresos: _renglonesEstado(ingresos, naturalezaAcreedora: true),
      gastos: _renglonesEstado(gastos),
    );
  }

  Future<MoneyValue> _calcularResultadoPeriodo(
    String entidadId,
    String vigencia,
  ) async {
    final ingresos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ? AND cuenta_codigo LIKE ?',
      whereArgs: [entidadId, vigencia, '4%'],
    );
    final gastosYCostos = await db.query(
      'saldos_cuentas',
      where: '''entidad_id = ? AND vigencia = ? AND
          (cuenta_codigo LIKE ? OR cuenta_codigo LIKE ? OR cuenta_codigo LIKE ?)''',
      whereArgs: [entidadId, vigencia, '5%', '6%', '7%'],
    );
    return _sumarSaldos(ingresos, naturalezaAcreedora: true) -
        _sumarSaldos(gastosYCostos);
  }

  MoneyValue _sumarSaldos(
    List<Map<String, dynamic>> saldos, {
    bool naturalezaAcreedora = false,
  }) {
    return saldos.fold<MoneyValue>(publicMoneyZero(), (sum, saldo) {
      final valor = publicMoneyFromSql(saldo['saldo_neto']);
      return sum + (naturalezaAcreedora ? -valor : valor);
    });
  }

  List<RenglonEstado> _renglonesEstado(
    List<Map<String, dynamic>> saldos, {
    bool naturalezaAcreedora = false,
  }) {
    return saldos
        .map(
          (saldo) => RenglonEstado(
            codigoCuenta: saldo['cuenta_codigo'] as String,
            nombreCuenta: saldo['cuenta_nombre'] as String,
            valor: naturalezaAcreedora
                ? -publicMoneyFromSql(saldo['saldo_neto'])
                : publicMoneyFromSql(saldo['saldo_neto']),
            nivel: 1,
          ),
        )
        .toList();
  }

  /// Genera Estado de Flujos de Efectivo (NICSP 2)
  Future<EstadoFlujosEfectivo> generarEstadoFlujosEfectivo({
    required String entidadId,
    required String vigencia,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    // Actividades de operación (cuentas 1, 4, 5 relacionadas con operación)
    final actividadesOperacion = await db.query(
      'detalles_asientos d JOIN asientos_contables_sp a ON d.asiento_id = a.id',
      columns: ['d.cuenta_codigo', 'd.cuenta_nombre', 'd.debito', 'd.credito'],
      where: 'a.entidad_id = ? AND a.fecha_asiento BETWEEN ? AND ? AND d.cuenta_codigo IN (?, ?)',
      whereArgs: [
        entidadId,
        fechaInicio.toIso8601String(),
        fechaFin.toIso8601String(),
        '1110',
        '1120',
      ],
    );

    // Cálculo simplificado - en producción se requiere lógica más compleja
    final totalOperacion = actividadesOperacion.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, r) => sum +
          (publicMoneyFromSql(r['debito']) - publicMoneyFromSql(r['credito'])),
    );

    return EstadoFlujosEfectivo(
      entidadId: entidadId,
      vigencia: vigencia,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      totalActividadesOperacion: totalOperacion,
      totalActividadesInversion: publicMoneyZero(),
      totalActividadesFinanciacion: publicMoneyZero(),
      variacionNetaEfectivo: totalOperacion,
      efectivoAlInicio: publicMoneyZero(),
      efectivoAlFinal: totalOperacion,
      actividadesOperacion: [],
      actividadesInversion: [],
      actividadesFinanciacion: [],
    );
  }

  /// Verifica si una vigencia está cerrada
  Future<bool> vigenciaCerrada(String entidadId, String vigencia) async {
    final resultado = await db.query(
      'cierres_vigencia',
      where: 'entidad_id = ? AND vigencia = ? AND estado = ?',
      whereArgs: [entidadId, vigencia, 'completado'],
    );

    return resultado.isNotEmpty;
  }
}
