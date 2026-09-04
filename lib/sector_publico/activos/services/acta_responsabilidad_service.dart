/// Servicio de Actas de Responsabilidad de Activos Publicos (Cuentadantes).
///
/// Maneja generacion, firma, entrega, traslado y devolucion de bienes.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../models/acta_responsabilidad.dart';

class ActaResponsabilidadService {
  ActaResponsabilidadService({
    required this.db,
    required this.auditoriaService,
  });

  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  /// API compatible con la UI existente: genera el acta y la firma/entrega
  /// en una sola operacion, dejando visible el ciclo en la base de datos.
  Future<ActaResponsabilidad> asignarResponsabilidad({
    required String entidadId,
    required String usuarioId,
    required String activoId,
    required String funcionarioId,
    required String funcionarioNombre,
    required String funcionarioIdentificacion,
    required String dependencia,
    required String ubicacionFisica,
    String? observaciones,
  }) async {
    final pendiente = await generarActaPendiente(
      entidadId: entidadId,
      usuarioId: usuarioId,
      activoId: activoId,
      funcionarioId: funcionarioId,
      funcionarioNombre: funcionarioNombre,
      funcionarioIdentificacion: funcionarioIdentificacion,
      dependencia: dependencia,
      ubicacionFisica: ubicacionFisica,
      observaciones: observaciones,
    );

    return firmarYEntregarActa(
      entidadId: entidadId,
      usuarioId: usuarioId,
      actaId: pendiente.id,
      firmadoPorFuncionario: funcionarioNombre,
      firmadoPorAlmacen: usuarioId,
    );
  }

  Future<ActaResponsabilidad> generarActaPendiente({
    required String entidadId,
    required String usuarioId,
    required String activoId,
    required String funcionarioId,
    required String funcionarioNombre,
    required String funcionarioIdentificacion,
    required String dependencia,
    required String ubicacionFisica,
    String? observaciones,
  }) async {
    final activo = await db.query(
      'activos_estado',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [activoId, entidadId],
      limit: 1,
    );
    if (activo.isEmpty) throw Exception('Activo no encontrado');

    final id = _uuid.v4();
    final now = DateTime.now();
    final numeroActa =
        'ACTA-${now.year}-${now.microsecondsSinceEpoch.toString().substring(8)}';

    final acta = ActaResponsabilidad(
      id: id,
      entidadId: entidadId,
      numeroActa: numeroActa,
      activoId: activoId,
      funcionarioId: funcionarioId,
      funcionarioNombre: funcionarioNombre,
      funcionarioIdentificacion: funcionarioIdentificacion,
      dependencia: dependencia,
      ubicacionFisica: ubicacionFisica,
      fechaAsignacion: now,
      estadoActa: EstadoActaResponsabilidad.pendienteFirma,
      observaciones: observaciones,
    );

    await db.insert('actas_responsabilidad', acta.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'activos',
      accion: 'generar_acta_responsabilidad',
      valorAnterior: {},
      valorNuevo: {
        'acta_id': id,
        'numero_acta': numeroActa,
        'activo_id': activoId,
        'funcionario_nombre': funcionarioNombre,
        'estado_acta': acta.estadoActa.name,
      },
      referenciaId: id,
    );

    return acta;
  }

  Future<ActaResponsabilidad> firmarYEntregarActa({
    required String entidadId,
    required String usuarioId,
    required String actaId,
    required String firmadoPorFuncionario,
    required String firmadoPorAlmacen,
  }) async {
    final acta = await _obtenerActa(entidadId: entidadId, actaId: actaId);
    if (acta.estadoActa != EstadoActaResponsabilidad.pendienteFirma) {
      throw StateError(
        'Solo un acta pendiente de firma puede ser firmada y entregada.',
      );
    }

    final now = DateTime.now();
    final hashActa = _calcularHashActa(
      acta,
      firmadoPorFuncionario: firmadoPorFuncionario,
      firmadoPorAlmacen: firmadoPorAlmacen,
      fechaEntrega: now,
    );
    final firmada = acta.copyWith(
      fechaEntrega: now,
      firmadoPorFuncionario: firmadoPorFuncionario,
      fechaFirmaFuncionario: now,
      firmadoPorAlmacen: firmadoPorAlmacen,
      fechaFirmaAlmacen: now,
      hashActa: hashActa,
      estadoActa: EstadoActaResponsabilidad.activa,
    );

    await db.update(
      'actas_responsabilidad',
      firmada.toJson(),
      where: 'id = ?',
      whereArgs: [actaId],
    );

    await db.update(
      'activos_estado',
      {
        'responsable': acta.funcionarioNombre,
        'ubicacion': acta.ubicacionFisica,
      },
      where: 'id = ?',
      whereArgs: [acta.activoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'firmar_entregar_acta_responsabilidad',
      valorAnterior: {'estado_acta': acta.estadoActa.name},
      valorNuevo: {
        'acta_id': actaId,
        'estado_acta': firmada.estadoActa.name,
        'fecha_entrega': now.toIso8601String(),
        'hash_acta': hashActa,
      },
      referenciaId: actaId,
    );

    return firmada;
  }

  Future<ActaResponsabilidad> devolverResponsabilidad({
    required String entidadId,
    required String usuarioId,
    required String actaId,
    String? observaciones,
  }) async {
    final acta = await _obtenerActa(entidadId: entidadId, actaId: actaId);
    if (acta.estadoActa != EstadoActaResponsabilidad.activa) {
      throw StateError('Solo un acta activa puede ser devuelta.');
    }

    final devuelta = acta.copyWith(
      fechaDevolucion: DateTime.now(),
      estadoActa: EstadoActaResponsabilidad.devuelta,
      observaciones: observaciones,
    );

    await db.update(
      'actas_responsabilidad',
      devuelta.toJson(),
      where: 'id = ?',
      whereArgs: [actaId],
    );
    await db.update(
      'activos_estado',
      {'responsable': null, 'ubicacion': null},
      where: 'id = ?',
      whereArgs: [acta.activoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'devolver_acta_responsabilidad',
      valorAnterior: {'estado_acta': acta.estadoActa.name},
      valorNuevo: {'acta_id': actaId, 'estado_acta': devuelta.estadoActa.name},
      referenciaId: actaId,
    );

    return devuelta;
  }

  Future<ActaResponsabilidad> trasladarResponsabilidad({
    required String entidadId,
    required String usuarioId,
    required String actaId,
    required String nuevoFuncionarioId,
    required String nuevoFuncionarioNombre,
    required String nuevoFuncionarioIdentificacion,
    required String nuevaDependencia,
    required String nuevaUbicacionFisica,
  }) async {
    final actaAnterior = await _obtenerActa(
      entidadId: entidadId,
      actaId: actaId,
    );
    if (actaAnterior.estadoActa != EstadoActaResponsabilidad.activa) {
      throw StateError('Solo un acta activa puede ser trasladada.');
    }

    await db.update(
      'actas_responsabilidad',
      {
        'estado_acta': EstadoActaResponsabilidad.trasladada.name,
        'fecha_devolucion': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [actaId],
    );

    return asignarResponsabilidad(
      entidadId: entidadId,
      usuarioId: usuarioId,
      activoId: actaAnterior.activoId,
      funcionarioId: nuevoFuncionarioId,
      funcionarioNombre: nuevoFuncionarioNombre,
      funcionarioIdentificacion: nuevoFuncionarioIdentificacion,
      dependencia: nuevaDependencia,
      ubicacionFisica: nuevaUbicacionFisica,
      observaciones: 'Traspaso desde acta #${actaAnterior.numeroActa}',
    );
  }

  Future<List<ActaResponsabilidad>> consultarActas({
    required String entidadId,
    String? activoId,
  }) async {
    var query = 'SELECT * FROM actas_responsabilidad WHERE entidad_id = ?';
    final args = <dynamic>[entidadId];

    if (activoId != null) {
      query += ' AND activo_id = ?';
      args.add(activoId);
    }

    query += ' ORDER BY fecha_asignacion DESC';
    final result = await db.rawQuery(query, args);
    return result.map((r) => ActaResponsabilidad.fromJson(r)).toList();
  }

  Future<String> exportarActaAPlano(String actaId) async {
    final res = await db.query(
      'actas_responsabilidad',
      where: 'id = ?',
      whereArgs: [actaId],
    );
    if (res.isEmpty) throw Exception('Acta de responsabilidad no encontrada');
    final acta = ActaResponsabilidad.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'ACTA_RESPONSABILIDAD_HEADER|${acta.numeroActa}|${acta.entidadId}|${acta.fechaAsignacion.toIso8601String()}|${acta.versionFormato}',
    );
    buffer.writeln(
      'CUENTADANTE|${acta.funcionarioIdentificacion}|${acta.funcionarioNombre}|${acta.dependencia}',
    );
    buffer.writeln('UBICACION|${acta.ubicacionFisica}');
    buffer.writeln('ACTIVO_ID|${acta.activoId}');
    buffer.writeln('ESTADO|${acta.estadoActa.name}');
    buffer.writeln(
      'FECHA_ENTREGA|${acta.fechaEntrega?.toIso8601String() ?? ''}',
    );
    buffer.writeln('FIRMA_FUNCIONARIO|${acta.firmadoPorFuncionario ?? ''}');
    buffer.writeln('FIRMA_ALMACEN|${acta.firmadoPorAlmacen ?? ''}');
    buffer.writeln('HASH_ACTA|${acta.hashActa ?? ''}');
    buffer.writeln('ACTA_RESPONSABILIDAD_FOOTER|FIN_DOCUMENTO');

    return buffer.toString();
  }

  Future<ActaResponsabilidad> _obtenerActa({
    required String entidadId,
    required String actaId,
  }) async {
    final res = await db.query(
      'actas_responsabilidad',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [actaId, entidadId],
      limit: 1,
    );
    if (res.isEmpty) throw Exception('Acta de responsabilidad no encontrada');
    return ActaResponsabilidad.fromJson(res.single);
  }

  String _calcularHashActa(
    ActaResponsabilidad acta, {
    required String firmadoPorFuncionario,
    required String firmadoPorAlmacen,
    required DateTime fechaEntrega,
  }) {
    final payload = jsonEncode({
      'numero_acta': acta.numeroActa,
      'entidad_id': acta.entidadId,
      'activo_id': acta.activoId,
      'funcionario_id': acta.funcionarioId,
      'funcionario_identificacion': acta.funcionarioIdentificacion,
      'ubicacion_fisica': acta.ubicacionFisica,
      'fecha_entrega': fechaEntrega.toIso8601String(),
      'firmado_por_funcionario': firmadoPorFuncionario,
      'firmado_por_almacen': firmadoPorAlmacen,
      'version_formato': acta.versionFormato,
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}
