import '../domain/business_rule.dart';

class RuleEngine {
  const RuleEngine();

  List<RuleEvaluationResult> evaluate(
    List<BusinessRule> rules,
    Map<String, Object?> context,
  ) {
    final ordered = [...rules]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return [
      for (final rule in ordered)
        if (rule.enabled) _evaluateRule(rule, context),
    ];
  }

  List<RuleAction> matchingActions(
    List<BusinessRule> rules,
    Map<String, Object?> context,
  ) {
    return evaluate(rules, context)
        .where((result) => result.matched)
        .expand((result) => result.actions)
        .toList();
  }

  RuleEvaluationResult _evaluateRule(
    BusinessRule rule,
    Map<String, Object?> context,
  ) {
    final matched = rule.conditions.every(
      (condition) => _matches(condition, context[condition.field]),
    );
    return RuleEvaluationResult(
      rule: rule,
      matched: matched,
      actions: matched ? rule.actions : const [],
    );
  }

  bool _matches(RuleCondition condition, Object? actual) {
    switch (condition.operator) {
      case RuleOperator.equals:
        return actual == condition.value;
      case RuleOperator.notEquals:
        return actual != condition.value;
      case RuleOperator.greaterThan:
        return _num(actual) > _num(condition.value);
      case RuleOperator.greaterOrEqual:
        return _num(actual) >= _num(condition.value);
      case RuleOperator.lessThan:
        return _num(actual) < _num(condition.value);
      case RuleOperator.lessOrEqual:
        return _num(actual) <= _num(condition.value);
      case RuleOperator.contains:
        return actual.toString().contains(condition.value.toString());
      case RuleOperator.inList:
        final list = condition.value is Iterable
            ? condition.value as Iterable
            : const [];
        return list.contains(actual);
      case RuleOperator.between:
        final value = _num(actual);
        return value >= _num(condition.value) &&
            value <= _num(condition.secondValue);
    }
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
