import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';

class PartidaReciprocaInput {
  const PartidaReciprocaInput({
    required this.detalleAsientoId,
    required this.montoEliminar,
  });

  final String detalleAsientoId;
  final MoneyValue montoEliminar;
}

/// Registra aprobaciones humanas de partidas reciprocas para NICSP 40.
/// Los asientos fuente nunca se modifican: la conciliacion solo afecta la
/// presentacion consolidada.
class ConciliacionReciprocasService {
  ConciliacionReciprocasService({required this.db});

  final Database db;
  final Uuid _uuid = const Uuid();

  Future<String> aprobarConciliacion({
    required String entidadConsolidadoraId,
    required String vigencia,
    required String usuarioId,
    required List<PartidaReciprocaInput> partidas,
    required MoneyValue toleranciaMonto,
    required int toleranciaDias,
    String? observaciones,
  }) async {
    if (partidas.length < 2) {
      throw StateError('La conciliacion requiere al menos dos partidas.');
    }
    if (toleranciaMonto < publicMoneyZero() || toleranciaDias < 0) {
      throw ArgumentError('Las tolerancias no pueden ser negativas.');
    }
    if (partidas.any((partida) => partida.montoEliminar <= publicMoneyZero())) {
      throw ArgumentError('Cada monto a eliminar debe ser mayor que cero.');
    }
    if (partidas.map((p) => p.detalleAsientoId).toSet().length !=
        partidas.length) {
      throw StateError('Una partida contable no puede repetirse.');
    }

    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadConsolidadoraId,
      usuarioId: usuarioId,
    );
    if (rol == null ||
        !RolesPermisosService.tienePermiso(
          rol,
          Permiso.aprobarConciliacionReciproca,
        )) {
      throw StateError(
        'El usuario no tiene permiso para aprobar conciliaciones reciprocas.',
      );
    }

    final ids = partidas.map((p) => p.detalleAsientoId).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final filas = await db.rawQuery('''
      SELECT d.id AS detalle_id, d.asiento_id, d.debito, d.credito,
             a.entidad_id, a.fecha_asiento, a.estado, a.numero_asiento,
             d.cuenta_codigo, d.cuenta_nombre
      FROM detalles_asientos d
      INNER JOIN asientos_contables_sp a ON a.id = d.asiento_id
      WHERE d.id IN ($placeholders)
    ''', ids);
    if (filas.length != ids.length) {
      throw StateError('Una o mas partidas contables no existen.');
    }

    final entidadesPermitidas = await _entidadesJerarquia(
      entidadConsolidadoraId,
    );
    final filasPorId = {
      for (final fila in filas) fila['detalle_id'].toString(): fila,
    };
    final asientos = <String>{};
    final entidades = <String>{};
    final fechas = <DateTime>[];
    var totalDebito = publicMoneyZero();
    var totalCredito = publicMoneyZero();
    final partidasValidadas = <Map<String, dynamic>>[];

    for (final input in partidas) {
      final fila = filasPorId[input.detalleAsientoId]!;
      final entidadId = fila['entidad_id'].toString();
      if (!entidadesPermitidas.contains(entidadId)) {
        throw StateError(
          'La partida ${input.detalleAsientoId} no pertenece a la jerarquia consolidada.',
        );
      }
      final estado = fila['estado'].toString();
      if (estado != 'registrado' && estado != 'cuadrado') {
        throw StateError(
          'El asiento ${fila['numero_asiento']} no esta registrado para consolidar.',
        );
      }
      final fecha = DateTime.parse(fila['fecha_asiento'].toString());
      if (fecha.year.toString() != vigencia) {
        throw StateError('Todas las partidas deben pertenecer a la vigencia.');
      }

      final debito = publicMoneyFromSql(fila['debito'], nullableAsZero: true);
      final credito = publicMoneyFromSql(fila['credito'], nullableAsZero: true);
      final lado = debito > publicMoneyZero() && credito == publicMoneyZero()
          ? 'debito'
          : credito > publicMoneyZero() && debito == publicMoneyZero()
          ? 'credito'
          : null;
      if (lado == null) {
        throw StateError(
          'La partida ${input.detalleAsientoId} no tiene un unico lado contable.',
        );
      }
      final disponible = lado == 'debito' ? debito : credito;
      final eliminacionesPrevias = await db.rawQuery('''
        SELECT COALESCE(SUM(p.monto_eliminar), 0) AS total
        FROM conciliaciones_reciprocas_partidas p
        INNER JOIN conciliaciones_reciprocas c ON c.id = p.conciliacion_id
        WHERE p.detalle_asiento_id = ? AND c.estado = 'aprobada'
      ''', [input.detalleAsientoId]);
      final yaEliminado = publicMoneyFromSql(
        eliminacionesPrevias.first['total'],
        nullableAsZero: true,
      );
      if (input.montoEliminar > disponible - yaEliminado) {
        throw StateError(
          'El monto a eliminar excede el valor de la partida ${input.detalleAsientoId}.',
        );
      }

      if (lado == 'debito') {
        totalDebito += input.montoEliminar;
      } else {
        totalCredito += input.montoEliminar;
      }
      asientos.add(fila['asiento_id'].toString());
      entidades.add(entidadId);
      fechas.add(fecha);
      partidasValidadas.add({
        ...fila,
        'lado': lado,
        'monto_eliminar': input.montoEliminar,
      });
    }

    if (asientos.length < 2 || entidades.length < 2) {
      throw StateError(
        'La conciliacion debe relacionar asientos de al menos dos entidades.',
      );
    }
    if (totalDebito == publicMoneyZero() || totalCredito == publicMoneyZero()) {
      throw StateError(
        'La conciliacion requiere debitos y creditos reciprocos.',
      );
    }

    fechas.sort();
    final diferenciaDias = fechas.last.difference(fechas.first).inDays;
    final diferenciaMonto = (totalDebito - totalCredito).abs();
    if (diferenciaDias > toleranciaDias) {
      throw StateError(
        'La diferencia de fechas excede la tolerancia aprobada.',
      );
    }
    if (diferenciaMonto > toleranciaMonto) {
      throw StateError(
        'La diferencia de montos excede la tolerancia aprobada.',
      );
    }

    final id = _uuid.v4();
    final fechaAprobacion = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert('conciliaciones_reciprocas', {
        'id': id,
        'entidad_consolidadora_id': entidadConsolidadoraId,
        'vigencia': vigencia,
        'monto_conciliado': (totalDebito < totalCredito ? totalDebito : totalCredito).toSql(),
        'tolerancia_monto': toleranciaMonto.toSql(),
        'tolerancia_dias': toleranciaDias,
        'diferencia_monto_validada': diferenciaMonto.toSql(),
        'diferencia_dias_validada': diferenciaDias,
        'aprobado_por': usuarioId,
        'fecha_aprobacion': fechaAprobacion,
        'estado': 'aprobada',
        'observaciones': observaciones,
      });
      for (final partida in partidasValidadas) {
        await txn.insert('conciliaciones_reciprocas_partidas', {
          'id': _uuid.v4(),
          'conciliacion_id': id,
          'entidad_id': partida['entidad_id'],
          'asiento_id': partida['asiento_id'],
          'detalle_asiento_id': partida['detalle_id'],
          'lado': partida['lado'],
          'monto_eliminar': (partida['monto_eliminar'] as MoneyValue).toSql(),
        });
      }
      await AuditoriaService(txn).registrarEvento(
        entidadId: entidadConsolidadoraId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.asientoContable,
        modulo: 'contabilidad_nicsp40',
        accion: 'APROBAR_CONCILIACION_RECIPROCA',
        valorAnterior: const {},
        valorNuevo: {
          'conciliacion_id': id,
          'vigencia': vigencia,
          'asientos': asientos.toList(),
          'monto_conciliado': (totalDebito < totalCredito ? totalDebito : totalCredito).toSql(),
          'tolerancia_monto': toleranciaMonto.toSql(),
          'tolerancia_dias': toleranciaDias,
        },
        referenciaId: id,
        observaciones: observaciones,
      );
    });
    return id;
  }

  Future<Set<String>> _entidadesJerarquia(String entidadConsolidadoraId) async {
    final filas = await db.rawQuery(
      '''
      SELECT id FROM entidades_territoriales
      WHERE activo = 1 AND (id = ? OR gobernacion_id = ?)
    ''',
      [entidadConsolidadoraId, entidadConsolidadoraId],
    );
    if (!filas.any((fila) => fila['id'] == entidadConsolidadoraId)) {
      throw StateError('La entidad consolidadora no existe o no esta activa.');
    }
    return filas.map((fila) => fila['id'].toString()).toSet();
  }

  Future<List<Map<String, dynamic>>> listarPartidas({
    required String entidadConsolidadoraId,
    required String vigencia,
  }) async {
    final entidades = await _entidadesJerarquia(entidadConsolidadoraId);
    final placeholders = List.filled(entidades.length, '?').join(',');
    return db.rawQuery(
      '''
      SELECT d.id AS detalle_id, d.asiento_id, a.numero_asiento, a.entidad_id,
             a.fecha_asiento, d.cuenta_codigo, d.cuenta_nombre,
             d.debito, d.credito
      FROM detalles_asientos d
      INNER JOIN asientos_contables_sp a ON a.id = d.asiento_id
      LEFT JOIN conciliaciones_reciprocas_partidas crp
        ON crp.detalle_asiento_id = d.id
      LEFT JOIN conciliaciones_reciprocas cr ON cr.id = crp.conciliacion_id
      WHERE a.entidad_id IN ($placeholders)
        AND SUBSTR(a.fecha_asiento, 1, 4) = ?
        AND a.estado IN ('registrado', 'cuadrado')
      GROUP BY d.id, d.asiento_id, a.numero_asiento, a.entidad_id,
               a.fecha_asiento, d.cuenta_codigo, d.cuenta_nombre,
               d.debito, d.credito
      HAVING COALESCE(SUM(
        CASE WHEN cr.estado = 'aprobada' THEN crp.monto_eliminar ELSE 0 END
      ), 0) < CASE WHEN d.debito > 0 THEN d.debito ELSE d.credito END
      ORDER BY a.fecha_asiento DESC, a.numero_asiento, d.cuenta_codigo
    ''',
      [...entidades, vigencia],
    );
  }

  Future<List<Map<String, dynamic>>> listarConciliaciones({
    required String entidadConsolidadoraId,
    required String vigencia,
  }) {
    return db.rawQuery(
      '''
      SELECT c.*, COUNT(p.id) AS total_partidas
      FROM conciliaciones_reciprocas c
      INNER JOIN conciliaciones_reciprocas_partidas p
        ON p.conciliacion_id = c.id
      WHERE c.entidad_consolidadora_id = ? AND c.vigencia = ?
      GROUP BY c.id
      ORDER BY c.fecha_aprobacion DESC
    ''',
      [entidadConsolidadoraId, vigencia],
    );
  }
}
