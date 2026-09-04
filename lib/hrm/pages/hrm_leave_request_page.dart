// lib/hrm/pages/hrm_leave_request_page.dart
//
// Tab "Solicitudes" dentro de HRM.
// Flujo completo: crear → enviar → ver estado → (aprobador: aprobar/rechazar).
// Reutiliza HrmLeaveRequestService (create) y HrmLeaveService (approve/reject).

import 'package:flutter/material.dart';

import '../../app_session.dart';
import '../../core/security/action_permission.dart';
import '../../db_helper.dart';
import '../../ui/merka_theme_tokens.dart';
import '../application/hrm_employee_service.dart';
import '../application/hrm_leave_request_service.dart';
import '../application/hrm_leave_service.dart';
import '../application/hrm_leave_type_service.dart';
import '../domain/hrm_employee.dart';
import '../domain/hrm_leave_request.dart';
import '../domain/hrm_leave_type.dart';

class HrmLeaveRequestPage extends StatefulWidget {
  const HrmLeaveRequestPage({super.key});

  @override
  State<HrmLeaveRequestPage> createState() => _HrmLeaveRequestPageState();
}

class _HrmLeaveRequestPageState extends State<HrmLeaveRequestPage> {
  final _requestSvc = HrmLeaveRequestService();
  final _leaveSvc = HrmLeaveService();
  final _employeeSvc = HrmEmployeeService();
  final _typeSvc = HrmLeaveTypeService();

  late Future<_PageData> _data;

  bool get _canApprove =>
      AppSession.puedeEjecutarAccion('hrm', AppAction.approve);

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_PageData> _load() async {
    final employees = await _employeeSvc.list();
    final types = await _typeSvc.list();
    final pending = await _requestSvc.pendingWithDetails();
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    return _PageData(
      companyId: companyId,
      employees: employees,
      leaveTypes: types,
      pending: pending,
    );
  }

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PageData>(
      future: _data,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final data = snapshot.data!;
        return _buildBody(context, data);
      },
    );
  }

  Widget _buildBody(BuildContext context, _PageData data) {
    return Column(
      children: [
        // Botón nueva solicitud
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Solicitudes de ausencia',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nueva solicitud'),
                onPressed: () => _openNewRequest(context, data),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Lista de solicitudes pendientes
        Expanded(
          child: data.pending.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_available,
                        size: 56,
                        color: MerkaThemeTokens.graphite600,
                      ),
                      const SizedBox(height: 12),
                      const Text('No hay solicitudes pendientes.'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Crear la primera solicitud'),
                        onPressed: () => _openNewRequest(context, data),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: data.pending.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _requestTile(context, data.pending[i], data),
                ),
        ),
      ],
    );
  }

  Widget _requestTile(
    BuildContext context,
    Map<String, dynamic> row,
    _PageData data,
  ) {
    final employeeName = row['employee_name']?.toString() ?? 'Empleado';
    final typeName = row['leave_type_name']?.toString() ?? '-';
    final startDate = _shortDate(
      row['start_date']?.toString() ?? row['date_applied']?.toString() ?? '',
    );
    final endDate = _shortDate(
      row['end_date']?.toString() ?? row['date_applied']?.toString() ?? '',
    );
    final status = row['status']?.toString() ?? 'pendiente';
    final leaveId = (row['id'] as num).toInt();
    final comments = row['comments']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: _statusIcon(status),
        title: Text(
          '$employeeName — $typeName',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Desde: $startDate  Hasta: $endDate'),
            if (comments.isNotEmpty)
              Text(
                comments,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MerkaThemeTokens.graphite600,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: _canApprove && status == 'pendiente'
            ? Wrap(
                spacing: 4,
                children: [
                  _actionButton(
                    icon: Icons.check_circle_outline,
                    color: MerkaThemeTokens.success,
                    tooltip: 'Aprobar',
                    onTap: () => _approveLeave(context, leaveId),
                  ),
                  _actionButton(
                    icon: Icons.cancel_outlined,
                    color: MerkaThemeTokens.danger,
                    tooltip: 'Rechazar',
                    onTap: () => _rejectLeave(context, leaveId),
                  ),
                ],
              )
            : _statusChip(status),
        isThreeLine: comments.isNotEmpty,
      ),
    );
  }

  Widget _statusIcon(String status) {
    return switch (status) {
      'aprobado' => const CircleAvatar(
        backgroundColor: MerkaThemeTokens.success,
        child: Icon(Icons.check, color: Colors.white, size: 18),
      ),
      'rechazado' => const CircleAvatar(
        backgroundColor: MerkaThemeTokens.danger,
        child: Icon(Icons.close, color: Colors.white, size: 18),
      ),
      _ => const CircleAvatar(
        backgroundColor: MerkaThemeTokens.warning,
        child: Icon(Icons.hourglass_top, color: Colors.white, size: 18),
      ),
    };
  }

  Widget _statusChip(String status) {
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) => IconButton(
    tooltip: tooltip,
    icon: Icon(icon, color: color),
    onPressed: onTap,
  );

  // ── Aprobar/Rechazar (delega al servicio existente) ────────────────────────

  Future<void> _approveLeave(BuildContext context, int leaveId) async {
    final actor = int.tryParse(AppSession.usuarioId ?? '');
    if (actor == null) {
      _snack('No hay usuario aprobador válido en la sesión.');
      return;
    }
    try {
      await _leaveSvc.approve(leaveId: leaveId, approvedBy: actor);
      _reload();
      if (mounted) {
        _snack('Solicitud aprobada.', ok: true);
      }
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _rejectLeave(BuildContext context, int leaveId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectReasonDialog(),
    );
    if (reason == null || !mounted) return;
    final actor = int.tryParse(AppSession.usuarioId ?? '');
    if (actor == null) {
      _snack('No hay usuario aprobador válido.');
      return;
    }
    try {
      await _leaveSvc.reject(
        leaveId: leaveId,
        rejectedBy: actor,
        reason: reason,
      );
      _reload();
      if (mounted) _snack('Solicitud rechazada.', ok: false);
    } catch (e) {
      _snack(e.toString());
    }
  }

  // ── Nueva solicitud ────────────────────────────────────────────────────────

  Future<void> _openNewRequest(BuildContext context, _PageData data) async {
    if (data.employees.isEmpty) {
      _snack('No hay empleados registrados. Crea empleados primero.');
      return;
    }
    if (data.leaveTypes.isEmpty) {
      _snack('No hay tipos de ausencia configurados.');
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _NewRequestDialog(
        companyId: data.companyId,
        employees: data.employees,
        leaveTypes: data.leaveTypes,
        service: _requestSvc,
      ),
    );
    if (created == true) _reload();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _shortDate(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final d = DateTime.parse(iso);
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/'
          '${d.year}';
    } catch (_) {
      return iso.substring(0, iso.length.clamp(0, 10));
    }
  }

  void _snack(String msg, {bool? ok}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok == true
            ? MerkaThemeTokens.success
            : ok == false
            ? MerkaThemeTokens.danger
            : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo para crear nueva solicitud
// ─────────────────────────────────────────────────────────────────────────────
class _NewRequestDialog extends StatefulWidget {
  const _NewRequestDialog({
    required this.companyId,
    required this.employees,
    required this.leaveTypes,
    required this.service,
  });

  final int companyId;
  final List<HrmEmployee> employees;
  final List<HrmLeaveType> leaveTypes;
  final HrmLeaveRequestService service;

  @override
  State<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<_NewRequestDialog> {
  late int _employeeId;
  late int _leaveTypeId;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final _commentsCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.employees.first.id!;
    _leaveTypeId = widget.leaveTypes.first.id!;
  }

  @override
  void dispose() {
    _commentsCtrl.dispose();
    super.dispose();
  }

  int get _days => _endDate.isBefore(_startDate)
      ? 0
      : _endDate.difference(_startDate).inDays + 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva solicitud de ausencia'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Empleado
              DropdownButtonFormField<int>(
                value: _employeeId,
                decoration: const InputDecoration(
                  labelText: 'Empleado *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                isExpanded: true,
                items: widget.employees
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.id,
                        child: Text(e.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _employeeId = v);
                },
              ),
              const SizedBox(height: 10),
              // Tipo de ausencia
              DropdownButtonFormField<int>(
                value: _leaveTypeId,
                decoration: const InputDecoration(
                  labelText: 'Tipo de ausencia *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                isExpanded: true,
                items: widget.leaveTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _leaveTypeId = v);
                },
              ),
              const SizedBox(height: 10),
              // Rango de fechas
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Fecha inicio *',
                      value: _startDate,
                      onChanged: (d) => setState(() => _startDate = d),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DateField(
                      label: 'Fecha fin *',
                      value: _endDate,
                      firstDate: _startDate,
                      onChanged: (d) => setState(() => _endDate = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (_days > 0)
                Text(
                  '$_days día${_days == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: MerkaThemeTokens.navy700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (_endDate.isBefore(_startDate))
                const Text(
                  'La fecha fin no puede ser anterior a la de inicio.',
                  style: TextStyle(
                    color: MerkaThemeTokens.danger,
                    fontSize: 12,
                  ),
                ),
              const SizedBox(height: 10),
              // Comentarios
              TextField(
                controller: _commentsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: MerkaThemeTokens.danger,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear solicitud'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_endDate.isBefore(_startDate)) {
      setState(() => _error = 'La fecha fin no puede ser anterior al inicio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final request = HrmLeaveRequest(
        companyId: widget.companyId,
        employeeId: _employeeId,
        leaveTypeId: _leaveTypeId,
        dateApplied: DateTime.now(),
        startDate: _startDate,
        endDate: _endDate,
        comments: _commentsCtrl.text.trim().isEmpty
            ? null
            : _commentsCtrl.text.trim(),
      );
      await widget.service.create(request);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget selector de fecha
// ─────────────────────────────────────────────────────────────────────────────
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) {
    final formatted =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: firstDate ?? DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(formatted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo de motivo de rechazo
// ─────────────────────────────────────────────────────────────────────────────
class _RejectReasonDialog extends StatefulWidget {
  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Motivo del rechazo'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Motivo *',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _ctrl.text.trim();
            if (reason.isNotEmpty) Navigator.pop(context, reason);
          },
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Datos del estado del widget
// ─────────────────────────────────────────────────────────────────────────────
class _PageData {
  const _PageData({
    required this.companyId,
    required this.employees,
    required this.leaveTypes,
    required this.pending,
  });

  final int companyId;
  final List<HrmEmployee> employees;
  final List<HrmLeaveType> leaveTypes;
  final List<Map<String, dynamic>> pending;
}
