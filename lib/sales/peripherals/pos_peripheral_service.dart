import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';

class PosPeripheralConfig {
  const PosPeripheralConfig({
    this.printerHost = '', this.printerPort = 9100, this.autoPrint = false,
    this.openDrawerAfterCashSale = false,
    this.labelHost = '', this.labelPort = 9100, this.labelLanguage = 'ZPL',
    this.scaleHost = '', this.scalePort = 4001, this.touchMode = false,
  });
  final String printerHost; final int printerPort; final bool autoPrint;
  final bool openDrawerAfterCashSale;
  final String labelHost; final int labelPort; final String labelLanguage;
  final String scaleHost; final int scalePort; final bool touchMode;
}

/// Integración directa con periféricos de red, sin servicios en nube.
///
/// Los lectores de código de barras USB que operan como teclado ya funcionan
/// con el campo de escaneo del POS. Para impresoras/cajón se usa ESC/POS por
/// TCP; etiquetas admiten ZPL/TSPL en modo RAW; las básculas TCP se leen en
/// modo texto. USB/serial nativo requiere driver/adaptador del fabricante.
class PosPeripheralService {
  PosPeripheralService._();
  static final PosPeripheralService instance = PosPeripheralService._();

  Future<void> _ensure(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pos_peripheral_config(
        company_id INTEGER PRIMARY KEY,
        printer_host TEXT NOT NULL DEFAULT '', printer_port INTEGER NOT NULL DEFAULT 9100,
        auto_print INTEGER NOT NULL DEFAULT 0, open_drawer_cash INTEGER NOT NULL DEFAULT 0,
        label_host TEXT NOT NULL DEFAULT '', label_port INTEGER NOT NULL DEFAULT 9100,
        label_language TEXT NOT NULL DEFAULT 'ZPL',
        scale_host TEXT NOT NULL DEFAULT '', scale_port INTEGER NOT NULL DEFAULT 4001,
        touch_mode INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info(pos_peripheral_config)');
    if (!columns.any((row) => row['name']?.toString() == 'touch_mode')) {
      await db.execute(
        'ALTER TABLE pos_peripheral_config ADD COLUMN touch_mode INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<PosPeripheralConfig> load() async {
    final db = await DatabaseHelper.instance.database; await _ensure(db);
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final rows = await db.query('pos_peripheral_config', where:'company_id = ?', whereArgs:[companyId], limit:1);
    if(rows.isEmpty) return const PosPeripheralConfig();
    final r=rows.first;
    return PosPeripheralConfig(
      printerHost:r['printer_host']?.toString()??'', printerPort:(r['printer_port'] as num?)?.toInt()??9100,
      autoPrint:r['auto_print']==1, openDrawerAfterCashSale:r['open_drawer_cash']==1,
      labelHost:r['label_host']?.toString()??'', labelPort:(r['label_port'] as num?)?.toInt()??9100,
      labelLanguage:r['label_language']?.toString()??'ZPL', scaleHost:r['scale_host']?.toString()??'',
      scalePort:(r['scale_port'] as num?)?.toInt()??4001, touchMode:r['touch_mode']==1,
    );
  }

  Future<void> save(PosPeripheralConfig c) async {
    final db=await DatabaseHelper.instance.database; await _ensure(db);
    final companyId=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.insert('pos_peripheral_config',{
      'company_id':companyId,'printer_host':c.printerHost.trim(),'printer_port':c.printerPort,
      'auto_print':c.autoPrint?1:0,'open_drawer_cash':c.openDrawerAfterCashSale?1:0,
      'label_host':c.labelHost.trim(),'label_port':c.labelPort,'label_language':c.labelLanguage,
      'scale_host':c.scaleHost.trim(),'scale_port':c.scalePort,'touch_mode':c.touchMode?1:0,'updated_at':DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm:ConflictAlgorithm.replace);
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion:'CONFIGURAR_PERIFERICOS_POS',entidad:'pos_peripheral_config',
      detalle:'Configuración de periféricos actualizada. No se almacenan credenciales en esta configuración.',
    );
  }

  Future<void> printTestReceipt() async {
    final c=await load(); _require(c.printerHost,'impresora');
    await _sendRaw(c.printerHost,c.printerPort,_escPosText('MERKA ERP\nPrueba de impresora\n${DateTime.now()}\n\n\n',cut:true));
  }

  Future<void> openCashDrawer() async {
    final c=await load(); _require(c.printerHost,'impresora/cajón');
    await _sendRaw(c.printerHost,c.printerPort,[0x1B,0x70,0x00,0x19,0xFA]);
  }

  Future<String> readScale() async {
    final c=await load(); _require(c.scaleHost,'báscula TCP');
    final socket=await Socket.connect(c.scaleHost,c.scalePort,timeout:const Duration(seconds:4));
    try {
      final text=await utf8.decoder.bind(socket).join().timeout(const Duration(seconds:2),onTimeout:()=> '');
      final match=RegExp(r'-?\d+(?:[\.,]\d+)?').firstMatch(text);
      if(match==null) throw StateError('La báscula respondió, pero no se encontró un peso numérico.');
      return match.group(0)!.replaceAll(',','.');
    } finally { await socket.close(); }
  }

  Future<void> printLabel({required String name,required String code,required String price}) async {
    final c=await load(); _require(c.labelHost,'impresora de etiquetas');
    final cleanName=name.replaceAll('^',' ').replaceAll('~',' ');
    final cleanCode=code.replaceAll('^','').replaceAll('~','');
    final payload=c.labelLanguage.toUpperCase()=='TSPL'
      ? 'SIZE 60 mm,40 mm\r\nCLS\r\nTEXT 30,30,"3",0,1,1,"$cleanName"\r\nBARCODE 30,90,"128",80,1,0,2,2,"$cleanCode"\r\nTEXT 30,190,"3",0,1,1,"$price"\r\nPRINT 1\r\n'
      : '^XA^PW480^FO25,25^A0N,30,30^FD$cleanName^FS^FO25,75^BCN,80,Y,N,N^FD$cleanCode^FS^FO25,190^A0N,32,32^FD$price^FS^XZ';
    await _sendRaw(c.labelHost,c.labelPort,utf8.encode(payload));
  }

  Future<void> afterSale(int saleId) async {
    final c=await load(); if(!c.autoPrint || c.printerHost.trim().isEmpty)return;
    final db=await DatabaseHelper.instance.database;
    final companyId=await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final currency=await MoneyCurrencyResolver.resolve(db,companyId:companyId);
    final sale=await db.query('ventas',where:'company_id = ? AND id = ?',whereArgs:[companyId,saleId],limit:1);
    if(sale.isEmpty)return;
    final details=await db.query('ventas_detalle',where:'company_id = ? AND venta_id = ?',whereArgs:[companyId,saleId]);
    final total=MoneyValue.fromSql(sale.first['total'],currency:currency,nullableAsZero:true).format();
    final lines=<String>['MERKA ERP','Factura POS #$saleId','Cliente: ${sale.first['cliente'] ?? 'Cliente general'}','--------------------------------'];
    for(final d in details){
      final subtotal=MoneyValue.fromSql(d['subtotal'],currency:currency,nullableAsZero:true).format();
      lines.add('${d['cantidad']} x ${d['producto']}'); lines.add('  $subtotal');
    }
    lines.addAll(['--------------------------------','TOTAL $total','','Gracias por su compra','','']);
    await _sendRaw(c.printerHost,c.printerPort,_escPosText(lines.join('\n'),cut:true));
    final methodId=(sale.first['metodo_pago_id'] as num?)?.toInt();
    if(c.openDrawerAfterCashSale && methodId!=null){
      final methods=await db.query('metodos_pago',where:'id = ?',whereArgs:[methodId],limit:1);
      if(methods.isNotEmpty && methods.first['nombre'].toString().toUpperCase().contains('EFECTIVO')){
        await openCashDrawer();
      }
    }
  }

  List<int> _escPosText(String text,{bool cut=false})=>[
    0x1B,0x40,...utf8.encode(text),...(cut?[0x1D,0x56,0x00]:const <int>[]),
  ];
  Future<void> _sendRaw(String host,int port,List<int> bytes) async {
    final socket=await Socket.connect(host,port,timeout:const Duration(seconds:5));
    try { socket.add(bytes); await socket.flush(); } finally { await socket.close(); }
  }
  void _require(String value,String device){ if(value.trim().isEmpty) throw StateError('Configura la dirección de $device.'); }
}
