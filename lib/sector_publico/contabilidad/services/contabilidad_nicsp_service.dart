/// Servicio de Contabilidad NICSP
/// Implementa asientos automáticos desde el flujo presupuestal
/// Resolución 533/2015 CGN + NICSP 1, 2, 12, 17, 19
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/asiento_contable.dart';
import '../models/cuenta_contable.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';

class ContabilidadNICSPService {
  final DatabaseExecutor db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  ContabilidadNICSPService({required this.db, required this.auditoriaService});

  Future<RolSectorPublico> _validarPermisoYSegregacion({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
    RolSectorPublico? rolQuienCrea,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    if (rol == null) {
      throw Exception(
        'Acceso denegado: El usuario $usuarioId no tiene un rol asignado en la entidad $entidadId',
      );
    }

    if (!RolesPermisosService.tienePermiso(rol, permiso)) {
      throw Exception(
        'Acceso denegado: El rol ${rol.name} no tiene permiso para ${permiso.name}',
      );
    }

    if (rolQuienCrea != null) {
      final esValido = RolesPermisosService.validarSegregacionFunciones(
        rolQuienEjecuta: rol,
        rolQuienAprobo: rolQuienCrea,
        accion: permiso,
      );
      if (!esValido) {
        throw Exception(
          'Segregación de funciones violada: Un ${rol.name} no puede ejecutar la acción ${permiso.name} sobre un registro creado por ${rolQuienCrea.name}',
        );
      }
    }

    return rol;
  }

  // ==================== ASIENTOS CONTABLES ====================

  /// Crea un asiento contable manual
  Future<AsientoContable> crearAsientoManual({
    required String entidadId,
    required String usuarioId,
    required DateTime fechaAsiento,
    required String descripcion,
    required List<DetalleAsiento> detalles,
    String? observaciones,
  }) async {
    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.crearAsientoContable,
    );
    final id = _uuid.v4();
    final numeroAsiento =
        'AS-${DateTime.now().year}-${_generarNumeroSecuencial()}';

    // Calcular totales
    final totalDebito = detalles.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, d) => sum + d.debito,
    );
    final totalCredito = detalles.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, d) => sum + d.credito,
    );

    // Verificar que esté cuadrado
    if (totalDebito != totalCredito) {
      throw Exception(
        'El asiento no está cuadrado. '
        'Débito: $totalDebito, Crédito: $totalCredito',
      );
    }

    final asiento = AsientoContable(
      id: id,
      entidadId: entidadId,
      numeroAsiento: numeroAsiento,
      fechaAsiento: fechaAsiento,
      descripcion: descripcion,
      tipoAsiento: TipoAsiento.manual,
      estado: EstadoAsiento.borrador,
      detalles: detalles,
      totalDebito: totalDebito,
      totalCredito: totalCredito,
      usuarioCreo: usuarioId,
    );

    await db.insert('asientos_contables_sp', {
      'id': id,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': descripcion,
      'tipo_asiento': TipoAsiento.manual.toString().split('.').last,
      'estado': EstadoAsiento.borrador.toString().split('.').last,
      'total_debito': totalDebito.toSql(),
      'total_credito': totalCredito.toSql(),
      'usuario_creo': usuarioId,
      'observaciones': observaciones,
    });

    // Insertar detalles
    for (final detalle in detalles) {
      await db.insert('detalles_asientos', {
        'id': _uuid.v4(),
        'asiento_id': id,
        'cuenta_codigo': detalle.cuentaCodigo,
        'cuenta_nombre': detalle.cuentaNombre,
        'debito': detalle.debito.toSql(),
        'credito': detalle.credito.toSql(),
        'referencia_id': detalle.referenciaId,
      });
    }

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.asientoContable,
      modulo: 'contabilidad',
      accion: 'creacion_asiento_manual',
      valorAnterior: {},
      valorNuevo: {
        'asiento_id': id,
        'numero_asiento': numeroAsiento,
        'total_debito': totalDebito.toSql(),
        'total_credito': totalCredito.toSql(),
      },
      referenciaId: id,
    );

    return asiento;
  }

  /// Genera asiento contable automático desde el flujo presupuestal
  /// NOTA: Nota presupuestal ≠ asiento contable (no confundir)
  Future<AsientoContable> generarAsientoPresupuestal({
    required String entidadId,
    required String usuarioId,
    required DateTime fechaAsiento,
    required String tipoDocumento, // OBLIGACION, PAGO, etc.
    required String referenciaOrigen,
    required String descripcion,
    required List<DetalleAsiento> detalles,
  }) async {
    final id = _uuid.v4();
    final numeroAsiento =
        'AS-${DateTime.now().year}-${_generarNumeroSecuencial()}';

    final totalDebito = detalles.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, d) => sum + d.debito,
    );
    final totalCredito = detalles.fold<MoneyValue>(
      publicMoneyZero(),
      (sum, d) => sum + d.credito,
    );

    final asiento = AsientoContable(
      id: id,
      entidadId: entidadId,
      numeroAsiento: numeroAsiento,
      fechaAsiento: fechaAsiento,
      descripcion: descripcion,
      tipoAsiento: TipoAsiento.automaticoPresupuestal,
      estado: EstadoAsiento.registrado,
      detalles: detalles,
      totalDebito: totalDebito,
      totalCredito: totalCredito,
      usuarioCreo: usuarioId,
      referenciaOrigen: referenciaOrigen,
      tipoDocumentoOrigen: tipoDocumento,
    );

    await db.insert('asientos_contables_sp', {
      'id': id,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': descripcion,
      'tipo_asiento': TipoAsiento.automaticoPresupuestal
          .toString()
          .split('.')
          .last,
      'estado': EstadoAsiento.borrador.toString().split('.').last,
      'total_debito': totalDebito.toSql(),
      'total_credito': totalCredito.toSql(),
      'usuario_creo': usuarioId,
      'referencia_origen': referenciaOrigen,
      'tipo_documento_origen': tipoDocumento,
    });

    for (final detalle in detalles) {
      await db.insert('detalles_asientos', {
        'id': _uuid.v4(),
        'asiento_id': id,
        'cuenta_codigo': detalle.cuentaCodigo,
        'cuenta_nombre': detalle.cuentaNombre,
        'debito': detalle.debito.toSql(),
        'credito': detalle.credito.toSql(),
        'referencia_id': detalle.referenciaId,
      });
    }

    await db.update(
      'asientos_contables_sp',
      {'estado': EstadoAsiento.registrado.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Actualizar saldos de cuentas
    await _actualizarSaldosCuentas(
      entidadId: entidadId,
      vigencia: fechaAsiento.year.toString(),
      detalles: detalles,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.asientoContable,
      modulo: 'contabilidad',
      accion: 'asiento_automatico_presupuestal',
      valorAnterior: {},
      valorNuevo: {
        'asiento_id': id,
        'tipo_documento': tipoDocumento,
        'referencia': referenciaOrigen,
      },
      referenciaId: id,
    );

    return asiento;
  }

  /// Genera asiento contable automático desde una obligación
  /// Db: Gasto / Cr: Cuentas por pagar (NICSP 19)
  Future<AsientoContable> generarAsientoObligacion({
    required String entidadId,
    required String usuarioId,
    required DateTime fechaReconocimiento,
    required String obligacionId,
    required String numeroObligacion,
    required String terceroNombre,
    required MoneyValue valorObligacion,
    required String cuentaGasto,
    required String nombreCuentaGasto,
  }) async {
    final detalles = [
      DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: cuentaGasto,
        cuentaNombre: nombreCuentaGasto,
        debito: valorObligacion,
        credito: publicMoneyZero(),
        referenciaId: obligacionId,
      ),
      DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: '2401',
        cuentaNombre: 'Cuentas por pagar a contratistas',
        debito: publicMoneyZero(),
        credito: valorObligacion,
        referenciaId: obligacionId,
      ),
    ];

    return generarAsientoPresupuestal(
      entidadId: entidadId,
      usuarioId: usuarioId,
      fechaAsiento: fechaReconocimiento,
      tipoDocumento: 'OBLIGACION',
      referenciaOrigen: obligacionId,
      descripcion:
          'Reconocimiento de obligación $numeroObligacion - $terceroNombre',
      detalles: detalles,
    );
  }

  /// Genera asiento contable automático desde un pago
  /// Db: Cuentas por pagar / Cr: Banco
  Future<AsientoContable> generarAsientoPago({
    required String entidadId,
    required String usuarioId,
    required DateTime fechaPago,
    required String pagoId,
    required String numeroPago,
    required String terceroNombre,
    required MoneyValue valorPago,
    required String cuentaBanco,
    required String nombreCuentaBanco,
  }) async {
    final detalles = [
      DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: '2401',
        cuentaNombre: 'Cuentas por pagar a contratistas',
        debito: valorPago,
        credito: publicMoneyZero(),
        referenciaId: pagoId,
      ),
      DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: cuentaBanco,
        cuentaNombre: nombreCuentaBanco,
        debito: publicMoneyZero(),
        credito: valorPago,
        referenciaId: pagoId,
      ),
    ];

    return generarAsientoPresupuestal(
      entidadId: entidadId,
      usuarioId: usuarioId,
      fechaAsiento: fechaPago,
      tipoDocumento: 'PAGO',
      referenciaOrigen: pagoId,
      descripcion: 'Pago $numeroPago - $terceroNombre',
      detalles: detalles,
    );
  }

  /// Registra un asiento contable (cambia estado a registrado)
  Future<AsientoContable> registrarAsiento({
    required String entidadId,
    required String usuarioId,
    required String asientoId,
  }) async {
    final asiento = await obtenerAsiento(asientoId);
    if (asiento == null) {
      throw Exception('Asiento no encontrado');
    }

    if (!asiento.sePuedeRegistrar()) {
      throw Exception('El asiento no se puede registrar');
    }

    await db.update(
      'asientos_contables_sp',
      {'estado': EstadoAsiento.registrado.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    // Actualizar saldos de cuentas
    await _actualizarSaldosCuentas(
      entidadId: entidadId,
      vigencia: asiento.fechaAsiento.year.toString(),
      detalles: asiento.detalles,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.asientoContable,
      modulo: 'contabilidad',
      accion: 'registro_asiento',
      valorAnterior: {'estado_anterior': asiento.estado.toString()},
      valorNuevo: {'estado_nuevo': EstadoAsiento.registrado.toString()},
      referenciaId: asientoId,
    );

    return asiento.copyWith(estado: EstadoAsiento.registrado);
  }

  /// Reversa un asiento contable
  Future<AsientoContable> reversarAsiento({
    required String entidadId,
    required String usuarioId,
    required String asientoId,
    required String motivo,
  }) async {
    final asientoOriginal = await obtenerAsiento(asientoId);
    if (asientoOriginal == null) {
      throw Exception('Asiento no encontrado');
    }

    final rolCreador = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: asientoOriginal.usuarioCreo,
    );

    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.reversarAsiento,
      rolQuienCrea: rolCreador,
    );

    if (!asientoOriginal.sePuedeReversar()) {
      throw Exception('El asiento no se puede reversar');
    }

    // Crear asiento de reversa (invertir débitos y créditos)
    final detallesReversa = asientoOriginal.detalles.map((d) {
      return DetalleAsiento(
        id: _uuid.v4(),
        cuentaCodigo: d.cuentaCodigo,
        cuentaNombre: d.cuentaNombre,
        debito: d.credito, // Invertir
        credito: d.debito, // Invertir
        referenciaId: asientoOriginal.id,
      );
    }).toList();

    final id = _uuid.v4();
    final numeroAsiento =
        'AS-${DateTime.now().year}-${_generarNumeroSecuencial()}';

    final asientoReversa = AsientoContable(
      id: id,
      entidadId: entidadId,
      numeroAsiento: numeroAsiento,
      fechaAsiento: DateTime.now(),
      descripcion:
          'REVERSA del asiento ${asientoOriginal.numeroAsiento} - $motivo',
      tipoAsiento: TipoAsiento.reversa,
      estado: EstadoAsiento.registrado,
      detalles: detallesReversa,
      totalDebito: asientoOriginal.totalCredito,
      totalCredito: asientoOriginal.totalDebito,
      usuarioCreo: usuarioId,
      referenciaOrigen: asientoOriginal.id,
      tipoDocumentoOrigen: 'REVERSA',
      observaciones: motivo,
    );

    await db.insert('asientos_contables_sp', {
      'id': id,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': asientoReversa.fechaAsiento.toIso8601String(),
      'descripcion': asientoReversa.descripcion,
      'tipo_asiento': TipoAsiento.reversa.toString().split('.').last,
      'estado': EstadoAsiento.borrador.toString().split('.').last,
      'total_debito': asientoReversa.totalDebito.toSql(),
      'total_credito': asientoReversa.totalCredito.toSql(),
      'usuario_creo': usuarioId,
      'referencia_origen': asientoOriginal.id,
      'tipo_documento_origen': 'REVERSA',
      'observaciones': motivo,
    });

    for (final detalle in detallesReversa) {
      await db.insert('detalles_asientos', {
        'id': _uuid.v4(),
        'asiento_id': id,
        'cuenta_codigo': detalle.cuentaCodigo,
        'cuenta_nombre': detalle.cuentaNombre,
        'debito': detalle.debito.toSql(),
        'credito': detalle.credito.toSql(),
        'referencia_id': detalle.referenciaId,
      });
    }

    await db.update(
      'asientos_contables_sp',
      {'estado': EstadoAsiento.registrado.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Actualizar estado del asiento original
    await db.update(
      'asientos_contables_sp',
      {'estado': EstadoAsiento.reversado.toString().split('.').last},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    // Actualizar saldos de cuentas
    await _actualizarSaldosCuentas(
      entidadId: entidadId,
      vigencia: asientoReversa.fechaAsiento.year.toString(),
      detalles: detallesReversa,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.reversaAsiento,
      modulo: 'contabilidad',
      accion: 'reversa_asiento',
      valorAnterior: {'asiento_original': asientoOriginal.id},
      valorNuevo: {'asiento_reversa': id, 'motivo': motivo},
      referenciaId: id,
    );

    return asientoReversa;
  }

  /// Obtiene un asiento por ID
  Future<AsientoContable?> obtenerAsiento(String id) async {
    final resultado = await db.query(
      'asientos_contables_sp',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;

    final asientoData = resultado.first;
    final detallesResult = await db.query(
      'detalles_asientos',
      where: 'asiento_id = ?',
      whereArgs: [id],
    );

    final detalles = detallesResult
        .map((d) => DetalleAsiento.fromJson(d))
        .toList();

    return AsientoContable(
      id: asientoData['id'] as String,
      entidadId: asientoData['entidad_id'] as String,
      numeroAsiento: asientoData['numero_asiento'] as String,
      fechaAsiento: DateTime.parse(asientoData['fecha_asiento'] as String),
      descripcion: asientoData['descripcion'] as String,
      tipoAsiento: TipoAsiento.values.firstWhere(
        (e) => e.toString() == 'TipoAsiento.${asientoData['tipo_asiento']}',
      ),
      estado: EstadoAsiento.values.firstWhere(
        (e) => e.toString() == 'EstadoAsiento.${asientoData['estado']}',
      ),
      detalles: detalles,
      totalDebito: publicMoneyFromSql(asientoData['total_debito']),
      totalCredito: publicMoneyFromSql(asientoData['total_credito']),
      usuarioCreo: asientoData['usuario_creo'] as String,
      usuarioReviso: asientoData['usuario_reviso'] as String?,
      fechaRevision: asientoData['fecha_revision'] != null
          ? DateTime.parse(asientoData['fecha_revision'] as String)
          : null,
      referenciaOrigen: asientoData['referencia_origen'] as String?,
      tipoDocumentoOrigen: asientoData['tipo_documento_origen'] as String?,
      observaciones: asientoData['observaciones'] as String?,
    );
  }

  // ==================== SALDOS DE CUENTAS ====================

  /// Actualiza los saldos de las cuentas después de un asiento
  Future<void> _actualizarSaldosCuentas({
    required String entidadId,
    required String vigencia,
    required List<DetalleAsiento> detalles,
  }) async {
    for (final detalle in detalles) {
      // Obtener saldo actual
      final saldoActual = await db.query(
        'saldos_cuentas',
        where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
        whereArgs: [entidadId, detalle.cuentaCodigo, vigencia],
      );

      final ahora = DateTime.now();

      if (saldoActual.isEmpty) {
        // Crear nuevo saldo
        await db.insert('saldos_cuentas', {
          'id': _uuid.v4(),
          'entidad_id': entidadId,
          'cuenta_codigo': detalle.cuentaCodigo,
          'cuenta_nombre': detalle.cuentaNombre,
          'saldo_deudor': detalle.debito.toSql(),
          'saldo_acreedor': detalle.credito.toSql(),
          'saldo_neto': (detalle.debito - detalle.credito).toSql(),
          'fecha_ultimo_movimiento': ahora.toIso8601String(),
          'vigencia': vigencia,
        });
      } else {
        // Actualizar saldo existente
        final saldoData = saldoActual.first;
        final nuevoDeudor =
            publicMoneyFromSql(saldoData['saldo_deudor']) + detalle.debito;
        final nuevoAcreedor =
            publicMoneyFromSql(saldoData['saldo_acreedor']) + detalle.credito;

        await db.update(
          'saldos_cuentas',
          {
            'saldo_deudor': nuevoDeudor.toSql(),
            'saldo_acreedor': nuevoAcreedor.toSql(),
            'saldo_neto': (nuevoDeudor - nuevoAcreedor).toSql(),
            'fecha_ultimo_movimiento': ahora.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [saldoData['id']],
        );
      }
    }
  }

  /// Obtiene el saldo de una cuenta
  Future<SaldoCuenta?> obtenerSaldoCuenta({
    required String entidadId,
    required String cuentaCodigo,
    required String vigencia,
  }) async {
    final resultado = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND cuenta_codigo = ? AND vigencia = ?',
      whereArgs: [entidadId, cuentaCodigo, vigencia],
    );

    if (resultado.isEmpty) return null;

    final data = resultado.first;
    return SaldoCuenta(
      cuentaId: data['id'] as String,
      cuentaCodigo: data['cuenta_codigo'] as String,
      cuentaNombre: data['cuenta_nombre'] as String,
      saldoDeudor: publicMoneyFromSql(data['saldo_deudor']),
      saldoAcreedor: publicMoneyFromSql(data['saldo_acreedor']),
      saldoNeto: publicMoneyFromSql(data['saldo_neto']),
      fechaUltimoMovimiento: DateTime.parse(
        data['fecha_ultimo_movimiento'] as String,
      ),
    );
  }

  /// Consulta asientos por periodo
  Future<List<AsientoContable>> consultarAsientos({
    required String entidadId,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    TipoAsiento? tipoAsiento,
  }) async {
    String query = 'SELECT * FROM asientos_contables_sp WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (fechaDesde != null) {
      query += ' AND fecha_asiento >= ?';
      args.add(fechaDesde.toIso8601String());
    }

    if (fechaHasta != null) {
      query += ' AND fecha_asiento <= ?';
      args.add(fechaHasta.toIso8601String());
    }

    if (tipoAsiento != null) {
      query += ' AND tipo_asiento = ?';
      args.add(tipoAsiento.toString().split('.').last);
    }

    query += ' ORDER BY fecha_asiento DESC';

    final resultados = await db.rawQuery(query, args);

    final asientos = <AsientoContable>[];
    for (final resultado in resultados) {
      final asiento = await obtenerAsiento(resultado['id'] as String);
      if (asiento != null) {
        asientos.add(asiento);
      }
    }

    return asientos;
  }

  // ==================== UTILIDADES ====================

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
