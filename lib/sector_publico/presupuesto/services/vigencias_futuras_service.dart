import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

import '../../contabilidad/models/asiento_contable.dart';
import '../../contabilidad/services/contabilidad_nicsp_service.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';

class VigenciasFuturasService {
  VigenciasFuturasService({required this.db});

  final Database db;
  final Uuid _uuid = const Uuid();

  Future<String> registrarAutorizacion({
    required String entidadId,
    required String usuarioId,
    required String tipo,
    required String regimenPresupuestal,
    required String causalLegal,
    required String objeto,
    required String planDesarrolloReferencia,
    required String mfmpReferencia,
    required int anioInicio,
    required int anioFin,
    required MoneyValue montoTotal,
    required MoneyValue apropiacionVigenciaActual,
    required Map<int, MoneyValue> distribucion,
    required String confisAutoridad,
    required String confisActoNumero,
    required DateTime confisActoFecha,
    required String confisSoporte,
    required String corporacionTipo,
    required String autorizacionAutoridad,
    required String autorizacionActoNumero,
    required DateTime autorizacionActoFecha,
    required String autorizacionSoporte,
    String? proyectoId,
    String? codigoBancoProyectos,
    String? estatutoPresupuestalEse,
    String? autoridadCompetenteEse,
    String? actoDelegacionEse,
    String? conceptoDnp,
    String? importanciaEstrategicaActo,
    String? excepcionUltimoAnio,
    String? autorizacionAnteriorId,
    String? motivoVersion,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.registrarAutorizacionVigenciaFutura,
    );
    if (tipo != 'ordinaria' && tipo != 'excepcional') {
      throw ArgumentError('Tipo de vigencia futura no valido.');
    }
    if (montoTotal <= publicMoneyZero() || distribucion.isEmpty) {
      throw ArgumentError('La autorizacion requiere monto y distribucion.');
    }
    if (anioInicio > anioFin ||
        distribucion.keys.any((anio) => anio < anioInicio || anio > anioFin)) {
      throw StateError('La distribucion no coincide con el rango autorizado.');
    }
    if (distribucion.keys.any((anio) => anio <= DateTime.now().year)) {
      throw StateError('La distribucion debe afectar vigencias posteriores.');
    }
    final totalDistribuido = distribucion.values.fold<MoneyValue>(
      publicMoneyZero(),
      (total, monto) => total + monto,
    );
    if ((totalDistribuido - montoTotal) != publicMoneyZero() ||
        distribucion.values.any((monto) => monto <= publicMoneyZero())) {
      throw StateError('La distribucion anual debe sumar el monto autorizado.');
    }
    if (tipo == 'ordinaria' &&
        apropiacionVigenciaActual <
            montoTotal.multiplyRatio(numerator: 15, denominator: 100)) {
      throw StateError(
        'La vigencia futura ordinaria requiere apropiacion actual minima del 15%.',
      );
    }
    if (tipo == 'excepcional' &&
        ((proyectoId ?? '').trim().isEmpty ||
            (codigoBancoProyectos ?? '').trim().isEmpty)) {
      throw StateError(
        'La vigencia futura excepcional exige proyecto inscrito y viable.',
      );
    }
    _exigirTexto({
      'regimen_presupuestal': regimenPresupuestal,
      'causal_legal': causalLegal,
      'objeto': objeto,
      'plan_desarrollo': planDesarrolloReferencia,
      'mfmp': mfmpReferencia,
      'confis_autoridad': confisAutoridad,
      'confis_acto': confisActoNumero,
      'confis_soporte': confisSoporte,
      'autoridad_final': autorizacionAutoridad,
      'acto_final': autorizacionActoNumero,
      'soporte_final': autorizacionSoporte,
    });

    final entidades = await db.query(
      'entidades_territoriales',
      where: 'id = ? AND activo = 1',
      whereArgs: [entidadId],
    );
    if (entidades.isEmpty) {
      throw StateError('Entidad no encontrada o inactiva.');
    }
    final tipoEntidad = entidades.single['tipo_entidad'].toString();
    final esMunicipio = tipoEntidad == 'municipio';
    final esDepartamento =
        tipoEntidad == 'departamento' || tipoEntidad == 'gobernacion';
    final esEse =
        tipoEntidad == 'hospitalEse' ||
        tipoEntidad == 'hospital' ||
        tipoEntidad == 'ese';
    if (!esMunicipio && !esDepartamento && !esEse) {
      throw StateError(
        'El tipo de entidad no tiene ruta de autorizacion definida.',
      );
    }
    if (esMunicipio && corporacionTipo != 'concejo') {
      throw StateError(
        'El municipio requiere autorizacion del concejo municipal.',
      );
    }
    if (esDepartamento && corporacionTipo != 'asamblea') {
      throw StateError(
        'El departamento requiere autorizacion de la asamblea departamental.',
      );
    }
    if (esEse) {
      _exigirTexto({
        'estatuto_presupuestal_ese': estatutoPresupuestalEse,
        'autoridad_competente_ese': autoridadCompetenteEse,
        'acto_delegacion_ese': actoDelegacionEse,
      });
    }

    var version = 1;
    if (autorizacionAnteriorId != null) {
      final anteriores = await db.query(
        'autorizaciones_vigencias_futuras',
        where: 'id = ? AND entidad_id = ? AND estado = ?',
        whereArgs: [autorizacionAnteriorId, entidadId, 'autorizada'],
      );
      if (anteriores.isEmpty) {
        throw StateError('La version anterior no existe en la entidad.');
      }
      version = (anteriores.single['version'] as num).toInt() + 1;
    }

    final id = _uuid.v4();
    final porcentaje = montoTotal.minorUnits == 0
        ? 0.0
        : apropiacionVigenciaActual.minorUnits * 100 / montoTotal.minorUnits;
    await db.transaction((txn) async {
      if (autorizacionAnteriorId != null) {
        await txn.update(
          'autorizaciones_vigencias_futuras',
          {'estado': 'revocada'},
          where: 'id = ?',
          whereArgs: [autorizacionAnteriorId],
        );
      }
      await txn.insert('autorizaciones_vigencias_futuras', {
        'id': id,
        'entidad_id': entidadId,
        'version': version,
        'autorizacion_anterior_id': autorizacionAnteriorId,
        'tipo': tipo,
        'regimen_presupuestal': regimenPresupuestal,
        'causal_legal': causalLegal,
        'objeto': objeto,
        'proyecto_id': proyectoId,
        'codigo_banco_proyectos': codigoBancoProyectos,
        'plan_desarrollo_referencia': planDesarrolloReferencia,
        'mfmp_referencia': mfmpReferencia,
        'anio_inicio': anioInicio,
        'anio_fin': anioFin,
        'monto_total': montoTotal.toSql(),
        'apropiacion_vigencia_actual': apropiacionVigenciaActual.toSql(),
        'porcentaje_respaldo_actual': porcentaje,
        'confis_autoridad': confisAutoridad,
        'confis_acto_numero': confisActoNumero,
        'confis_acto_fecha': confisActoFecha.toIso8601String(),
        'confis_soporte': confisSoporte,
        'corporacion_tipo': corporacionTipo,
        'autorizacion_autoridad': autorizacionAutoridad,
        'autorizacion_acto_numero': autorizacionActoNumero,
        'autorizacion_acto_fecha': autorizacionActoFecha.toIso8601String(),
        'autorizacion_soporte': autorizacionSoporte,
        'estatuto_presupuestal_ese': estatutoPresupuestalEse,
        'autoridad_competente_ese': autoridadCompetenteEse,
        'acto_delegacion_ese': actoDelegacionEse,
        'concepto_dnp': conceptoDnp,
        'importancia_estrategica_acto': importanciaEstrategicaActo,
        'excepcion_ultimo_anio': excepcionUltimoAnio,
        'estado': 'autorizada',
        'registrado_por': usuarioId,
        'fecha_registro': DateTime.now().toIso8601String(),
        'motivo_version': motivoVersion,
      });
      for (final anualidad in distribucion.entries) {
        await txn.insert('vigencias_futuras_distribucion', {
          'id': _uuid.v4(),
          'autorizacion_id': id,
          'anio': anualidad.key,
          'monto_autorizado': anualidad.value.toSql(),
          'saldo_disponible': anualidad.value.toSql(),
        });
      }
      await AuditoriaService(txn).registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.creacionRegistro,
        modulo: 'presupuesto',
        accion: 'REGISTRAR_AUTORIZACION_VIGENCIA_FUTURA',
        valorAnterior: const {},
        valorNuevo: {
          'autorizacion_id': id,
          'tipo': tipo,
          'version': version,
          'monto_total': montoTotal.toSql(),
          'distribucion': distribucion.toString(),
        },
        referenciaId: id,
      );
    });
    return id;
  }

  Future<String> comprometerVigenciaFutura({
    required String entidadId,
    required String usuarioId,
    required String autorizacionId,
    required String rpId,
    required int anio,
    required MoneyValue monto,
    DatabaseExecutor? executor,
  }) async {
    if (monto <= publicMoneyZero()) {
      throw ArgumentError('El compromiso debe ser mayor que cero.');
    }
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.expedirRP,
      executor: executor,
    );
    if (executor != null) {
      return _registrarCompromiso(
        executor: executor,
        entidadId: entidadId,
        usuarioId: usuarioId,
        autorizacionId: autorizacionId,
        rpId: rpId,
        anio: anio,
        monto: monto,
      );
    }
    return db.transaction(
      (txn) => _registrarCompromiso(
        executor: txn,
        entidadId: entidadId,
        usuarioId: usuarioId,
        autorizacionId: autorizacionId,
        rpId: rpId,
        anio: anio,
        monto: monto,
      ),
    );
  }

  Future<String> _registrarCompromiso({
    required DatabaseExecutor executor,
    required String entidadId,
    required String usuarioId,
    required String autorizacionId,
    required String rpId,
    required int anio,
    required MoneyValue monto,
  }) async {
    final autorizaciones = await executor.query(
      'autorizaciones_vigencias_futuras',
      where: 'id = ? AND entidad_id = ? AND estado = ?',
      whereArgs: [autorizacionId, entidadId, 'autorizada'],
    );
    if (autorizaciones.isEmpty) {
      throw StateError('No existe autorizacion vigente para comprometer.');
    }
    final rps = await executor.query(
      'rps',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [rpId, entidadId],
    );
    if (rps.isEmpty) throw StateError('El RP no pertenece a la entidad.');
    if (rps.single['vigencia'].toString() != anio.toString()) {
      throw StateError('El RP no pertenece a la vigencia futura autorizada.');
    }
    final distribuciones = await executor.query(
      'vigencias_futuras_distribucion',
      where: 'autorizacion_id = ? AND anio = ?',
      whereArgs: [autorizacionId, anio],
    );
    if (distribuciones.isEmpty) {
      throw StateError('La vigencia solicitada no fue autorizada.');
    }
    final distribucion = distribuciones.single;
    final saldo = publicMoneyFromSql(distribucion['saldo_disponible']);
    if (monto > saldo) {
      throw StateError('El compromiso excede el monto futuro autorizado.');
    }
    final compromisoId = _uuid.v4();
    await executor.insert('compromisos_vigencias_futuras', {
      'id': compromisoId,
      'autorizacion_id': autorizacionId,
      'distribucion_id': distribucion['id'],
      'entidad_id': entidadId,
      'rp_id': rpId,
      'anio': anio,
      'monto_comprometido': monto.toSql(),
      'registrado_por': usuarioId,
      'fecha_registro': DateTime.now().toIso8601String(),
    });
    await executor.update(
      'vigencias_futuras_distribucion',
      {
        'monto_comprometido':
            (publicMoneyFromSql(distribucion['monto_comprometido']) + monto).toSql(),
        'saldo_disponible': (saldo - monto).toSql(),
      },
      where: 'id = ?',
      whereArgs: [distribucion['id']],
    );
    await AuditoriaService(executor).registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.expedicionRP,
      modulo: 'presupuesto',
      accion: 'COMPROMETER_VIGENCIA_FUTURA',
      valorAnterior: {'saldo_autorizado': saldo.toSql()},
      valorNuevo: {
        'compromiso_id': compromisoId,
        'rp_id': rpId,
        'anio': anio,
        'monto': monto.toSql(),
      },
      referenciaId: compromisoId,
    );
    return compromisoId;
  }

  Future<String> registrarRecepcionSatisfaccion({
    required String entidadId,
    required String usuarioId,
    required String terceroId,
    required String terceroNombre,
    required String actaNumero,
    required DateTime fechaRecepcion,
    required String descripcion,
    required MoneyValue valor,
    required String soporte,
    String? contratoId,
    String? rpId,
    String? obligacionId,
    String? facturaNumero,
    String? motivoSinObligacion,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.registrarObligacion,
    );
    _exigirTexto({
      'acta_numero': actaNumero,
      'descripcion': descripcion,
      'soporte': soporte,
    });
    if (valor <= publicMoneyZero()) {
      throw ArgumentError('El valor recibido debe ser positivo.');
    }

    Map<String, Object?>? obligacion;
    if (obligacionId != null) {
      final obligaciones = await db.query(
        'obligaciones',
        where: 'id = ? AND entidad_id = ?',
        whereArgs: [obligacionId, entidadId],
      );
      if (obligaciones.isEmpty) {
        throw StateError('La obligacion asociada no existe en la entidad.');
      }
      obligacion = obligaciones.single;
    } else if ((motivoSinObligacion ?? '').trim().isEmpty) {
      throw StateError(
        'El recibido sin obligacion exige motivo e incidente de control.',
      );
    }

    return db.transaction((txn) async {
      final recepcionId = _uuid.v4();
      final sinObligacion = obligacion == null;
      await txn.insert('recepciones_satisfaccion', {
        'id': recepcionId,
        'entidad_id': entidadId,
        'tercero_id': terceroId,
        'tercero_nombre': terceroNombre,
        'contrato_id': contratoId,
        'rp_id': rpId,
        'obligacion_id': obligacionId,
        'acta_numero': actaNumero,
        'factura_numero': facturaNumero,
        'fecha_recepcion': fechaRecepcion.toIso8601String(),
        'descripcion': descripcion,
        'valor_recibido': valor.toSql(),
        'valor_reconocido': valor.toSql(),
        'estado_contable': sinObligacion
            ? 'pasivo_reconocido_excepcional'
            : 'vinculada_obligacion',
        'soporte': soporte,
        'bloquea_pago': sinObligacion ? 1 : 0,
        'registrado_por': usuarioId,
        'fecha_registro': DateTime.now().toIso8601String(),
      });

      if (sinObligacion) {
        await txn.insert('incidentes_recibido_sin_obligacion', {
          'id': _uuid.v4(),
          'recepcion_id': recepcionId,
          'entidad_id': entidadId,
          'motivo': motivoSinObligacion,
          'reportado_por': usuarioId,
          'fecha_reporte': DateTime.now().toIso8601String(),
          'estado': 'abierto',
          'bloquea_pago': 1,
        });
        final contabilidad = ContabilidadNICSPService(
          db: txn,
          auditoriaService: AuditoriaService(txn),
        );
        final asiento = await contabilidad.generarAsientoPresupuestal(
          entidadId: entidadId,
          usuarioId: usuarioId,
          fechaAsiento: fechaRecepcion,
          tipoDocumento: 'RECIBIDO_SIN_OBLIGACION',
          referenciaOrigen: recepcionId,
          descripcion: 'Devengo excepcional $actaNumero - $terceroNombre',
          detalles: [
            DetalleAsiento(
              id: _uuid.v4(),
              cuentaCodigo: '5111',
              cuentaNombre: 'Gastos generales',
              debito: valor,
              credito: publicMoneyZero(),
              referenciaId: recepcionId,
            ),
            DetalleAsiento(
              id: _uuid.v4(),
              cuentaCodigo: '2401',
              cuentaNombre: 'Cuentas por pagar a contratistas',
              debito: publicMoneyZero(),
              credito: valor,
              referenciaId: recepcionId,
            ),
          ],
        );
        await txn.update(
          'recepciones_satisfaccion',
          {'asiento_contable_id': asiento.id},
          where: 'id = ?',
          whereArgs: [recepcionId],
        );
      }

      await AuditoriaService(txn).registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.creacionRegistro,
        modulo: 'presupuesto',
        accion: 'REGISTRAR_RECEPCION_SATISFACCION',
        valorAnterior: const {},
        valorNuevo: {
          'recepcion_id': recepcionId,
          'obligacion_id': obligacionId,
          'valor': valor.toSql(),
          'bloquea_pago': sinObligacion,
        },
        referenciaId: recepcionId,
      );
      return recepcionId;
    });
  }

  Future<void> _validarPermiso({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
    DatabaseExecutor? executor,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: executor ?? db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );
    if (rol == null || !RolesPermisosService.tienePermiso(rol, permiso)) {
      throw StateError('Acceso denegado para ${permiso.name}.');
    }
  }

  void _exigirTexto(Map<String, String?> campos) {
    for (final campo in campos.entries) {
      if ((campo.value ?? '').trim().isEmpty) {
        throw StateError('El campo ${campo.key} es obligatorio.');
      }
    }
  }
}
