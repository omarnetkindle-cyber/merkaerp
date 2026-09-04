import 'dart:async';

import 'copilot_models.dart';

typedef CopilotToolHandler =
    Future<CopilotResponse> Function(
      Map<String, Object?> arguments,
      CopilotIdentity identity,
    );

class CopilotToolDefinition {
  const CopilotToolDefinition({
    required this.id,
    required this.description,
    required this.moduleId,
    required this.handler,
    this.parameters = const <String, Object?>{},
  });

  final String id;
  final String description;
  final String moduleId;
  final Map<String, Object?> parameters;
  final CopilotToolHandler handler;

  Map<String, Object?> toFunctionSchema() => {
    'type': 'function',
    'function': {
      'name': id,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': parameters,
        'additionalProperties': false,
      },
    },
  };
}

class CopilotToolRegistry {
  final Map<String, CopilotToolDefinition> _tools = {};

  void register(CopilotToolDefinition tool) => _tools[tool.id] = tool;

  List<CopilotToolDefinition> available(CopilotIdentity identity) => _tools
      .values
      .where((tool) => identity.canAccess(tool.moduleId))
      .toList(growable: false);

  List<Map<String, Object?>> schemas(CopilotIdentity identity) =>
      available(identity).map((tool) => tool.toFunctionSchema()).toList();

  Future<CopilotResponse> execute(
    CopilotToolCall call,
    CopilotIdentity identity,
  ) async {
    final tool = _tools[call.name];
    if (tool == null) {
      throw StateError('La herramienta solicitada no existe.');
    }
    if (!identity.canAccess(tool.moduleId)) {
      throw StateError(
        'No tienes permiso para consultar o actuar en ${tool.moduleId}.',
      );
    }
    return tool.handler(call.arguments, identity);
  }
}
