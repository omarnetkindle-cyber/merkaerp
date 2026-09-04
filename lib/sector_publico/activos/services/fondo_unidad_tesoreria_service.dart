/// Servicio de Fondo de Unidad de Tesorería (FUT Local / Recursos de Terceros)
/// Manejo de recursos de terceros
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/fondo_unidad_tesoreria.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class FondoUnidadTesoreriaService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  FondoUnidadTesoreriaService({
    required this.db,
    required this.auditoriaService,
  });

  /// Crea un Fondo de Unidad de Tesorería (FUT)
  Future<FondoUnidadTesoreria> crearFUT({
    required String entidadId,
    required String usuarioId,
    required String nombreFUT,
    required TipoFondoUnidadTesoreria tipoFUT,
    required String terceroId,
    required String terceroNombre,
    required String terceroIdentificacion,
    required MoneyValue valorInicial,
    String? numeroContrato,
    String? numeroConvenio,
    String? responsable,
  }) async {
    final id = _uuid.v4();
    final numeroFUT = 'FUT-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaApertura = DateTime.now();

    final fut = FondoUnidadTesoreria(
      id: id,
      entidadId: entidadId,
      numeroFUT: numeroFUT,
      nombreFUT: nombreFUT,
      tipoFUT: tipoFUT,
      numeroContrato: numeroContrato,
      numeroConvenio: numeroConvenio,
      terceroId: terceroId,
      terceroNombre: terceroNombre,
      terceroIdentificacion: terceroIdentificacion,
      valorInicial: valorInicial,
      valorEjecutado: publicMoneyZero(),
      saldoDisponible: valorInicial,
      fechaApertura: fechaApertura,
      estado: EstadoFondoUnidadTesoreria.activo,
      responsable: responsable,
    );

    await db.insert('fondo_unidad_tesoreria', fut.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'activos',
      accion: 'creacion_fut',
      valorAnterior: {},
      valorNuevo: {
        'fut_id': id,
        'numero_fut': numeroFUT,
        'valor_inicial': valorInicial.toSql(),
      },
      referenciaId: id,
    );

    return fut;
  }

  /// Registra una ejecución en el FUT
  Future<FondoUnidadTesoreria> registrarEjecucion({
    required String entidadId,
    required String usuarioId,
    required String futId,
    required MoneyValue montoEjecucion,
  }) async {
    final futResult = await db.query(
      'fondo_unidad_tesoreria',
      where: 'id = ?',
      whereArgs: [futId],
    );

    if (futResult.isEmpty) {
      throw Exception('FUT no encontrado');
    }

    final fut = FondoUnidadTesoreria.fromJson(futResult.first);

    if (!fut.estaActivo()) {
      throw Exception('El FUT no está activo');
    }

    if (montoEjecucion > fut.saldoDisponible) {
      throw Exception('El monto excede el saldo disponible');
    }

    final nuevoValorEjecutado = fut.valorEjecutado + montoEjecucion;
    final nuevoSaldo = fut.saldoDisponible - montoEjecucion;

    await db.update(
      'fondo_unidad_tesoreria',
      {
        'valor_ejecutado': nuevoValorEjecutado.toSql(),
        'saldo_disponible': nuevoSaldo.toSql(),
        'estado': EstadoFondoUnidadTesoreria.enEjecucion.name,
      },
      where: 'id = ?',
      whereArgs: [futId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'ejecucion_fut',
      valorAnterior: {
        'valor_ejecutado_anterior': fut.valorEjecutado.toSql(),
        'saldo_anterior': fut.saldoDisponible.toSql(),
      },
      valorNuevo: {
        'monto_ejecucion': montoEjecucion.toSql(),
        'valor_ejecutado_nuevo': nuevoValorEjecutado.toSql(),
        'saldo_nuevo': nuevoSaldo.toSql(),
      },
      referenciaId: futId,
    );

    return FondoUnidadTesoreria(
      id: fut.id,
      entidadId: fut.entidadId,
      numeroFUT: fut.numeroFUT,
      nombreFUT: fut.nombreFUT,
      tipoFUT: fut.tipoFUT,
      numeroContrato: fut.numeroContrato,
      numeroConvenio: fut.numeroConvenio,
      terceroId: fut.terceroId,
      terceroNombre: fut.terceroNombre,
      terceroIdentificacion: fut.terceroIdentificacion,
      valorInicial: fut.valorInicial,
      valorEjecutado: nuevoValorEjecutado,
      saldoDisponible: nuevoSaldo,
      fechaApertura: fut.fechaApertura,
      fechaCierre: fut.fechaCierre,
      estado: EstadoFondoUnidadTesoreria.enEjecucion,
      responsable: fut.responsable,
      observaciones: fut.observaciones,
    );
  }

  Future<List<FondoUnidadTesoreria>> consultarFUT({
    required String entidadId,
    EstadoFondoUnidadTesoreria? estado,
  }) async {
    String query = 'SELECT * FROM fondo_unidad_tesoreria WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.name);
    }

    query += ' ORDER BY fecha_apertura DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => FondoUnidadTesoreria.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
