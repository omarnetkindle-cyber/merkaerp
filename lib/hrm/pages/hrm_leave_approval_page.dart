import 'package:flutter/material.dart';

import '../../app_session.dart';
import '../../core/commands/command_registry.dart';
import '../../ui/widgets/expandable_record_card.dart';
import '../application/hrm_leave_service.dart';

class HrmLeaveApprovalPage extends StatefulWidget {
  const HrmLeaveApprovalPage({super.key, required this.canApprove});

  final bool canApprove;

  @override
  State<HrmLeaveApprovalPage> createState() => _HrmLeaveApprovalPageState();
}

class _HrmLeaveApprovalPageState extends State<HrmLeaveApprovalPage> {
  final _service = HrmLeaveService();
  late Future<List<Map<String, dynamic>>> _pending;
  late final String _commandOwner;

  @override
  void initState() {
    super.initState();
    _commandOwner = 'hrm.leave.approval:${identityHashCode(this)}';
    _reload();
  }

  @override
  void dispose() {
    CommandRegistry.instance.clearContext(_commandOwner);
    super.dispose();
  }

  void _reload() {
    _pending = _service.pendingForApproval();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canApprove) {
      return const Center(
        child: Text('No tienes permiso para aprobar solicitudes de ausencia.'),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('No se pudo cargar aprobaciones: ${snapshot.error}'),
          );
        }
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        if (rows.isEmpty) {
          return const Center(child: Text('No hay solicitudes pendientes.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) => _row(context, rows[index]),
        );
      },
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> row) {
    final employee = row['employee_name']?.toString() ?? 'Empleado';
    final leaveName = row['leave_name']?.toString() ?? 'Ausencia';
    final date = row['date']?.toString() ?? '';
    final days = row['length_days']?.toString() ?? '';
    final leaveId = (row['id'] as num).toInt();
    return ExpandableRecordCard(
      criticalFields: [
        RecordCardField(
          label: 'Empleado',
          value: employee,
          icon: Icons.badge,
          emphasized: true,
        ),
        RecordCardField(
          label: 'Tipo de ausencia',
          value: leaveName,
          icon: Icons.event_busy,
          emphasized: true,
        ),
        RecordCardField(
          label: 'Periodo',
          value: date,
          icon: Icons.calendar_today,
        ),
        RecordCardField(
          label: 'Dias',
          value: days,
          icon: Icons.timelapse,
          emphasized: true,
        ),
      ],
      secondaryFields: [
        RecordCardField(label: 'Solicitud', value: '#$leaveId'),
        RecordCardField(label: 'Estado', value: 'Pendiente de aprobación'),
      ],
      actions: [
        RecordCardAction(
          id: 'approve',
          label: 'Aprobar',
          icon: Icons.check_circle,
          visible: widget.canApprove,
          onPressed: (_) async {
            _activateCommandContext(context, row);
            await _approve(context, leaveId);
          },
        ),
        RecordCardAction(
          id: 'reject',
          label: 'Rechazar',
          icon: Icons.cancel,
          visible: widget.canApprove,
          onPressed: (_) async {
            _activateCommandContext(context, row);
            await _reject(context, leaveId);
          },
        ),
      ],
    );
  }

  void _activateCommandContext(BuildContext context, Map<String, dynamic> row) {
    final leaveId = (row['id'] as num).toInt();
    final employee = row['employee_name']?.toString() ?? 'Empleado';
    final leaveName = row['leave_name']?.toString() ?? 'Ausencia';
    CommandRegistry.instance.setContext(
      CommandContext(
        moduleId: 'hrm',
        recordType: 'hrm_leave',
        recordId: '$leaveId',
        label: '$employee - $leaveName',
        ownerId: _commandOwner,
        actions: {
          'approve': (commandContext, _) => _approve(commandContext, leaveId),
          'reject': (commandContext, _) => _reject(commandContext, leaveId),
        },
      ),
    );
  }

  Future<void> _approve(BuildContext context, int leaveId) async {
    final actor = int.tryParse(AppSession.usuarioId ?? '');
    if (actor == null) {
      _message('No hay un usuario aprobador valido en la sesion.');
      return;
    }
    try {
      await _service.approve(leaveId: leaveId, approvedBy: actor);
      if (mounted) setState(_reload);
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _reject(BuildContext context, int leaveId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectDialog(),
    );
    if (reason == null || !mounted) return;
    final actor = int.tryParse(AppSession.usuarioId ?? '');
    if (actor == null) {
      _message('No hay un usuario aprobador valido en la sesion.');
      return;
    }
    try {
      await _service.reject(
        leaveId: leaveId,
        rejectedBy: actor,
        reason: reason,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RejectDialog extends StatefulWidget {
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Motivo del rechazo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Motivo requerido'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _controller.text.trim();
            if (reason.isNotEmpty) Navigator.pop(context, reason);
          },
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}
