enum RuleOperator {
  equals,
  notEquals,
  greaterThan,
  greaterOrEqual,
  lessThan,
  lessOrEqual,
  contains,
  inList,
  between,
}

class RuleCondition {
  const RuleCondition({
    required this.field,
    required this.operator,
    required this.value,
    this.secondValue,
  });

  final String field;
  final RuleOperator operator;
  final Object? value;
  final Object? secondValue;
}

class RuleAction {
  const RuleAction({required this.type, this.parameters = const {}});

  final String type;
  final Map<String, Object?> parameters;

  Map<String, Object?> toMap() => {'type': type, 'parameters': parameters};
}

class BusinessRule {
  const BusinessRule({
    required this.id,
    required this.name,
    required this.conditions,
    required this.actions,
    this.priority = 100,
    this.enabled = true,
  });

  final String id;
  final String name;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;
  final int priority;
  final bool enabled;
}

class RuleEvaluationResult {
  const RuleEvaluationResult({
    required this.rule,
    required this.matched,
    required this.actions,
  });

  final BusinessRule rule;
  final bool matched;
  final List<RuleAction> actions;

  Map<String, Object?> toMap() => {
    'rule_id': rule.id,
    'rule_name': rule.name,
    'matched': matched,
    'actions': actions.map((action) => action.toMap()).toList(),
  };
}
