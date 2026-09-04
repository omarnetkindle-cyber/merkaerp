/// Servicio de Control Disciplinario
/// Código Disciplinario Ónico
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import '../models/proceso_disciplinario.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class DisciplinarioService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  DisciplinarioService({required this.db, required this.auditoriaService});

  /// Inicia un proceso disciplinario
  Future<ProcesoDisciplinario> iniciarProceso({
    required String entidadId,
    required String usuarioId,
    required TipoProceso tipoProceso,
    required String servidorPublico,
    required String identificacion,
    required String cargo,
    required String dependencia,
    required String descripcion,
  }) async {
    final id = _uuid.v4();
    final numeroProceso =
        'PD-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaInicio = DateTime.now();

    final proceso = ProcesoDisciplinario(
      id: id,
      entidadId: entidadId,
      numeroProceso: numeroProceso,
      tipoProceso: tipoProceso,
      servidorPublico: servidorPublico,
      identificacion: identificacion,
      cargo: cargo,
      dependencia: dependencia,
      descripcion: descripcion,
      fechaInicio: fechaInicio,
      estado: EstadoProcesoDisciplinario.iniciado,
    );

    await db.insert('procesos_disciplinarios', proceso.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'transparencia',
      accion: 'inicio_proceso_disciplinario',
      valorAnterior: {},
      valorNuevo: {
        'proceso_id': id,
        'numero_proceso': numeroProceso,
        'servidor_publico': servidorPublico,
      },
      referenciaId: id,
    );

    return proceso;
  }

  /// Registra decisión del proceso disciplinario
  Future<ProcesoDisciplinario> registrarDecision({
    required String entidadId,
    required String usuarioId,
    required String procesoId,
    required EstadoProcesoDisciplinario estadoDecision,
    String? sancion,
    MoneyValue? montoSancion,
  }) async {
    final procesoResult = await db.query(
      'procesos_disciplinarios',
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    if (procesoResult.isEmpty) {
      throw Exception('Proceso no encontrado');
    }

    final proceso = ProcesoDisciplinario.fromJson(procesoResult.first);

    if (proceso.estado == EstadoProcesoDisciplinario.archivado) {
      throw Exception('El proceso ya está archivado');
    }

    final fechaDecision = DateTime.now();

    await db.update(
      'procesos_disciplinarios',
      {
        'estado': estadoDecision.toString().split('.').last,
        'fecha_decision': fechaDecision.toIso8601String(),
        'sancion': sancion,
        'monto_sancion': montoSancion?.toSql(),
      },
      where: 'id = ?',
      whereArgs: [procesoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'transparencia',
      accion: 'decision_proceso_disciplinario',
      valorAnterior: {'estado_anterior': proceso.estado.toString()},
      valorNuevo: {
        'estado_nuevo': estadoDecision.toString(),
        'sancion': sancion,
        'monto_sancion': montoSancion?.toWireMap(),
      },
      referenciaId: procesoId,
    );

    return proceso.copyWith(
      estado: estadoDecision,
      fechaDecision: fechaDecision,
      sancion: sancion,
      montoSancion: montoSancion,
    );
  }

  Future<List<ProcesoDisciplinario>> consultarProcesos({
    required String entidadId,
    EstadoProcesoDisciplinario? estado,
  }) async {
    String query = 'SELECT * FROM procesos_disciplinarios WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_inicio DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => ProcesoDisciplinario.fromJson(r)).toList();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
