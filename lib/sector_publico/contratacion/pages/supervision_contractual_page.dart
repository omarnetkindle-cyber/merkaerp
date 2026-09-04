import 'package:flutter/material.dart';
import '../../../app_session.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../../db_helper.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../services/interventoria_liquidacion_service.dart';
import '../services/supervision_dashboard_service.dart';

class SupervisionContractualPage extends StatefulWidget {
  const SupervisionContractualPage({super.key, required this.entidadId, required this.usuarioId});
  final String entidadId;
  final String usuarioId;

  @override
  State<SupervisionContractualPage> createState() => _SupervisionContractualPageState();
}

class _SupervisionContractualPageState extends State<SupervisionContractualPage> {
  bool _loading = true;
  String? _error;
  List<ContractSupervisionSummary> _contracts = const [];
  SupervisionDashboardService? _dashboard;
  InterventoriaLiquidacionService? _service;

  bool get _canSeeAll => AppSession.puedeAdministrar() || AppSession.puedeEjecutarPermiso(Permiso.consultarTodo);

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final db = await DatabaseHelper.instance.database;
      final audit = AuditoriaService(db);
      _dashboard = SupervisionDashboardService(db);
      _service = InterventoriaLiquidacionService(db: db, auditoriaService: audit);
      final rows = await _dashboard!.contracts(entityId: widget.entidadId, userId: widget.usuarioId, canSeeAll: _canSeeAll);
      if (mounted) setState(() => _contracts = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No fue posible cargar supervisión: $_error')));
    if (_contracts.isEmpty) {
      final msg = _canSeeAll
          ? 'No hay contratos para supervisar.'
          : 'No tienes contratos asignados como supervisor o interventor.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.assignment_turned_in_outlined, size: 64),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      );
    }

    final today = DateTime.now();
    final dueSoon = _contracts.where((c) { final d=DateTime.tryParse(c.endDate ?? ''); return d != null && d.isAfter(today) && d.difference(today).inDays <= 30; }).length;
    final policiesSoon = _contracts.where((c) { final d=DateTime.tryParse(c.nextPolicyExpiry ?? ''); return d != null && d.isAfter(today) && d.difference(today).inDays <= 30; }).length;
    final alerts = _contracts.fold<int>(0, (sum, c) => sum + c.openAlerts);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          _metric('Asignados', _contracts.length.toString(), Icons.assignment_ind_outlined),
          _metric('Vencen ≤30 días', dueSoon.toString(), Icons.event_busy_outlined),
          _metric('Pólizas ≤30 días', policiesSoon.toString(), Icons.security_outlined),
          _metric('Alertas abiertas', alerts.toString(), Icons.warning_amber_rounded),
        ]),
        const SizedBox(height: 18),
        Text('Bandeja de supervisión', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('El avance físico proviene de los informes de supervisión. El avance financiero se calcula con pagos registrados frente al valor contractual; no sustituye la revisión del expediente.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ..._contracts.map(_contractCard),
      ]),
    );
  }

  Widget _metric(String label, String value, IconData icon) => SizedBox(width: 185, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)), Text(label, style: Theme.of(context).textTheme.bodySmall)]))]))));

  Widget _contractCard(ContractSupervisionSummary c) {
    final end = DateTime.tryParse(c.endDate ?? '');
    final days = end?.difference(DateTime.now()).inDays;
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('${c.number} · ${c.contractor}', style: const TextStyle(fontWeight: FontWeight.w700))), _statusChip(c.status)]),
      const SizedBox(height: 6), Text(c.object, maxLines: 2, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 10), Wrap(spacing: 18, runSpacing: 6, children: [
        Text('Supervisor: ${c.supervisor}'), Text('Físico: ${c.physicalProgress.toStringAsFixed(1)}%'), Text('Financiero: ${c.financialProgress.toStringAsFixed(1)}%'),
        Text('Pagado: ${publicMoneyFromSql(c.paid, nullableAsZero: true).format()}'),
        if (days != null) Text(days < 0 ? 'Vencido hace ${days.abs()} días' : 'Faltan $days días'),
        if (c.openAlerts > 0) Text('${c.openAlerts} alerta(s) abierta(s)', style: TextStyle(color: MerkaThemeTokens.danger, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12), LinearProgressIndicator(value: (c.physicalProgress / 100).clamp(0.0, 1.0).toDouble()),
      const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: () => _report(c), icon: const Icon(Icons.note_add_outlined), label: const Text('Informe')),
        OutlinedButton.icon(onPressed: () => _alert(c), icon: const Icon(Icons.warning_amber_outlined), label: const Text('Alerta')),
        OutlinedButton.icon(onPressed: () => _trace(c), icon: const Icon(Icons.account_tree_outlined), label: const Text('Trazabilidad')),
      ])
    ])));
  }

  Widget _statusChip(String value) => Chip(label: Text(value.isEmpty ? 'Sin estado' : value.replaceAll('_',' ')));

  Future<void> _report(ContractSupervisionSummary c) async {
    if (!AppSession.puedeEjecutarPermiso(Permiso.supervisarContrato) && !AppSession.puedeAdministrar()) { _snack('No tienes permiso para registrar informes.', error:true); return; }
    var type = TipoInforme.mensual;
    final content = TextEditingController();
    final observations = TextEditingController();
    final progress = TextEditingController(text: c.physicalProgress.toStringAsFixed(0));
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      title: Text('Informe · ${c.number}'),
      content: SizedBox(width: 620, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<TipoInforme>(initialValue: type, decoration: const InputDecoration(labelText: 'Tipo de informe'), items: TipoInforme.values.map((e)=>DropdownMenuItem(value:e, child:Text(_reportLabel(e)))).toList(), onChanged:(v)=>setD(()=>type=v ?? type)),
        const SizedBox(height: 10), TextField(controller: progress, keyboardType: const TextInputType.numberWithOptions(decimal:true), decoration: const InputDecoration(labelText:'Avance físico % (0–100)')),
        const SizedBox(height: 10), TextField(controller: content, minLines: 5, maxLines: 10, decoration: const InputDecoration(labelText:'Contenido y verificación realizada', alignLabelWithHint:true)),
        const SizedBox(height: 10), TextField(controller: observations, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText:'Observaciones')),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancelar')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('Registrar'))],
    )));
    if (accepted != true || !mounted) return;
    final pct = double.tryParse(progress.text.replaceAll(',','.')) ?? -1;
    if (content.text.trim().isEmpty || pct < 0 || pct > 100) { _snack('Completa el contenido y usa un avance entre 0 y 100.', error:true); return; }
    try {
      await _service!.registrarInformeSupervision(entidadId: widget.entidadId, usuarioId: widget.usuarioId, contratoId: c.id, tipoInforme: type, fechaInforme: DateTime.now(), contenido: content.text.trim(), elaboradoPor: AppSession.nombre, porcentajeEjecucion: pct, observaciones: observations.text.trim().isEmpty ? null : [observations.text.trim()]);
      _snack('Informe registrado y avance contractual actualizado.'); await _load();
    } catch(e) { _snack('No fue posible registrar el informe: $e', error:true); }
  }

  Future<void> _alert(ContractSupervisionSummary c) async {
    if (!AppSession.puedeEjecutarPermiso(Permiso.supervisarContrato) && !AppSession.puedeAdministrar()) { _snack('No tienes permiso para registrar alertas.', error:true); return; }
    var type = TipoAlerta.retrasoEjecucion;
    final description = TextEditingController();
    final correction = TextEditingController();
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title: Text('Alerta · ${c.number}'), content:SizedBox(width:620, child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min, children:[
        DropdownButtonFormField<TipoAlerta>(initialValue:type, decoration:const InputDecoration(labelText:'Tipo'), items:TipoAlerta.values.map((e)=>DropdownMenuItem(value:e, child:Text(_alertLabel(e)))).toList(), onChanged:(v)=>setD(()=>type=v ?? type)),
        const SizedBox(height:10), TextField(controller:description,minLines:4,maxLines:8,decoration:const InputDecoration(labelText:'Situación detectada',alignLabelWithHint:true)),
        const SizedBox(height:10), TextField(controller:correction,minLines:2,maxLines:5,decoration:const InputDecoration(labelText:'Medida correctiva propuesta')),
      ]))), actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancelar')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('Registrar'))]
    )));
    if (accepted != true || description.text.trim().isEmpty) return;
    try { await _service!.registrarAlertaIncumplimiento(entidadId:widget.entidadId,usuarioId:widget.usuarioId,contratoId:c.id,tipoAlerta:type,descripcion:description.text.trim(),fechaDeteccion:DateTime.now(),detectadoPor:AppSession.nombre,medidaCorrectiva:correction.text.trim().isEmpty?null:correction.text.trim()); _snack('Alerta registrada.'); await _load(); } catch(e){_snack('No fue posible registrar la alerta: $e',error:true);}
  }

  Future<void> _trace(ContractSupervisionSummary c) async {
    try {
      final data = await _dashboard!.traceability(c.id);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ContractTraceabilityPage(contractNumber:c.number, data:data)));
    } catch(e) { _snack('No fue posible construir la trazabilidad: $e', error:true); }
  }

  String _reportLabel(TipoInforme t) => switch(t){TipoInforme.inicial=>'Inicial',TipoInforme.mensual=>'Periódico / mensual',TipoInforme.finalInforme=>'Final',TipoInforme.especial=>'Especial'};
  String _alertLabel(TipoAlerta t) => switch(t){TipoAlerta.retrasoEjecucion=>'Retraso de ejecución',TipoAlerta.incumplimientoEspecificaciones=>'Incumplimiento de especificaciones',TipoAlerta.problemasCalidad=>'Calidad',TipoAlerta.retrasoPago=>'Retraso de pago',TipoAlerta.otro=>'Otro'};
  void _snack(String text,{bool error=false}) { if(!mounted)return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text),backgroundColor:error?MerkaThemeTokens.danger:MerkaThemeTokens.success)); }
}

class ContractTraceabilityPage extends StatelessWidget {
  const ContractTraceabilityPage({super.key, required this.contractNumber, required this.data});
  final String contractNumber;
  final Map<String,Object?> data;

  @override
  Widget build(BuildContext context) {
    List<Map<String,Object?>> list(String key) =>
        (data[key] as List? ?? const []).map((e) => Map<String,Object?>.from(e as Map)).toList();

    final sections = <({String title, IconData icon, List<Map<String,Object?>> rows})>[
      (title: 'Proceso', icon: Icons.gavel_outlined, rows: list('process')),
      (title: 'CDP', icon: Icons.request_quote_outlined, rows: list('cdp')),
      (title: 'RP', icon: Icons.verified_outlined, rows: list('rps')),
      (title: 'Obligaciones', icon: Icons.receipt_long_outlined, rows: list('obligations')),
      (title: 'Pagos', icon: Icons.payments_outlined, rows: list('payments')),
      (title: 'Polizas', icon: Icons.security_outlined, rows: list('policies')),
      (title: 'Informes de supervision', icon: Icons.assignment_turned_in_outlined, rows: list('reports')),
      (title: 'Alertas', icon: Icons.warning_amber_outlined, rows: list('alerts')),
      (title: 'Liquidacion', icon: Icons.task_alt_outlined, rows: list('liquidations')),
      (title: 'SGDEA / documentos vinculados', icon: Icons.folder_copy_outlined, rows: list('documents')),
    ];

    final sectionCards = sections.map((s) {
      final children = s.rows.isEmpty
          ? <Widget>[const ListTile(title: Text('Sin registros vinculados.'))]
          : s.rows.map((r) => ListTile(
              title: Text(_primary(s.title, r)),
              subtitle: Text(_secondary(r)),
              dense: true,
            )).toList();
      return Card(
        child: ExpansionTile(
          leading: Icon(s.icon),
          title: Text(s.title),
          subtitle: Text('${s.rows.length} registro(s)'),
          children: children,
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Trazabilidad · $contractNumber')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cadena contractual',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Proceso - CDP - RP - obligacion - pago - supervision - documentos. '
                    'La ausencia de un vinculo se muestra como pendiente; '
                    'MerkaERP no inventa soportes que no esten registrados.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...sectionCards,
        ],
      ),
    );
  }

  String _primary(String section, Map<String,Object?> r) {
    const preferred = [
      'numero_proceso', 'numero_cdp', 'numero_rp', 'numero_obligacion',
      'numero_pago', 'numero_poliza', 'tipo_informe', 'tipo_alerta',
      'numero_contrato', 'expediente_code', 'document_title', 'radicado_number',
    ];
    for (final k in preferred) {
      final v = r[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return section;
  }

  String _secondary(Map<String,Object?> r) {
    const preferred = [
      'objeto_contrato', 'objeto_gasto', 'tercero_nombre', 'aseguradora',
      'contenido', 'descripcion', 'expediente_title', 'estado',
      'fecha_informe', 'fecha_deteccion', 'fecha_ejecucion',
    ];
    final parts = <String>[];
    for (final k in preferred) {
      final v = r[k]?.toString().trim();
      if (v != null && v.isNotEmpty && !parts.contains(v)) parts.add(v);
      if (parts.length >= 3) break;
    }
    return parts.join(' - ');
  }
}
