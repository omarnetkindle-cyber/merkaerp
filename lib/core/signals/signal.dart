import '../commands/command_registry.dart';
import '../security/action_permission.dart';

enum SignalPriority { urgent, high, medium, low, info }

extension SignalPriorityLabel on SignalPriority {
  String get label => switch (this) {
    SignalPriority.urgent => 'Urgente',
    SignalPriority.high => 'Alta',
    SignalPriority.medium => 'Media',
    SignalPriority.low => 'Baja',
    SignalPriority.info => 'Informativa',
  };

  int get sortWeight => switch (this) {
    SignalPriority.urgent => 0,
    SignalPriority.high => 1,
    SignalPriority.medium => 2,
    SignalPriority.low => 3,
    SignalPriority.info => 4,
  };
}

/// Normalized local signal produced by an existing module alert/query.
class Signal {
  const Signal({
    required this.id,
    required this.source,
    required this.priority,
    required this.title,
    required this.description,
    this.entityType,
    this.entityId,
    this.navigationModuleId,
    this.suggestedAction,
    this.commandId,
    this.permissionModuleId,
    this.requiredPermission,
    this.requiredAction,
    this.commandContext,
  });

  final String id;
  final String source;
  final SignalPriority priority;
  final String title;
  final String description;
  final String? entityType;
  final String? entityId;
  final String? navigationModuleId;
  final String? suggestedAction;
  final String? commandId;
  final String? permissionModuleId;
  final String? requiredPermission;
  final AppAction? requiredAction;
  final CommandContext? commandContext;

  bool get hasSuggestedAction => commandId != null;
}

abstract interface class SignalSource {
  String get id;

  Future<List<Signal>> load();
}
