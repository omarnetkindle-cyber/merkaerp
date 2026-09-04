/// Servicio de auditoría append-only con hash encadenado
/// Implementa las reglas no negociables: nada se borra, todo se audita
library;

import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/registro_auditoria.dart';
import 'package:sqflite/sqflite.dart';

class AuditoriaService {
  final DatabaseExecutor? _db;
  final Uuid _uuid = const Uuid();

  AuditoriaService(this._db);

  /// Registra un evento de auditoría de forma append-only
  /// Nunca se permite eliminación física de registros
  Future<RegistroAuditoria> registrarEvento({
    required String entidadId,
    required String usuarioId,
    String? usuarioNombre,
    String? ipDireccion,
    required TipoEventoAuditoria tipoEvento,
    required String modulo,
    required String accion,
    required Map<String, dynamic> valorAnterior,
    required Map<String, dynamic> valorNuevo,
    String? referenciaId,
    String? observaciones,
  }) async {
    if (_db == null) {
      throw Exception('Base de datos no inicializada');
    }

    // Obtener el último hash para encadenamiento
    final ultimoHash = await _obtenerUltimoHash(entidadId);

    // Crear el registro de auditoría
    final id = _uuid.v4();
    final fechaHora = DateTime.now();
    
    final datosRegistro = {
      'id': id,
      'entidad_id': entidadId,
      'usuario_id': usuarioId,
      'usuario_nombre': usuarioNombre,
      'ip_direccion': ipDireccion,
      'fecha_hora': fechaHora.toIso8601String(),
      'tipo_evento': tipoEvento.toString().split('.').last,
      'modulo': modulo,
      'accion': accion,
      'valor_anterior': valorAnterior,
      'valor_nuevo': valorNuevo,
      'hash_anterior': ultimoHash,
      'referencia_id': referenciaId,
      'observaciones': observaciones,
    };

    // Calcular hash actual
    final hashActual = RegistroAuditoria.calcularHash(datosRegistro);
    datosRegistro['hash_actual'] = hashActual;

    // Insertar en base de datos (append-only)
    await _db.insert(
      'auditoria_registros',
      {
        'id': id,
        'entidad_id': entidadId,
        'usuario_id': usuarioId,
        'usuario_nombre': usuarioNombre,
        'ip_direccion': ipDireccion,
        'fecha_hora': fechaHora.toIso8601String(),
        'tipo_evento': tipoEvento.toString().split('.').last,
        'modulo': modulo,
        'accion': accion,
        'valor_anterior': jsonEncode(valorAnterior),
        'valor_nuevo': jsonEncode(valorNuevo),
        'hash_anterior': ultimoHash,
        'hash_actual': hashActual,
        'referencia_id': referenciaId,
        'observaciones': observaciones,
      },
    );

    return RegistroAuditoria(
      id: id,
      entidadId: entidadId,
      usuarioId: usuarioId,
      usuarioNombre: usuarioNombre,
      ipDireccion: ipDireccion,
      fechaHora: fechaHora,
      tipoEvento: tipoEvento,
      modulo: modulo,
      accion: accion,
      valorAnterior: valorAnterior,
      valorNuevo: valorNuevo,
      hashAnterior: ultimoHash,
      hashActual: hashActual,
      referenciaId: referenciaId,
      observaciones: observaciones,
    );
  }

  /// Obtiene el hash del último registro de auditoría para una entidad
  Future<String?> _obtenerUltimoHash(String entidadId) async {
    if (_db == null) return null;

    final result = await _db.rawQuery('''
      SELECT hash_actual 
      FROM auditoria_registros 
      WHERE entidad_id = ? 
      ORDER BY fecha_hora DESC 
      LIMIT 1
    ''', [entidadId]);

    if (result.isEmpty) return null;
    return result.first['hash_actual'] as String?;
  }

  /// Verifica la integridad de la cadena de auditoría para una entidad
  Future<bool> verificarIntegridadCadena(String entidadId) async {
    if (_db == null) return false;

    final registros = await _db.query(
      'auditoria_registros',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
      orderBy: 'fecha_hora ASC',
    );

    String? hashEsperado;

    for (final registro in registros) {
      final hashActual = registro['hash_actual']?.toString();
      final hashAnterior = registro['hash_anterior']?.toString();
      if (hashActual == null || hashActual.isEmpty || hashAnterior != hashEsperado) {
        return false;
      }

      Map<String, dynamic> decodeMap(Object? value) {
        if (value is Map) return value.cast<String, dynamic>();
        if (value is! String || value.trim().isEmpty) return <String, dynamic>{};
        try {
          final decoded = jsonDecode(value);
          return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
        } catch (_) {
          // Los registros heredados serializados con Map.toString() no son
          // verificables criptográficamente de forma inequívoca.
          throw const FormatException('Registro de auditoría legado no canónico');
        }
      }

      try {
        final contenido = <String, dynamic>{
          'id': registro['id'],
          'entidad_id': registro['entidad_id'],
          'usuario_id': registro['usuario_id'],
          'usuario_nombre': registro['usuario_nombre'],
          'ip_direccion': registro['ip_direccion'],
          'fecha_hora': registro['fecha_hora'],
          'tipo_evento': registro['tipo_evento'],
          'modulo': registro['modulo'],
          'accion': registro['accion'],
          'valor_anterior': decodeMap(registro['valor_anterior']),
          'valor_nuevo': decodeMap(registro['valor_nuevo']),
          'hash_anterior': hashAnterior,
          'referencia_id': registro['referencia_id'],
          'observaciones': registro['observaciones'],
        };
        if (RegistroAuditoria.calcularHash(contenido) != hashActual) return false;
      } on FormatException {
        return false;
      }

      hashEsperado = hashActual;
    }

    return true;
  }

  /// Consulta registros de auditoría con filtros
  Future<List<RegistroAuditoria>> consultarRegistros({
    required String entidadId,
    String? usuarioId,
    TipoEventoAuditoria? tipoEvento,
    String? modulo,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    String? referenciaId,
    int? limite,
  }) async {
    if (_db == null) return [];

    String query = 'SELECT * FROM auditoria_registros WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (usuarioId != null) {
      query += ' AND usuario_id = ?';
      args.add(usuarioId);
    }

    if (tipoEvento != null) {
      query += ' AND tipo_evento = ?';
      args.add(tipoEvento.toString().split('.').last);
    }

    if (modulo != null) {
      query += ' AND modulo = ?';
      args.add(modulo);
    }

    if (fechaDesde != null) {
      query += ' AND fecha_hora >= ?';
      args.add(fechaDesde.toIso8601String());
    }

    if (fechaHasta != null) {
      query += ' AND fecha_hora <= ?';
      args.add(fechaHasta.toIso8601String());
    }

    if (referenciaId != null) {
      query += ' AND referencia_id = ?';
      args.add(referenciaId);
    }

    query += ' ORDER BY fecha_hora DESC';

    if (limite != null) {
      query += ' LIMIT ?';
      args.add(limite);
    }

    final resultados = await _db.rawQuery(query, args);

    return resultados.map((r) => RegistroAuditoria.fromJson({
      'id': r['id'],
      'entidad_id': r['entidad_id'],
      'usuario_id': r['usuario_id'],
      'usuario_nombre': r['usuario_nombre'],
      'ip_direccion': r['ip_direccion'],
      'fecha_hora': r['fecha_hora'],
      'tipo_evento': r['tipo_evento'],
      'modulo': r['modulo'],
      'accion': r['accion'],
      'valor_anterior': r['valor_anterior'],
      'valor_nuevo': r['valor_nuevo'],
      'hash_anterior': r['hash_anterior'],
      'hash_actual': r['hash_actual'],
      'referencia_id': r['referencia_id'],
      'observaciones': r['observaciones'],
    })).toList();
  }

  /// Registra un intento de eliminación (siempre bloqueado)
  /// Esta función se llama cuando alguien intenta eliminar un registro sensible
  Future<void> registrarIntentoEliminacion({
    required String entidadId,
    required String usuarioId,
    String? usuarioNombre,
    String? ipDireccion,
    required String modulo,
    required String referenciaId,
    required Map<String, dynamic> datosIntentados,
  }) async {
    await registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      usuarioNombre: usuarioNombre,
      ipDireccion: ipDireccion,
      tipoEvento: TipoEventoAuditoria.intentoEliminacion,
      modulo: modulo,
      accion: 'INTENTO DE ELIMINACIÓN - BLOQUEADO POR SISTEMA',
      valorAnterior: datosIntentados,
      valorNuevo: {'mensaje': 'Operación bloqueada: prohibido eliminar registros'},
      referenciaId: referenciaId,
      observaciones: 'El usuario intentó eliminar un registro sensible. La operación fue bloqueada por el sistema.',
    );
  }

  static const String retentionSettingKey = 'auditoria_retencion_anios';

  /// Archiva lógicamente registros que superan la política de retención
  /// parametrizada por la propia entidad. Si la entidad no ha adoptado una
  /// política válida, no se realiza ninguna acción automática.
  ///
  /// [retentionYearsOverride] existe para operaciones administrativas y tests;
  /// la operación normal obtiene el valor de `configuraciones_generales`.
  Future<void> archivarRegistrosAntiguos(
    String entidadId, {
    int? retentionYearsOverride,
  }) async {
    if (_db == null) return;

    var years = retentionYearsOverride;
    if (years == null) {
      final rows = await _db.query(
        'configuraciones_generales',
        columns: ['valor'],
        where: 'entidad_id = ? AND clave = ? AND estado = ?',
        whereArgs: [entidadId, retentionSettingKey, 'activo'],
        orderBy: 'fecha_actualizacion DESC',
        limit: 1,
      );
      if (rows.isEmpty) return;
      years = int.tryParse(rows.first['valor']?.toString() ?? '');
    }

    if (years == null || years <= 0 || years > 500) return;
    final now = DateTime.now();
    final fechaLimite = DateTime(
      now.year - years,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );

    // Nunca se elimina: solo se marca para archivo histórico.
    await _db.update(
      'auditoria_registros',
      {'archivado': 1},
      where: 'entidad_id = ? AND fecha_hora < ?',
      whereArgs: [entidadId, fechaLimite.toIso8601String()],
    );
  }
}
