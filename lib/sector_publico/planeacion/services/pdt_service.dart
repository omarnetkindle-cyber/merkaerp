/// Servicio de PDT (Plan de Desarrollo Territorial)
/// Plan de Desarrollo Territorial - 4 años
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/pdt.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class PDTService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  PDTService({
    required this.db,
    required this.auditoriaService,
  });

  /// Crea un PDT
  Future<PDT> crearPDT({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String nombrePDT,
    required String vision,
    required String mision,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    final id = _uuid.v4();

    final pdt = PDT(
      id: id,
      entidadId: entidadId,
      vigencia: vigencia,
      nombrePDT: nombrePDT,
      vision: vision,
      mision: mision,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      estado: EstadoPDT.borrador,
    );

    await db.insert('pdt', pdt.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'planeacion',
      accion: 'creacion_pdt',
      valorAnterior: {},
      valorNuevo: {
        'pdt_id': id,
        'nombre_pdt': nombrePDT,
        'vigencia': vigencia,
      },
      referenciaId: id,
    );

    return pdt;
  }

  /// Aprueba PDT en Concejo
  Future<PDT> aprobarPDTConcejo({
    required String entidadId,
    required String usuarioId,
    required String pdtId,
    required String actoAdministrativo,
  }) async {
    final pdtResult = await db.query(
      'pdt',
      where: 'id = ?',
      whereArgs: [pdtId],
    );

    if (pdtResult.isEmpty) {
      throw Exception('PDT no encontrado');
    }

    final pdt = PDT.fromJson(pdtResult.first);

    if (pdt.estado != EstadoPDT.borrador) {
      throw Exception('Solo se pueden aprobar PDT en estado borrador');
    }

    final fechaAprobacion = DateTime.now();

    await db.update(
      'pdt',
      {
        'estado': EstadoPDT.aprobadoConcejo.toString().split('.').last,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
        'acto_administrativo': actoAdministrativo,
      },
      where: 'id = ?',
      whereArgs: [pdtId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'aprobacion_pdt_concejo',
      valorAnterior: {'estado_anterior': pdt.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoPDT.aprobadoConcejo.toString(),
        'acto_administrativo': actoAdministrativo,
      },
      referenciaId: pdtId,
    );

    return pdt.copyWith(
      estado: EstadoPDT.aprobadoConcejo,
      fechaAprobacion: fechaAprobacion,
      actoAdministrativo: actoAdministrativo,
    );
  }

  /// Aprueba PDT a nivel departamental
  Future<PDT> aprobarPDTDepartamental({
    required String entidadId,
    required String usuarioId,
    required String pdtId,
    required String actoAdministrativo,
  }) async {
    final pdtResult = await db.query(
      'pdt',
      where: 'id = ?',
      whereArgs: [pdtId],
    );

    if (pdtResult.isEmpty) {
      throw Exception('PDT no encontrado');
    }

    final pdt = PDT.fromJson(pdtResult.first);

    if (!pdt.requiereAprobacionDepartamental()) {
      throw Exception('El PDT debe estar aprobado por Concejo primero');
    }

    final fechaAprobacion = DateTime.now();

    await db.update(
      'pdt',
      {
        'estado': EstadoPDT.aprobadoDepartamental.toString().split('.').last,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
        'acto_administrativo': actoAdministrativo,
      },
      where: 'id = ?',
      whereArgs: [pdtId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'aprobacion_pdt_departamental',
      valorAnterior: {'estado_anterior': pdt.estado.toString()},
      valorNuevo: {
        'estado_nuevo': EstadoPDT.aprobadoDepartamental.toString(),
        'acto_administrativo': actoAdministrativo,
      },
      referenciaId: pdtId,
    );

    return pdt.copyWith(
      estado: EstadoPDT.aprobadoDepartamental,
      fechaAprobacion: fechaAprobacion,
      actoAdministrativo: actoAdministrativo,
    );
  }

  Future<PDT?> obtenerPDTVigente(String entidadId) async {
    final resultado = await db.query(
      'pdt',
      where: 'entidad_id = ? AND estado = ?',
      whereArgs: [entidadId, EstadoPDT.vigente.toString().split('.').last],
    );

    if (resultado.isEmpty) return null;
    return PDT.fromJson(resultado.first);
  }

  Future<List<PDT>> consultarPDT({
    required String entidadId,
    EstadoPDT? estado,
  }) async {
    String query = 'SELECT * FROM pdt WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_inicio DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => PDT.fromJson(r)).toList();
  }
}

