import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'core/webhooks/webhook.dart';
import 'core/webhooks/webhook_service.dart';

class WebhooksPage extends StatefulWidget {
  const WebhooksPage({super.key});

  @override
  State<WebhooksPage> createState() => _WebhooksPageState();
}

class _WebhooksPageState extends State<WebhooksPage> {
  final WebhookService _webhookService = WebhookService.instance;
  List<Webhook> _webhooks = [];
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final webhooks = await _webhookService.getWebhooksByCompany(
        db,
        companyId,
      );

      if (!mounted) return;
      setState(() {
        _webhooks = webhooks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar webhooks: $e')));
    }
  }

  Future<void> _toggleWebhookActive(Webhook webhook) async {
    setState(() => _isUpdating = true);
    try {
      final db = await DatabaseHelper.instance.database;
      if (webhook.isActive) {
        await _webhookService.deactivateWebhook(db, webhook.id!);
      } else {
        await _webhookService.activateWebhook(db, webhook.id!);
      }
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              webhook.isActive ? 'Webhook desactivado' : 'Webhook activado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar webhook: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _deleteWebhook(Webhook webhook) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Webhook'),
        content: Text(
          '¿Está seguro de eliminar el webhook para el evento "${webhook.event}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _webhookService.deleteWebhook(db, webhook.id!);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Webhook eliminado')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar webhook: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _showAddWebhookDialog() async {
    final eventController = TextEditingController();
    final urlController = TextEditingController();
    final secretController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Webhook'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: eventController,
                decoration: const InputDecoration(
                  labelText: 'Evento',
                  hintText: 'ej: sale.created, inventory.low',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://ejemplo.com/webhook',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: secretController,
                decoration: const InputDecoration(
                  labelText: 'Secreto (opcional)',
                  hintText: 'Para verificar firma HMAC',
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final companyId = await DatabaseHelper.instance
            .obtenerEmpresaActivaId();

        final webhook = Webhook(
          companyId: companyId,
          event: eventController.text.trim(),
          url: urlController.text.trim(),
          secret: secretController.text.trim().isEmpty
              ? null
              : secretController.text.trim(),
          createdAt: DateTime.now(),
        );

        await _webhookService.registerWebhook(db, webhook);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Webhook agregado exitosamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al agregar webhook: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Webhooks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _webhooks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.webhook, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No hay webhooks configurados',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Agrega webhooks para integraciones externas',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _webhooks.length,
              itemBuilder: (context, index) {
                final webhook = _webhooks[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: webhook.isActive
                          ? Colors.green
                          : Colors.grey,
                      child: Icon(
                        webhook.isActive ? Icons.check : Icons.close,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(webhook.event),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          webhook.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Reintentos: ${webhook.retryCount}/${webhook.maxRetries}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: _isUpdating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'toggle') {
                                _toggleWebhookActive(webhook);
                              } else if (value == 'delete') {
                                _deleteWebhook(webhook);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'toggle',
                                child: Text(
                                  webhook.isActive ? 'Desactivar' : 'Activar',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: const Text(
                                  'Eliminar',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isUpdating ? null : _showAddWebhookDialog,
        tooltip: 'Agregar Webhook',
        child: const Icon(Icons.add),
      ),
    );
  }
}
