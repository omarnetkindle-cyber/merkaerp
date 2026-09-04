import 'package:flutter/material.dart';

import '../commands/command_registry.dart';
import 'traceability_chain.dart';
import 'traceability_chain_page.dart';
import '../../db_helper.dart';
import '../../ui/widgets/expandable_record_card.dart';

RecordCardAction traceabilityRecordAction({
  required String rootEntityType,
  required String rootRecordId,
  String? tenantId,
}) {
  return RecordCardAction(
    id: 'traceability_thread',
    label: 'Ver hilo de trazabilidad',
    icon: Icons.route,
    onPressed: (context) async {
      final database = await DatabaseHelper.instance.database;
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TraceabilityChainPage(
            service: TraceabilityChainService.standard(),
            rootEntityType: rootEntityType,
            rootRecordId: rootRecordId,
            database: database,
            tenantId: tenantId,
            commandContext: CommandRegistry.instance.context,
          ),
        ),
      );
    },
  );
}
