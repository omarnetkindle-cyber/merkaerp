import 'dart:convert';
import '../core/currency/currency.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';

enum UnidadMedida {
  unidad,
  kilogramo,
  litro,
  metro,
  metro_cuadrado,
  metro_cubico,
}

class IngredienteReceta {
  const IngredienteReceta({
    required this.productoId,
    required this.productoNombre,
    required this.cantidad,
    required this.unidad,
    this.costoUnitario,
  });

  final int productoId;
  final String productoNombre;
  final double cantidad;
  final UnidadMedida unidad;
  final MoneyValue? costoUnitario;

  MoneyValue get costoTotal {
    final costo = costoUnitario;
    if (costo == null) {
      throw StateError('A currency-resolved unit cost is required');
    }
    return costo.multiplyDecimal(cantidad.toString());
  }

  Map<String, dynamic> toJson() {
    return {
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'cantidad': cantidad,
      'unidad': unidad.name,
      'costo_unitario': costoUnitario?.toSql(),
    };
  }

  static IngredienteReceta fromJson(
    Map<String, dynamic> json, {
    required Currency currency,
  }) {
    return IngredienteReceta(
      productoId: json['producto_id'] as int,
      productoNombre: json['producto_nombre'] as String,
      cantidad: (json['cantidad'] as num).toDouble(),
      unidad: UnidadMedida.values.firstWhere(
        (e) => e.name == json['unidad'],
        orElse: () => UnidadMedida.unidad,
      ),
      costoUnitario: json['costo_unitario'] == null
          ? null
          : MoneyValue.fromSql(json['costo_unitario'], currency: currency),
    );
  }
}

class Receta {
  const Receta({
    required this.id,
    required this.productoId,
    required this.productoNombre,
    required this.nombre,
    required this.ingredientes,
    required this.costoTotal,
    required this.creadoEn,
    this.descripcion,
    this.version = 1,
    this.activo = true,
  });

  final int id;
  final int productoId;
  final String productoNombre;
  final String nombre;
  final List<IngredienteReceta> ingredientes;
  final MoneyValue costoTotal;
  final DateTime creadoEn;
  final String? descripcion;
  final int version;
  final bool activo;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'nombre': nombre,
      'ingredientes': jsonEncode(ingredientes.map((i) => i.toJson()).toList()),
      'costo_total': costoTotal,
      'creado_en': creadoEn.toIso8601String(),
      'descripcion': descripcion,
      'version': version,
      'activo': activo ? 1 : 0,
    };
  }

  static Receta fromMap(
    Map<String, dynamic> map, {
    required Currency currency,
  }) {
    final ingredientesJson = jsonDecode(map['ingredientes'] as String) as List;
    final ingredientes = ingredientesJson
        .map(
          (i) => IngredienteReceta.fromJson(
            i as Map<String, dynamic>,
            currency: currency,
          ),
        )
        .toList();

    return Receta(
      id: map['id'] as int,
      productoId: map['producto_id'] as int,
      productoNombre: map['producto_nombre'] as String,
      nombre: map['nombre'] as String,
      ingredientes: ingredientes,
      costoTotal: MoneyValue.fromSql(map['costo_total'], currency: currency),
      creadoEn: DateTime.parse(map['creado_en'] as String),
      descripcion: map['descripcion'] as String?,
      version: map['version'] as int? ?? 1,
      activo: (map['activo'] as int?) == 1,
    );
  }
}

class RecetasService {
  RecetasService._();

  static final RecetasService instance = RecetasService._();

  Future<int> crearReceta({
    required int productoId,
    required String productoNombre,
    required String nombre,
    required List<IngredienteReceta> ingredientes,
    String? descripcion,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );

    // Calcular costo total
    var costoTotal = MoneyValue(minorUnits: 0, currency: currency);
    for (final ingrediente in ingredientes) {
      costoTotal += ingrediente.costoTotal;
    }

    final id = await db.insert('recetas', {
      'company_id': companyId,
      'producto_id': productoId,
      'producto_nombre': productoNombre,
      'nombre': nombre,
      'ingredientes': jsonEncode(ingredientes.map((i) => i.toJson()).toList()),
      'costo_total': costoTotal.toSql(),
      'descripcion': descripcion,
      'version': 1,
      'activo': 1,
      'creado_en': DateTime.now().toIso8601String(),
    });

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RECETA_CREADA',
      entidad: 'produccion',
      detalle:
          'ID: $id, Producto: $productoNombre, Costo: ${costoTotal.format()}',
    );

    return id;
  }

  Future<Receta?> obtenerReceta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'recetas',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    return Receta.fromMap(rows.first, currency: currency);
  }

  Future<Receta?> obtenerRecetaPorProducto(int productoId) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.query(
      'recetas',
      where: 'producto_id = ? AND company_id = ? AND activo = ?',
      whereArgs: [productoId, companyId, 1],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    return Receta.fromMap(rows.first, currency: currency);
  }

  Future<List<Receta>> listarRecetas({bool soloActivas = true}) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    String where = 'company_id = ?';
    List<dynamic> whereArgs = [companyId];

    if (soloActivas) {
      where += ' AND activo = ?';
      whereArgs.add(1);
    }

    final rows = await db.query(
      'recetas',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'creado_en DESC',
    );

    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    return rows.map((row) => Receta.fromMap(row, currency: currency)).toList();
  }

  Future<void> actualizarReceta(
    int id, {
    String? nombre,
    List<IngredienteReceta>? ingredientes,
    String? descripcion,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final updates = <String, dynamic>{};

    if (nombre != null) updates['nombre'] = nombre;
    if (ingredientes != null) {
      updates['ingredientes'] = jsonEncode(
        ingredientes.map((i) => i.toJson()).toList(),
      );
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );
      var costoTotal = MoneyValue(minorUnits: 0, currency: currency);
      for (final ingrediente in ingredientes) {
        costoTotal += ingrediente.costoTotal;
      }
      updates['costo_total'] = costoTotal.toSql();
      updates['version'] = FieldValue.increment(1);
    }
    if (descripcion != null) updates['descripcion'] = descripcion;

    await db.update(
      'recetas',
      updates,
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RECETA_ACTUALIZADA',
      entidad: 'produccion',
      detalle: 'ID: $id',
    );
  }

  Future<void> desactivarReceta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.update(
      'recetas',
      {'activo': 0},
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RECETA_DESACTIVADA',
      entidad: 'produccion',
      detalle: 'ID: $id',
    );
  }

  Future<void> eliminarReceta(int id) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    await db.delete(
      'recetas',
      where: 'id = ? AND company_id = ?',
      whereArgs: [id, companyId],
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'RECETA_ELIMINADA',
      entidad: 'produccion',
      detalle: 'ID: $id',
    );
  }

  Future<Map<int, double>> calcularRequerimientosParaProduccion(
    Map<int, double> productosCantidad,
  ) async {
    final requerimientos = <int, double>{};

    for (final entry in productosCantidad.entries) {
      final productoId = entry.key;
      final cantidad = entry.value;

      final receta = await obtenerRecetaPorProducto(productoId);
      if (receta != null) {
        for (final ingrediente in receta.ingredientes) {
          final cantidadRequerida = ingrediente.cantidad * cantidad;
          requerimientos[ingrediente.productoId] =
              (requerimientos[ingrediente.productoId] ?? 0) + cantidadRequerida;
        }
      }
    }

    return requerimientos;
  }

  Future<Map<String, dynamic>> obtenerCostosProduccion(
    Map<int, double> productosCantidad,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    var costoTotal = MoneyValue(minorUnits: 0, currency: currency);
    final desglose = <String, MoneyValue>{};

    for (final entry in productosCantidad.entries) {
      final productoId = entry.key;
      final cantidad = entry.value;

      final receta = await obtenerRecetaPorProducto(productoId);
      if (receta != null) {
        final costoProducto = receta.costoTotal.multiplyDecimal(
          cantidad.toString(),
        );
        costoTotal += costoProducto;
        desglose[receta.productoNombre] = costoProducto;
      }
    }

    return {
      'costo_total': costoTotal.toWireMap(),
      'desglose': desglose.map(
        (key, value) => MapEntry(key, value.toWireMap()),
      ),
    };
  }

  Future<List<Map<String, dynamic>>> obtenerProductosSinReceta() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    final rows = await db.rawQuery(
      '''
      SELECT p.id, p.nombre, p.stock, p.costo
      FROM productos p
      LEFT JOIN recetas r ON p.id = r.producto_id AND r.activo = 1
      WHERE p.company_id = ? AND r.id IS NULL
    ''',
      [companyId],
    );

    return rows.map((row) => row as Map<String, dynamic>).toList();
  }
}

class FieldValue {
  static int increment(int value) => value;
}
