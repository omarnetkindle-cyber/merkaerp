/// Servicio de Formulación MGA (Metodología General Ajustada)
/// Conpes 4048/2014 y normas DNP
/// Formulación de proyectos de inversión con 8 campos obligatorios
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum EstadoFormulacion {
  borrador,
  en_revision,
  viabilizado,
  rechazado,
}

class FormulacionMGAService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  FormulacionMGAService({
    required this.db,
    required this.auditoriaService,
  });

  /// Registra un proyecto MGA con los 8 campos obligatorios
  Future<Map<String, dynamic>> registrarProyectoMGA({
    required String entidadId,
    required String usuarioId,
    // Campo 1: Código BPIN
    required String codigoBPIN,
    // Campo 2: Nombre del proyecto
    required String nombreProyecto,
    // Campo 3: Problema central
    required String problemaCentral,
    // Campo 4: Objetivo general
    required String objetivoGeneral,
    // Campo 5: Localización geográfica
    required String localizacionGeografica,
    // Campo 6: Población beneficiada
    required int poblacionBeneficiada,
    // Campo 7: Costo total del proyecto
    required double costoTotal,
    // Campo 8: Fuente de financiación
    required String fuenteFinanciacion,
    // Campos adicionales
    String? descripcion,
    String? justificacion,
    String? indicadores,
    String? metas,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    final id = _uuid.v4();

    // Validar formato BPIN (12 dígitos)
    if (!_validarFormatoBPIN(codigoBPIN)) {
      throw Exception('El código BPIN debe tener 12 dígitos');
    }

    // Validar campos obligatorios
    if (nombreProyecto.isEmpty || problemaCentral.isEmpty || objetivoGeneral.isEmpty) {
      throw Exception('Los campos nombre, problema central y objetivo general son obligatorios');
    }

    if (localizacionGeografica.isEmpty) {
      throw Exception('La localización geográfica es obligatoria');
    }

    if (poblacionBeneficiada <= 0) {
      throw Exception('La población beneficiada debe ser mayor a 0');
    }

    if (costoTotal <= 0) {
      throw Exception('El costo total debe ser mayor a 0');
    }

    if (fuenteFinanciacion.isEmpty) {
      throw Exception('La fuente de financiación es obligatoria');
    }

    await db.insert('proyectos_mga', {
      'id': id,
      'entidad_id': entidadId,
      'codigo_bpin': codigoBPIN,
      'nombre_proyecto': nombreProyecto,
      'problema_central': problemaCentral,
      'objetivo_general': objetivoGeneral,
      'localizacion_geografica': localizacionGeografica,
      'poblacion_beneficiada': poblacionBeneficiada,
      'costo_total': costoTotal,
      'fuente_financiacion': fuenteFinanciacion,
      'descripcion': descripcion,
      'justificacion': justificacion,
      'indicadores': indicadores,
      'metas': metas,
      'fecha_inicio': fechaInicio?.toIso8601String(),
      'fecha_fin': fechaFin?.toIso8601String(),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': EstadoFormulacion.borrador.toString().split('.').last,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'planeacion',
      accion: 'registro_proyecto_mga',
      valorAnterior: {},
      valorNuevo: {
        'proyecto_id': id,
        'codigo_bpin': codigoBPIN,
        'nombre_proyecto': nombreProyecto,
        'costo_total': costoTotal,
      },
      referenciaId: id,
    );

    return {
      'proyecto_id': id,
      'codigo_bpin': codigoBPIN,
      'nombre_proyecto': nombreProyecto,
      'estado': EstadoFormulacion.borrador.toString().split('.').last,
    };
  }

  /// Actualiza un proyecto MGA
  Future<Map<String, dynamic>> actualizarProyectoMGA({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    String? nombreProyecto,
    String? problemaCentral,
    String? objetivoGeneral,
    String? localizacionGeografica,
    int? poblacionBeneficiada,
    double? costoTotal,
    String? fuenteFinanciacion,
    String? descripcion,
    String? justificacion,
    String? indicadores,
    String? metas,
    DateTime? fechaInicio,
    DateTime? fechaFin,
  }) async {
    final proyecto = await db.query(
      'proyectos_mga',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    if (proyecto.isEmpty) {
      throw Exception('Proyecto no encontrado');
    }

    final estadoActual = proyecto.first['estado'];
    if (estadoActual == 'viabilizado') {
      throw Exception('No se puede modificar un proyecto viabilizado');
    }

    final actualizaciones = <String, dynamic>{};
    if (nombreProyecto != null) actualizaciones['nombre_proyecto'] = nombreProyecto;
    if (problemaCentral != null) actualizaciones['problema_central'] = problemaCentral;
    if (objetivoGeneral != null) actualizaciones['objetivo_general'] = objetivoGeneral;
    if (localizacionGeografica != null) actualizaciones['localizacion_geografica'] = localizacionGeografica;
    if (poblacionBeneficiada != null) actualizaciones['poblacion_beneficiada'] = poblacionBeneficiada;
    if (costoTotal != null) actualizaciones['costo_total'] = costoTotal;
    if (fuenteFinanciacion != null) actualizaciones['fuente_financiacion'] = fuenteFinanciacion;
    if (descripcion != null) actualizaciones['descripcion'] = descripcion;
    if (justificacion != null) actualizaciones['justificacion'] = justificacion;
    if (indicadores != null) actualizaciones['indicadores'] = indicadores;
    if (metas != null) actualizaciones['metas'] = metas;
    if (fechaInicio != null) actualizaciones['fecha_inicio'] = fechaInicio.toIso8601String();
    if (fechaFin != null) actualizaciones['fecha_fin'] = fechaFin.toIso8601String();

    if (actualizaciones.isEmpty) {
      throw Exception('No se proporcionaron campos para actualizar');
    }

    await db.update(
      'proyectos_mga',
      actualizaciones,
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'actualizacion_proyecto_mga',
      valorAnterior: {
        'estado_anterior': estadoActual,
      },
      valorNuevo: actualizaciones,
      referenciaId: proyectoId,
    );

    return {
      'proyecto_id': proyectoId,
      'campos_actualizados': actualizaciones.keys.toList(),
    };
  }

  /// Envía proyecto a viabilización
  Future<Map<String, dynamic>> enviarAViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    required String motivo,
  }) async {
    final proyecto = await db.query(
      'proyectos_mga',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    if (proyecto.isEmpty) {
      throw Exception('Proyecto no encontrado');
    }

    final estadoActual = proyecto.first['estado'];
    if (estadoActual != 'borrador') {
      throw Exception('Solo se pueden enviar proyectos en estado borrador');
    }

    await db.update(
      'proyectos_mga',
      {
        'estado': EstadoFormulacion.en_revision.toString().split('.').last,
        'fecha_envio_viabilizacion': DateTime.now().toIso8601String(),
        'motivo_envio': motivo,
      },
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'envio_viabilizacion_proyecto_mga',
      valorAnterior: {
        'estado_anterior': estadoActual,
      },
      valorNuevo: {
        'estado_nuevo': EstadoFormulacion.en_revision.toString().split('.').last,
      },
      referenciaId: proyectoId,
    );

    return {
      'proyecto_id': proyectoId,
      'estado': EstadoFormulacion.en_revision.toString().split('.').last,
    };
  }

  /// Aprueba viabilización de proyecto
  Future<Map<String, dynamic>> aprobarViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    required String conceptoTecnico,
    required String numeroActoAdministrativo,
    required DateTime fechaActo,
  }) async {
    final proyecto = await db.query(
      'proyectos_mga',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    if (proyecto.isEmpty) {
      throw Exception('Proyecto no encontrado');
    }

    final estadoActual = proyecto.first['estado'];
    if (estadoActual != 'en_revision') {
      throw Exception('Solo se pueden viabilizar proyectos en estado en revisión');
    }

    await db.update(
      'proyectos_mga',
      {
        'estado': EstadoFormulacion.viabilizado.toString().split('.').last,
        'fecha_viabilizacion': DateTime.now().toIso8601String(),
        'concepto_tecnico': conceptoTecnico,
        'numero_acto_administrativo': numeroActoAdministrativo,
        'fecha_acto_administrativo': fechaActo.toIso8601String(),
        'viabilizado_por': usuarioId,
      },
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'aprobacion_viabilizacion_proyecto_mga',
      valorAnterior: {
        'estado_anterior': estadoActual,
      },
      valorNuevo: {
        'estado_nuevo': EstadoFormulacion.viabilizado.toString().split('.').last,
        'numero_acto_administrativo': numeroActoAdministrativo,
      },
      referenciaId: proyectoId,
    );

    return {
      'proyecto_id': proyectoId,
      'estado': EstadoFormulacion.viabilizado.toString().split('.').last,
      'numero_acto_administrativo': numeroActoAdministrativo,
    };
  }

  /// Rechaza viabilización de proyecto
  Future<Map<String, dynamic>> rechazarViabilizacion({
    required String entidadId,
    required String usuarioId,
    required String proyectoId,
    required String motivoRechazo,
  }) async {
    final proyecto = await db.query(
      'proyectos_mga',
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    if (proyecto.isEmpty) {
      throw Exception('Proyecto no encontrado');
    }

    final estadoActual = proyecto.first['estado'];
    if (estadoActual != 'en_revision') {
      throw Exception('Solo se pueden rechazar proyectos en estado en revisión');
    }

    await db.update(
      'proyectos_mga',
      {
        'estado': EstadoFormulacion.rechazado.toString().split('.').last,
        'fecha_rechazo': DateTime.now().toIso8601String(),
        'motivo_rechazo': motivoRechazo,
        'rechazado_por': usuarioId,
      },
      where: 'id = ?',
      whereArgs: [proyectoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'planeacion',
      accion: 'rechazo_viabilizacion_proyecto_mga',
      valorAnterior: {
        'estado_anterior': estadoActual,
      },
      valorNuevo: {
        'estado_nuevo': EstadoFormulacion.rechazado.toString().split('.').last,
        'motivo_rechazo': motivoRechazo,
      },
      referenciaId: proyectoId,
    );

    return {
      'proyecto_id': proyectoId,
      'estado': EstadoFormulacion.rechazado.toString().split('.').last,
    };
  }

  /// Consulta proyectos MGA por entidad
  Future<List<Map<String, dynamic>>> consultarProyectosMGA({
    required String entidadId,
    EstadoFormulacion? estado,
    String? codigoBPIN,
  }) async {
    String query = 'SELECT * FROM proyectos_mga WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    if (codigoBPIN != null) {
      query += ' AND codigo_bpin = ?';
      args.add(codigoBPIN);
    }

    query += ' ORDER BY fecha_registro DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Genera reporte de proyectos MGA
  Future<Map<String, dynamic>> generarReporteProyectosMGA({
    required String entidadId,
    String? periodo,
  }) async {
    String query = 'SELECT * FROM proyectos_mga WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (periodo != null) {
      query += ' AND fecha_registro LIKE ?';
      args.add('$periodo%');
    }

    final proyectos = await db.rawQuery(query, args);

    double totalCosto = proyectos.fold<double>(
      0,
      (sum, r) => sum + (r['costo_total'] as num).toDouble(),
    );

    int totalPoblacion = proyectos.fold<int>(
      0,
      (sum, r) => sum + (r['poblacion_beneficiada'] as int),
    );

    // Por estado
    final porEstado = <String, int>{};
    for (final p in proyectos) {
      final estado = p['estado'] as String?;
      if (estado == null) continue;
      porEstado[estado] = (porEstado[estado] ?? 0) + 1;
    }
 
    // Por fuente de financiación
    final porFuente = <String, int>{};
    for (final p in proyectos) {
      final fuente = p['fuente_financiacion'] as String?;
      if (fuente == null) continue;
      porFuente[fuente] = (porFuente[fuente] ?? 0) + 1;
    }

    return {
      'total_proyectos': proyectos.length,
      'total_costo': totalCosto,
      'total_poblacion_beneficiada': totalPoblacion,
      'promedio_costo': proyectos.isNotEmpty ? totalCosto / proyectos.length : 0,
      'por_estado': porEstado,
      'por_fuente_financiacion': porFuente,
      'detalles': proyectos,
    };
  }

  /// Valida el formato del código BPIN (12 dígitos)
  bool _validarFormatoBPIN(String codigoBPIN) {
    final regex = RegExp(r'^\d{12}$');
    return regex.hasMatch(codigoBPIN);
  }

  /// Valida que los 8 campos obligatorios estén completos
  Map<String, bool> validarCamposObligatorios({
    required String codigoBPIN,
    required String nombreProyecto,
    required String problemaCentral,
    required String objetivoGeneral,
    required String localizacionGeografica,
    required int poblacionBeneficiada,
    required double costoTotal,
    required String fuenteFinanciacion,
  }) {
    return {
      'codigo_bpin': _validarFormatoBPIN(codigoBPIN),
      'nombre_proyecto': nombreProyecto.isNotEmpty,
      'problema_central': problemaCentral.isNotEmpty,
      'objetivo_general': objetivoGeneral.isNotEmpty,
      'localizacion_geografica': localizacionGeografica.isNotEmpty,
      'poblacion_beneficiada': poblacionBeneficiada > 0,
      'costo_total': costoTotal > 0,
      'fuente_financiacion': fuenteFinanciacion.isNotEmpty,
    };
  }
}
