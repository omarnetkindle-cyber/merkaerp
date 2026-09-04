import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'core/templates/pdf_layout_settings_service.dart';
import 'core/templates/document_template_resolver.dart';
import 'app_session.dart';
import 'db_helper.dart';
import 'pdf_output_dialog.dart';

class DocumentoPdfService {
  const DocumentoPdfService._();

  static Future<File> crearFacturaVenta(Map<String, dynamic> venta) async {
    final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final layout = await PdfLayoutSettingsService.instance.load();
    final detalle = await DatabaseHelper.instance.obtenerDetalleVenta(
      (venta['id'] as num).toInt(),
    );
    final currency = await MoneyCurrencyResolver.resolve(
      await DatabaseHelper.instance.database,
      companyId: await DatabaseHelper.instance.obtenerEmpresaActivaId(),
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat(layout),
        build: (_) => [
          _encabezadoEmpresa(empresa, 'Factura POS #${venta['id']}', layout),
          pw.SizedBox(height: 12),
          _bloqueDatos([
            ['Fecha', _fecha(venta['fecha']?.toString() ?? '')],
            ['Cliente', venta['cliente']?.toString() ?? 'Cliente general'],
            ['Estado', venta['estado']?.toString() ?? 'emitida'],
          ]),
          pw.SizedBox(height: 14),
          _tablaProductos(
            detalle.map((item) {
              final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;
              final precio = MoneyValue.fromSql(
                item['precio_unitario'],
                currency: currency,
                nullableAsZero: true,
              );
              final subtotal = MoneyValue.fromSql(
                item['subtotal'],
                currency: currency,
                nullableAsZero: true,
              );
              return [
                item['producto']?.toString() ?? '',
                _cantidad(cantidad),
                _moneda(precio),
                _moneda(subtotal),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _totales(
            subtotal: MoneyValue.fromSql(
              venta['subtotal'],
              currency: currency,
              nullableAsZero: true,
            ),
            impuesto: MoneyValue.fromSql(
              venta['impuesto_total'],
              currency: currency,
              nullableAsZero: true,
            ),
            total: MoneyValue.fromSql(
              venta['total'],
              currency: currency,
              nullableAsZero: true,
            ),
          ),
          pw.SizedBox(height: 22),
          _documentClosure(
            layout,
            'MERKAERP|FACTURA_POS|${venta['id']}|${venta['fecha']}|${venta['total']}|${empresa['nit'] ?? ''}',
          ),
        ],
      ),
    );

    return _guardarPdf(pdf, 'factura_pos_${venta['id']}.pdf');
  }

  static Future<File> crearComprobanteCompra(
    Map<String, dynamic> compra,
  ) async {
    final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final layout = await PdfLayoutSettingsService.instance.load();
    final detalle = await DatabaseHelper.instance.obtenerDetalleCompra(
      (compra['id'] as num).toInt(),
    );
    final currency = await MoneyCurrencyResolver.resolve(
      await DatabaseHelper.instance.database,
      companyId: await DatabaseHelper.instance.obtenerEmpresaActivaId(),
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat(layout),
        build: (_) => [
          _encabezadoEmpresa(empresa, 'Comprobante de compra #${compra['id']}', layout),
          pw.SizedBox(height: 12),
          _bloqueDatos([
            ['Fecha', _fecha(compra['fecha']?.toString() ?? '')],
            ['Proveedor', compra['proveedor']?.toString() ?? 'Sin proveedor'],
            ['Factura proveedor', compra['numero_factura']?.toString() ?? '-'],
            ['Estado', compra['estado']?.toString() ?? ''],
          ]),
          pw.SizedBox(height: 14),
          _tablaProductos(
            detalle.map((item) {
              final cantidad = (item['cantidad'] as num?)?.toDouble() ?? 0;
              final costo = MoneyValue.fromSql(
                item['costo_unitario'],
                currency: currency,
                nullableAsZero: true,
              );
              final subtotal = MoneyValue.fromSql(
                item['subtotal'],
                currency: currency,
                nullableAsZero: true,
              );
              return [
                item['producto']?.toString() ?? '',
                _cantidad(cantidad),
                _moneda(costo),
                _moneda(subtotal),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _totales(
            subtotal: MoneyValue.fromSql(
              compra['subtotal'],
              currency: currency,
              nullableAsZero: true,
            ),
            impuesto: MoneyValue.fromSql(
              compra['impuesto_total'],
              currency: currency,
              nullableAsZero: true,
            ),
            total: MoneyValue.fromSql(
              compra['total'],
              currency: currency,
              nullableAsZero: true,
            ),
          ),
          pw.SizedBox(height: 22),
          _documentClosure(layout, 'MERKAERP|COMPRA|${compra['id']}|${compra['fecha']}|${compra['total']}|${empresa['nit'] ?? ''}'),
        ],
      ),
    );

    return _guardarPdf(pdf, 'comprobante_compra_${compra['id']}.pdf');
  }

  static Future<File> crearComprobanteContable(
    Map<String, dynamic> comprobante,
  ) async {
    final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final layout = await PdfLayoutSettingsService.instance.load();
    final detalle = await DatabaseHelper.instance.obtenerDetalleComprobante(
      (comprobante['id'] as num).toInt(),
    );
    final currency = await MoneyCurrencyResolver.resolve(
      await DatabaseHelper.instance.database,
      companyId: await DatabaseHelper.instance.obtenerEmpresaActivaId(),
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: _pageFormat(layout),
        build: (_) => [
          _encabezadoEmpresa(
            empresa,
            'Comprobante ${comprobante['consecutivo']}',
            layout,
          ),
          pw.SizedBox(height: 12),
          _bloqueDatos([
            ['Fecha', _fecha(comprobante['fecha']?.toString() ?? '')],
            ['Tipo', comprobante['tipo']?.toString() ?? ''],
            ['Concepto', comprobante['concepto']?.toString() ?? ''],
            ['Tercero', comprobante['tercero']?.toString() ?? '-'],
            ['Estado', comprobante['estado']?.toString() ?? ''],
          ]),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: ['Cuenta', 'Descripcion', 'Debito', 'Credito'],
            data: detalle.map((linea) {
              return [
                '${linea['codigo']} ${linea['cuenta']}',
                linea['descripcion']?.toString() ?? '',
                _moneda(
                  MoneyValue.fromSql(
                    linea['debito'],
                    currency: currency,
                    nullableAsZero: true,
                  ),
                ),
                _moneda(
                  MoneyValue.fromSql(
                    linea['credito'],
                    currency: currency,
                    nullableAsZero: true,
                  ),
                ),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF3E8BE),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total: ${_moneda(MoneyValue.fromSql(comprobante['total'], currency: currency, nullableAsZero: true))}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
            ),
          ),
          pw.SizedBox(height: 22),
          _documentClosure(layout, 'MERKAERP|COMPROBANTE|${comprobante['consecutivo']}|${comprobante['fecha']}|${comprobante['total']}|${empresa['nit'] ?? ''}'),
        ],
      ),
    );

    return _guardarPdf(pdf, 'comprobante_${comprobante['consecutivo']}.pdf');
  }

  static Future<void> compartir(File archivo, String asunto) async {
    await Printing.sharePdf(
      bytes: await archivo.readAsBytes(),
      filename: archivo.uri.pathSegments.last,
    );
  }

  static Future<void> imprimir(File archivo) async {
    await Printing.layoutPdf(onLayout: (_) async => archivo.readAsBytes());
  }

  /// Muestra diálogo Imprimir / Correo / Visualizar para un PDF guardado.
  static Future<void> mostrarOpcionesSalida(
    BuildContext context,
    File archivo, {
    String titulo = 'Documento PDF',
    String? emailDestino,
  }) async {
    await PdfOutputDialog.mostrar(
      context: context,
      titulo: titulo,
      emailDestino: emailDestino,
      generarBytes: () async => archivo.readAsBytes(),
    );
  }

  static pw.Widget _encabezadoEmpresa(
    Map<String, dynamic> empresa,
    String documento,
    PdfLayoutSettings layout,
  ) {
    final nombre = empresa['nombre']?.toString().trim().isEmpty ?? true
        ? 'MerkaERP'
        : empresa['nombre'].toString();
    final logoPath = empresa['logo_path']?.toString() ?? '';
    pw.ImageProvider? logo;
    if (layout.showLogo && logoPath.isNotEmpty && File(logoPath).existsSync()) {
      logo = pw.MemoryImage(File(logoPath).readAsBytesSync());
    }
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) ...[
              pw.Image(logo, width: 56, height: 56, fit: pw.BoxFit.contain),
              pw.SizedBox(width: 10),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  nombre,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if ((empresa['nit'] ?? '').toString().isNotEmpty)
                  pw.Text('NIT/Doc: ${empresa['nit']}'),
                if ((empresa['regimen'] ?? '').toString().isNotEmpty)
                  pw.Text('Regimen: ${empresa['regimen']}'),
                if ((empresa['direccion'] ?? '').toString().isNotEmpty)
                  pw.Text('Direccion: ${empresa['direccion']}'),
                if ((empresa['telefono'] ?? '').toString().isNotEmpty)
                  pw.Text('Telefono: ${empresa['telefono']}'),
                if ((empresa['email'] ?? '').toString().isNotEmpty)
                  pw.Text('Email: ${empresa['email']}'),
                if ((empresa['ciudad'] ?? '').toString().isNotEmpty)
                  pw.Text('Ciudad: ${empresa['ciudad']}'),
              ],
            ),
          ],
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: const PdfColor.fromInt(0xFF0A2540)),
          ),
          child: pw.Text(
            documento,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    );
  }

  static pw.Widget _bloqueDatos(List<List<String>> filas) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF7F7F7),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        children: filas
            .map(
              (fila) => pw.Row(
                children: [
                  pw.SizedBox(
                    width: 95,
                    child: pw.Text(
                      fila[0],
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Expanded(child: pw.Text(fila[1])),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  static pw.Widget _tablaProductos(List<List<String>> data) {
    return pw.TableHelper.fromTextArray(
      headers: ['Producto', 'Cant.', 'Valor unit.', 'Subtotal'],
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF3E8BE),
      ),
    );
  }

  static pw.Widget _totales({
    required MoneyValue subtotal,
    required MoneyValue impuesto,
    required MoneyValue total,
  }) {
    pw.Widget row(String label, String value, {bool strong = false}) {
      return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              label,
              textAlign: pw.TextAlign.right,
              style: strong
                  ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  : null,
            ),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: strong
                  ? pw.TextStyle(fontWeight: pw.FontWeight.bold)
                  : null,
            ),
          ),
        ],
      );
    }

    return pw.Column(
      children: [
        row('Subtotal', _moneda(subtotal)),
        row('Impuesto', _moneda(impuesto)),
        row('Total', _moneda(total), strong: true),
      ],
    );
  }


  static PdfPageFormat _pageFormat(PdfLayoutSettings layout) =>
      layout.paperSize == 'letter' ? PdfPageFormat.letter : PdfPageFormat.a4;

  static pw.Widget _documentClosure(PdfLayoutSettings layout, String verificationData) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: const PdfColor.fromInt(0xFFD4A72C)),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(height: 20),
                  pw.Container(width: 180, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey700)))),
                  pw.SizedBox(height: 4),
                  pw.Text(layout.signatureLabel.isEmpty ? 'Responsable / autorizado' : layout.signatureLabel, style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Generado por: ${AppSession.nombre}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
            ),
            if (layout.showInternalQr)
              pw.Column(
                children: [
                  pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: verificationData, width: 56, height: 56),
                  pw.SizedBox(height: 3),
                  pw.Text('Trazabilidad interna', style: const pw.TextStyle(fontSize: 7)),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          layout.footerText.isEmpty ? 'Documento generado por MerkaERP.' : layout.footerText,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        if (layout.showInternalQr)
          pw.Text(
            'El QR anterior es de control interno. No sustituye CUFE, QR DIAN, firma digital ni validaciones regulatorias cuando sean exigibles.',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
      ],
    );
  }

  static Future<File> _guardarPdf(pw.Document pdf, String nombre) async {
    final dir = await getTemporaryDirectory();
    final archivo = File(p.join(dir.path, nombre));
    await archivo.writeAsBytes(await pdf.save());
    return archivo;
  }

  static String _moneda(MoneyValue valor) => valor.format();

  static String _cantidad(double valor) =>
      valor % 1 == 0 ? valor.toInt().toString() : valor.toString();

  static String _fecha(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String pad(int n) => n.toString().padLeft(2, '0');
      return '${pad(dt.day)}/${pad(dt.month)}/${dt.year} ${pad(dt.hour)}:${pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  // ── Render HTML usando plantilla activa ────────────────────────────────────
  //
  // Estos métodos son el puente entre el TemplateService (plantillas en BD)
  // y el documento final. Si la empresa configuró una plantilla personalizada
  // en TemplatesPage → setAsDefault, ese HTML es el que se genera aquí.
  // Si no hay plantilla personalizada, se usa la plantilla global por defecto.
  //
  // El HTML se puede usar para:
  //   • Vista previa en WebView dentro de la app.
  //   • Exportación HTML independiente.
  //   • Futura integración con servicios de generación de PDF basados en HTML.

  /// Genera el HTML de una factura POS usando la plantilla activa para
  /// la empresa. Retorna null si no existe ninguna plantilla registrada.
  static Future<String?> renderHtmlFactura(
    Map<String, dynamic> venta, {
    required Map<String, dynamic> empresa,
    required List<Map<String, dynamic>> detalle,
    required String currency,
  }) async {
    final itemsHtml = DocumentTemplateResolver.buildItemsTable(
      detalle.map((item) => {
        'producto': item['producto']?.toString() ?? '',
        'cantidad': _cantidad((item['cantidad'] as num?)?.toDouble() ?? 0),
        'precio_unitario_fmt': item['precio_unitario_fmt']?.toString() ??
            item['precio_unitario']?.toString() ?? '',
        'subtotal_fmt': item['subtotal_fmt']?.toString() ??
            item['subtotal']?.toString() ?? '',
      }).toList(),
    );
    final data = DocumentTemplateResolver.buildInvoiceData(
      empresa: empresa,
      venta: venta,
      clienteNombre: venta['cliente']?.toString() ?? 'Cliente general',
      clienteNit: '',
      subtotalFmt: venta['subtotal_fmt']?.toString() ??
          venta['subtotal']?.toString() ?? '',
      impuestoFmt: venta['impuesto_total_fmt']?.toString() ??
          venta['impuesto_total']?.toString() ?? '',
      totalFmt: venta['total_fmt']?.toString() ??
          venta['total']?.toString() ?? '',
      itemsTableHtml: itemsHtml,
    );
    return DocumentTemplateResolver.instance.renderHtml('invoice', data);
  }

  /// Genera el HTML de una cotización usando la plantilla activa.
  static Future<String?> renderHtmlCotizacion(
    Map<String, dynamic> cotizacion, {
    required Map<String, dynamic> empresa,
    required List<Map<String, dynamic>> detalle,
    String? validUntil,
  }) async {
    final itemsHtml = DocumentTemplateResolver.buildItemsTable(
      detalle.map((item) => {
        'producto': item['producto']?.toString() ?? '',
        'cantidad': _cantidad((item['cantidad'] as num?)?.toDouble() ?? 0),
        'precio_unitario_fmt': item['precio_unitario_fmt']?.toString() ??
            item['precio_unitario']?.toString() ?? '',
        'subtotal_fmt': item['subtotal_fmt']?.toString() ??
            item['subtotal']?.toString() ?? '',
      }).toList(),
    );
    final data = DocumentTemplateResolver.buildQuoteData(
      empresa: empresa,
      cotizacion: cotizacion,
      clienteNombre: cotizacion['cliente']?.toString() ?? 'Cliente',
      clienteNit: '',
      subtotalFmt: cotizacion['subtotal_fmt']?.toString() ??
          cotizacion['subtotal']?.toString() ?? '',
      impuestoFmt: cotizacion['impuesto_fmt']?.toString() ??
          cotizacion['impuesto']?.toString() ?? '',
      totalFmt: cotizacion['total_fmt']?.toString() ??
          cotizacion['total']?.toString() ?? '',
      itemsTableHtml: itemsHtml,
      validUntil: validUntil,
    );
    return DocumentTemplateResolver.instance.renderHtml('quote', data);
  }
}
