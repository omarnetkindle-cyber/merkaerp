/// Servicio de Activos del Estado
/// NICSP 17 - Depreciación y gestión de activos
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/activo_estado.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

class ActivosService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  ActivosService({
    required this.db,
    required this.auditoriaService,
  });

  /// Registra un activo del estado
  Future<ActivoEstado> registrarActivo({
    required String entidadId,
    required String usuarioId,
    required String numeroInventario,
    required String nombreActivo,
    required TipoActivo tipoActivo,
    required String marca,
    required String modelo,
    required String serie,
    required MoneyValue valorAdquisicion,
    required DateTime fechaAdquisicion,
    required DateTime fechaPuestaEnMarcha,
    required int vidaUtilAnios,
    required MoneyValue valorResidual,
    String? ubicacion,
    String? responsable,
  }) async {
    final id = _uuid.v4();
    // depreciacionAnual = (valorAdquisicion - valorResidual) / vidaUtilAnios
    // calculada para referencia futura pero el registro actual usa valor neto directamente
    final valorNeto = valorAdquisicion;

    final activo = ActivoEstado(
      id: id,
      entidadId: entidadId,
      numeroInventario: numeroInventario,
      nombreActivo: nombreActivo,
      tipoActivo: tipoActivo,
      marca: marca,
      modelo: modelo,
      serie: serie,
      valorAdquisicion: valorAdquisicion,
      valorLibros: valorAdquisicion,
      valorNeto: valorNeto,
      fechaAdquisicion: fechaAdquisicion,
      fechaPuestaEnMarcha: fechaPuestaEnMarcha,
      vidaUtilAnios: vidaUtilAnios,
      valorResidual: valorResidual,
      depreciacionAcumulada: publicMoneyZero(),
      estado: EstadoActivo.nuevo,
      ubicacion: ubicacion,
      responsable: responsable,
    );

    await db.insert('activos_estado', activo.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'activos',
      accion: 'registro_activo',
      valorAnterior: {},
      valorNuevo: {
        'activo_id': id,
        'numero_inventario': numeroInventario,
        'valor_adquisicion': valorAdquisicion.toSql(),
      },
      referenciaId: id,
    );

    return activo;
  }

  /// Actualiza depreciación de un activo (NICSP 17)
  Future<ActivoEstado> actualizarDepreciacion({
    required String entidadId,
    required String usuarioId,
    required String activoId,
  }) async {
    final activoResult = await db.query(
      'activos_estado',
      where: 'id = ?',
      whereArgs: [activoId],
    );

    if (activoResult.isEmpty) {
      throw Exception('Activo no encontrado');
    }

    final activo = ActivoEstado.fromJson(activoResult.first);

    final depreciacionAcumulada = activo.calcularDepreciacionAcumuladaActual();
    final valorNeto = activo.calcularValorNetoActual();

    await db.update(
      'activos_estado',
      {
        'depreciacion_acumulada': depreciacionAcumulada.toSql(),
        'valor_neto': valorNeto.toSql(),
      },
      where: 'id = ?',
      whereArgs: [activoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'actualizacion_depreciacion',
      valorAnterior: {
        'depreciacion_anterior': activo.depreciacionAcumulada.toSql(),
        'valor_neto_anterior': activo.valorNeto.toSql(),
      },
      valorNuevo: {
        'depreciacion_nueva': depreciacionAcumulada.toSql(),
        'valor_nuevo': valorNeto.toSql(),
      },
      referenciaId: activoId,
    );

    return activo.copyWith(
      depreciacionAcumulada: depreciacionAcumulada,
      valorNeto: valorNeto,
    );
  }

  /// Da de baja un activo
  Future<ActivoEstado> darDeBaja({
    required String entidadId,
    required String usuarioId,
    required String activoId,
    required String motivo,
  }) async {
    final activoResult = await db.query(
      'activos_estado',
      where: 'id = ?',
      whereArgs: [activoId],
    );

    if (activoResult.isEmpty) {
      throw Exception('Activo no encontrado');
    }

    await db.update(
      'activos_estado',
      {
        'estado': EstadoActivo.dadoDeBaja.toString().split('.').last,
        'observaciones': motivo,
      },
      where: 'id = ?',
      whereArgs: [activoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'activos',
      accion: 'baja_activo',
      valorAnterior: {},
      valorNuevo: {'activo_id': activoId, 'motivo': motivo},
      referenciaId: activoId,
    );

    final activo = ActivoEstado.fromJson(activoResult.first);
    return activo.copyWith(
      estado: EstadoActivo.dadoDeBaja,
      observaciones: motivo,
    );
  }

  Future<List<ActivoEstado>> consultarActivos({
    required String entidadId,
    EstadoActivo? estado,
    TipoActivo? tipoActivo,
  }) async {
    String query = 'SELECT * FROM activos_estado WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    if (tipoActivo != null) {
      query += ' AND tipo_activo = ?';
      args.add(tipoActivo.toString().split('.').last);
    }

    query += ' ORDER BY fecha_adquisicion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados.map((r) => ActivoEstado.fromJson(r)).toList();
  }
}

