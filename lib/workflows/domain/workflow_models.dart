enum WorkflowDecision { approve, reject, returnToPrevious }

enum WorkflowInstanceStatus { draft, running, approved, rejected, cancelled }

class WorkflowCondition {
  const WorkflowCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  final String field;
  final String operator;
  final Object? value;
}

class WorkflowStepDefinition {
  const WorkflowStepDefinition({
    required this.id,
    required this.name,
    required this.order,
    this.requiredRole,
    this.conditions = const [],
    this.actions = const [],
  });

  final String id;
  final String name;
  final int order;
  final String? requiredRole;
  final List<WorkflowCondition> conditions;
  final List<String> actions;
}

class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.module,
    required this.steps,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String module;
  final List<WorkflowStepDefinition> steps;
  final bool enabled;

  List<WorkflowStepDefinition> applicableSteps(Map<String, Object?> context) {
    final filtered = steps.where((step) {
      return step.conditions.every((condition) {
        final actual = context[condition.field];
        switch (condition.operator) {
          case '>':
            return _num(actual) > _num(condition.value);
          case '>=':
            return _num(actual) >= _num(condition.value);
          case '<':
            return _num(actual) < _num(condition.value);
          case '<=':
            return _num(actual) <= _num(condition.value);
          case '!=':
            return actual != condition.value;
          default:
            return actual == condition.value;
        }
      });
    }).toList();
    filtered.sort((a, b) => a.order.compareTo(b.order));
    return filtered;
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class WorkflowInstance {
  const WorkflowInstance({
    required this.id,
    required this.definitionId,
    required this.documentId,
    required this.status,
    required this.currentStepIndex,
    required this.context,
    this.history = const [],
  });

  final String id;
  final String definitionId;
  final String documentId;
  final WorkflowInstanceStatus status;
  final int currentStepIndex;
  final Map<String, Object?> context;
  final List<String> history;

  WorkflowInstance copyWith({
    WorkflowInstanceStatus? status,
    int? currentStepIndex,
    List<String>? history,
  }) {
    return WorkflowInstance(
      id: id,
      definitionId: definitionId,
      documentId: documentId,
      status: status ?? this.status,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      context: context,
      history: history ?? this.history,
    );
  }
}
