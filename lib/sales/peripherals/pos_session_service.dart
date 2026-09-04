import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../app_session.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';

class PosSessionService {
  PosSessionService._(); static final instance=PosSessionService._();
  Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS pos_product_favorites(
      company_id INTEGER NOT NULL, product_id INTEGER NOT NULL, created_at TEXT NOT NULL,
      PRIMARY KEY(company_id, product_id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS pos_suspended_sales(
      id INTEGER PRIMARY KEY AUTOINCREMENT, company_id INTEGER NOT NULL,
      user_id TEXT NOT NULL, user_name TEXT NOT NULL, created_at TEXT NOT NULL,
      customer_id INTEGER, customer_name TEXT, payment_method_id INTEGER,
      cart_json TEXT NOT NULL, note TEXT)''');
  }
  Future<Set<int>> favoriteIds() async {final db=await DatabaseHelper.instance.database;await _ensure(db);final c=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);final r=await db.query('pos_product_favorites',where:'company_id = ?',whereArgs:[c]);return r.map((e)=>(e['product_id'] as num).toInt()).toSet();}
  Future<void> toggleFavorite(int productId) async {final db=await DatabaseHelper.instance.database;await _ensure(db);final c=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);final rows=await db.query('pos_product_favorites',where:'company_id = ? AND product_id = ?',whereArgs:[c,productId],limit:1);if(rows.isEmpty){await db.insert('pos_product_favorites',{'company_id':c,'product_id':productId,'created_at':DateTime.now().toUtc().toIso8601String()});}else{await db.delete('pos_product_favorites',where:'company_id = ? AND product_id = ?',whereArgs:[c,productId]);}}
  Future<int> suspend({required List<Map<String,dynamic>> cart,required int? customerId,required String customerName,required int paymentMethodId,String note=''}) async {if(cart.isEmpty)throw StateError('No hay productos para suspender.');final db=await DatabaseHelper.instance.database;await _ensure(db);final c=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);final payload=cart.map(_serializeItem).toList();final id=await db.insert('pos_suspended_sales',{'company_id':c,'user_id':AppSession.usuarioId??'local','user_name':AppSession.nombre,'created_at':DateTime.now().toUtc().toIso8601String(),'customer_id':customerId,'customer_name':customerName,'payment_method_id':paymentMethodId,'cart_json':jsonEncode(payload),'note':note.trim()});await DatabaseHelper.instance.registrarEventoAuditoria(accion:'SUSPENDER_VENTA_POS',entidad:'pos_suspended_sales',entidadId:id,detalle:'Venta suspendida por ${AppSession.nombre} con ${cart.length} líneas.');return id;}
  Future<List<Map<String,dynamic>>> list() async {final db=await DatabaseHelper.instance.database;await _ensure(db);final c=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);return db.query('pos_suspended_sales',where:'company_id = ?',whereArgs:[c],orderBy:'created_at DESC',limit:50);}
  Future<Map<String,dynamic>> consume(int id,Currency currency) async {final db=await DatabaseHelper.instance.database;await _ensure(db);final c=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);final rows=await db.query('pos_suspended_sales',where:'company_id = ? AND id = ?',whereArgs:[c,id],limit:1);if(rows.isEmpty)throw StateError('La venta suspendida ya no existe.');final r=rows.first;final raw=jsonDecode(r['cart_json'].toString()) as List;final cart=raw.map((e)=>_deserializeItem(Map<String,dynamic>.from(e as Map),currency)).toList();await db.delete('pos_suspended_sales',where:'company_id = ? AND id = ?',whereArgs:[c,id]);await DatabaseHelper.instance.registrarEventoAuditoria(accion:'RECUPERAR_VENTA_POS',entidad:'pos_suspended_sales',entidadId:id,detalle:'Venta suspendida recuperada por ${AppSession.nombre}.');return {'cart':cart,'customer_id':(r['customer_id'] as num?)?.toInt(),'customer_name':r['customer_name']?.toString()??'Cliente general','payment_method_id':(r['payment_method_id'] as num?)?.toInt()};}
  Map<String,dynamic> _serializeItem(Map<String,dynamic> item)=>item.map((k,v)=>MapEntry(k,v is MoneyValue?{'__money_minor':v.minorUnits,'currency':v.currencyCode}:v));
  Map<String,dynamic> _deserializeItem(Map<String,dynamic> item,Currency currency)=>item.map((k,v){if(v is Map&&v.containsKey('__money_minor'))return MapEntry(k,MoneyValue(minorUnits:(v['__money_minor'] as num).toInt(),currency:currency));return MapEntry(k,v);});
}
