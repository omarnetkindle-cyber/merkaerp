import 'package:flutter/material.dart';

import '../../core/commands/command_registry.dart';
import '../../core/evidence/evidence_capsule_service.dart';
import '../merka_theme_tokens.dart';

/// A field displayed by [ExpandableRecordCard].
class RecordCardField {
  const RecordCardField({
    required this.label,
    required this.value,
    this.icon,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool emphasized;
}

/// An action exposed by a record card.
///
/// A command action is evaluated by the same registry and RBAC gate used by
/// the global command palette. Direct callbacks are useful for local UI
/// affordances such as opening a history dialog.
class RecordCardAction {
  const RecordCardAction({
    required this.id,
    required this.label,
    required this.icon,
    this.onPressed,
    this.commandId,
    this.commandContext,
    this.registry,
    this.visible = true,
  }) : assert(onPressed != null || commandId != null);

  final String id;
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext context)? onPressed;
  final String? commandId;
  final CommandContext? commandContext;
  final CommandRegistry? registry;
  final bool visible;

  bool isVisible() {
    if (!visible) return false;
    if (commandId == null) return true;
    final commandRegistry = registry ?? CommandRegistry.instance;
    return commandRegistry
        .available(commandContext: commandContext)
        .any((command) => command.id == commandId);
  }

  Future<void> invoke(BuildContext context) async {
    if (commandId != null) {
      final commandRegistry = registry ?? CommandRegistry.instance;
      await commandRegistry.execute(
        commandId!,
        context,
        commandContext: commandContext,
      );
      return;
    }
    await onPressed!(context);
  }
}

/// Compact, in-place representation for dense records.
class ExpandableRecordCard extends StatefulWidget {
  const ExpandableRecordCard({
    super.key,
    required this.criticalFields,
    this.secondaryFields = const <RecordCardField>[],
    this.actions = const <RecordCardAction>[],
    this.evidenceRequest,
    this.onEvidenceRequested,
    this.initiallyExpanded = false,
    this.onExpandedChanged,
  });

  final List<RecordCardField> criticalFields;
  final List<RecordCardField> secondaryFields;
  final List<RecordCardAction> actions;
  final EvidenceRequest? evidenceRequest;
  final Future<void> Function(EvidenceRequest request)? onEvidenceRequested;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<ExpandableRecordCard> createState() => _ExpandableRecordCardState();
}

class _ExpandableRecordCardState extends State<ExpandableRecordCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configuredActions = [...widget.actions];
    if (widget.evidenceRequest != null && widget.onEvidenceRequested != null) {
      configuredActions.add(
        RecordCardAction(
          id: 'export_evidence',
          label: 'Exportar evidencia',
          icon: Icons.fact_check_outlined,
          onPressed: (_) =>
              widget.onEvidenceRequested!(widget.evidenceRequest!),
        ),
      );
    }
    final availableActions = configuredActions
        .where((action) => action.isVisible())
        .toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 10,
                      children: widget.criticalFields
                          .map((field) => _FieldView(field: field))
                          .toList(),
                    ),
                  ),
                  if (availableActions.isNotEmpty)
                    ...availableActions.map(
                      (action) => IconButton(
                        tooltip: action.label,
                        icon: Icon(action.icon),
                        color: theme.colorScheme.primary,
                        onPressed: () => _invoke(action),
                      ),
                    ),
                  IconButton(
                    tooltip: _expanded
                        ? 'Contraer detalles'
                        : 'Expandir detalles',
                    icon: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.expand_more),
                    ),
                    onPressed: _toggle,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    color: MerkaThemeTokens.paper100.withValues(alpha: 0.42),
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.secondaryFields.isNotEmpty)
                          Wrap(
                            spacing: 18,
                            runSpacing: 10,
                            children: widget.secondaryFields
                                .map((field) => _FieldView(field: field))
                                .toList(),
                          ),
                        if (availableActions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 4,
                              children: availableActions
                                  .map(
                                    (action) => TextButton.icon(
                                      onPressed: () => _invoke(action),
                                      icon: Icon(action.icon, size: 18),
                                      label: Text(action.label),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _invoke(RecordCardAction action) async {
    try {
      await action.invoke(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _FieldView extends StatelessWidget {
  const _FieldView({required this.field});

  final RecordCardField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 240),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (field.icon != null) ...[
            Icon(field.icon, size: 16, color: MerkaThemeTokens.graphite600),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: MerkaThemeTokens.graphite600,
                  ),
                ),
                Text(
                  field.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: field.emphasized
                      ? theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                      : theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
