import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DocumentReportsService {
  const DocumentReportsService._();

  static Future<Uint8List> radicadoReceipt({
    required Map<String, Object?> radicado,
    required List<Map<String, Object?>> workflow,
    String organizationName = 'MerkaERP',
  }) async {
    final pdf = pw.Document();
    final number = radicado['number']?.toString() ?? '';
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(organizationName, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text('COMPROBANTE DE RADICACIÓN', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    _line('Radicado', number),
                    _line('Dirección', _direction(radicado['direction']?.toString())),
                    _line('Fecha y hora', _date(radicado['received_at'])),
                    _line('Canal', radicado['channel']?.toString() ?? ''),
                    _line('Estado', radicado['status']?.toString() ?? ''),
                    if (radicado['due_at'] != null) _line('Vencimiento', _date(radicado['due_at'])),
                  ]),
                ),
                if (number.isNotEmpty)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'MERKAERP:RADICADO:$number',
                    width: 92,
                    height: 92,
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            _line('Asunto', radicado['subject']?.toString() ?? ''),
            _line('Remitente', radicado['sender_name']?.toString() ?? ''),
            _line('Destinatario', radicado['recipient_name']?.toString() ?? ''),
            if ((radicado['description']?.toString() ?? '').isNotEmpty)
              _line('Descripción', radicado['description']?.toString() ?? ''),
            pw.SizedBox(height: 18),
            pw.Text('TRAZABILIDAD INICIAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (workflow.isEmpty)
              pw.Text('Sin actuaciones registradas.')
            else
              pw.TableHelper.fromTextArray(
                headers: const ['Fecha', 'Actuación', 'Estado', 'Responsable/usuario'],
                data: workflow.take(12).map((row) => [
                  _date(row['created_at']),
                  row['action']?.toString() ?? '',
                  row['to_status']?.toString() ?? '',
                  row['to_user_id']?.toString() ?? row['actor_user_id']?.toString() ?? '',
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                cellStyle: const pw.TextStyle(fontSize: 8),
                border: pw.TableBorder.all(width: .4),
              ),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Este comprobante identifica el registro dentro del sistema de gestión documental. '
              'La integridad de los documentos electrónicos asociados se controla mediante huella SHA-256 y bitácora de acceso.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static Future<Uint8List> fuid({
    required Map<String, Object?> transfer,
    required List<Map<String, Object?>> items,
    String organizationName = 'MerkaERP',
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(organizationName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          pw.Text('INVENTARIO DOCUMENTAL / SOPORTE DE TRANSFERENCIA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.Text('Transferencia: ${transfer['transfer_number'] ?? ''} · ${transfer['from_stage'] ?? ''} → ${transfer['to_stage'] ?? ''}'),
          pw.SizedBox(height: 8),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const ['No.', 'Código expediente', 'Unidad documental / asunto', 'Etapa', 'Cierre', 'Aceptado', 'Observación'],
            data: List.generate(items.length, (index) {
              final row = items[index];
              return [
                '${index + 1}', row['expediente_code']?.toString() ?? '',
                row['expediente_title']?.toString() ?? '', row['current_archive_stage']?.toString() ?? '',
                _date(row['closed_at']), row['accepted'] == 1 ? 'Sí' : row['accepted'] == 0 ? 'No' : 'Pendiente',
                row['observation']?.toString() ?? '',
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7),
            border: pw.TableBorder.all(width: .35),
          ),
          pw.SizedBox(height: 16),
          pw.Text('Acta / referencia: ${transfer['act_reference'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Estado: ${transfer['status'] ?? ''}', style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.RichText(text: pw.TextSpan(children: [
          pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.TextSpan(text: value),
        ])),
      );

  static String _direction(String? value) => switch (value) {
        'incoming' => 'Recibido', 'outgoing' => 'Enviado', 'internal' => 'Interno', _ => value ?? '',
      };

  static String _date(Object? value) {
    final raw = value?.toString() ?? '';
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
