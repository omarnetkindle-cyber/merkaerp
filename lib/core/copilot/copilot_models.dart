import 'dart:convert';

enum CopilotPriority { info, warning, critical }

enum CopilotActionKind {
  navigate,
  prepareSale,
  preparePurchase,
  collectPayment,
}

class CopilotIdentity {
  const CopilotIdentity({
    required this.userId,
    required this.userName,
    required this.role,
    required this.allowedModuleIds,
  });

  final String userId;
  final String userName;
  final String role;
  final Set<String> allowedModuleIds;

  bool canAccess(String moduleId) => allowedModuleIds.contains(moduleId);
}

class CopilotSource {
  const CopilotSource({
    required this.label,
    required this.entity,
    this.recordId,
    this.asOf,
  });

  final String label;
  final String entity;
  final String? recordId;
  final DateTime? asOf;
}

class CopilotActionProposal {
  const CopilotActionProposal({
    required this.id,
    required this.label,
    required this.kind,
    required this.moduleId,
    this.arguments = const <String, Object?>{},
    this.requiresConfirmation = false,
  });

  final String id;
  final String label;
  final CopilotActionKind kind;
  final String moduleId;
  final Map<String, Object?> arguments;
  final bool requiresConfirmation;
}

class CopilotResponse {
  const CopilotResponse({
    required this.intent,
    required this.text,
    required this.provider,
    this.toolId,
    this.priority = CopilotPriority.info,
    this.sources = const <CopilotSource>[],
    this.actions = const <CopilotActionProposal>[],
  });

  final String intent;
  final String text;
  final String provider;
  final String? toolId;
  final CopilotPriority priority;
  final List<CopilotSource> sources;
  final List<CopilotActionProposal> actions;
}

class CopilotToolCall {
  const CopilotToolCall({required this.name, this.arguments = const {}});

  final String name;
  final Map<String, Object?> arguments;

  factory CopilotToolCall.fromJson(Map<String, Object?> json) {
    final rawArguments = json['arguments'];
    Map<String, Object?> arguments = const {};
    if (rawArguments is Map) {
      arguments = Map<String, Object?>.from(rawArguments);
    } else if (rawArguments is String && rawArguments.trim().isNotEmpty) {
      final decoded = jsonDecode(rawArguments);
      if (decoded is Map) arguments = Map<String, Object?>.from(decoded);
    }
    return CopilotToolCall(
      name: json['name']?.toString() ?? '',
      arguments: arguments,
    );
  }
}

class CopilotConversationTurn {
  const CopilotConversationTurn({required this.role, required this.content});

  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}
