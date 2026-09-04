/// Servicio de Flujo de Viabilización
/// Conpes 4048/2014 y normas DNP
/// Flujo de viabilización de proyectos de inversión
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum EtapaViabilizacion {
  registro,
  revision_tecnica,
  revision_financiera,
  aprobacion,
  rechazo,
}

class ViabilizacionService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  ViabilizacionService({
    required this.db,
    required this.auditoriaService,
  });

  /// Inicia el flujo de viabilización de un proyecto
  Future<Map<String, dynamic>> iniciarViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    required String motivo,
  }) async {
    final id = _uuid.v4();

    // Verificar que el proyecto existe
    final proyecto = await db.query(
      'proyectos_mga',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    if (proyecto.isEmpty) {
      throw Exception('Proyecto no encontrado');
    }

    // Verificar que no haya un flujo activo
    final flujoActivo = await db.query(
      'flujos_viabilizacion',
      where: 'proyecto_id = ? AND etapa IN (?, ?, ?)',
      whereArgs: [
        proyectoId,
        EtapaViabilizacion.registro.toString().split('.').last,
        EtapaViabilizacion.revision_tecnica.toString().split('.').last,
        EtapaViabilizacion.revision_financiera.toString().split('.').last,
      ],
    );

    if (flujoActivo.isNotEmpty) {
      throw Exception('Ya existe un flujo de viabilización activo para este proyecto');
    }

    await db.insert('flujos_viabilizacion', {
      'id': id,
      'entidad_id': entidadId,
      'proyecto_id': proyectoId,
      'etapa': EtapaViabilizacion.registro.toString().split('.').last,
      'motivo': motivo,
      'fecha_inicio': DateTime.now().toIso8601String(),
      'iniciado_por': usuarioId,
      'estado': 'activo',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'planeacion',
      accion: 'inicio_viabilizacion',
      valorAnterior: {},
      valorNuevo: {
        'flujo_id': id,
        'proyecto_id': proyectoId,
        'etapa': EtapaViabilizacion.registro.toString(),
      },
      referenciaId: id,
    );

    return {
      'flujo_id': id,
      'proyecto_id': proyectoId,
      'etapa': EtapaViabilizacion.registro.toString().split('.').last,
      'estado': 'activo',
    };
  }

  /// Avanza a la siguiente etapa del flujo
  Future<Map<String, dynamic>> avanzarEtapa({
    required String entidadId,
    required String usuarioId,
    required String flujoId,
    required EtapaViabilizacion siguienteEtapa,
    required String concepto,
    String? observaciones,
  }) async {
    final flujo = await db.query(
      'flujos_viabilizacion',
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    if (flujo.isEmpty) {
      throw Exception('Flujo no encontrado');
    }

    final etapaActual = EtapaViabilizacion.values.firstWhere(
      (e) => e.toString().split('.').last == flujo.first['etapa'],
    );

    // Validar secuencia de etapas
    if (!_validarSecuenciaEtapas(etapaActual, siguienteEtapa)) {
      throw Exception('Secuencia de etapas inválida');
    }

    await db.update(
      'flujos_viabilizacion',
      {
        'etapa': siguienteEtapa.toString().split('.').last,
        'concepto': concepto,
        'observaciones': observaciones,
        'fecha_ultima_actualizacion': DateTime.now().toIso8601String(),
        'actualizado_por': usuarioId,
      },
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'avance_etapa_viabilizacion',
      valorAnterior: {
        'etapa_anterior': etapaActual.toString(),
      },
      valorNuevo: {
        'etapa_nueva': siguienteEtapa.toString(),
        'concepto': concepto,
      },
      referenciaId: flujoId,
    );

    return {
      'flujo_id': flujoId,
      'etapa_anterior': etapaActual.toString().split('.').last,
      'etapa_nueva': siguienteEtapa.toString().split('.').last,
    };
  }

  /// Aprueba la viabilización
  Future<Map<String, dynamic>> aprobarViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String flujoId,
    required String numeroActoAdministrativo,
    required DateTime fechaActo,
    required String conceptoFinal,
  }) async {
    final flujo = await db.query(
      'flujos_viabilizacion',
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    if (flujo.isEmpty) {
      throw Exception('Flujo no encontrado');
    }

    final etapaActual = flujo.first['etapa'];
    if (etapaActual != EtapaViabilizacion.revision_financiera.toString().split('.').last) {
      throw Exception('Solo se puede aprobar un proyecto en etapa de revisión financiera');
    }

    await db.update(
      'flujos_viabilizacion',
      {
        'etapa': EtapaViabilizacion.aprobacion.toString().split('.').last,
        'numero_acto_administrativo': numeroActoAdministrativo,
        'fecha_acto_administrativo': fechaActo.toIso8601String(),
        'concepto_final': conceptoFinal,
        'fecha_aprobacion': DateTime.now().toIso8601String(),
        'aprobado_por': usuarioId,
        'estado': 'completado',
      },
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    // Actualizar estado del proyecto a viabilizado
    await db.update(
      'proyectos_mga',
      {
        'estado': 'viabilizado',
        'fecha_viabilizacion': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [flujo.first['proyecto_id']],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'aprobacion_viabilizacion',
      valorAnterior: {
        'etapa_anterior': etapaActual,
      },
      valorNuevo: {
        'etapa_nueva': EtapaViabilizacion.aprobacion.toString(),
        'numero_acto_administrativo': numeroActoAdministrativo,
      },
      referenciaId: flujoId,
    );

    return {
      'flujo_id': flujoId,
      'etapa': EtapaViabilizacion.aprobacion.toString().split('.').last,
      'numero_acto_administrativo': numeroActoAdministrativo,
      'estado': 'completado',
    };
  }

  /// Rechaza la viabilización
  Future<Map<String, dynamic>> rechazarViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String flujoId,
    required String motivoRechazo,
    required EtapaViabilizacion etapaRechazo,
  }) async {
    final flujo = await db.query(
      'flujos_viabilizacion',
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    if (flujo.isEmpty) {
      throw Exception('Flujo no encontrado');
    }

    await db.update(
      'flujos_viabilizacion',
      {
        'etapa': EtapaViabilizacion.rechazo.toString().split('.').last,
        'motivo_rechazo': motivoRechazo,
        'etapa_rechazo': etapaRechazo.toString().split('.').last,
        'fecha_rechazo': DateTime.now().toIso8601String(),
        'rechazado_por': usuarioId,
        'estado': 'rechazado',
      },
      where: 'id = ?',
      whereArgs: [flujoId],
    );

    // Actualizar estado del proyecto a rechazado
    await db.update(
      'proyectos_mga',
      {
        'estado': 'rechazado',
        'motivo_rechazo': motivoRechazo,
      },
      where: 'id = ?',
      whereArgs: [flujo.first['proyecto_id']],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'rechazo_viabilizacion',
      valorAnterior: {
        'etapa_anterior': flujo.first['etapa'],
      },
      valorNuevo: {
        'etapa_nueva': EtapaViabilizacion.rechazo.toString(),
        'motivo_rechazo': motivoRechazo,
      },
      referenciaId: flujoId,
    );

    return {
      'flujo_id': flujoId,
      'etapa': EtapaViabilizacion.rechazo.toString().split('.').last,
      'estado': 'rechazado',
    };
  }

  /// Consulta flujos de viabilización por entidad
  Future<List<Map<String, dynamic>>> consultarFlujosViabilizacion({
    required String entidadId,
    EtapaViabilizacion? etapa,
    String? estado,
  }) async {
    String query = 'SELECT * FROM flujos_viabilizacion WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (etapa != null) {
      query += ' AND etapa = ?';
      args.add(etapa.toString().split('.').last);
    }

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado);
    }

    query += ' ORDER BY fecha_inicio DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta flujo de viabilización de un proyecto
  Future<Map<String, dynamic>?> consultarFlujoProyecto({
    required String proyectoId,
  }) async {
    final resultado = await db.query(
      'flujos_viabilizacion',
      where: 'proyecto_id = ?',
      whereArgs: [proyectoId],
      orderBy: 'fecha_inicio DESC',
      limit: 1,
    );

    if (resultado.isEmpty) return null;
    return resultado.first;
  }

  /// Genera reporte de viabilización
  Future<Map<String, dynamic>> generarReporteViabilizacion({
    required String entidadId,
    String? periodo,
  }) async {
    String query = 'SELECT * FROM flujos_viabilizacion WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (periodo != null) {
      query += ' AND fecha_inicio LIKE ?';
      args.add('$periodo%');
    }

    final flujos = await db.rawQuery(query, args);

    // Por etapa
    final porEtapa = <String, int>{};
    for (final f in flujos) {
      final etapa = f['etapa'] as String?;
      if (etapa == null) continue;
      porEtapa[etapa] = (porEtapa[etapa] ?? 0) + 1;
    }
 
    // Por estado
    final porEstado = <String, int>{};
    for (final f in flujos) {
      final estado = f['estado'] as String?;
      if (estado == null) continue;
      porEstado[estado] = (porEstado[estado] ?? 0) + 1;
    }

    // Tiempos promedio por etapa
    final tiemposPorEtapa = <String, double>{};
    for (final f in flujos) {
      if (f['fecha_inicio'] != null && f['fecha_ultima_actualizacion'] != null) {
        final inicio = DateTime.parse(f['fecha_inicio'] as String);
        final fin = DateTime.parse(f['fecha_ultima_actualizacion'] as String);
        final duracion = fin.difference(inicio).inDays;
        final etapa = f['etapa'] as String?;
        if (etapa == null) continue;
        if (!tiemposPorEtapa.containsKey(etapa)) {
          tiemposPorEtapa[etapa] = 0;
        }
        tiemposPorEtapa[etapa] = tiemposPorEtapa[etapa]! + duracion;
      }
    }

    // Calcular promedios
    for (final etapa in tiemposPorEtapa.keys) {
      final cantidad = porEtapa[etapa] ?? 1;
      tiemposPorEtapa[etapa] = tiemposPorEtapa[etapa]! / cantidad;
    }

    return {
      'total_flujos': flujos.length,
      'por_etapa': porEtapa,
      'por_estado': porEstado,
      'tiempos_promedio_dias': tiemposPorEtapa,
      'detalles': flujos,
    };
  }

  /// Valida la secuencia de etapas
  bool _validarSecuenciaEtapas(EtapaViabilizacion actual, EtapaViabilizacion siguiente) {
    final secuencia = [
      EtapaViabilizacion.registro,
      EtapaViabilizacion.revision_tecnica,
      EtapaViabilizacion.revision_financiera,
      EtapaViabilizacion.aprobacion,
    ];

    final indiceActual = secuencia.indexOf(actual);
    final indiceSiguiente = secuencia.indexOf(siguiente);

    return indiceSiguiente == indiceActual + 1;
  }

  /// Obtiene la siguiente etapa válida
  EtapaViabilizacion? obtenerSiguienteEtapa(EtapaViabilizacion actual) {
    final secuencia = [
      EtapaViabilizacion.registro,
      EtapaViabilizacion.revision_tecnica,
      EtapaViabilizacion.revision_financiera,
      EtapaViabilizacion.aprobacion,
    ];

    final indice = secuencia.indexOf(actual);
    if (indice < 0 || indice >= secuencia.length - 1) return null;

    return secuencia[indice + 1];
  }
}
