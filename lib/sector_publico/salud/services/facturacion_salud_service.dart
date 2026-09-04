/// Servicio de Facturación y Contratación de Salud Pública (EPS / ADRES)
/// Servicio intermedio entre RIPS y Glosas para la conciliación de cartera en salud
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/contrato_eps.dart';
import '../models/factura_salud.dart';
import '../../security/auditoria_service.dart';
import '../../models/registro_auditoria.dart';

class FacturacionSaludService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  FacturacionSaludService({required this.db, required this.auditoriaService});

  /// Registra un contrato de capitación / evento con EPS o ADRES
  Future<ContratoEPS> registrarContratoEPS({
    required String entidadId,
    required String usuarioId,
    required String numeroContrato,
    required String epsAdresNombre,
    required String epsAdresNit,
    required RegimenSalud regimen,
    required MoneyValue montoContrato,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    String? observaciones,
  }) async {
    final id = _uuid.v4();

    final contrato = ContratoEPS(
      id: id,
      entidadId: entidadId,
      numeroContrato: numeroContrato,
      epsAdresNombre: epsAdresNombre,
      epsAdresNit: epsAdresNit,
      regimen: regimen,
      montoContrato: montoContrato,
      montoFacturado: publicMoneyZero(),
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      estado: 'activo',
      observaciones: observaciones,
    );

    await db.insert('contratos_eps_adres', contrato.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'salud',
      accion: 'registrar_contrato_eps',
      valorAnterior: {},
      valorNuevo: {
        'contrato_id': id,
        'numero_contrato': numeroContrato,
        'eps_nombre': epsAdresNombre,
        'monto_contrato': montoContrato.toWireMap(),
      },
      referenciaId: id,
    );

    return contrato;
  }

  /// Genera una factura de prestación de servicios de salud vinculada a un contrato EPS/ADRES
  Future<FacturaSalud> generarFacturaSalud({
    required String entidadId,
    required String usuarioId,
    required String contratoId,
    required String numeroFactura,
    required String periodo,
    required MoneyValue montoTotal,
    String? observaciones,
  }) async {
    final resContrato = await db.query(
      'contratos_eps_adres',
      where: 'id = ?',
      whereArgs: [contratoId],
    );
    if (resContrato.isEmpty) throw Exception('Contrato EPS no encontrado');

    final contrato = ContratoEPS.fromJson(resContrato.first);

    final id = _uuid.v4();

    final factura = FacturaSalud(
      id: id,
      entidadId: entidadId,
      contratoId: contratoId,
      numeroFactura: numeroFactura,
      periodo: periodo,
      montoTotal: montoTotal,
      montoGlosado: publicMoneyZero(),
      montoPagado: publicMoneyZero(),
      fechaEmision: DateTime.now(),
      estado: 'emitida',
      observaciones: observaciones,
    );

    await db.insert('facturas_salud', factura.toJson());

    // Actualizar el monto acumulado facturado en el contrato EPS
    final nuevoMontoFacturado = contrato.montoFacturado + montoTotal;
    await db.update(
      'contratos_eps_adres',
      {'monto_facturado': nuevoMontoFacturado.toSql()},
      where: 'id = ?',
      whereArgs: [contratoId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'salud',
      accion: 'generar_factura_salud',
      valorAnterior: {},
      valorNuevo: {
        'factura_id': id,
        'numero_factura': numeroFactura,
        'monto_total': montoTotal.toWireMap(),
        'contrato_id': contratoId,
      },
      referenciaId: id,
    );

    return factura;
  }

  /// Consultar Contratos EPS/ADRES
  Future<List<ContratoEPS>> consultarContratos({
    required String entidadId,
  }) async {
    final res = await db.query(
      'contratos_eps_adres',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
      orderBy: 'fecha_inicio DESC',
    );
    return res.map((r) => ContratoEPS.fromJson(r)).toList();
  }

  /// Consultar Facturas de Salud
  Future<List<FacturaSalud>> consultarFacturas({
    required String entidadId,
    String? contratoId,
  }) async {
    String query = 'SELECT * FROM facturas_salud WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (contratoId != null) {
      query += ' AND contrato_id = ?';
      args.add(contratoId);
    }

    query += ' ORDER BY fecha_emision DESC';
    final res = await db.rawQuery(query, args);
    return res.map((r) => FacturaSalud.fromJson(r)).toList();
  }

  /// Exportar Factura de Salud a formato plano .txt para cobro a EPS / ADRES
  Future<String> exportarFacturaAPlano(String facturaId) async {
    final res = await db.query(
      'facturas_salud',
      where: 'id = ?',
      whereArgs: [facturaId],
    );
    if (res.isEmpty) throw Exception('Factura de salud no encontrada');
    final fac = FacturaSalud.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'FACTURA_SALUD_HEADER|${fac.numeroFactura}|${fac.entidadId}|CONTRATO|${fac.contratoId}',
    );
    buffer.writeln(
      'VALORES|PERIODO|${fac.periodo}|MONTO_TOTAL|${publicMoneyForDisplay(fac.montoTotal)}|GLOSADO|${publicMoneyForDisplay(fac.montoGlosado)}|PAGADO|${publicMoneyForDisplay(fac.montoPagado)}',
    );
    buffer.writeln(
      'ESTADO|${fac.estado}|FECHA|${fac.fechaEmision.toIso8601String()}',
    );
    buffer.writeln('FACTURA_SALUD_FOOTER|DOCUMENTO_OFICIAL_COBRO_EPS_ADRES');

    return buffer.toString();
  }
}
