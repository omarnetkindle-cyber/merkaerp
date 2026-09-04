import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/module_definition.dart';
import '../security/action_permission.dart';

typedef CommandHandler =
    FutureOr<void> Function(
      BuildContext context,
      CommandContext commandContext,
    );

typedef CommandAuthorization =
    bool Function(CommandDefinition command, CommandContext context);

class CommandContext {
  const CommandContext({
    this.moduleId,
    this.recordType,
    this.recordId,
    this.label,
    this.ownerId,
    this.metadata = const <String, Object?>{},
    this.actions = const <String, CommandHandler>{},
  });

  final String? moduleId;
  final String? recordType;
  final String? recordId;
  final String? label;
  final String? ownerId;
  final Map<String, Object?> metadata;
  final Map<String, CommandHandler> actions;

  bool get hasRecord => recordType != null && recordId != null;

  CommandHandler? action(String key) => actions[key];
}

class CommandDefinition {
  const CommandDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.moduleId,
    required this.handler,
    this.permissionModuleId,
    this.requiredAction,
    this.permissionLabel,
    this.contextType,
    this.actionKey,
    this.priority = 0,
    this.contextual = false,
    this.authorize,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final String moduleId;
  final String? permissionModuleId;
  final AppAction? requiredAction;
  final String? permissionLabel;
  final String? contextType;
  final String? actionKey;
  final int priority;
  final bool contextual;
  final CommandHandler handler;
  final bool Function(CommandContext context)? authorize;

  bool matches(CommandContext context) {
    if (!contextual) return true;
    return context.recordType == contextType && context.hasRecord;
  }

  FutureOr<void> execute(BuildContext context, CommandContext commandContext) =>
      handler(context, commandContext);
}

class CommandRegistry extends ChangeNotifier {
  CommandRegistry({CommandAuthorization? authorization})
    : _authorization = authorization;

  static final CommandRegistry instance = CommandRegistry();

  final Map<String, CommandDefinition> _commands = {};
  CommandAuthorization? _authorization;
  CommandContext _context = const CommandContext();

  CommandContext get context => _context;

  void setAuthorization(CommandAuthorization authorization) {
    _authorization = authorization;
    notifyListeners();
  }

  void register(CommandDefinition command) {
    _commands[command.id] = command;
    notifyListeners();
  }

  void registerAll(Iterable<CommandDefinition> commands) {
    for (final command in commands) {
      _commands[command.id] = command;
    }
    notifyListeners();
  }

  void registerModuleCommands(
    Iterable<ModuleDefinition> modules, {
    required bool Function(ModuleDefinition module) authorize,
    required FutureOr<void> Function(
      BuildContext context,
      ModuleDefinition module,
    )
    onOpen,
  }) {
    _commands.removeWhere((id, _) => id.startsWith('module.open.'));
    for (final module in modules) {
      final commandId = 'module.open.${module.id}';
      _commands[commandId] = CommandDefinition(
        id: commandId,
        label: 'Abrir ${module.title}',
        description: 'Navegar al módulo ${module.title}.',
        icon: module.icon,
        color: module.color,
        moduleId: module.id,
        priority: 10,
        handler: (context, _) => onOpen(context, module),
        authorize: (_) => authorize(module),
      );
    }
    notifyListeners();
  }

  void setContext(CommandContext context) {
    _context = context;
    notifyListeners();
  }

  void clearContext(String ownerId) {
    if (_context.ownerId != ownerId) return;
    _context = const CommandContext();
    notifyListeners();
  }

  List<CommandDefinition> available({
    String query = '',
    CommandContext? commandContext,
  }) {
    final normalized = query.trim().toLowerCase();
    final activeContext = commandContext ?? _context;
    final commands = _commands.values
        .where((command) => _isVisible(command, activeContext))
        .where((command) {
      if (normalized.isEmpty) return true;
      final haystack =
          '${command.label} ${command.description} ${command.moduleId} '
                  '${command.permissionLabel ?? ''}'
              .toLowerCase();
      return haystack.contains(normalized) || _fuzzyMatch(haystack, normalized);
    }).toList();
    commands.sort((a, b) {
      final contextualOrder = (b.contextual ? 1 : 0) - (a.contextual ? 1 : 0);
      if (contextualOrder != 0) return contextualOrder;
      final priorityOrder = b.priority.compareTo(a.priority);
      if (priorityOrder != 0) return priorityOrder;
      return a.label.compareTo(b.label);
    });
    return commands;
  }

  Future<void> execute(
    String commandId,
    BuildContext context, {
    CommandContext? commandContext,
  }) async {
    final command = _commands[commandId];
    if (command == null) {
      throw StateError('El comando "$commandId" no existe.');
    }
    final activeContext = commandContext ?? _context;
    if (!_isVisible(command, activeContext)) {
      throw StateError('No tienes permiso para ejecutar este comando.');
    }
    await command.execute(context, activeContext);
  }

  bool _isVisible(CommandDefinition command, [CommandContext? context]) {
    final activeContext = context ?? _context;
    if (!command.matches(activeContext)) return false;
    if (command.authorize != null && !command.authorize!(activeContext)) {
      return false;
    }
    if (_authorization != null && !_authorization!(command, activeContext)) {
      return false;
    }
    if (command.contextual &&
        (command.actionKey == null ||
            activeContext.action(command.actionKey!) == null)) {
      return false;
    }
    return true;
  }

  bool _fuzzyMatch(String source, String query) {
    var index = 0;
    for (final codeUnit in query.codeUnits) {
      index = source.indexOf(String.fromCharCode(codeUnit), index);
      if (index == -1) return false;
      index++;
    }
    return true;
  }
}

class CommandPaletteHost extends StatelessWidget {
  const CommandPaletteHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showCommandPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showCommandPalette(context),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.hostContext});

  final BuildContext hostContext;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commands = CommandRegistry.instance.available(
      query: _queryController.text,
    );
    return AlertDialog(
      title: const Text('Command Palette'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.manage_search),
                hintText: 'Buscar accion, modulo o registro',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: commands.isEmpty
                  ? const Center(child: Text('Sin comandos disponibles.'))
                  : ListView.separated(
                      itemCount: commands.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (itemContext, index) {
                        final command = commands[index];
                        return ListTile(
                          leading: Icon(command.icon, color: command.color),
                          title: Text(command.label),
                          subtitle: Text(command.description),
                          trailing: command.contextual
                              ? const Chip(label: Text('Contexto'))
                              : null,
                          onTap: () async {
                            Navigator.pop(context);
                            try {
                              await CommandRegistry.instance.execute(
                                command.id,
                                widget.hostContext,
                              );
                            } catch (error) {
                              if (widget.hostContext.mounted) {
                                ScaffoldMessenger.of(
                                  widget.hostContext,
                                ).showSnackBar(
                                  SnackBar(content: Text(error.toString())),
                                );
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCommandPalette(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _CommandPaletteDialog(hostContext: context),
  );
}
