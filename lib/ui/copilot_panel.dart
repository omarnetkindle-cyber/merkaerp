import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../app_session.dart';
import '../core/copilot/copilot_models.dart';
import '../core/copilot/copilot_orchestrator.dart';
import '../core/copilot/copilot_configuration_service.dart';
import '../core/copilot/local_llm_client.dart';
import '../features/module_definition.dart';
import 'merka_theme_tokens.dart';

class CopilotMessage {
  const CopilotMessage({
    required this.fromUser,
    required this.text,
    this.response,
  });

  final bool fromUser;
  final String text;
  final CopilotResponse? response;
}

class CopilotPanel extends StatefulWidget {
  const CopilotPanel({
    super.key,
    required this.onClose,
    required this.modules,
    required this.onNavigateToModule,
    required this.onLoadSaleProduct,
    required this.onLoadClientPayment,
    required this.onLoadPurchaseOrder,
    this.orchestrator,
  });

  final VoidCallback onClose;
  final List<ModuleDefinition> modules;
  final ValueChanged<String> onNavigateToModule;
  final ValueChanged<String> onLoadSaleProduct;
  final VoidCallback onLoadClientPayment;
  final VoidCallback onLoadPurchaseOrder;
  final CopilotOrchestrator? orchestrator;

  @override
  State<CopilotPanel> createState() => _CopilotPanelState();
}

class _CopilotPanelState extends State<CopilotPanel> {
  late final CopilotOrchestrator _orchestrator;
  final List<CopilotMessage> _messages = [];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _scrollTimer;
  bool _loading = false;

  CopilotIdentity get _identity => CopilotIdentity(
    userId: AppSession.usuarioId ?? 'sin_sesion',
    userName: AppSession.nombre,
    role: AppSession.rol ?? 'sin_sesion',
    allowedModuleIds: widget.modules.map((module) => module.id).toSet(),
  );

  @override
  void initState() {
    super.initState();
    _orchestrator = widget.orchestrator ?? CopilotOrchestrator();
    _loadWelcomeMessage();
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadWelcomeMessage() async {
    setState(() => _loading = true);
    try {
      final alerts = await _orchestrator.authorizedAlerts(_identity);
      final expiring = alerts.where((a) => a.kind == 'expiring_product').length;
      final critical = alerts.where((a) => a.kind == 'critical_stock').length;
      final receivables = alerts.where((a) => a.kind == 'receivable').length;
      var text = 'Buenos dias. Soy el asistente local de MerkaERP.\n\n';
      if (alerts.isEmpty) {
        text +=
            'No veo alertas autorizadas para tu sesion. Puedes consultar datos '
            'o preparar acciones segun tus permisos.';
      } else {
        text += 'Novedades operativas visibles para tu rol:\n';
        if (critical > 0) text += '- $critical productos con stock critico.\n';
        if (expiring > 0) text += '- $expiring lotes proximos a vencer.\n';
        if (receivables > 0) text += '- $receivables cobranzas pendientes.\n';
        text +=
            '\nPuedo consultar los datos o llevarte al modulo correspondiente.';
      }
      if (!mounted) return;
      setState(
        () => _messages.add(CopilotMessage(fromUser: false, text: text)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          const CopilotMessage(
            fromUser: false,
            text:
                'No pude cargar las alertas. Todavia puedes hacer una consulta.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit(String text) async {
    final query = text.trim();
    if (query.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _messages.add(CopilotMessage(fromUser: true, text: query));
      _inputController.clear();
    });
    _scrollToBottom();
    try {
      final history = _messages
          .take(_messages.length - 1)
          .map(
            (message) => CopilotConversationTurn(
              role: message.fromUser ? 'user' : 'assistant',
              content: message.text,
            ),
          )
          .toList();
      final response = await _orchestrator.respond(
        prompt: query,
        identity: _identity,
        history: history,
      );
      if (!mounted) return;
      setState(
        () => _messages.add(
          CopilotMessage(
            fromUser: false,
            text: response.text,
            response: response,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _messages.add(
          const CopilotMessage(
            fromUser: false,
            text: 'No pude completar la consulta de forma segura.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _executeAction(CopilotActionProposal action) async {
    if (!_identity.canAccess(action.moduleId)) {
      await _auditAction(action, 'rechazado_permiso');
      _showMessage('Ya no tienes acceso al modulo solicitado.');
      return;
    }
    if (action.requiresConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar accion'),
          content: Text(
            '${action.label}. Solo se abrira o preparara el modulo; no se '
            'guardaran datos automaticamente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        await _auditAction(action, 'cancelado_usuario');
        return;
      }
    }
    switch (action.kind) {
      case CopilotActionKind.navigate:
        widget.onNavigateToModule(action.moduleId);
      case CopilotActionKind.prepareSale:
        widget.onLoadSaleProduct(action.arguments['query']?.toString() ?? '');
      case CopilotActionKind.preparePurchase:
        widget.onLoadPurchaseOrder();
      case CopilotActionKind.collectPayment:
        widget.onLoadClientPayment();
    }
    await _auditAction(action, 'delegado_modulo');
  }

  Future<void> _auditAction(
    CopilotActionProposal action,
    String outcome,
  ) async {
    try {
      await _orchestrator.auditAction(
        action: action,
        identity: _identity,
        outcome: outcome,
      );
    } catch (_) {
      // La auditoria del asistente no debe bloquear la regla del modulo destino.
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _showLocalModelSettings() async {
    final service = CopilotConfigurationService();
    final current = await service.load();
    if (!mounted) return;
    final endpoint = TextEditingController(text: current.endpoint.toString());
    final model = TextEditingController(text: current.model);
    var enabled = current.enabled;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modelo local'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar interpretacion con modelo local'),
                  subtitle: const Text(
                    'Requiere llama-server ejecutandose en este equipo. El '
                    'motor verificable sigue siendo el responsable de datos y acciones.',
                  ),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: endpoint,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint loopback',
                    hintText: 'http://127.0.0.1:8080/v1/chat/completions',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del modelo servido',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await service.save(
                    LocalLlmConfiguration(
                      enabled: enabled,
                      endpoint: Uri.parse(endpoint.text.trim()),
                      model: model.text.trim(),
                    ),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    endpoint.dispose();
    model.dispose();
    if (saved == true && mounted) {
      _showMessage('Configuracion local actualizada.');
    }
  }

  void _scrollToBottom() {
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final moduleIds = _identity.allowedModuleIds;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.brain(),
                color: MerkaThemeTokens.navy800,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Copilot MerkaERP',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: MerkaThemeTokens.graphite900,
                      ),
                    ),
                    Text(
                      'IA local opcional + reglas verificables',
                      style: TextStyle(
                        fontSize: 10,
                        color: MerkaThemeTokens.graphite600,
                      ),
                    ),
                  ],
                ),
              ),
              if (AppSession.puedeAdministrar())
                IconButton(
                  tooltip: 'Configurar modelo local',
                  icon: const Icon(Icons.memory, size: 19),
                  onPressed: _showLocalModelSettings,
                ),
              IconButton(
                tooltip: 'Cerrar',
                icon: Icon(PhosphorIcons.x(), size: 18),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _Bubble(
                    message: _messages[index],
                    onAction: _executeAction,
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (moduleIds.contains('sales'))
                _SuggestionChip(
                  label: 'Ventas de hoy',
                  onTap: () => _submit('Ventas de hoy'),
                ),
              if (moduleIds.contains('inventory'))
                _SuggestionChip(
                  label: 'Productos criticos',
                  onTap: () => _submit('Productos criticos'),
                ),
              if (moduleIds.contains('receivables'))
                _SuggestionChip(
                  label: 'Cobranza pendiente',
                  onTap: () => _submit('Cobranza pendiente'),
                ),
              if (moduleIds.contains('purchases'))
                _SuggestionChip(
                  label: 'Preparar compra',
                  onTap: () => _submit('Crear compra'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  enabled: !_loading,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: 'Consulta datos o prepara una accion...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _loading ? null : _submit,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Enviar',
                onPressed: _loading
                    ? null
                    : () => _submit(_inputController.text),
                icon: Icon(PhosphorIcons.paperPlaneRight(), size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.onAction});

  final CopilotMessage message;
  final ValueChanged<CopilotActionProposal> onAction;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    final response = message.response;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? MerkaThemeTokens.navy800 : MerkaThemeTokens.paper50,
          borderRadius: BorderRadius.circular(8),
          border: isUser ? null : Border.all(color: MerkaThemeTokens.paper100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : MerkaThemeTokens.graphite900,
                fontSize: 13,
              ),
            ),
            if (response != null && response.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Fuente: ${response.sources.map((source) => source.entity).join(', ')}',
                style: const TextStyle(
                  fontSize: 10,
                  color: MerkaThemeTokens.graphite600,
                ),
              ),
            ],
            if (response != null && response.actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final action in response.actions)
                    OutlinedButton.icon(
                      onPressed: () => onAction(action),
                      icon: const Icon(Icons.arrow_forward, size: 14),
                      label: Text(action.label),
                    ),
                ],
              ),
            ],
            if (response != null) ...[
              const SizedBox(height: 6),
              Text(
                response.provider == 'local_llm'
                    ? 'Interpretado por modelo local; datos verificados por MerkaERP'
                    : 'Respuesta verificable de MerkaERP',
                style: const TextStyle(
                  fontSize: 9,
                  color: MerkaThemeTokens.graphite600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
