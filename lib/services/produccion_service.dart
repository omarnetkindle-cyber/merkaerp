import '../db_helper.dart';
import 'recetas_service.dart';

enum EstadoOrdenProduccion {
  pendiente,
  en_proceso,
  pausada,
  completada,
  cancelada,
}

class OrdenProduccion {
  const OrdenProduccion({
    required this.id,
    required this.productoId,
    required this.productoNombre,
    required this.cantidad,
    required this.estado,
    required this.fechaCreacion,
    this.fechaInicio,
    this.fechaCompletado,
    this.recetaId,
    this.observaciones,
    this.asignadoA,
  });

  final int id;
  final int productoId;
  final String productoNombre;
  final double cantidad;
  final EstadoOrdenProduccion estado;
  final DateTime fechaCreacion;
  final DateTime? fechaInicio;
  final DateTime? fechaCompletado;
  final int? recetaId;
  final String? observaciones;
  final String? asignadoA;

  bool get estaActiva => estado == EstadoOrdenProduccion.pendiente || 
                         estado == EstadoOrdenProduccion.en_proceso;
  
  bool get estaCompletada => estado == EstadoOrdenProduccion.completada;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'cantidad': cantidad,
      'estado': estado.name,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_inicio': fechaInicio?.toIso8601String(),
      'fecha_completado': fechaCompletado?.toIso8601String(),
      'receta_id': recetaId,
      'observaciones': observaciones,
      'asignado_a': asignadoA,
    };
  }

  static OrdenProduccion fromMap(Map<String, dynamic> map) {
    return OrdenProduccion(
      id: map['id'] as int,
      productoId: map['producto_id'] as int,
      productoNombre: map['producto_nombre'] as String,
      cantidad: (map['cantidad'] as num).toDouble(),
      estado: EstadoOrdenProduccion.values.firstWhere(
        (e) => e.name == map['estado'],
        orElse: () => EstadoOrdenProduccion.pendiente,
      ),
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
      fechaInicio: map['fecha_inicio'] != null 
          ? DateTime.parse(map['fecha_inicio'] as String) 
          : null,
      fechaCompletado: map['fecha_completado'] != null 
          ? DateTime.parse(map['fecha_completado'] as String) 
          : null,
      recetaId: map['receta_id'] as int?,
      observaciones: map['observaciones'] as String?,
      asignadoA: map['asignado_a'] as String?,
    );
  }
}

class ProduccionService {
  ProduccionService._();

  static final ProduccionService instance = ProduccionService._();

  Future<int> crearOrdenProduccion({
    required int productoId,
    required String productoNombre,
    required double cantidad,
    String? observaciones,
    String? asignadoA,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    // Verificar si existe receta para el producto
    final receta = await RecetasService.instance.obtenerRecetaPorProducto(productoId);

    final id = await db.insert('ordenes_produccion', {
      'company_id': companyId,
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'cantidad': cantidad,
      'estado': EstadoOrdenProduccion.pendiente.name,
      'fecha_creacion': DateTime.now().toIso8601String(),
      'receta_id': receta?.id,
      'observaciones': observaciones,
      'asignado_a': asignadoA,
    });

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_CREADA',
      entidad: 'produccion',
      detalle: 'ID: $id, Producto: $productoNombre, Cantidad: $cantidad',
    );

    return id;
  }

  Future<OrdenProduccion?> obtenerOrden(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'ordenes_produccion',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return OrdenProduccion.fromMap(rows.first);
  }

  Future<List<OrdenProduccion>> listarOrdenes({
    EstadoOrdenProduccion? estado,
    DateTime? desde,
    DateTime? hasta,
    String? asignadoA,
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
      where += ' AND fecha_creacion >= ?';
      whereArgs.add(desde.toIso8601String());
    }

    if (hasta != null) {
      where += ' AND fecha_creacion <= ?';
      whereArgs.add(hasta.toIso8601String());
    }

    if (asignadoA != null) {
      where += ' AND asignado_a = ?';
      whereArgs.add(asignadoA);
    }

    final rows = await db.query(
      'ordenes_produccion',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'fecha_creacion DESC',
    );

    return rows.map((row) => OrdenProduccion.fromMap(row)).toList();
  }

  Future<void> iniciarProduccion(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final orden = await obtenerOrden(id);
    if (orden == null) throw Exception('Orden no encontrada');

    // Verificar disponibilidad de ingredientes si hay receta
    if (orden.recetaId != null) {
      final receta = await RecetasService.instance.obtenerReceta(orden.recetaId!);
      if (receta != null) {
        final requerimientos = await RecetasService.instance
            .calcularRequerimientosParaProduccion({orden.productoId: orden.cantidad});

        for (final req in requerimientos.entries) {
          final producto = await db.query(
            'productos',
            where: 'id = ?',
            whereArgs: [req.key],
            limit: 1,
          );

          if (producto.isNotEmpty) {
            final stock = (producto.first['stock'] as num).toDouble();
            if (stock < req.value) {
              throw Exception('Stock insuficiente para producto ID ${req.key}');
            }
          }
        }
      }
    }

    await db.update(
      'ordenes_produccion',
      {
        'estado': EstadoOrdenProduccion.en_proceso.name,
        'fecha_inicio': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_INICIADA',
      entidad: 'produccion',
      detalle: 'ID: $id',
    );
  }

  Future<void> completarProduccion(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final orden = await obtenerOrden(id);
    if (orden == null) throw Exception('Orden no encontrada');

    // Descontar ingredientes si hay receta
    if (orden.recetaId != null) {
      final receta = await RecetasService.instance.obtenerReceta(orden.recetaId!);
      if (receta != null) {
        final requerimientos = await RecetasService.instance
            .calcularRequerimientosParaProduccion({orden.productoId: orden.cantidad});

        for (final req in requerimientos.entries) {
          await db.update(
            'productos',
            {'stock': FieldValue.increment(-req.value)},
            where: 'id = ?',
            whereArgs: [req.key],
          );
        }
      }
    }

    // Incrementar stock del producto producido
    await db.update(
      'productos',
      {'stock': FieldValue.increment(orden.cantidad)},
      where: 'id = ?',
      whereArgs: [orden.productoId],
    );

    await db.update(
      'ordenes_produccion',
      {
        'estado': EstadoOrdenProduccion.completada.name,
        'fecha_completado': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_COMPLETADA',
      entidad: 'produccion',
      detalle: 'ID: $id, Cantidad: ${orden.cantidad}',
    );
  }

  Future<void> pausarProduccion(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'ordenes_produccion',
      {'estado': EstadoOrdenProduccion.pausada.name},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_PAUSADA',
      entidad: 'produccion',
      detalle: 'ID: $id',
    );
  }

  Future<void> cancelarProduccion(int id, String motivo) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'ordenes_produccion',
      {
        'estado': EstadoOrdenProduccion.cancelada.name,
        'observaciones': motivo,
      },
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_CANCELADA',
      entidad: 'produccion',
      detalle: 'ID: $id, Motivo: $motivo',
    );
  }

  Future<void> asignarOrden(int id, String asignadoA) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'ordenes_produccion',
      {'asignado_a': asignadoA},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'ORDEN_PRODUCCION_ASIGNADA',
      entidad: 'produccion',
      detalle: 'ID: $id, Asignado a: $asignadoA',
    );
  }

  Future<Map<String, dynamic>> obtenerMetricasProduccion() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'ordenes_produccion',
      where: 'company_id = ?',
      whereArgs: [companyId],
    );

    int pendientes = 0;
    int enProceso = 0;
    int pausadas = 0;
    int completadas = 0;
    int canceladas = 0;

    for (final row in rows) {
      final estado = row['estado'] as String;
      switch (estado) {
        case 'pendiente':
          pendientes++;
          break;
        case 'en_proceso':
          enProceso++;
          break;
        case 'pausada':
          pausadas++;
          break;
        case 'completada':
          completadas++;
          break;
        case 'cancelada':
          canceladas++;
          break;
      }
    }

    return {
      'total': rows.length,
      'pendientes': pendientes,
      'en_proceso': enProceso,
      'pausadas': pausadas,
      'completadas': completadas,
      'canceladas': canceladas,
    };
  }
}

class FieldValue {
  static double increment(double value) => value;
}
