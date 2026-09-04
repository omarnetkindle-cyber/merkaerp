import '../domain/workflow_models.dart';

class WorkflowEngine {
  const WorkflowEngine();

  WorkflowInstance start({
    required WorkflowDefinition definition,
    required String documentId,
    required Map<String, Object?> context,
  }) {
    final steps = definition.applicableSteps(context);
    return WorkflowInstance(
      id: '${definition.id}:$documentId',
      definitionId: definition.id,
      documentId: documentId,
      status: steps.isEmpty
          ? WorkflowInstanceStatus.approved
          : WorkflowInstanceStatus.running,
      currentStepIndex: 0,
      context: context,
      history: const ['started'],
    );
  }

  WorkflowInstance decide({
    required WorkflowDefinition definition,
    required WorkflowInstance instance,
    required WorkflowDecision decision,
    required String actor,
  }) {
    final steps = definition.applicableSteps(instance.context);
    if (instance.status != WorkflowInstanceStatus.running) return instance;

    switch (decision) {
      case WorkflowDecision.approve:
        final next = instance.currentStepIndex + 1;
        return instance.copyWith(
          currentStepIndex: next,
          status: next >= steps.length
              ? WorkflowInstanceStatus.approved
              : WorkflowInstanceStatus.running,
          history: [
            ...instance.history,
            'approved:${steps[instance.currentStepIndex].id}:$actor',
          ],
        );
      case WorkflowDecision.reject:
        return instance.copyWith(
          status: WorkflowInstanceStatus.rejected,
          history: [...instance.history, 'rejected:$actor'],
        );
      case WorkflowDecision.returnToPrevious:
        final previous = instance.currentStepIndex <= 0
            ? 0
            : instance.currentStepIndex - 1;
        return instance.copyWith(
          currentStepIndex: previous,
          history: [...instance.history, 'returned:$actor'],
        );
    }
  }
}

class WorkflowTemplateCatalog {
  const WorkflowTemplateCatalog._();

  static const purchaseApproval = WorkflowDefinition(
    id: 'purchase_high_value',
    name: 'Compra de alto valor',
    module: 'purchases',
    steps: [
      WorkflowStepDefinition(
        id: 'manager',
        name: 'Aprobacion gerente',
        order: 1,
        requiredRole: 'gerente',
        conditions: [
          WorkflowCondition(field: 'total', operator: '>=', value: 5000000),
        ],
        actions: ['notify.manager'],
      ),
      WorkflowStepDefinition(
        id: 'finance',
        name: 'Aprobacion financiera',
        order: 2,
        requiredRole: 'contador',
        conditions: [
          WorkflowCondition(field: 'total', operator: '>=', value: 5000000),
        ],
        actions: ['notify.finance', 'lock.purchase'],
      ),
    ],
  );

  static const templates = [purchaseApproval];

  static List<Map<String, Object?>> toMap() {
    return [
      for (final template in templates)
        {
          'id': template.id,
          'name': template.name,
          'module': template.module,
          'steps': [
            for (final step in template.steps)
              {
                'id': step.id,
                'name': step.name,
                'order': step.order,
                'required_role': step.requiredRole,
                'actions': step.actions,
              },
          ],
        },
    ];
  }
}
