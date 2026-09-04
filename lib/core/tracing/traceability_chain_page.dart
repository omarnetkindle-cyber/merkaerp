import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../commands/command_registry.dart';
import '../evidence/evidence_capsule_service.dart';
import 'traceability_chain.dart';
import '../../ui/widgets/expandable_record_card.dart';

class TraceabilityChainPage extends StatefulWidget {
  const TraceabilityChainPage({
    super.key,
    required this.service,
    required this.rootEntityType,
    required this.rootRecordId,
    required this.database,
    this.tenantId,
    this.commandContext,
  });

  final TraceabilityChainService service;
  final String rootEntityType;
  final String rootRecordId;
  final DatabaseExecutor database;
  final String? tenantId;
  final CommandContext? commandContext;

  @override
  State<TraceabilityChainPage> createState() => _TraceabilityChainPageState();
}

class _TraceabilityChainPageState extends State<TraceabilityChainPage> {
  late final Future<TraceabilityChain> _chainFuture;

  @override
  void initState() {
    super.initState();
    _chainFuture = widget.service.build(
      rootEntityType: widget.rootEntityType,
      rootRecordId: widget.rootRecordId,
      db: widget.database,
      tenantId: widget.tenantId,
      commandContext: widget.commandContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hilo de trazabilidad')),
      body: FutureBuilder<TraceabilityChain>(
        future: _chainFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('No se pudo reconstruir el hilo: ${snapshot.error}'),
            );
          }
          final chain = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                chain.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Registro raíz: ${chain.rootEntityType} #${chain.rootRecordId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              ...chain.steps.asMap().entries.map(
                (entry) => _stepCard(context, chain, entry.key, entry.value),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stepCard(
    BuildContext context,
    TraceabilityChain chain,
    int index,
    ChainStep step,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (step.state) {
      TraceabilityStepState.complete => colorScheme.primary,
      TraceabilityStepState.blocked => colorScheme.error,
      TraceabilityStepState.pending => colorScheme.secondary,
    };
    final registry = CommandRegistry.instance;
    final commandVisible = step.actionAvailable(registry);
    final evidenceRequest =
        step.evidenceRecordType == null || step.recordId == null
        ? null
        : EvidenceRequest(
            domain: step.navigationModuleId ?? 'workspace',
            recordType: step.evidenceRecordType!,
            recordId: step.recordId!,
          );
    final actions = <RecordCardAction>[
      if (commandVisible && step.commandId != null)
        RecordCardAction(
          id: 'resolve_${step.id}',
          label: 'Resolver paso',
          icon: Icons.playlist_add_check,
          commandId: step.commandId,
          commandContext: step.commandContext,
        ),
      if (step.navigationModuleId != null)
        RecordCardAction(
          id: 'open_${step.id}',
          label: 'Abrir registro',
          icon: Icons.open_in_new,
          onPressed: (_) async {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Abrir módulo ${step.navigationModuleId} para #${step.recordId ?? '-'}',
                ),
              ),
            );
          },
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Column(
            children: [
              Icon(
                step.isComplete ? Icons.check_circle : Icons.block,
                color: color,
              ),
              if (index < chain.steps.length - 1)
                Container(
                  width: 2,
                  height: 86,
                  color: color.withValues(alpha: .35),
                ),
            ],
          ),
        ),
        Expanded(
          child: ExpandableRecordCard(
            criticalFields: [
              RecordCardField(
                label: 'Paso',
                value: step.label,
                emphasized: true,
              ),
              RecordCardField(
                label: 'Estado',
                value: step.state.label,
                emphasized: true,
              ),
              RecordCardField(
                label: 'Registro',
                value: step.recordId ?? 'No creado',
              ),
            ],
            secondaryFields: [
              RecordCardField(label: 'Entidad', value: step.entityType),
              RecordCardField(
                label: 'Rol responsable',
                value: step.requiredRole ?? 'No definido',
              ),
              if (step.blockingRule != null)
                RecordCardField(
                  label: 'Regla que bloquea',
                  value: step.blockingRule!,
                ),
            ],
            actions: actions,
            evidenceRequest: evidenceRequest,
            onEvidenceRequested: (request) =>
                EvidenceCapsuleService().exportJson(request),
          ),
        ),
      ],
    );
  }
}
