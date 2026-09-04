import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Diálogo con opciones de salida para documentos PDF.
class PdfOutputDialog {
  static Future<void> mostrar({
    required BuildContext context,
    required String titulo,
    required Future<Uint8List> Function() generarBytes,
    String? emailDestino,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: const Text('Seleccione cómo desea procesar el documento PDF:'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Imprimir'),
            onPressed: () async {
              Navigator.pop(ctx);
              final bytes = await generarBytes();
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Compartir PDF'),
            onPressed: () async {
              Navigator.pop(ctx);
              final bytes = await generarBytes();
              await Printing.sharePdf(bytes: bytes, filename: 'documento.pdf');
              if (!context.mounted) return;
              final destino = emailDestino?.trim();
              if (destino != null && destino.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Use el selector del sistema para compartir el PDF. Destinatario sugerido: $destino'),
                  ),
                );
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Visualizar'),
            onPressed: () async {
              Navigator.pop(ctx);
              final bytes = await generarBytes();
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            },
          ),
        ],
      ),
    );
  }

}
