// lib/core/templates/document_template_resolver.dart
//
// Único punto de resolución de plantillas de documentos.
//
// Flujo:
//   1. Busca la plantilla activa/predeterminada por empresa y tipo.
//   2. Si no existe una personalizada, usa la plantilla global (company_id=0).
//   3. Renderiza el HTML con los datos del documento.
//
// Garantiza que cuando `TemplatesPage` marca una plantilla como predeterminada,
// esa decisión se refleja en el documento generado — no se ignora.
//
// Tipos de plantilla soportados:
//   • 'invoice'        → Factura POS
//   • 'quote'          → Cotización
//   • 'purchase_order' → Pedido de compra
//   • 'receipt'        → Recibo de pago

import '../../db_helper.dart';
import 'document_template.dart';
import 'template_service.dart';

class DocumentTemplateResolver {
  DocumentTemplateResolver._();
  static final DocumentTemplateResolver instance = DocumentTemplateResolver._();

  final TemplateService _svc = TemplateService.instance;

  /// Obtiene la plantilla activa para [templateType] en la empresa activa.
  ///
  /// Prioridad:
  ///   1. Plantilla predeterminada de la empresa activa (company_id = X).
  ///   2. Plantilla predeterminada global (company_id = 0).
  ///   3. null si no existe ninguna.
  Future<DocumentTemplate?> resolve(String templateType) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();

    // 1. Plantilla predeterminada de la empresa
    final companyTemplates = await db.query(
      'document_templates',
      where: 'company_id = ? AND template_type = ? AND is_default = 1',
      whereArgs: [companyId, templateType],
      limit: 1,
    );
    if (companyTemplates.isNotEmpty) {
      return DocumentTemplate.fromMap(companyTemplates.first);
    }

    // 2. Plantilla predeterminada global
    final globalTemplates = await db.query(
      'document_templates',
      where: 'company_id = 0 AND template_type = ? AND is_default = 1',
      whereArgs: [templateType],
      limit: 1,
    );
    if (globalTemplates.isNotEmpty) {
      return DocumentTemplate.fromMap(globalTemplates.first);
    }

    // 3. Cualquier plantilla del tipo (fallback)
    return _svc.getDefaultTemplate(db, templateType);
  }

  /// Renderiza el HTML de la plantilla activa con los datos provistos.
  /// Retorna el HTML listo para mostrar o exportar.
  /// Si no existe plantilla, retorna null.
  Future<String?> renderHtml(
    String templateType,
    Map<String, dynamic> data,
  ) async {
    final template = await resolve(templateType);
    if (template == null) return null;
    return _svc.renderDocument(template, data);
  }

  /// Construye el mapa de datos para una factura POS.
  static Map<String, dynamic> buildInvoiceData({
    required Map<String, dynamic> empresa,
    required Map<String, dynamic> venta,
    required String clienteNombre,
    required String clienteNit,
    required String subtotalFmt,
    required String impuestoFmt,
    required String totalFmt,
    required String itemsTableHtml,
  }) {
    return {
      'company_name': empresa['nombre']?.toString() ?? '',
      'company_nit': empresa['nit']?.toString() ?? '',
      'company_address': empresa['direccion']?.toString() ?? '',
      'company_phone': empresa['telefono']?.toString() ?? '',
      'company_email': empresa['email']?.toString() ?? '',
      'document_number': venta['id']?.toString() ?? '',
      'document_date': _shortDate(venta['fecha']?.toString() ?? ''),
      'customer_name': clienteNombre,
      'customer_nit': clienteNit,
      'customer_address': '',
      'customer_phone': '',
      'customer_email': '',
      'document_subtotal': subtotalFmt,
      'document_tax': impuestoFmt,
      'document_total': totalFmt,
      'items_table': itemsTableHtml,
    };
  }

  /// Construye el mapa de datos para una cotización.
  static Map<String, dynamic> buildQuoteData({
    required Map<String, dynamic> empresa,
    required Map<String, dynamic> cotizacion,
    required String clienteNombre,
    required String clienteNit,
    required String subtotalFmt,
    required String impuestoFmt,
    required String totalFmt,
    required String itemsTableHtml,
    String? validUntil,
  }) {
    return {
      'company_name': empresa['nombre']?.toString() ?? '',
      'company_nit': empresa['nit']?.toString() ?? '',
      'company_address': empresa['direccion']?.toString() ?? '',
      'company_phone': empresa['telefono']?.toString() ?? '',
      'company_email': empresa['email']?.toString() ?? '',
      'document_number': cotizacion['id']?.toString() ?? '',
      'document_date': _shortDate(cotizacion['fecha']?.toString() ?? ''),
      'customer_name': clienteNombre,
      'customer_nit': clienteNit,
      'customer_address': '',
      'customer_phone': '',
      'customer_email': '',
      'document_subtotal': subtotalFmt,
      'document_tax': impuestoFmt,
      'document_total': totalFmt,
      'items_table': itemsTableHtml,
      'valid_until': validUntil ?? '',
    };
  }

  /// Genera la tabla HTML de ítems para inyectar en el template.
  static String buildItemsTable(List<Map<String, dynamic>> items) {
    final buffer = StringBuffer('''
<table style="width:100%;border-collapse:collapse;margin:16px 0">
  <thead>
    <tr style="background:#f5f5f5">
      <th style="padding:10px;text-align:left;border-bottom:1px solid #ddd">Descripción</th>
      <th style="padding:10px;text-align:right;border-bottom:1px solid #ddd">Cant.</th>
      <th style="padding:10px;text-align:right;border-bottom:1px solid #ddd">Precio unit.</th>
      <th style="padding:10px;text-align:right;border-bottom:1px solid #ddd">Total</th>
    </tr>
  </thead>
  <tbody>
''');
    for (final item in items) {
      buffer.write('''
    <tr>
      <td style="padding:8px;border-bottom:1px solid #eee">${item['producto'] ?? item['descripcion'] ?? ''}</td>
      <td style="padding:8px;text-align:right;border-bottom:1px solid #eee">${item['cantidad'] ?? ''}</td>
      <td style="padding:8px;text-align:right;border-bottom:1px solid #eee">${item['precio_unitario_fmt'] ?? item['precio_unitario'] ?? ''}</td>
      <td style="padding:8px;text-align:right;border-bottom:1px solid #eee">${item['subtotal_fmt'] ?? item['subtotal'] ?? ''}</td>
    </tr>
''');
    }
    buffer.write('  </tbody>\n</table>');
    return buffer.toString();
  }

  static String _shortDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return iso.substring(0, iso.length.clamp(0, 10));
    }
  }
}
