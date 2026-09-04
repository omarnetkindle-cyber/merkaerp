import 'package:flutter/material.dart';

import '../../app_session.dart';
import '../../sector_publico/security/roles_permisos_service.dart';
import '../application/communication_service.dart';
import '../application/integration_settings_service.dart';
import '../domain/integration_definition.dart';
import '../domain/integration_profile.dart';

class IntegrationsPage extends StatefulWidget {
  const IntegrationsPage({super.key});

  @override
  State<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends State<IntegrationsPage> {
  final service = IntegrationSettingsService.instance;
  late Future<List<IntegrationDefinition>> _definitions;

  bool get _canEdit =>
      AppSession.puedeAdministrar() ||
      AppSession.puedeEjecutarPermiso(Permiso.configurarEntidad);

  @override
  void initState() {
    super.initState();
    _definitions = service.definitionsForCurrentLicense();
  }

  void _reload() => setState(() {
        _definitions = service.definitionsForCurrentLicense();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de Integraciones'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
        ],
      ),
      body: FutureBuilder<List<IntegrationDefinition>>(
        future: _definitions,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final definitions = snapshot.data!;
          final grouped = <String, List<IntegrationDefinition>>{};
          for (final definition in definitions) {
            grouped.putIfAbsent(definition.category, () => []).add(definition);
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.key_outlined, size: 34),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Credenciales propiedad de cada organización', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            const Text('MerkaERP entrega los conectores preparados. Cada empresa o entidad registra sus propias credenciales; los secretos se guardan en el almacén seguro del sistema operativo y no en SQLite.'),
                            if (!_canEdit) ...[
                              const SizedBox(height: 8),
                              const Text('Tu rol puede consultar el estado, pero no modificar credenciales.', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final group in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(group.key, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1100 ? 3 : constraints.maxWidth >= 700 ? 2 : 1;
                    final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final definition in group.value)
                          SizedBox(width: width, child: _IntegrationCard(definition: definition, canEdit: _canEdit, onChanged: _reload)),
                      ],
                    );
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({required this.definition, required this.canEdit, required this.onChanged});

  final IntegrationDefinition definition;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final service = IntegrationSettingsService.instance;
    return FutureBuilder<IntegrationProfile>(
      future: service.load(definition.key),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final status = profile?.status ?? 'not_configured';
        final enabled = profile?.enabled ?? false;
        final statusInfo = _status(status, enabled);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: canEdit ? () => _openDialog(context) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(child: Icon(_iconFor(definition.key))),
                      const SizedBox(width: 12),
                      Expanded(child: Text(definition.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      Icon(statusInfo.$1, color: statusInfo.$2),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(definition.description, maxLines: 4, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(label: Text(statusInfo.$3), avatar: Icon(enabled ? Icons.toggle_on : Icons.toggle_off, size: 18)),
                      if (profile?.lastCheckedAt != null)
                        Text('Verificado ${_shortDate(profile!.lastCheckedAt!)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDialog(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IntegrationDialog(definition: definition),
    );
    if (changed == true) onChanged();
  }

  static (IconData, Color, String) _status(String status, bool enabled) {
    if (!enabled) return (Icons.pause_circle_outline, Colors.grey, 'Deshabilitada');
    return switch (status) {
      'connected' => (Icons.check_circle, Colors.green, 'Conectada'),
      'error' => (Icons.error, Colors.red, 'Error'),
      'configured' => (Icons.settings_suggest, Colors.orange, 'Configurada'),
      _ => (Icons.radio_button_unchecked, Colors.grey, 'Sin configurar'),
    };
  }

  static IconData _iconFor(String key) => switch (key) {
        'dian' => Icons.receipt_long,
        'whatsapp_meta' => Icons.chat,
        'smtp' => Icons.email,
        'stripe' || 'paypal' || 'mercadopago' => Icons.payments,
        'cloud_backup' => Icons.cloud_upload,
        'trm_source' => Icons.currency_exchange,
        'transparency_portal' => Icons.public,
        'signature_provider' => Icons.draw,
        _ => Icons.hub,
      };

  static String _shortDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _IntegrationDialog extends StatefulWidget {
  const _IntegrationDialog({required this.definition});
  final IntegrationDefinition definition;

  @override
  State<_IntegrationDialog> createState() => _IntegrationDialogState();
}

class _IntegrationDialogState extends State<_IntegrationDialog> {
  final service = IntegrationSettingsService.instance;
  final Map<String, TextEditingController> controllers = {};
  final Map<String, bool> toggles = {};
  final Map<String, String?> choices = {};
  final Map<String, bool> existingSecrets = {};
  bool enabled = false;
  bool loading = true;
  bool saving = false;
  String? message;
  bool? messageOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await service.load(widget.definition.key);
    final values = await service.loadValues(widget.definition);
    for (final field in widget.definition.fields) {
      if (field.kind == IntegrationFieldKind.toggle) {
        toggles[field.key] = (values[field.key] ?? field.defaultValue ?? 'false').toLowerCase() == 'true';
      } else if (field.kind == IntegrationFieldKind.choice) {
        choices[field.key] = values[field.key]?.isNotEmpty == true ? values[field.key] : field.defaultValue;
      } else {
        final value = field.isSecret ? '' : (values[field.key] ?? field.defaultValue ?? '');
        controllers[field.key] = TextEditingController(text: value);
        if (field.isSecret) existingSecrets[field.key] = (values[field.key] ?? '').isNotEmpty;
      }
    }
    if (!mounted) return;
    setState(() {
      enabled = profile.enabled;
      loading = false;
    });
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values() {
    final values = <String, String>{};
    for (final field in widget.definition.fields) {
      values[field.key] = switch (field.kind) {
        IntegrationFieldKind.toggle => (toggles[field.key] ?? false).toString(),
        IntegrationFieldKind.choice => choices[field.key] ?? '',
        _ => controllers[field.key]?.text ?? '',
      };
    }
    return values;
  }

  /// Muestra un diálogo para ingresar el destinatario y envía un correo real.
  Future<void> _sendSmtpTest(BuildContext context) async {
    // Primero guardar la configuración actual para que sendTestEmail la lea.
    final saved = await _save();
    if (!saved || !context.mounted) return;

    final defaultRecipient = controllers['sender_email']?.text.trim() ?? '';
    final recipientCtrl = TextEditingController(text: defaultRecipient);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar correo de prueba'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se enviará un correo real al destinatario indicado para '
                'verificar autenticación y entrega.'),
            const SizedBox(height: 12),
            TextField(
              controller: recipientCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Destinatario de prueba',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Enviar'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final recipient = recipientCtrl.text.trim();
    if (!recipient.contains('@')) {
      setState(() {
        message = 'Destinatario no válido.';
        messageOk = false;
      });
      return;
    }

    setState(() { saving = true; message = null; });
    try {
      final result = await CommunicationService.instance.sendTestEmail(testRecipient: recipient);
      if (!mounted) return;
      setState(() {
        saving = false;
        message = result.ok
            ? '✓ Correo de prueba enviado a "$recipient". Revisa la bandeja de entrada.'
            : '✗ ${result.message}';
        messageOk = result.ok;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        message = 'Error inesperado al enviar: $e';
        messageOk = false;
      });
    }
  }

  Future<bool> _save({bool test = false}) async {
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await service.save(widget.definition, values: _values(), enabled: enabled);
      IntegrationCheckResult? result;
      if (test && enabled) result = await service.testConnection(widget.definition);
      if (!mounted) return false;
      setState(() {
        saving = false;
        message = result?.message ?? 'Configuración guardada.';
        messageOk = result?.ok ?? true;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        saving = false;
        message = 'No fue posible guardar la configuración.';
        messageOk = false;
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.definition.name),
      content: SizedBox(
        width: 620,
        child: loading
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.definition.description),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Integración habilitada'),
                      subtitle: const Text('Deshabilitar conserva la configuración pero impide su uso.'),
                      value: enabled,
                      onChanged: saving ? null : (value) => setState(() => enabled = value),
                    ),
                    const Divider(),
                    for (final field in widget.definition.fields) ...[
                      _field(field),
                      const SizedBox(height: 12),
                    ],
                    if (message != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (messageOk == true ? Colors.green : Colors.red).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(message!, style: TextStyle(color: messageOk == true ? Colors.green.shade800 : Colors.red.shade800)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cerrar')),
        // Botón dedicado solo para SMTP: envía un correo real de prueba.
        if (widget.definition.key == 'smtp')
          OutlinedButton.icon(
            onPressed: saving ? null : () => _sendSmtpTest(context),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Enviar correo de prueba'),
          ),
        OutlinedButton.icon(
          onPressed: saving ? null : () async => _save(test: true),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('Guardar y probar'),
        ),
        FilledButton(
          onPressed: saving
              ? null
              : () async {
                  final ok = await _save();
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
          child: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _field(IntegrationFieldDefinition field) {
    if (field.kind == IntegrationFieldKind.toggle) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.label),
        value: toggles[field.key] ?? false,
        onChanged: (value) => setState(() => toggles[field.key] = value),
      );
    }
    if (field.kind == IntegrationFieldKind.choice) {
      return DropdownButtonFormField<String>(
        initialValue: choices[field.key],
        decoration: InputDecoration(labelText: field.label, border: const OutlineInputBorder()),
        items: field.options.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: (value) => setState(() => choices[field.key] = value),
      );
    }
    final controller = controllers[field.key]!;
    final secretConfigured = field.isSecret && (existingSecrets[field.key] ?? false);
    return TextFormField(
      controller: controller,
      obscureText: field.isSecret,
      keyboardType: field.kind == IntegrationFieldKind.number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: '${field.label}${field.required ? ' *' : ''}',
        hintText: secretConfigured ? '•••••••• (credencial guardada; deja vacío para conservar)' : field.hint,
        helperText: secretConfigured ? 'Existe una credencial protegida en el almacén seguro.' : field.hint,
        border: const OutlineInputBorder(),
        prefixIcon: field.isSecret ? const Icon(Icons.lock_outline) : null,
      ),
    );
  }
}
