import 'dart:convert';
import '../db_helper.dart';

enum EstadoRuta { pendiente, en_curso, completada, cancelada }

class PuntoEntrega {
  const PuntoEntrega({
    required this.id,
    required this.clientId,
    required this.clienteNombre,
    required this.direccion,
    required this.ordenId,
    required this.ordenReferencia,
    this.telefono,
    this.observaciones,
    this.entregado = false,
    this.horaEntrega,
  });

  final int id;
  final int clientId;
  final String clienteNombre;
  final String direccion;
  final int ordenId;
  final String ordenReferencia;
  final String? telefono;
  final String? observaciones;
  final bool entregado;
  final DateTime? horaEntrega;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clientId,
      'cliente_nombre': clienteNombre,
      'direccion': direccion,
      'orden_id': ordenId,
      'orden_referencia': ordenReferencia,
      'telefono': telefono,
      'observaciones': observaciones,
      'entregado': entregado ? 1 : 0,
      'hora_entrega': horaEntrega?.toIso8601String(),
    };
  }

  static PuntoEntrega fromMap(Map<String, dynamic> map) {
    return PuntoEntrega(
      id: map['id'] as int,
      clientId: map['cliente_id'] as int,
      clienteNombre: map['cliente_nombre'] as String,
      direccion: map['direccion'] as String,
      ordenId: map['orden_id'] as int,
      ordenReferencia: map['orden_referencia'] as String,
      telefono: map['telefono'] as String?,
      observaciones: map['observaciones'] as String?,
      entregado: (map['entregado'] as int?) == 1,
      horaEntrega: map['hora_entrega'] != null
          ? DateTime.parse(map['hora_entrega'] as String)
          : null,
    );
  }
}

class RutaEntrega {
  const RutaEntrega({
    required this.id,
    required this.nombre,
    required this.fecha,
    required this.conductor,
    required this.vehiculo,
    required this.estado,
    required this.puntos,
    required this.creadoEn,
    this.observaciones,
    this.horaInicio,
    this.horaFin,
  });

  final int id;
  final String nombre;
  final DateTime fecha;
  final String conductor;
  final String vehiculo;
  final EstadoRuta estado;
  final List<PuntoEntrega> puntos;
  final DateTime creadoEn;
  final String? observaciones;
  final DateTime? horaInicio;
  final DateTime? horaFin;

  int get totalPuntos => puntos.length;
  int get puntosEntregados => puntos.where((p) => p.entregado).length;
  double get progreso => totalPuntos > 0 ? puntosEntregados / totalPuntos : 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'fecha': fecha.toIso8601String(),
      'conductor': conductor,
      'vehiculo': vehiculo,
      'estado': estado.name,
      'puntos': jsonEncode(puntos.map((p) => p.toMap()).toList()),
      'creado_en': creadoEn.toIso8601String(),
      'observaciones': observaciones,
      'hora_inicio': horaInicio?.toIso8601String(),
      'hora_fin': horaFin?.toIso8601String(),
    };
  }

  static RutaEntrega fromMap(Map<String, dynamic> map) {
    final puntosJson = jsonDecode(map['puntos'] as String) as List;
    final puntos = puntosJson
        .map((p) => PuntoEntrega.fromMap(p as Map<String, dynamic>))
        .toList();

    return RutaEntrega(
      id: map['id'] as int,
      nombre: map['nombre'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      conductor: map['conductor'] as String,
      vehiculo: map['vehiculo'] as String,
      estado: EstadoRuta.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoRuta.pendiente,
      ),
      puntos: puntos,
      creadoEn: DateTime.parse(map['creado_en'] as String),
      observaciones: map['observaciones'] as String?,
      horaInicio: map['hora_inicio'] != null
          ? DateTime.parse(map['hora_inicio'] as String)
          : null,
      horaFin: map['hora_fin'] != null
          ? DateTime.parse(map['hora_fin'] as String)
          : null,
    );
  }
}

class RutasService {
  RutasService._();

  static final RutasService instance = RutasService._();

  Future<int> crearRuta({
    required String nombre,
    required DateTime fecha,
    required String conductor,
    required String vehiculo,
    required List<PuntoEntrega> puntos,
    String? observaciones,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final id = await db.insert('rutas_entrega', {
      'company_id': companyId,
      'nombre': nombre,
      'fecha': fecha.toIso8601String(),
      'conductor': conductor,
      'vehiculo': vehiculo,
      'estado': EstadoRuta.pendiente.name,
      'puntos': jsonEncode(puntos.map((p) => p.toMap()).toList()),
      'observaciones': observaciones,
      'creado_en': DateTime.now().toIso8601String(),
    });

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_CREADA',
      entidad: 'rutas',
      detalle: 'ID: $id, Nombre: $nombre, Puntos: ${puntos.length}',
    );

    return id;
  }

  Future<RutaEntrega?> obtenerRuta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'rutas_entrega',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return RutaEntrega.fromMap(rows.first);
  }

  Future<List<RutaEntrega>> listarRutas({
    EstadoRuta? estado,
    DateTime? desde,
    DateTime? hasta,
    String? conductor,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    String where = 'company_id = ?';
    List<dynamic> whereArgs = [companyId];

    if (estado != null) {
      where += ' AND estado = ?';
      whereArgs.add(estado.name);
    }

    if (desde != null) {
      where += ' AND fecha >= ?';
      whereArgs.add(desde.toIso8601String());
    }

    if (hasta != null) {
      where += ' AND fecha <= ?';
      whereArgs.add(hasta.toIso8601String());
    }

    if (conductor != null) {
      where += ' AND conductor = ?';
      whereArgs.add(conductor);
    }

    final rows = await db.query(
      'rutas_entrega',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'fecha DESC',
    );

    return rows.map((row) => RutaEntrega.fromMap(row)).toList();
  }

  Future<void> iniciarRuta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'rutas_entrega',
      {
        'estado': EstadoRuta.en_curso.name,
        'hora_inicio': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_INICIADA',
      entidad: 'rutas',
      detalle: 'ID: $id',
    );
  }

  Future<void> completarRuta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'rutas_entrega',
      {
        'estado': EstadoRuta.completada.name,
        'hora_fin': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_COMPLETADA',
      entidad: 'rutas',
      detalle: 'ID: $id',
    );
  }

  Future<void> cancelarRuta(int id, String motivo) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'rutas_entrega',
      {
        'estado': EstadoRuta.cancelada.name,
        'observaciones': motivo,
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_CANCELADA',
      entidad: 'rutas',
      detalle: 'ID: $id, Motivo: $motivo',
    );
  }

  Future<void> marcarPuntoEntregado(int rutaId, int puntoId) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final ruta = await obtenerRuta(rutaId);
    if (ruta == null) throw Exception('Ruta no encontrada');

    final puntosActualizados = ruta.puntos.map((p) {
      if (p.id == puntoId) {
        return PuntoEntrega(
          id: p.id,
          clientId: p.clientId,
          clienteNombre: p.clienteNombre,
          direccion: p.direccion,
          ordenId: p.ordenId,
          ordenReferencia: p.ordenReferencia,
          telefono: p.telefono,
          observaciones: p.observaciones,
          entregado: true,
          horaEntrega: DateTime.now(),
        );
      }
      return p;
    }).toList();

    await db.update(
      'rutas_entrega',
      {
        'puntos': jsonEncode(puntosActualizados.map((p) => p.toMap()).toList()),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [rutaId, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'PUNTO_ENTREGA_MARCADO',
      entidad: 'rutas',
      detalle: 'Ruta ID: $rutaId, Punto ID: $puntoId',
    );
  }

  Future<void> actualizarRuta(int id, {
    String? nombre,
    String? conductor,
    String? vehiculo,
    List<PuntoEntrega>? puntos,
    String? observaciones,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final updates = <String, dynamic>{};

    if (nombre != null) updates['nombre'] = nombre;
    if (conductor != null) updates['conductor'] = conductor;
    if (vehiculo != null) updates['vehiculo'] = vehiculo;
    if (puntos != null) updates['puntos'] = jsonEncode(puntos.map((p) => p.toMap()).toList());
    if (observaciones != null) updates['observaciones'] = observaciones;

    await db.update(
      'rutas_entrega',
      updates,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_ACTUALIZADA',
      entidad: 'rutas',
      detalle: 'ID: $id',
    );
  }

  Future<void> eliminarRuta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.delete(
      'rutas_entrega',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RUTA_ENTREGA_ELIMINADA',
      entidad: 'rutas',
      detalle: 'ID: $id',
    );
  }

  Future<List<Map<String, dynamic>>> obtenerRutasPorConductor(String conductor) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'rutas_entrega',
      where: 'company_id = ? AND conductor = ?',
      whereArgs: [companyId, conductor],
      orderBy: 'fecha DESC',
    );

    return rows.map((row) => row as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>> obtenerMetricasRutas() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'rutas_entrega',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );

    int pendientes = 0;
    int enCurso = 0;
    int completadas = 0;
    int canceladas = 0;
    int totalPuntos = 0;
    int puntosEntregados = 0;

    for (final row in rows) {
      final estado = row['estado'] as String;
      switch (estado) {
        case 'pendiente':
          pendientes++;
          break;
        case 'en_curso':
          enCurso++;
          break;
        case 'completada':
          completadas++;
          break;
        case 'cancelada':
          canceladas++;
          break;
      }

      final ruta = RutaEntrega.fromMap(row);
      totalPuntos += ruta.totalPuntos;
      puntosEntregados += ruta.puntosEntregados;
    }

    return {
      'total_rutas': rows.length,
      'pendientes': pendientes,
      'en_curso': enCurso,
      'completadas': completadas,
      'canceladas': canceladas,
      'total_puntos': totalPuntos,
      'puntos_entregados': puntosEntregados,
      'tasa_entrega': totalPuntos > 0 ? puntosEntregados / totalPuntos : 0,
    };
  }
}
