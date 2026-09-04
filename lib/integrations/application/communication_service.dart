import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../../db_helper.dart';
import 'integration_settings_service.dart';

class CommunicationResult {
  const CommunicationResult({required this.ok, required this.message, this.externalId});
  final bool ok;
  final String message;
  final String? externalId;
}

class CommunicationService {
  CommunicationService._();
  static final CommunicationService instance = CommunicationService._();
  final _settings = IntegrationSettingsService.instance;

  Future<CommunicationResult> sendWhatsAppText({
    required String recipient,
    required String message,
  }) async {
    if (!await _settings.isConfigured('whatsapp_meta')) {
      return const CommunicationResult(ok: false, message: 'WhatsApp Business no está configurado.');
    }
    final values = await _settings.loadValues(
      (await _settings.definitionsForCurrentLicense()).firstWhere((d) => d.key == 'whatsapp_meta'),
    );
    final normalized = recipient.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length < 8) return const CommunicationResult(ok: false, message: 'Número de WhatsApp no válido.');
    try {
      final version = values['api_version']!.trim();
      final phoneId = values['phone_number_id']!.trim();
      final response = await http.post(
        Uri.parse('https://graph.facebook.com/$version/$phoneId/messages'),
        headers: {
          'Authorization': 'Bearer ${values['access_token']}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': normalized,
          'type': 'text',
          'text': {'preview_url': true, 'body': message},
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? id;
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['messages'] is List && (body['messages'] as List).isNotEmpty) {
            id = ((body['messages'] as List).first as Map?)?['id']?.toString();
          }
        } catch (_) {}
        await _audit('WHATSAPP_ENVIADO', recipient, id);
        return CommunicationResult(ok: true, message: 'Mensaje aceptado por WhatsApp Business.', externalId: id);
      }
      return CommunicationResult(ok: false, message: 'WhatsApp respondió HTTP ${response.statusCode}.');
    } catch (_) {
      return const CommunicationResult(ok: false, message: 'No fue posible enviar el mensaje por WhatsApp.');
    }
  }


  Future<CommunicationResult> sendWhatsAppDocument({
    required String recipient,
    required File file,
    String? caption,
  }) async {
    if (!await _settings.isConfigured('whatsapp_meta')) {
      return const CommunicationResult(ok: false, message: 'WhatsApp Business no está configurado.');
    }
    if (!await file.exists()) {
      return const CommunicationResult(ok: false, message: 'El documento que se intentó enviar ya no existe.');
    }
    final definition = (await _settings.definitionsForCurrentLicense()).firstWhere((d) => d.key == 'whatsapp_meta');
    final values = await _settings.loadValues(definition);
    final normalized = recipient.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.length < 8) return const CommunicationResult(ok: false, message: 'Número de WhatsApp no válido.');
    final version = values['api_version']!.trim();
    final phoneId = values['phone_number_id']!.trim();
    final token = values['access_token']!;
    try {
      // 1) Meta exige cargar el archivo y obtener media_id antes de enviar el documento.
      final upload = http.MultipartRequest('POST', Uri.parse('https://graph.facebook.com/$version/$phoneId/media'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['messaging_product'] = 'whatsapp'
        ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: file.uri.pathSegments.last));
      final uploadResponse = await upload.send().timeout(const Duration(seconds: 35));
      final uploadBody = await uploadResponse.stream.bytesToString();
      if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
        return CommunicationResult(ok: false, message: 'WhatsApp no aceptó el archivo (HTTP ${uploadResponse.statusCode}).');
      }
      final decoded = jsonDecode(uploadBody);
      final mediaId = decoded is Map ? decoded['id']?.toString() : null;
      if (mediaId == null || mediaId.isEmpty) {
        return const CommunicationResult(ok: false, message: 'WhatsApp aceptó la carga pero no devolvió un identificador de medio.');
      }

      // 2) Enviar por media_id. Una respuesta 2xx significa aceptado por Meta,
      // no que el destinatario necesariamente lo haya leído.
      final response = await http.post(
        Uri.parse('https://graph.facebook.com/$version/$phoneId/messages'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'messaging_product': 'whatsapp',
          'to': normalized,
          'type': 'document',
          'document': {
            'id': mediaId,
            'filename': file.uri.pathSegments.last,
            if (caption != null && caption.trim().isNotEmpty) 'caption': caption.trim(),
          },
        }),
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return CommunicationResult(ok: false, message: 'WhatsApp no aceptó el envío (HTTP ${response.statusCode}).');
      }
      String? id;
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['messages'] is List && (body['messages'] as List).isNotEmpty) {
          id = ((body['messages'] as List).first as Map?)?['id']?.toString();
        }
      } catch (_) {}
      await _audit('WHATSAPP_DOCUMENTO_ENVIADO', recipient, id ?? mediaId);
      return CommunicationResult(ok: true, message: 'Documento aceptado por WhatsApp Business.', externalId: id ?? mediaId);
    } catch (_) {
      return const CommunicationResult(ok: false, message: 'No fue posible cargar o enviar el documento por WhatsApp.');
    }
  }

  Future<CommunicationResult> sendEmail({
    required String recipient,
    required String subject,
    required String text,
    String? html,
  }) async {
    if (!await _settings.isConfigured('smtp')) {
      return const CommunicationResult(ok: false, message: 'El correo SMTP no está configurado.');
    }
    final definition = (await _settings.definitionsForCurrentLicense()).firstWhere((d) => d.key == 'smtp');
    return _sendEmailWithValues(
      recipient: recipient,
      subject: subject,
      text: text,
      html: html,
      values: await _settings.loadValues(definition),
    );
  }

  /// Envía un correo de prueba real al [testRecipient] (o al sender si no se especifica).
  /// Valida conectividad, autenticación y envío reales contra el servidor SMTP configurado.
  Future<CommunicationResult> sendTestEmail({String? testRecipient}) async {
    if (!await _settings.isConfigured('smtp')) {
      return const CommunicationResult(ok: false, message: 'Configura y habilita SMTP antes de enviar la prueba.');
    }
    final definition = (await _settings.definitionsForCurrentLicense()).firstWhere((d) => d.key == 'smtp');
    final values = await _settings.loadValues(definition);
    final sender = values['sender_email']?.trim() ?? '';
    final recipient = (testRecipient?.trim().isNotEmpty == true) ? testRecipient! : sender;
    if (!recipient.contains('@')) {
      return const CommunicationResult(ok: false, message: 'Destinatario de prueba no válido. Verifica el campo "Correo remitente".');
    }
    return _sendEmailWithValues(
      recipient: recipient,
      subject: '✓ Prueba de configuración SMTP — MerkaERP',
      text:
          'Este es un correo de prueba enviado por MerkaERP para verificar la '
          'configuración SMTP.\n\n'
          'Si lo recibes, la integración de correo está funcionando correctamente.\n\n'
          'Enviado: ${DateTime.now().toLocal()}',
      values: values,
    );
  }

  Future<CommunicationResult> _sendEmailWithValues({
    required String recipient,
    required String subject,
    required String text,
    String? html,
    required Map<String, String> values,
  }) async {
    final host = values['host']!.trim();
    final port = int.tryParse(values['port'] ?? '') ?? 587;
    final username = values['username']!.trim();
    final password = values['password']!;
    final sender = values['sender_email']!.trim();
    final senderName = (values['sender_name'] ?? '').trim();
    if (!recipient.contains('@')) return const CommunicationResult(ok: false, message: 'Correo destinatario no válido.');
    try {
      final server = SmtpServer(
        host,
        port: port,
        username: username,
        password: password,
        ssl: port == 465,
        allowInsecure: false,
      );
      final mail = Message()
        ..from = senderName.isEmpty ? Address(sender) : Address(sender, senderName)
        ..recipients.add(recipient.trim())
        ..subject = subject
        ..text = text;
      if (html != null && html.trim().isNotEmpty) mail.html = html;
      final report = await send(mail, server);
      final external = report.toString();
      await _audit('CORREO_ENVIADO', recipient, external);
      return CommunicationResult(ok: true, message: 'Correo entregado al servidor SMTP.', externalId: external);
    } catch (_) {
      return const CommunicationResult(ok: false, message: 'El servidor SMTP no aceptó el correo. Revisa credenciales, TLS y destinatario.');
    }
  }

  Future<void> _audit(String action, String recipient, String? externalId) =>
      DatabaseHelper.instance.registrarEventoAuditoria(
        accion: action,
        entidad: 'integrations',
        detalle: 'destinatario=$recipient${externalId == null ? '' : '; ref=$externalId'}',
      );
}
