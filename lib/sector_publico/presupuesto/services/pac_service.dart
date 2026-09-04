/// Servicio de Programa Anual Mensualizado de Caja (PAC)
/// Implementa validaciones según Art. 74-76 Decreto 111/1996
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import '../models/pac.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';

class PACService {
  final DatabaseExecutor db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  PACService({
    required this.db,
    required this.auditoriaService,
  });

  Future<RolSectorPublico> _validarPermiso({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    if (rol == null) {
      throw Exception('Acceso denegado: El usuario $usuarioId no tiene un rol asignado en la entidad $entidadId');
    }

    if (!RolesPermisosService.tienePermiso(rol, permiso)) {
      throw Exception('Acceso denegado: El rol ${rol.name} no tiene permiso para ${permiso.name}');
    }

    return rol;
  }

  /// Programa el PAC para un mes y rubro
  Future<PAC> programarPAC({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int mes,
    required String codigoRubro,
    required MoneyValue valorProgramado,
    required String funcionarioProgramo,
  }) async {
    await _validarPermiso(entidadId: entidadId, usuarioId: usuarioId, permiso: Permiso.modificarPAC);
    // Verificar si ya existe un PAC para este mes y rubro
    final existente = await db.query(
      'pac',
      where: 'entidad_id = ? AND vigencia = ? AND mes = ? AND codigo_rubro = ?',
      whereArgs: [entidadId, vigencia, mes, codigoRubro],
    );

    if (existente.isNotEmpty) {
      throw Exception('Ya existe un PAC programado para este mes y rubro');
    }

    final id = _uuid.v4();
    final fechaCreacion = DateTime.now();

    final pac = PAC(
      id: id,
      entidadId: entidadId,
      vigencia: vigencia,
      mes: mes,
      codigoRubro: codigoRubro,
      valorProgramado: valorProgramado,
      valorEjecutado: publicMoneyZero(),
      saldoDisponible: valorProgramado,
      fechaCreacion: fechaCreacion,
      estado: EstadoPAC.borrador,
    );

    await db.insert('pac', pac.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'tesoreria',
      accion: 'programacion_pac',
      valorAnterior: {},
      valorNuevo: pac.toJson(),
      referenciaId: id,
    );

    return pac;
  }

  /// Aprueba un PAC (requiere acto administrativo)
  /// VALIDACIÓN NORMATIVA: Requiere acto administrativo (Resolución)
  Future<PAC> aprobarPAC({
    required String entidadId,
    required String usuarioId,
    required String pacId,
    required String funcionarioAprobo,
    required String actoAdministrativo,
  }) async {
    final pac = await obtenerPAC(pacId);
    if (pac == null) {
      throw Exception('PAC no encontrado');
    }

    if (pac.estado != EstadoPAC.borrador && pac.estado != EstadoPAC.modificado) {
      throw Exception('Solo se pueden aprobar PAC en estado borrador o modificado');
    }

    final fechaAprobacion = DateTime.now();

    await db.update(
      'pac',
      {
        'estado': EstadoPAC.aprobado.toString().split('.').last,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
        'funcionario_aprobo': funcionarioAprobo,
        'acto_administrativo': actoAdministrativo,
      },
      where: 'id = ?',
      whereArgs: [pacId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'tesoreria',
      accion: 'aprobacion_pac',
      valorAnterior: {'estado_anterior': pac.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoPAC.aprobado.toString(),
        'acto_administrativo': actoAdministrativo,
      },
      referenciaId: pacId,
    );

    return pac.copyWith(
      estado: EstadoPAC.aprobado,
      fechaAprobacion: fechaAprobacion,
      funcionarioAprobo: funcionarioAprobo,
      actoAdministrativo: actoAdministrativo,
    );
  }

  /// Verifica cupo PAC para un pago
  /// VALIDACIÓN NORMATIVA DURA: Bloquea pagos que superen el cupo (Art. 74 EOP)
  Future<bool> verificarCupoPAC({
    required String entidadId,
    required String vigencia,
    required int mes,
    required String codigoRubro,
    required MoneyValue montoPago,
  }) async {
    final pac = await db.query(
      'pac',
      where: 'entidad_id = ? AND vigencia = ? AND mes = ? AND codigo_rubro = ? AND estado = ?',
      whereArgs: [
        entidadId,
        vigencia,
        mes,
        codigoRubro,
        EstadoPAC.aprobado.toString().split('.').last,
      ],
    );

    if (pac.isEmpty) {
      throw Exception(
        'No hay PAC aprobado para el mes $mes y rubro $codigoRubro. '
        'Art. 74 EOP: Ningún pago puede hacerse sin cupo PAC aprobado.'
      );
    }

    final pacData = PAC.fromJson(pac.first);

    if (!pacData.tieneCupoParaPago(montoPago)) {
      throw Exception(
        'Cupo PAC insuficiente para el pago. '
        'Cupo disponible: ${pacData.saldoDisponible}, '
        'Monto solicitado: $montoPago. '
        'Art. 74 EOP: El incumplimiento del PAC es causal de mala conducta.'
      );
    }

    return true;
  }

  /// Actualiza el PAC después de un pago
  Future<void> actualizarPagoPAC({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required int mes,
    required String codigoRubro,
    required MoneyValue montoPago,
  }) async {
    final pac = await db.query(
      'pac',
      where: 'entidad_id = ? AND vigencia = ? AND mes = ? AND codigo_rubro = ?',
      whereArgs: [entidadId, vigencia, mes, codigoRubro],
    );

    if (pac.isEmpty) return;

    final pacData = PAC.fromJson(pac.first);
    final nuevoValorEjecutado = pacData.valorEjecutado + montoPago;
    final nuevoSaldo = pacData.saldoDisponible - montoPago;

    await db.update(
      'pac',
      {
        'valor_ejecutado': nuevoValorEjecutado.toSql(),
        'saldo_disponible': nuevoSaldo.toSql(),
        'estado': nuevoSaldo == publicMoneyZero()
            ? EstadoPAC.ejecutado.toString().split('.').last 
            : pacData.estado.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [pacData.id],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.pago,
      modulo: 'tesoreria',
      accion: 'actualizacion_pac',
      valorAnterior: {
        'valor_ejecutado_anterior': pacData.valorEjecutado.toSql(),
        'saldo_anterior': pacData.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'valor_ejecutado_nuevo': nuevoValorEjecutado.toSql(),
        'saldo_nuevo': nuevoSaldo.toSql(),
        'monto_pago': montoPago.toSql(),
      },
      referenciaId: pacData.id,
    );
  }

  /// Modifica un PAC con acto administrativo
  /// VALIDACIÓN NORMATIVA: Requiere acto administrativo (Art. 76 EOP)
  Future<PAC> modificarPAC({
    required String entidadId,
    required String usuarioId,
    required String pacId,
    required MoneyValue nuevoValorProgramado,
    required String funcionarioModifico,
    required String actoAdministrativo,
  }) async {
    final pac = await obtenerPAC(pacId);
    if (pac == null) {
      throw Exception('PAC no encontrado');
    }

    if (!pac.estaAprobado()) {
      throw Exception('Solo se pueden modificar PAC aprobados');
    }

    // Verificar que no se reduzca por debajo de lo ya ejecutado
    if (nuevoValorProgramado < pac.valorEjecutado) {
      throw Exception(
        'No se puede reducir el PAC por debajo del valor ya ejecutado. '
        'Ejecutado: ${pac.valorEjecutado}, Nuevo valor: $nuevoValorProgramado'
      );
    }

    final nuevoSaldo = nuevoValorProgramado - pac.valorEjecutado;

    await db.update(
      'pac',
      {
        'valor_programado': nuevoValorProgramado.toSql(),
        'saldo_disponible': nuevoSaldo.toSql(),
        'estado': EstadoPAC.modificado.toString().split('.').last,
        'acto_administrativo': actoAdministrativo,
      },
      where: 'id = ?',
      whereArgs: [pacId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'tesoreria',
      accion: 'modificacion_pac',
      valorAnterior: {
        'valor_anterior': pac.valorProgramado.toSql(),
        'saldo_anterior': pac.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'valor_nuevo': nuevoValorProgramado.toSql(),
        'saldo_nuevo': nuevoSaldo.toSql(),
        'acto_administrativo': actoAdministrativo,
      },
      referenciaId: pacId,
    );

    return pac.copyWith(
      valorProgramado: nuevoValorProgramado,
      saldoDisponible: nuevoSaldo,
      estado: EstadoPAC.modificado,
      actoAdministrativo: actoAdministrativo,
    );
  }

  /// Traslada cupo entre meses del mismo año
  /// VALIDACIÓN NORMATIVA: Requiere acto administrativo (Art. 76 EOP)
  Future<void> trasladarCupoPAC({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String codigoRubro,
    required int mesOrigen,
    required int mesDestino,
    required MoneyValue montoTraslado,
    required String funcionarioAutoriza,
    required String actoAdministrativo,
  }) async {
    // Obtener PAC origen
    final pacOrigen = await db.query(
      'pac',
      where: 'entidad_id = ? AND vigencia = ? AND mes = ? AND codigo_rubro = ?',
      whereArgs: [entidadId, vigencia, mesOrigen, codigoRubro],
    );

    if (pacOrigen.isEmpty) {
      throw Exception('No existe PAC para el mes origen');
    }

    final pacOrigenData = PAC.fromJson(pacOrigen.first);

    if (pacOrigenData.saldoDisponible < montoTraslado) {
      throw Exception(
        'Saldo insuficiente en el mes origen. '
        'Disponible: ${pacOrigenData.saldoDisponible}, '
        'Traslado: $montoTraslado'
      );
    }

    // Obtener PAC destino
    final pacDestino = await db.query(
      'pac',
      where: 'entidad_id = ? AND vigencia = ? AND mes = ? AND codigo_rubro = ?',
      whereArgs: [entidadId, vigencia, mesDestino, codigoRubro],
    );

    if (pacDestino.isEmpty) {
      throw Exception('No existe PAC para el mes destino');
    }

    final pacDestinoData = PAC.fromJson(pacDestino.first);

    // Actualizar PAC origen
    await db.update(
      'pac',
      {
        'saldo_disponible': (pacOrigenData.saldoDisponible - montoTraslado).toSql(),
        'estado': EstadoPAC.modificado.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [pacOrigenData.id],
    );

    // Actualizar PAC destino
    await db.update(
      'pac',
      {
        'valor_programado': (pacDestinoData.valorProgramado + montoTraslado).toSql(),
        'saldo_disponible': (pacDestinoData.saldoDisponible + montoTraslado).toSql(),
        'estado': EstadoPAC.modificado.toString().split('.').last,
      },
      where: 'id = ?',
      whereArgs: [pacDestinoData.id],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'tesoreria',
      accion: 'traslado_cupo_pac',
      valorAnterior: {
        'mes_origen': mesOrigen,
        'saldo_origen_anterior': pacOrigenData.saldoDisponible.toSql(),
        'mes_destino': mesDestino,
        'saldo_destino_anterior': pacDestinoData.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'monto_traslado': montoTraslado.toSql(),
        'saldo_origen_nuevo': (pacOrigenData.saldoDisponible - montoTraslado).toSql(),
        'saldo_destino_nuevo': (pacDestinoData.saldoDisponible + montoTraslado).toSql(),
        'acto_administrativo': actoAdministrativo,
      },
    );
  }

  /// Registra un embargo judicial (informativo, por inembargabilidad)
  /// VALIDACIÓN NORMATIVA: Cuentas públicas son inembargables (Art. 19 EOP)
  Future<void> registrarEmbargoJudicial({
    required String entidadId,
    required String usuarioId,
    required String numeroProceso,
    required String juzgado,
    String? terceroId,
    required String terceroNombre,
    required MoneyValue valorEmbargo,
  }) async {
    final id = _uuid.v4();
    final fechaRegistro = DateTime.now();

    await db.insert('embargos_judiciales', {
      'id': id,
      'entidad_id': entidadId,
      'numero_proceso': numeroProceso,
      'juzgado': juzgado,
      'tercero_id': terceroId,
      'tercero_nombre': terceroNombre,
      'valor_embargo': valorEmbargo.toSql(),
      'fecha_registro': fechaRegistro.toIso8601String(),
      'activo': 1,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'tesoreria',
      accion: 'registro_embargo_judicial',
      valorAnterior: {},
      valorNuevo: {
        'numero_proceso': numeroProceso,
        'juzgado': juzgado,
        'valor_embargo': valorEmbargo.toSql(),
        'nota': 'Registro informativo - Cuentas públicas inembargables (Art. 19 EOP)',
      },
      referenciaId: id,
    );
  }

  /// Obtiene un PAC por ID
  Future<PAC?> obtenerPAC(String id) async {
    final resultado = await db.query(
      'pac',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return PAC.fromJson(resultado.first);
  }

  /// Consulta PAC por vigencia y mes
  Future<List<PAC>> consultarPAC({
    required String entidadId,
    required String vigencia,
    int? mes,
    String? codigoRubro,
  }) async {
    String query = 'SELECT * FROM pac WHERE entidad_id = ? AND vigencia = ?';
    List<dynamic> args = [entidadId, vigencia];

    if (mes != null) {
      query += ' AND mes = ?';
      args.add(mes);
    }

    if (codigoRubro != null) {
      query += ' AND codigo_rubro = ?';
      args.add(codigoRubro);
    }

    query += ' ORDER BY mes, codigo_rubro';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => PAC.fromJson(r)).toList();
  }

  /// Consulta el resumen de ejecución PAC por vigencia
  Future<Map<String, dynamic>> consultarResumenEjecucionPAC({
    required String entidadId,
    required String vigencia,
  }) async {
    final resultados = await db.rawQuery('''
      SELECT 
        mes,
        SUM(valor_programado) as total_programado,
        SUM(valor_ejecutado) as total_ejecutado,
        SUM(saldo_disponible) as total_saldo
      FROM pac
      WHERE entidad_id = ? AND vigencia = ?
      GROUP BY mes
      ORDER BY mes
    ''', [entidadId, vigencia]);

    return {
      'entidad_id': entidadId,
      'vigencia': vigencia,
      'resumen_mensual': resultados,
    };
  }
}
