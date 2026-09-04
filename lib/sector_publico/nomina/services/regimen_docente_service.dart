/// Servicio de Régimen Docente Territorial
/// Decreto 1278/2002 y normas complementarias
/// Gestión de docentes del sector público territorial
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum GradoDocente {
  grado1,
  grado2,
  grado3,
  grado4,
  grado5,
  grado6,
  grado7,
  grado8,
  grado9,
  grado10,
  grado11,
  grado12,
  grado13,
  grado14,
  grado15,
  grado16,
  grado17,
  grado18,
  grado19,
  grado20,
}

enum EscalafonDocente { titular, provisional, interino, contratista }

class RegimenDocenteService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  // Tabla de salarios por grado (actualizada anualmente por decreto)
  static final Map<GradoDocente, MoneyValue> _salariosPorGrado = {
    GradoDocente.grado1: _salario(2719687),
    GradoDocente.grado2: _salario(2855661),
    GradoDocente.grado3: _salario(2991635),
    GradoDocente.grado4: _salario(3127609),
    GradoDocente.grado5: _salario(3263583),
    GradoDocente.grado6: _salario(3399557),
    GradoDocente.grado7: _salario(3535531),
    GradoDocente.grado8: _salario(3671505),
    GradoDocente.grado9: _salario(3807479),
    GradoDocente.grado10: _salario(3943453),
    GradoDocente.grado11: _salario(4079427),
    GradoDocente.grado12: _salario(4215401),
    GradoDocente.grado13: _salario(4351375),
    GradoDocente.grado14: _salario(4487349),
    GradoDocente.grado15: _salario(4623323),
    GradoDocente.grado16: _salario(4759297),
    GradoDocente.grado17: _salario(4895271),
    GradoDocente.grado18: _salario(5031245),
    GradoDocente.grado19: _salario(5167219),
    GradoDocente.grado20: _salario(5303193),
  };

  static MoneyValue _salario(int pesos) =>
      publicMoneyFromMajor(pesos.toString());

  RegimenDocenteService({required this.db, required this.auditoriaService});

  /// Registra un docente en el régimen territorial
  Future<Map<String, dynamic>> registrarDocente({
    required String entidadId,
    required String usuarioId,
    required String empleadoId,
    required GradoDocente grado,
    required EscalafonDocente escalafon,
    required String especialidad,
    required String nivelEducativo, // preescolar, primaria, secundaria, media
    required String asignatura,
    required String institucionEducativa,
    String? codigoDANE,
  }) async {
    final id = _uuid.v4();

    // Obtener salario según grado
    final salarioMensual = _salariosPorGrado[grado]!;

    await db.insert('docentes_territoriales', {
      'id': id,
      'entidad_id': entidadId,
      'empleado_id': empleadoId,
      'grado': grado.toString().split('.').last,
      'escalafon': escalafon.toString().split('.').last,
      'especialidad': especialidad,
      'nivel_educativo': nivelEducativo,
      'asignatura': asignatura,
      'institucion_educativa': institucionEducativa,
      'codigo_dane': codigoDANE,
      'salario_mensual': salarioMensual.toSql(),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'activo',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'registro_docente_territorial',
      valorAnterior: {},
      valorNuevo: {
        'docente_id': id,
        'empleado_id': empleadoId,
        'grado': grado.toString(),
        'escalafon': escalafon.toString(),
        'salario_mensual': salarioMensual.toWireMap(),
      },
      referenciaId: id,
    );

    return {
      'docente_id': id,
      'empleado_id': empleadoId,
      'grado': grado.toString(),
      'escalafon': escalafon.toString(),
      'salario_mensual': publicMoneyForDisplay(salarioMensual),
      'estado': 'activo',
    };
  }

  /// Solicita ascenso de grado
  Future<Map<String, dynamic>> solicitarAscensoGrado({
    required String entidadId,
    required String usuarioId,
    required String docenteId,
    required GradoDocente gradoActual,
    required GradoDocente gradoSolicitado,
    required String motivo,
    required DateTime fechaSolicitud,
    required List<String> documentosSoporte,
  }) async {
    final id = _uuid.v4();

    // Validar que el grado solicitado sea superior al actual
    if (_obtenerNumeroGrado(gradoSolicitado) <=
        _obtenerNumeroGrado(gradoActual)) {
      throw Exception('El grado solicitado debe ser superior al actual');
    }

    await db.insert('solicitudes_ascenso', {
      'id': id,
      'entidad_id': entidadId,
      'docente_id': docenteId,
      'grado_actual': gradoActual.toString().split('.').last,
      'grado_solicitado': gradoSolicitado.toString().split('.').last,
      'motivo': motivo,
      'fecha_solicitud': fechaSolicitud.toIso8601String(),
      'documentos_soporte': documentosSoporte.join(','),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'pendiente_revision',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'solicitud_ascenso_grado',
      valorAnterior: {},
      valorNuevo: {
        'solicitud_id': id,
        'docente_id': docenteId,
        'grado_actual': gradoActual.toString(),
        'grado_solicitado': gradoSolicitado.toString(),
      },
      referenciaId: id,
    );

    return {
      'solicitud_id': id,
      'docente_id': docenteId,
      'grado_solicitado': gradoSolicitado.toString(),
      'estado': 'pendiente_revision',
    };
  }

  /// Aprueba solicita de ascenso y actualiza grado
  Future<Map<String, dynamic>> aprobarAscensoGrado({
    required String entidadId,
    required String usuarioId,
    required String solicitudId,
    required String motivoAprobacion,
    required DateTime fechaAprobacion,
  }) async {
    final solicitud = await db.query(
      'solicitudes_ascenso',
      where: 'id = ?',
      whereArgs: [solicitudId],
    );

    if (solicitud.isEmpty) {
      throw Exception('Solicitud no encontrada');
    }

    final docenteId = solicitud.first['docente_id'];
    final gradoSolicitado = GradoDocente.values.firstWhere(
      (e) =>
          e.toString().split('.').last == solicitud.first['grado_solicitado'],
    );

    // Actualizar grado del docente
    await db.update(
      'docentes_territoriales',
      {
        'grado': gradoSolicitado.toString().split('.').last,
        'salario_mensual': _salariosPorGrado[gradoSolicitado]!.toSql(),
      },
      where: 'id = ?',
      whereArgs: [docenteId],
    );

    // Actualizar estado de solicitud
    await db.update(
      'solicitudes_ascenso',
      {
        'estado': 'aprobada',
        'motivo_aprobacion': motivoAprobacion,
        'fecha_aprobacion': fechaAprobacion.toIso8601String(),
        'aprobado_por': usuarioId,
      },
      where: 'id = ?',
      whereArgs: [solicitudId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'nomina',
      accion: 'aprobacion_ascenso_grado',
      valorAnterior: {'estado_anterior': solicitud.first['estado']},
      valorNuevo: {
        'estado_nuevo': 'aprobada',
        'grado_nuevo': gradoSolicitado.toString(),
        'salario_nuevo': _salariosPorGrado[gradoSolicitado]!.toWireMap(),
      },
      referenciaId: solicitudId,
    );

    return {
      'solicitud_id': solicitudId,
      'docente_id': docenteId,
      'grado_nuevo': gradoSolicitado.toString(),
      'estado': 'aprobada',
    };
  }

  /// Calcula prima de antigüedad
  Future<MoneyValue> calcularPrimaAntiguedad({
    required String docenteId,
    required DateTime fechaCalculo,
  }) async {
    final docente = await db.query(
      'docentes_territoriales',
      where: 'id = ?',
      whereArgs: [docenteId],
    );

    if (docente.isEmpty) {
      throw Exception('Docente no encontrado');
    }

    final fechaIngreso = DateTime.parse(
      docente.first['fecha_registro'] as String,
    );
    final aniosServicio = fechaCalculo.year - fechaIngreso.year;

    if (aniosServicio < 3) return publicMoneyZero();

    final salarioMensual = publicMoneyFromSql(docente.first['salario_mensual']);

    // Prima de antigüedad: 1% por cada año de servicio, máximo 15%
    final porcentaje = (aniosServicio * 0.01).clamp(0, 0.15);
    return salarioMensual.multiplyDecimal(porcentaje.toString());
  }

  /// Calcula prima de servicios
  Future<MoneyValue> calcularPrimaServicios({
    required String docenteId,
    required String periodo, // Formato: '2024-06' (semestre)
  }) async {
    final docente = await db.query(
      'docentes_territoriales',
      where: 'id = ?',
      whereArgs: [docenteId],
    );

    if (docente.isEmpty) {
      throw Exception('Docente no encontrado');
    }

    final salarioMensual = publicMoneyFromSql(docente.first['salario_mensual']);

    // Prima de servicios: 1 mes de salario por semestre
    return salarioMensual;
  }

  /// Calcula prima de navidad
  Future<MoneyValue> calcularPrimaNavidad({
    required String docenteId,
    required int anio,
  }) async {
    final docente = await db.query(
      'docentes_territoriales',
      where: 'id = ?',
      whereArgs: [docenteId],
    );

    if (docente.isEmpty) {
      throw Exception('Docente no encontrado');
    }

    final salarioMensual = publicMoneyFromSql(docente.first['salario_mensual']);

    // Prima de navidad: 1 mes de salario
    return salarioMensual;
  }

  /// Genera liquidación de prestaciones sociales
  Future<Map<String, dynamic>> generarLiquidacionPrestaciones({
    required String entidadId,
    required String usuarioId,
    required String docenteId,
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) async {
    final primaAntiguedad = await calcularPrimaAntiguedad(
      docenteId: docenteId,
      fechaCalculo: fechaFin,
    );

    final primaServicios = await calcularPrimaServicios(
      docenteId: docenteId,
      periodo: '${fechaFin.year}-${fechaFin.month}',
    );

    final primaNavidad = await calcularPrimaNavidad(
      docenteId: docenteId,
      anio: fechaFin.year,
    );

    // Vacaciones (15 días hábiles por año)
    final aniosServicio = fechaFin.difference(fechaInicio).inDays / 365;
    final salarioMensual = (await db.query(
      'docentes_territoriales',
      where: 'id = ?',
      whereArgs: [docenteId],
    )).first['salario_mensual'];
    final salarioMensualMoney = publicMoneyFromSql(salarioMensual);
    final valorVacaciones = salarioMensualMoney
        .multiplyDecimal('0.5')
        .multiplyDecimal(aniosServicio.toString());

    final totalPrestaciones =
        primaAntiguedad + primaServicios + primaNavidad + valorVacaciones;

    await db.insert('liquidaciones_prestaciones', {
      'id': _uuid.v4(),
      'entidad_id': entidadId,
      'docente_id': docenteId,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'prima_antiguedad': primaAntiguedad.toSql(),
      'prima_servicios': primaServicios.toSql(),
      'prima_navidad': primaNavidad.toSql(),
      'valor_vacaciones': valorVacaciones.toSql(),
      'total_prestaciones': totalPrestaciones.toSql(),
      'fecha_registro': DateTime.now().toIso8601String(),
      'estado': 'aprobado',
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'liquidacion_prestaciones_docente',
      valorAnterior: {},
      valorNuevo: {
        'docente_id': docenteId,
        'total_prestaciones': totalPrestaciones.toWireMap(),
      },
      referenciaId: docenteId,
    );

    return {
      'docente_id': docenteId,
      'prima_antiguedad': publicMoneyForDisplay(primaAntiguedad),
      'prima_servicios': publicMoneyForDisplay(primaServicios),
      'prima_navidad': publicMoneyForDisplay(primaNavidad),
      'valor_vacaciones': publicMoneyForDisplay(valorVacaciones),
      'total_prestaciones': publicMoneyForDisplay(totalPrestaciones),
    };
  }

  /// Consulta docentes por entidad
  Future<List<Map<String, dynamic>>> consultarDocentes({
    required String entidadId,
    GradoDocente? grado,
    EscalafonDocente? escalafon,
    String? nivelEducativo,
  }) async {
    String query =
        'SELECT * FROM docentes_territoriales WHERE entidad_id = ? AND estado = ?';
    List<dynamic> args = [entidadId, 'activo'];

    if (grado != null) {
      query += ' AND grado = ?';
      args.add(grado.toString().split('.').last);
    }

    if (escalafon != null) {
      query += ' AND escalafon = ?';
      args.add(escalafon.toString().split('.').last);
    }

    if (nivelEducativo != null) {
      query += ' AND nivel_educativo = ?';
      args.add(nivelEducativo);
    }

    query += ' ORDER BY grado ASC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Consulta solicitudes de ascenso
  Future<List<Map<String, dynamic>>> consultarSolicitudesAscenso({
    required String entidadId,
    String? estado,
  }) async {
    String query = 'SELECT * FROM solicitudes_ascenso WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado);
    }

    query += ' ORDER BY fecha_solicitud DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }

  /// Genera reporte de nómina docente
  Future<Map<String, dynamic>> generarReporteNominaDocente({
    required String entidadId,
    required String periodo,
  }) async {
    final docentes = await consultarDocentes(entidadId: entidadId);

    var totalSalarios = publicMoneyZero();
    final detalles = <Map<String, dynamic>>[];

    for (final docente in docentes) {
      final salario = publicMoneyFromSql(docente['salario_mensual']);
      totalSalarios += salario;

      detalles.add({
        'docente_id': docente['id'],
        'empleado_id': docente['empleado_id'],
        'grado': docente['grado'],
        'escalafon': docente['escalafon'],
        'institucion_educativa': docente['institucion_educativa'],
        'salario_mensual': publicMoneyForDisplay(salario),
      });
    }

    // Por grado
    final porGrado = <String, int>{};
    for (final docente in docentes) {
      final grado = docente['grado'];
      porGrado[grado] = (porGrado[grado] ?? 0) + 1;
    }

    // Por escalafón
    final porEscalafon = <String, int>{};
    for (final docente in docentes) {
      final escalafon = docente['escalafon'];
      porEscalafon[escalafon] = (porEscalafon[escalafon] ?? 0) + 1;
    }

    return {
      'periodo': periodo,
      'total_docentes': docentes.length,
      'total_salarios': publicMoneyForDisplay(totalSalarios),
      'promedio_salario': docentes.isNotEmpty
          ? publicMoneyForDisplay(totalSalarios / docentes.length)
          : 0,
      'por_grado': porGrado,
      'por_escalafon': porEscalafon,
      'detalles': detalles,
    };
  }

  /// Obtiene el número de un grado para comparación
  int _obtenerNumeroGrado(GradoDocente grado) {
    switch (grado) {
      case GradoDocente.grado1:
        return 1;
      case GradoDocente.grado2:
        return 2;
      case GradoDocente.grado3:
        return 3;
      case GradoDocente.grado4:
        return 4;
      case GradoDocente.grado5:
        return 5;
      case GradoDocente.grado6:
        return 6;
      case GradoDocente.grado7:
        return 7;
      case GradoDocente.grado8:
        return 8;
      case GradoDocente.grado9:
        return 9;
      case GradoDocente.grado10:
        return 10;
      case GradoDocente.grado11:
        return 11;
      case GradoDocente.grado12:
        return 12;
      case GradoDocente.grado13:
        return 13;
      case GradoDocente.grado14:
        return 14;
      case GradoDocente.grado15:
        return 15;
      case GradoDocente.grado16:
        return 16;
      case GradoDocente.grado17:
        return 17;
      case GradoDocente.grado18:
        return 18;
      case GradoDocente.grado19:
        return 19;
      case GradoDocente.grado20:
        return 20;
    }
  }
}
