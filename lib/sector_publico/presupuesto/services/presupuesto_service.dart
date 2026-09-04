/// Servicio de Presupuesto Público
/// Implementa el flujo obligatorio: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
/// Con validaciones normativas duras según Decreto 111/1996 (EOP)
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/apropiacion.dart';
import '../models/cdp.dart';
import '../models/rp.dart';
import '../models/obligacion.dart';
import '../models/pago.dart';
import 'pac_service.dart';
import 'vigencias_futuras_service.dart';
import '../../contabilidad/services/contabilidad_nicsp_service.dart';
import '../../planeacion/services/trazabilidad_plan_presupuesto_service.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';

class PresupuestoService {
  final Database db;
  final AuditoriaService? auditoriaService;
  final Uuid _uuid = const Uuid();

  PresupuestoService({required this.db, this.auditoriaService});

  // ==================== APROPIACIÓN ====================

  /// Crea una nueva apropiación presupuestal
  Future<Apropiacion> crearApropiacion({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String codigoRubro,
    required String nombreRubro,
    required MoneyValue valorApropiado,
    required String fuenteFinanciacion,
    required String sector,
    required String programa,
    required String subprograma,
    required String proyecto,
    required String actividad,
    required String objetoGasto,
    required DateTime fechaAprobacionConcejo,
    required String actoAdministrativo,
  }) async {
    final id = _uuid.v4();
    final fechaCreacion = DateTime.now();

    final apropiacion = Apropiacion(
      id: id,
      entidadId: entidadId,
      vigencia: vigencia,
      codigoRubro: codigoRubro,
      nombreRubro: nombreRubro,
      valorInicial: valorApropiado,
      valorApropiado: valorApropiado,
      valorCDP: publicMoneyZero(),
      valorRP: publicMoneyZero(),
      valorObligado: publicMoneyZero(),
      valorPagado: publicMoneyZero(),
      saldoDisponible: valorApropiado,
      fuenteFinanciacion: fuenteFinanciacion,
      sector: sector,
      programa: programa,
      subprograma: subprograma,
      proyecto: proyecto,
      actividad: actividad,
      objetoGasto: objetoGasto,
      fechaCreacion: fechaCreacion,
      fechaAprobacionConcejo: fechaAprobacionConcejo,
      actoAdministrativo: actoAdministrativo,
      activo: true,
    );

    await db.insert('apropiaciones', apropiacion.toJson());

    await auditoriaService?.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'presupuesto',
      accion: 'creacion_apropiacion',
      valorAnterior: {},
      valorNuevo: apropiacion.toJson(),
      referenciaId: id,
    );

    return apropiacion;
  }

  /// Obtiene una apropiación por ID
  Future<Apropiacion?> obtenerApropiacion(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final resultado = await (executor ?? db).query(
      'apropiaciones',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return Apropiacion.fromJson(resultado.first);
  }

  /// Valida permiso y segregación de funciones (Fail-closed)
  Future<RolSectorPublico> _validarPermisoYSegregacion({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
    RolSectorPublico? rolQuienCrea,
    DatabaseExecutor? executor,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: executor ?? db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    // Fail-Closed: si no hay un funcionario activo con rol resuelto, bloquear inmediatamente.
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

  // ==================== CDP ====================

  /// Expide un CDP con validación de disponibilidad real
  /// VALIDACIÓN NORMATIVA DURA: Verifica disponibilidad en el rubro
  Future<CDP> expedirCDP({
    required String entidadId,
    required String usuarioId,
    required String apropiacionId,
    required MoneyValue valorCDP,
    required String funcionarioExpedidor,
    required String funcionarioSolicitante,
    required String objetoGasto,
    required String? contratoNumero,
    String? proyectoId,
    String? metaCodigo,
  }) async {
    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.expedirCDP,
    );
    // Obtener la apropiación
    final apropiacion = await obtenerApropiacion(apropiacionId);
    if (apropiacion == null) {
      throw Exception('Apropiación no encontrada');
    }

    // VALIDACIÓN NORMATIVA: Verificar disponibilidad real
    if (!apropiacion.tieneDisponibilidad(valorCDP)) {
      throw Exception(
        'Saldo insuficiente en la apropiación. '
        'Disponible: ${apropiacion.calcularSaldoDisponibleCDP()}, '
        'Solicitado: $valorCDP',
      );
    }

    // Generar número de CDP
    final requiereTrazabilidadPlan = proyectoId != null || metaCodigo != null;
    if (requiereTrazabilidadPlan) {
      if (proyectoId == null ||
          proyectoId.trim().isEmpty ||
          metaCodigo == null ||
          metaCodigo.trim().isEmpty) {
        throw ArgumentError(
          'La trazabilidad PDT/MGA del CDP exige proyectoId y metaCodigo.',
        );
      }
      await TrazabilidadPlanPresupuestoService(db).validarMetaParaApropiacion(
        entidadId: entidadId,
        apropiacionId: apropiacionId,
        proyectoId: proyectoId,
        metaCodigo: metaCodigo,
      );
    }

    final numeroCDP =
        'CDP-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaExpedicion = DateTime.now();
    final fechaVigencia = fechaExpedicion.add(
      const Duration(days: 180),
    ); // 6 meses

    final cdp = CDP(
      id: _uuid.v4(),
      entidadId: entidadId,
      numeroCDP: numeroCDP,
      vigencia: apropiacion.vigencia,
      apropiacionId: apropiacionId,
      codigoRubro: apropiacion.codigoRubro,
      valorCDP: valorCDP,
      valorComprometidoRP: publicMoneyZero(),
      saldoDisponible: valorCDP,
      fechaExpedicion: fechaExpedicion,
      fechaVigencia: fechaVigencia,
      funcionarioExpedidor: funcionarioExpedidor,
      funcionarioSolicitante: funcionarioSolicitante,
      objetoGasto: objetoGasto,
      contratoNumero: contratoNumero,
      estado: EstadoCDP.vigente,
    );

    await db.insert('cdps', cdp.toJson());

    // Actualizar apropiación
    await db.update(
      'apropiaciones',
      {
        'valor_cdp': (apropiacion.valorCDP + valorCDP).toSql(),
        'saldo_disponible':
            (apropiacion.calcularSaldoDisponibleCDP() - valorCDP).toSql(),
      },
      where: 'id = ?',
      whereArgs: [apropiacionId],
    );

    await auditoriaService?.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.expedicionCDP,
      modulo: 'presupuesto',
      accion: 'expedicion_cdp',
      valorAnterior: {
        'apropiacion_id': apropiacionId,
        'saldo_anterior': apropiacion.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'cdp_id': cdp.id,
        'numero_cdp': numeroCDP,
        'valor': valorCDP.toSql(),
      },
      referenciaId: cdp.id,
    );

    if (requiereTrazabilidadPlan) {
      await TrazabilidadPlanPresupuestoService(db).registrarTrazabilidadCDP(
        id: _uuid.v4(),
        entidadId: entidadId,
        cdpId: cdp.id,
        apropiacionId: apropiacionId,
        proyectoId: proyectoId!,
        metaCodigo: metaCodigo!,
        fechaVinculacion: fechaExpedicion,
      );
    }

    return cdp;
  }

  /// Obtiene un CDP por ID
  Future<CDP?> obtenerCDP(String id, {DatabaseExecutor? executor}) async {
    final resultado = await (executor ?? db).query(
      'cdps',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return CDP.fromJson(resultado.first);
  }

  // ==================== RP ====================

  /// Expide un RP con validación de contrato previo
  /// VALIDACIÓN NORMATIVA DURA: Requiere contrato firmado (Ley 80/1993 Art. 41)
  Future<RP> expedirRP({
    required String entidadId,
    required String usuarioId,
    required String cdpId,
    required String contratoId,
    required String contratoNumero,
    required MoneyValue valorRP,
    required String funcionarioExpedidor,
    required String funcionarioSolicitante,
    required String objetoGasto,
    String? autorizacionVigenciaFuturaId,
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? db;
    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.expedirRP,
      executor: database,
    );
    // Obtener el CDP
    final cdp = await obtenerCDP(cdpId, executor: database);
    if (cdp == null) {
      throw Exception('CDP no encontrado');
    }
    final anioCDP = int.tryParse(cdp.vigencia);
    final esVigenciaFutura = anioCDP != null && anioCDP > DateTime.now().year;
    if (esVigenciaFutura && autorizacionVigenciaFuturaId == null) {
      throw StateError(
        'Un RP de vigencia futura exige autorizacion plurianual vigente.',
      );
    }
    if (!esVigenciaFutura && autorizacionVigenciaFuturaId != null) {
      throw StateError(
        'La autorizacion plurianual solo puede usarse en una vigencia futura.',
      );
    }
    if (esVigenciaFutura && executor == null) {
      return db.transaction(
        (txn) => expedirRP(
          entidadId: entidadId,
          usuarioId: usuarioId,
          cdpId: cdpId,
          contratoId: contratoId,
          contratoNumero: contratoNumero,
          valorRP: valorRP,
          funcionarioExpedidor: funcionarioExpedidor,
          funcionarioSolicitante: funcionarioSolicitante,
          objetoGasto: objetoGasto,
          autorizacionVigenciaFuturaId: autorizacionVigenciaFuturaId,
          executor: txn,
        ),
      );
    }

    // VALIDACIÓN NORMATIVA: Verificar que el CDP esté vigente
    if (!cdp.estaVigente()) {
      throw Exception(
        'CDP no vigente. Estado: ${cdp.estado}, Vence: ${cdp.fechaVigencia}',
      );
    }

    // VALIDACIÓN NORMATIVA: Verificar saldo disponible en CDP
    if (!cdp.tieneSaldoParaRP(valorRP)) {
      throw Exception(
        'Saldo insuficiente en el CDP. '
        'Disponible: ${cdp.saldoDisponible}, '
        'Solicitado: $valorRP',
      );
    }

    // VALIDACIÓN NORMATIVA DURA: Requerir contrato (Ley 80/1993 Art. 41)
    if (contratoId.isEmpty || contratoNumero.isEmpty) {
      throw Exception(
        'El RP requiere un contrato firmado previo (Ley 80/1993 Art. 41)',
      );
    }
    final contratoResult = await database.query(
      'contratos',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [contratoId, entidadId],
    );
    if (contratoResult.isEmpty ||
        contratoResult.first['numero_contrato'] != contratoNumero ||
        contratoResult.first['estado'] != 'firmado' ||
        contratoResult.first['cdp_id'] != cdpId ||
        contratoResult.first['rp_id'] != null) {
      throw Exception(
        'El RP requiere un contrato firmado, sin RP asociado y vinculado al CDP indicado',
      );
    }

    // Generar número de RP
    final numeroRP = 'RP-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaExpedicion = DateTime.now();
    final fechaVigencia = fechaExpedicion.add(
      const Duration(days: 365),
    ); // 1 año

    final rp = RP(
      id: _uuid.v4(),
      entidadId: entidadId,
      numeroRP: numeroRP,
      vigencia: cdp.vigencia,
      cdpId: cdpId,
      numeroCDP: cdp.numeroCDP,
      contratoId: contratoId,
      contratoNumero: contratoNumero,
      codigoRubro: cdp.codigoRubro,
      valorRP: valorRP,
      valorObligado: publicMoneyZero(),
      saldoDisponible: valorRP,
      fechaExpedicion: fechaExpedicion,
      fechaVigencia: fechaVigencia,
      funcionarioExpedidor: funcionarioExpedidor,
      funcionarioSolicitante: funcionarioSolicitante,
      objetoGasto: objetoGasto,
      estado: EstadoRP.vigente,
    );

    await database.insert('rps', rp.toJson());

    // Actualizar CDP
    await database.update(
      'cdps',
      {
        'valor_comprometido_rp': (cdp.valorComprometidoRP + valorRP).toSql(),
        'saldo_disponible': (cdp.saldoDisponible - valorRP).toSql(),
      },
      where: 'id = ?',
      whereArgs: [cdpId],
    );

    // Actualizar apropiación
    final apropiacion = await obtenerApropiacion(
      cdp.apropiacionId,
      executor: database,
    );
    if (apropiacion != null) {
      await database.update(
        'apropiaciones',
        {
          'valor_rp': (apropiacion.valorRP + valorRP).toSql(),
          'saldo_disponible':
              (apropiacion.calcularSaldoDisponibleCDP() - valorRP).toSql(),
        },
        where: 'id = ?',
        whereArgs: [apropiacion.id],
      );
    }

    if (esVigenciaFutura) {
      await VigenciasFuturasService(db: db).comprometerVigenciaFutura(
        entidadId: entidadId,
        usuarioId: usuarioId,
        autorizacionId: autorizacionVigenciaFuturaId!,
        rpId: rp.id,
        anio: anioCDP,
        monto: valorRP,
        executor: database,
      );
    }

    final auditoria = executor == null
        ? auditoriaService
        : AuditoriaService(database);
    await auditoria?.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.expedicionRP,
      modulo: 'presupuesto',
      accion: 'expedicion_rp',
      valorAnterior: {
        'cdp_id': cdpId,
        'saldo_anterior': cdp.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'rp_id': rp.id,
        'numero_rp': numeroRP,
        'valor': valorRP.toSql(),
        'contrato': contratoNumero,
      },
      referenciaId: rp.id,
    );

    await TrazabilidadPlanPresupuestoService(
      database,
    ).registrarTrazabilidadRPDesdeCDP(
      id: _uuid.v4(),
      entidadId: entidadId,
      rpId: rp.id,
      cdpId: cdpId,
      fechaVinculacion: fechaExpedicion,
    );

    return rp;
  }

  /// Obtiene un RP por ID
  Future<RP?> obtenerRP(String id, {DatabaseExecutor? executor}) async {
    final resultado = await (executor ?? db).query(
      'rps',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return RP.fromJson(resultado.first);
  }

  // ==================== OBLIGACIÓN ====================

  /// Registra una obligación con validación de acta de recibo
  /// VALIDACIÓN NORMATIVA DURA: Verifica acta de recibo a satisfacción o factura válida
  Future<Obligacion> registrarObligacion({
    required String entidadId,
    required String usuarioId,
    required String rpId,
    required String contratoId,
    required String contratoNumero,
    required String terceroId,
    required String terceroNombre,
    required MoneyValue valorObligacion,
    required String funcionarioReconocio,
    required String objetoGasto,
    String? actaReciboNumero,
    DateTime? actaReciboFecha,
    String? facturaNumero,
    DateTime? facturaFecha,
    DatabaseExecutor? executor,
  }) async {
    if (executor == null) {
      return db.transaction(
        (txn) => registrarObligacion(
          entidadId: entidadId,
          usuarioId: usuarioId,
          rpId: rpId,
          contratoId: contratoId,
          contratoNumero: contratoNumero,
          terceroId: terceroId,
          terceroNombre: terceroNombre,
          valorObligacion: valorObligacion,
          funcionarioReconocio: funcionarioReconocio,
          objetoGasto: objetoGasto,
          actaReciboNumero: actaReciboNumero,
          actaReciboFecha: actaReciboFecha,
          facturaNumero: facturaNumero,
          facturaFecha: facturaFecha,
          executor: txn,
        ),
      );
    }
    final database = executor;
    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.registrarObligacion,
      executor: database,
    );
    // Obtener el RP
    final rp = await obtenerRP(rpId, executor: database);
    if (rp == null) {
      throw Exception('RP no encontrado');
    }

    // VALIDACIÓN NORMATIVA: Verificar que el RP esté vigente
    if (!rp.estaVigente()) {
      throw Exception('RP no vigente');
    }

    // VALIDACIÓN NORMATIVA: Verificar saldo disponible en RP
    if (!rp.tieneSaldoParaObligacion(valorObligacion)) {
      throw Exception(
        'Saldo insuficiente en el RP. '
        'Disponible: ${rp.saldoDisponible}, '
        'Solicitado: $valorObligacion',
      );
    }

    // VALIDACIÓN NORMATIVA DURA: Requerir acta de recibo o factura
    if ((actaReciboNumero == null || actaReciboNumero.isEmpty) &&
        (facturaNumero == null || facturaNumero.isEmpty)) {
      throw Exception(
        'La obligación requiere acta de recibo a satisfacción o factura válida',
      );
    }

    // Generar número de obligación
    final numeroObligacion =
        'OBL-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaReconocimiento = DateTime.now();

    final obligacion = Obligacion(
      id: _uuid.v4(),
      entidadId: entidadId,
      numeroObligacion: numeroObligacion,
      vigencia: rp.vigencia,
      rpId: rpId,
      numeroRP: rp.numeroRP,
      contratoId: contratoId,
      contratoNumero: contratoNumero,
      terceroId: terceroId,
      terceroNombre: terceroNombre,
      codigoRubro: rp.codigoRubro,
      valorObligacion: valorObligacion,
      valorPagado: publicMoneyZero(),
      saldoPendiente: valorObligacion,
      fechaReconocimiento: fechaReconocimiento,
      funcionarioReconocio: funcionarioReconocio,
      objetoGasto: objetoGasto,
      actaReciboNumero: actaReciboNumero,
      actaReciboFecha: actaReciboFecha,
      facturaNumero: facturaNumero,
      facturaFecha: facturaFecha,
      estado: EstadoObligacion.pendiente,
    );

    final compromisosFuturos = await database.query(
      'compromisos_vigencias_futuras',
      where: 'rp_id = ? AND entidad_id = ? AND estado = ?',
      whereArgs: [rpId, entidadId, 'vigente'],
    );
    Map<String, Object?>? compromisoFuturo;
    if (compromisosFuturos.isNotEmpty) {
      compromisoFuturo = compromisosFuturos.single;
      final disponibleObligar =
          publicMoneyFromSql(compromisoFuturo['monto_comprometido']) -
          publicMoneyFromSql(compromisoFuturo['monto_obligado']);
      if (valorObligacion > disponibleObligar) {
        throw StateError(
          'La obligacion excede el compromiso de vigencia futura.',
        );
      }
    }

    await database.insert('obligaciones', obligacion.toJson());

    // Actualizar RP
    await database.update(
      'rps',
      {
        'valor_obligado': (rp.valorObligado + valorObligacion).toSql(),
        'saldo_disponible': (rp.saldoDisponible - valorObligacion).toSql(),
      },
      where: 'id = ?',
      whereArgs: [rpId],
    );

    if (compromisoFuturo != null) {
      final nuevoObligado =
          publicMoneyFromSql(compromisoFuturo['monto_obligado']) +
          valorObligacion;
      await database.insert('obligaciones_vigencias_futuras', {
        'id': _uuid.v4(),
        'compromiso_id': compromisoFuturo['id'],
        'obligacion_id': obligacion.id,
        'monto_obligado': valorObligacion.toSql(),
        'fecha_registro': fechaReconocimiento.toIso8601String(),
      });
      await database.update(
        'compromisos_vigencias_futuras',
        {'monto_obligado': nuevoObligado.toSql()},
        where: 'id = ?',
        whereArgs: [compromisoFuturo['id']],
      );
      await database.rawUpdate(
        '''
        UPDATE vigencias_futuras_distribucion
        SET monto_obligado = monto_obligado + ?
        WHERE id = ?
        ''',
        [valorObligacion.toSql(), compromisoFuturo['distribucion_id']],
      );
    }

    await AuditoriaService(database).registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.registroObligacion,
      modulo: 'presupuesto',
      accion: 'registro_obligacion',
      valorAnterior: {
        'rp_id': rpId,
        'saldo_anterior': rp.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'obligacion_id': obligacion.id,
        'numero_obligacion': numeroObligacion,
        'valor': valorObligacion.toSql(),
        'tercero': terceroNombre,
      },
      referenciaId: obligacion.id,
    );

    return obligacion;
  }

  /// Obtiene una obligación por ID
  Future<Obligacion?> obtenerObligacion(String id) async {
    final resultado = await db.query(
      'obligaciones',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return Obligacion.fromJson(resultado.first);
  }

  // ==================== PAGO ====================

  /// Programa un pago con validación de cupo PAC
  /// VALIDACIÓN NORMATIVA DURA: Verifica cupo PAC del mes (Art. 74 EOP)
  Future<Pago> programarPago({
    required String entidadId,
    required String usuarioId,
    required String obligacionId,
    required String terceroId,
    required String terceroNombre,
    required String bancoDestino,
    required String cuentaDestino,
    required String tipoCuenta,
    required MoneyValue valorPago,
    required String funcionarioProgramo,
    required TipoPago tipoPago,
    required int mesPAC, // Mes para el cual se programa el pago
  }) async {
    // Obtener la obligación
    final obligacion = await obtenerObligacion(obligacionId);
    if (obligacion == null) {
      throw Exception('Obligación no encontrada');
    }

    // VALIDACIÓN NORMATIVA: Verificar que se puede pagar
    if (!obligacion.sePuedePagar()) {
      throw Exception(
        'La obligación no se puede pagar. '
        'Estado: ${obligacion.estado}, '
        'Tiene acta: ${obligacion.tieneActaRecibo()}, '
        'Tiene factura: ${obligacion.tieneFacturaValida()}',
      );
    }

    // VALIDACIÓN NORMATIVA: Verificar saldo pendiente
    if (obligacion.saldoPendiente < valorPago) {
      throw Exception(
        'Saldo pendiente insuficiente. '
        'Pendiente: ${obligacion.saldoPendiente}, '
        'Solicitado: $valorPago',
      );
    }

    // VALIDACIÓN NORMATIVA DURA: Verificar cupo PAC (Art. 74 EOP)
    // Esta validación se hará en el servicio de PAC
    // Aquí solo verificamos que el mes sea válido
    if (mesPAC < 1 || mesPAC > 12) {
      throw Exception('Mes PAC inválido: $mesPAC');
    }

    // Generar número de pago
    final numeroPago =
        'PAG-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaProgramacion = DateTime.now();

    final pago = Pago(
      id: _uuid.v4(),
      entidadId: entidadId,
      numeroPago: numeroPago,
      vigencia: obligacion.vigencia,
      obligacionId: obligacionId,
      numeroObligacion: obligacion.numeroObligacion,
      rpId: obligacion.rpId,
      numeroRP: obligacion.numeroRP,
      terceroId: terceroId,
      terceroNombre: terceroNombre,
      bancoDestino: bancoDestino,
      cuentaDestino: cuentaDestino,
      tipoCuenta: tipoCuenta,
      valorPago: valorPago,
      mesPAC: mesPAC,
      fechaProgramacion: fechaProgramacion,
      funcionarioAprobo: funcionarioProgramo, // Mismo que programa por defecto
      funcionarioProgramo: funcionarioProgramo,
      tipoPago: tipoPago,
      estado: EstadoPago.programado,
    );

    await db.insert('pagos', pago.toJson());

    await auditoriaService?.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'presupuesto',
      accion: 'programacion_pago',
      valorAnterior: {'obligacion_id': obligacionId},
      valorNuevo: {
        'pago_id': pago.id,
        'numero_pago': numeroPago,
        'valor': valorPago.toSql(),
        'mes_pac': mesPAC,
      },
      referenciaId: pago.id,
    );

    return pago;
  }

  /// Programa el pago de un recibido solo cuando ya esta regularizado con una
  /// obligacion presupuestal real. Nunca fabrica la obligacion retrospectiva.
  Future<Pago> programarPagoRecepcion({
    required String entidadId,
    required String usuarioId,
    required String recepcionId,
    required String terceroId,
    required String terceroNombre,
    required String bancoDestino,
    required String cuentaDestino,
    required String tipoCuenta,
    required MoneyValue valorPago,
    required String funcionarioProgramo,
    required TipoPago tipoPago,
    required int mesPAC,
  }) async {
    final recepciones = await db.query(
      'recepciones_satisfaccion',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [recepcionId, entidadId],
    );
    if (recepciones.isEmpty) throw StateError('Recepcion no encontrada.');
    final recepcion = recepciones.single;
    if (recepcion['bloquea_pago'] == 1 || recepcion['obligacion_id'] == null) {
      throw StateError(
        'Pago bloqueado: el recibido no tiene obligacion presupuestal regularizada.',
      );
    }
    return programarPago(
      entidadId: entidadId,
      usuarioId: usuarioId,
      obligacionId: recepcion['obligacion_id'].toString(),
      terceroId: terceroId,
      terceroNombre: terceroNombre,
      bancoDestino: bancoDestino,
      cuentaDestino: cuentaDestino,
      tipoCuenta: tipoCuenta,
      valorPago: valorPago,
      funcionarioProgramo: funcionarioProgramo,
      tipoPago: tipoPago,
      mesPAC: mesPAC,
    );
  }

  /// Consume una anualidad autorizada y la vincula a un RP ya expedido.
  Future<String> comprometerVigenciaFutura({
    required String entidadId,
    required String usuarioId,
    required String autorizacionId,
    required String rpId,
    required int anio,
    required MoneyValue monto,
  }) {
    return VigenciasFuturasService(db: db).comprometerVigenciaFutura(
      entidadId: entidadId,
      usuarioId: usuarioId,
      autorizacionId: autorizacionId,
      rpId: rpId,
      anio: anio,
      monto: monto,
    );
  }

  /// Obtiene un pago por ID
  Future<Pago?> obtenerPago(String id) async {
    final resultado = await db.query('pagos', where: 'id = ?', whereArgs: [id]);

    if (resultado.isEmpty) return null;
    return Pago.fromJson(resultado.first);
  }

  /// Aprobar Pago con segregación de funciones dura (Fail-Closed)
  Future<Pago> aprobarPago({
    required String entidadId,
    required String usuarioId,
    required String pagoId,
    required String usuarioIdCreador,
  }) async {
    final rolCreador = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioIdCreador,
    );

    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.aprobarPago,
      rolQuienCrea: rolCreador,
    );

    final res = await db.query('pagos', where: 'id = ?', whereArgs: [pagoId]);
    if (res.isEmpty) throw Exception('Pago no encontrado');
    final pago = Pago.fromJson(res.first);

    final fechaAprobacion = DateTime.now();
    await db.update(
      'pagos',
      {
        'estado': EstadoPago.aprobado.name,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [pagoId],
    );

    return Pago(
      id: pago.id,
      entidadId: pago.entidadId,
      numeroPago: pago.numeroPago,
      vigencia: pago.vigencia,
      obligacionId: pago.obligacionId,
      numeroObligacion: pago.numeroObligacion,
      rpId: pago.rpId,
      numeroRP: pago.numeroRP,
      terceroId: pago.terceroId,
      terceroNombre: pago.terceroNombre,
      bancoDestino: pago.bancoDestino,
      cuentaDestino: pago.cuentaDestino,
      tipoCuenta: pago.tipoCuenta,
      valorPago: pago.valorPago,
      mesPAC: pago.mesPAC,
      fechaProgramacion: pago.fechaProgramacion,
      fechaAprobacion: fechaAprobacion,
      funcionarioAprobo: usuarioId,
      funcionarioProgramo: pago.funcionarioProgramo,
      tipoPago: pago.tipoPago,
      estado: EstadoPago.aprobado,
    );
  }

  /// Ejecutar Pago (Tesorero) con segregación de funciones dura (Fail-Closed)
  Future<Pago> ejecutarPago({
    required String entidadId,
    required String usuarioId,
    required String pagoId,
    required String usuarioIdAprobador,
  }) async {
    final rolAprobador = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioIdAprobador,
    );

    await _validarPermisoYSegregacion(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.ejecutarPago,
      rolQuienCrea: rolAprobador,
    );

    return db.transaction((txn) async {
      final res = await txn.query(
        'pagos',
        where: 'id = ?',
        whereArgs: [pagoId],
      );
      if (res.isEmpty) throw Exception('Pago no encontrado');
      final pago = Pago.fromJson(res.first);

      if (pago.entidadId != entidadId) {
        throw Exception('El pago no pertenece a la entidad indicada');
      }
      if (pago.estado != EstadoPago.aprobado) {
        throw Exception('El pago debe estar aprobado antes de ejecutarse');
      }

      final obligaciones = await txn.query(
        'obligaciones',
        where: 'id = ? AND entidad_id = ?',
        whereArgs: [pago.obligacionId, entidadId],
      );
      if (obligaciones.isEmpty) throw Exception('Obligacion no encontrada');
      final obligacion = Obligacion.fromJson(obligaciones.first);
      if (obligacion.saldoPendiente < pago.valorPago) {
        throw Exception('Saldo pendiente insuficiente en la obligacion');
      }

      final apropiaciones = await txn.query(
        'apropiaciones',
        where: 'entidad_id = ? AND vigencia = ? AND codigo_rubro = ?',
        whereArgs: [entidadId, pago.vigencia, obligacion.codigoRubro],
      );
      if (apropiaciones.isEmpty) {
        throw Exception('Apropiacion no encontrada para el rubro del pago');
      }
      final apropiacion = Apropiacion.fromJson(apropiaciones.first);

      // All mutations and their audit entries share the SQLite transaction.
      final auditoriaTransaccional = AuditoriaService(txn);
      final pacService = PACService(
        db: txn,
        auditoriaService: auditoriaTransaccional,
      );
      final contabilidadService = ContabilidadNICSPService(
        db: txn,
        auditoriaService: auditoriaTransaccional,
      );

      await pacService.verificarCupoPAC(
        entidadId: entidadId,
        vigencia: pago.vigencia,
        mes: pago.mesPAC,
        codigoRubro: obligacion.codigoRubro,
        montoPago: pago.valorPago,
      );

      final fechaEjecucion = DateTime.now();
      final nuevoValorPagado = obligacion.valorPagado + pago.valorPago;
      final nuevoSaldoPendiente = obligacion.saldoPendiente - pago.valorPago;
      final nuevoEstadoObligacion = nuevoSaldoPendiente == publicMoneyZero()
          ? EstadoObligacion.pagadaTotalmente
          : EstadoObligacion.pagadaParcialmente;

      await txn.update(
        'obligaciones',
        {
          'valor_pagado': nuevoValorPagado.toSql(),
          'saldo_pendiente': nuevoSaldoPendiente.toSql(),
          'estado': nuevoEstadoObligacion.name,
        },
        where: 'id = ?',
        whereArgs: [obligacion.id],
      );
      final vinculosVigenciaFutura = await txn.query(
        'obligaciones_vigencias_futuras',
        where: 'obligacion_id = ?',
        whereArgs: [obligacion.id],
      );
      if (vinculosVigenciaFutura.isNotEmpty) {
        final vinculo = vinculosVigenciaFutura.single;
        final nuevoPagadoVigencia =
            publicMoneyFromSql(vinculo['monto_pagado']) + pago.valorPago;
        final montoObligadoVigencia = publicMoneyFromSql(
          vinculo['monto_obligado'],
        );
        if (nuevoPagadoVigencia > montoObligadoVigencia) {
          throw StateError(
            'El pago excede la obligacion vinculada a la vigencia futura.',
          );
        }
        final compromisos = await txn.query(
          'compromisos_vigencias_futuras',
          where: 'id = ? AND entidad_id = ?',
          whereArgs: [vinculo['compromiso_id'], entidadId],
        );
        if (compromisos.isEmpty) {
          throw StateError('Compromiso de vigencia futura no encontrado.');
        }
        final compromiso = compromisos.single;
        await txn.update(
          'obligaciones_vigencias_futuras',
          {'monto_pagado': nuevoPagadoVigencia.toSql()},
          where: 'id = ?',
          whereArgs: [vinculo['id']],
        );
        await txn.rawUpdate(
          '''
          UPDATE compromisos_vigencias_futuras
          SET monto_pagado = monto_pagado + ?
          WHERE id = ?
          ''',
          [pago.valorPago.toSql(), compromiso['id']],
        );
        await txn.rawUpdate(
          '''
          UPDATE vigencias_futuras_distribucion
          SET monto_pagado = monto_pagado + ?
          WHERE id = ?
          ''',
          [pago.valorPago.toSql(), compromiso['distribucion_id']],
        );
      }
      await txn.update(
        'apropiaciones',
        {'valor_pagado': (apropiacion.valorPagado + pago.valorPago).toSql()},
        where: 'id = ?',
        whereArgs: [apropiacion.id],
      );
      await txn.update(
        'pagos',
        {
          'estado': EstadoPago.pagado.name,
          'fecha_ejecucion': fechaEjecucion.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [pago.id],
      );

      await pacService.actualizarPagoPAC(
        entidadId: entidadId,
        usuarioId: usuarioId,
        vigencia: pago.vigencia,
        mes: pago.mesPAC,
        codigoRubro: obligacion.codigoRubro,
        montoPago: pago.valorPago,
      );
      await contabilidadService.generarAsientoPago(
        entidadId: entidadId,
        usuarioId: usuarioId,
        fechaPago: fechaEjecucion,
        pagoId: pago.id,
        numeroPago: pago.numeroPago,
        terceroNombre: pago.terceroNombre,
        valorPago: pago.valorPago,
        cuentaBanco: '1110',
        nombreCuentaBanco: 'Efectivo y equivalentes de efectivo',
      );

      return pago.copyWith(
        fechaEjecucion: fechaEjecucion,
        estado: EstadoPago.pagado,
      );
    });
  }

  // ==================== UTILIDADES ====================

  /// Genera un número secuencial para documentos
  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }

  /// Consulta apropiaciones por vigencia
  Future<List<Apropiacion>> consultarApropiaciones({
    required String entidadId,
    required String vigencia,
  }) async {
    final resultados = await db.query(
      'apropiaciones',
      where: 'entidad_id = ? AND vigencia = ? AND activo = 1',
      whereArgs: [entidadId, vigencia],
      orderBy: 'codigo_rubro',
    );

    return resultados.map((r) => Apropiacion.fromJson(r)).toList();
  }

  /// Consulta CDPs por apropiación
  Future<List<CDP>> consultarCDPsPorApropiacion(String apropiacionId) async {
    final resultados = await db.query(
      'cdps',
      where: 'apropiacion_id = ?',
      whereArgs: [apropiacionId],
      orderBy: 'fecha_expedicion DESC',
    );

    return resultados.map((r) => CDP.fromJson(r)).toList();
  }

  /// Consulta RPs por CDP
  Future<List<RP>> consultarRPsPorCDP(String cdpId) async {
    final resultados = await db.query(
      'rps',
      where: 'cdp_id = ?',
      whereArgs: [cdpId],
      orderBy: 'fecha_expedicion DESC',
    );

    return resultados.map((r) => RP.fromJson(r)).toList();
  }

  /// Consulta obligaciones por RP
  Future<List<Obligacion>> consultarObligacionesPorRP(String rpId) async {
    final resultados = await db.query(
      'obligaciones',
      where: 'rp_id = ?',
      whereArgs: [rpId],
      orderBy: 'fecha_reconocimiento DESC',
    );

    return resultados.map((r) => Obligacion.fromJson(r)).toList();
  }

  /// Consulta pagos por obligación
  Future<List<Pago>> consultarPagosPorObligacion(String obligacionId) async {
    final resultados = await db.query(
      'pagos',
      where: 'obligacion_id = ?',
      whereArgs: [obligacionId],
      orderBy: 'fecha_programacion DESC',
    );

    return resultados.map((r) => Pago.fromJson(r)).toList();
  }
}
