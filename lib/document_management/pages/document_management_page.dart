import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app_session.dart';
import '../../sector_publico/security/roles_permisos_service.dart';
import '../../ui/enterprise_design_system.dart';
import '../application/document_management_service.dart';
import '../domain/document_models.dart';
import '../reports/document_reports_service.dart';

class DocumentManagementPage extends StatelessWidget {
  const DocumentManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: DocumentManagementService.instance.isPublicSector,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final isPublic = snapshot.data!;
        final tabs = <Tab>[
          const Tab(icon: Icon(Icons.dashboard_outlined), text: 'Resumen'),
          const Tab(icon: Icon(Icons.mark_email_read_outlined), text: 'Radicación'),
          const Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Expedientes'),
          const Tab(icon: Icon(Icons.archive_outlined), text: 'Archivo'),
          if (isPublic) const Tab(icon: Icon(Icons.account_tree_outlined), text: 'TRD / TVD'),
          if (isPublic) const Tab(icon: Icon(Icons.policy_outlined), text: 'Instrumentos'),
          const Tab(icon: Icon(Icons.tune), text: 'Configuración'),
        ];
        final pages = <Widget>[
          const _DashboardTab(),
          const _RadicadosTab(),
          const _CasesTab(),
          const _ArchiveTab(),
          if (isPublic) const _RetentionTab(),
          if (isPublic) const _InstrumentsTab(),
          const _DocumentSettingsTab(),
        ];
        return DefaultTabController(
          length: tabs.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text(isPublic ? 'Gestión Documental · SGDEA' : 'Gestión Documental Empresarial'),
              bottom: TabBar(isScrollable: true, tabs: tabs),
            ),
            body: TabBarView(children: pages),
          ),
        );
      },
    );
  }
}

bool get _canAdminDocs => AppSession.puedeAdministrar() ||
    AppSession.puedeEjecutarPermiso(Permiso.administrarGestionDocumental);
bool get _canRadicate => AppSession.puedeAdministrar() ||
    AppSession.puedeEjecutarPermiso(Permiso.radicarDocumentos) ||
    AppSession.rol != null;
bool get _canArchive => AppSession.puedeAdministrar() ||
    AppSession.puedeEjecutarPermiso(Permiso.administrarArchivo);

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Future<DocumentDashboardSnapshot>? future;
  @override
  void initState() { super.initState(); future = DocumentManagementService.instance.dashboard(); }
  void reload() => setState(() => future = DocumentManagementService.instance.dashboard());

  @override
  Widget build(BuildContext context) => FutureBuilder<DocumentDashboardSnapshot>(
    future: future,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final d = snapshot.data!;
      final cards = [
        ('Radicados hoy', d.today, Icons.today), ('Pendientes', d.pending, Icons.pending_actions),
        ('Vencidos', d.overdue, Icons.warning_amber), ('Para firma', d.forSignature, Icons.draw),
        ('Expedientes abiertos', d.openCases, Icons.folder_open), ('Préstamos activos', d.activeLoans, Icons.assignment_return),
        ('Transferencias pendientes', d.transfersPending, Icons.move_to_inbox),
      ];
      return RefreshIndicator(
        onRefresh: () async { reload(); await future; },
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Control documental', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Radicación, trámite, expediente, archivo, retención y trazabilidad en una sola cadena.'),
            ])),
            IconButton(onPressed: reload, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
          ]),
          const SizedBox(height: 18),
          LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth >= 1000 ? 4 : constraints.maxWidth >= 650 ? 2 : 1;
            final width = (constraints.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final c in cards) SizedBox(width: width, child: Card(child: Padding(
                padding: const EdgeInsets.all(18), child: Row(children: [
                  CircleAvatar(child: Icon(c.$3)), const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.$2}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text(c.$1),
                  ])),
                ]),
              ))),
            ]);
          }),
          const SizedBox(height: 18),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reglas de integridad', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const _Rule(icon: Icons.lock_outline, text: 'Los originales electrónicos se conservan con huella SHA-256 y no se eliminan desde la disposición final.'),
            const _Rule(icon: Icons.history, text: 'Cada actuación, consulta, préstamo, transferencia y disposición genera trazabilidad.'),
            const _Rule(icon: Icons.business_center_outlined, text: 'Numeración, términos, calendario, instrumentos y reglas archivísticas son configurables por organización.'),
          ]))),
        ]),
      );
    },
  );
}

class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text}); final IconData icon; final String text;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 10), Expanded(child: Text(text))]));
}

class _RadicadosTab extends StatefulWidget { const _RadicadosTab(); @override State<_RadicadosTab> createState() => _RadicadosTabState(); }
class _RadicadosTabState extends State<_RadicadosTab> {
  final service = DocumentManagementService.instance;
  final search = TextEditingController();
  String status = 'all';
  Future<List<Map<String, Object?>>>? future;
  @override void initState() { super.initState(); reload(); }
  void reload() => setState(() => future = service.listRadicados(search: search.text, status: status));

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(children: [
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 330, child: TextField(controller: search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar radicado, asunto o tercero'), onSubmitted: (_) => reload())),
        SizedBox(width: 180, child: DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Estado'), items: const [
          DropdownMenuItem(value: 'all', child: Text('Todos')), DropdownMenuItem(value: 'registered', child: Text('Radicado')),
          DropdownMenuItem(value: 'assigned', child: Text('Asignado')), DropdownMenuItem(value: 'in_progress', child: Text('En trámite')),
          DropdownMenuItem(value: 'for_signature', child: Text('Para firma')), DropdownMenuItem(value: 'responded', child: Text('Respondido')),
          DropdownMenuItem(value: 'closed', child: Text('Cerrado')), DropdownMenuItem(value: 'archived', child: Text('Archivado')),
        ], onChanged: (v) { status = v ?? 'all'; reload(); })),
        FilledButton.icon(onPressed: _canRadicate ? () => _newRadicado(context) : null, icon: const Icon(Icons.add), label: const Text('Nuevo radicado')),
        IconButton(tooltip: 'Actualizar radicados', onPressed: reload, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 12),
      Expanded(child: FutureBuilder<List<Map<String, Object?>>>(future: future, builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snapshot.data!;
        if (rows.isEmpty) return const Center(child: Text('No hay radicados con estos filtros.'));
        return ListView.separated(itemCount: rows.length, separatorBuilder: (_, _) => const Divider(height: 1), itemBuilder: (context, index) {
          final row = rows[index];
          final overdue = _isOverdue(row);
          return ListTile(
            leading: CircleAvatar(child: Icon(_directionIcon(row['direction']?.toString()))),
            title: Text('${row['number']} · ${row['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${row['sender_name'] ?? ''} → ${row['recipient_name'] ?? ''}\n${_date(row['received_at'])}${row['due_at'] == null ? '' : ' · vence ${_date(row['due_at'])}'}'),
            isThreeLine: true,
            trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Chip(label: Text(overdue ? 'VENCIDO' : _statusLabel(row['status']?.toString())), avatar: overdue ? const Icon(Icons.warning, size: 16) : null),
              IconButton(tooltip: 'Abrir detalle', onPressed: () => _detail(context, (row['id'] as num).toInt()), icon: const Icon(Icons.chevron_right)),
            ]),
            onTap: () => _detail(context, (row['id'] as num).toInt()),
          );
        });
      })),
    ]),
  );

  Future<void> _newRadicado(BuildContext context) async {
    final result = await showDialog<bool>(context: context, builder: (_) => const _NewRadicadoDialog());
    if (result == true) reload();
  }

  Future<void> _detail(BuildContext context, int id) async {
    await showDialog(context: context, builder: (_) => _RadicadoDetailDialog(id: id));
    reload();
  }
}

class _NewRadicadoDialog extends StatefulWidget { const _NewRadicadoDialog(); @override State<_NewRadicadoDialog> createState() => _NewRadicadoDialogState(); }
class _NewRadicadoDialogState extends State<_NewRadicadoDialog> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(); final sender = TextEditingController(); final recipient = TextEditingController();
  final description = TextEditingController(); final term = TextEditingController(); final user = TextEditingController();
  DocumentDirection direction = DocumentDirection.incoming; String channel = 'digital'; String priority = 'normal'; String access = 'public';
  bool busy = false;
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Registrar documento'),
    content: SizedBox(width: 620, child: Form(key: form, child: SingleChildScrollView(child: Column(children: [
      DropdownButtonFormField<DocumentDirection>(initialValue: direction, decoration: const InputDecoration(labelText: 'Tipo de radicación'), items: DocumentDirection.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(), onChanged: (v) => setState(() => direction = v ?? direction)),
      TextFormField(controller: subject, decoration: const InputDecoration(labelText: 'Asunto *'), validator: _required),
      Row(children: [Expanded(child: TextFormField(controller: sender, decoration: const InputDecoration(labelText: 'Remitente *'), validator: _required)), const SizedBox(width: 10), Expanded(child: TextFormField(controller: recipient, decoration: const InputDecoration(labelText: 'Destinatario *'), validator: _required))]),
      TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Descripción / observaciones'), maxLines: 2),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: channel, decoration: const InputDecoration(labelText: 'Canal'), items: const ['digital','presencial','correo','mensajeria','web'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => channel = v ?? channel)),
        const SizedBox(width: 10),
        Expanded(child: TextFormField(controller: term, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Término (días hábiles)'))),
      ]),
      Row(children: [
        Expanded(child: DropdownButtonFormField<String>(initialValue: priority, decoration: const InputDecoration(labelText: 'Prioridad'), items: const ['normal','alta','urgente'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => priority = v ?? priority)),
        const SizedBox(width: 10),
        Expanded(child: DropdownButtonFormField<String>(initialValue: access, decoration: const InputDecoration(labelText: 'Acceso'), items: const [
          DropdownMenuItem(value:'public', child: Text('Público / ordinario')), DropdownMenuItem(value:'classified', child: Text('Clasificado')),
          DropdownMenuItem(value:'reserved', child: Text('Reservado')), DropdownMenuItem(value:'personal_data', child: Text('Datos personales')),
        ], onChanged: (v) => access = v ?? access)),
      ]),
      TextFormField(controller: user, decoration: const InputDecoration(labelText: 'Usuario responsable (opcional)')),
    ])))),
    actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')), FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Radicar'))],
  );
  Future<void> _save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() => busy = true);
    try {
      final created = await DocumentManagementService.instance.registerRadicado(RadicadoInput(
        direction: direction, subject: subject.text, senderName: sender.text, recipientName: recipient.text,
        description: description.text, channel: channel, priority: priority, accessLevel: access,
        termBusinessDays: int.tryParse(term.text.trim()), assignedUserId: user.text.trim().isEmpty ? null : user.text.trim(),
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Radicado ${created.number} creado.')));
    } catch (e) { if (mounted) _error(context, e); setState(() => busy = false); }
  }
}

class _RadicadoDetailDialog extends StatefulWidget { const _RadicadoDetailDialog({required this.id}); final int id; @override State<_RadicadoDetailDialog> createState() => _RadicadoDetailDialogState(); }
class _RadicadoDetailDialogState extends State<_RadicadoDetailDialog> {
  final service = DocumentManagementService.instance;
  Future<(Map<String,Object?>?, List<Map<String,Object?>>, List<Map<String,Object?>>)>? future;
  @override void initState(){ super.initState(); reload(); }
  void reload() => setState(() => future = _load());
  Future<(Map<String,Object?>?, List<Map<String,Object?>>, List<Map<String,Object?>>)> _load() async => (
    await service.getRadicado(widget.id), await service.workflow(widget.id), await service.documentsFor(radicadoId: widget.id));
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Detalle del radicado'),
    content: SizedBox(width: EnterpriseDialogSizing.width(context, 800), height: EnterpriseDialogSizing.height(context, 560), child: FutureBuilder(future: future, builder: (context, snapshot) {
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final data = snapshot.data!; final row = data.$1; if (row == null) return const Text('Radicado no encontrado.');
      return ListView(children: [
        Row(children: [Expanded(child: Text('${row['number']}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))), Chip(label: Text(_statusLabel(row['status']?.toString())))]),
        const SizedBox(height: 6), Text(row['subject']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8), Text('${row['sender_name'] ?? ''} → ${row['recipient_name'] ?? ''}'),
        Text('Registrado: ${_date(row['received_at'])}${row['due_at'] == null ? '' : ' · vence ${_date(row['due_at'])}'}'),
        if ((row['description']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top:8), child: Text(row['description'].toString())),
        const Divider(height: 28),
        Row(children: [Text('Documentos (${data.$3.length})', style: const TextStyle(fontWeight: FontWeight.bold)), const Spacer(), if (_canRadicate) TextButton.icon(onPressed: _attach, icon: const Icon(Icons.attach_file), label: const Text('Adjuntar'))]),
        for (final doc in data.$3)
          ListTile(
            dense: true,
            leading: Icon(doc['is_signed'] == 1 ? Icons.verified : Icons.description_outlined),
            title: Text(doc['title']?.toString() ?? doc['file_name']?.toString() ?? ''),
            subtitle: Text(
              'v${doc['version_number']} · SHA-256 ${_shortHash(doc['sha256'])}'
              '${doc['is_signed'] == 1 ? ' · Firmado' : ''}',
            ),
            trailing: _DocumentActions(doc: doc, service: service),
          ),
        const Divider(), Text('Trazabilidad', style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final event in data.$2) ListTile(dense:true, leading: const Icon(Icons.history, size:20), title: Text('${event['action']} → ${_statusLabel(event['to_status']?.toString())}'), subtitle: Text('${_date(event['created_at'])}${event['comment'] == null ? '' : ' · ${event['comment']}'}')),
      ]);
    })),
    actions: [
      TextButton.icon(onPressed: _print, icon: const Icon(Icons.print), label: const Text('Comprobante')),
      PopupMenuButton<String>(enabled: _canRadicate, onSelected: _action, itemBuilder: (_) => const [
        PopupMenuItem(value:'progress', child: Text('Marcar en trámite')), PopupMenuItem(value:'signature', child: Text('Enviar a firma')),
        PopupMenuItem(value:'responded', child: Text('Marcar respondido')), PopupMenuItem(value:'close', child: Text('Cerrar')),
        PopupMenuItem(value:'archive', child: Text('Archivar')),
      ], child: const Padding(padding: EdgeInsets.symmetric(horizontal:12), child: Row(mainAxisSize:MainAxisSize.min, children:[Icon(Icons.more_horiz),SizedBox(width:6),Text('Actuación')]))),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar ventana')),
    ],
  );
  Future<void> _attach() async {
    final pick = await FilePicker.platform.pickFiles(withData: false); final path = pick?.files.single.path; if (path == null) return;
    try { await service.attachFile(sourcePath:path, title:pick!.files.single.name, radicadoId:widget.id); reload(); } catch(e){ if(mounted) _error(context,e); }
  }
  Future<void> _print() async { final data=await _load(); if(data.$1==null)return; final bytes=await DocumentReportsService.radicadoReceipt(radicado:data.$1!,workflow:data.$2); await Printing.layoutPdf(onLayout:(_)=>bytes, name:'Radicado_${data.$1!['number']}.pdf'); }
  Future<void> _action(String action) async {
    try {
      if(action=='progress') await service.markInProgress(widget.id, comment:'Actuación registrada desde Gestión Documental');
      if(action=='signature') await service.markForSignature(widget.id, comment:'Enviado a firma/revisión');
      if(action=='responded') await service.markResponded(widget.id, comment:'Respuesta registrada');
      if(action=='close') { if (!mounted) return; final c=await _ask(context,'Motivo / actuación de cierre'); if(c==null)return; await service.closeRadicado(widget.id,comment:c); }
      if(action=='archive') await service.archiveRadicado(widget.id,comment:'Archivado desde Gestión Documental');
      reload();
    } catch(e){ if(mounted)_error(context,e); }
  }
}

class _CasesTab extends StatefulWidget { const _CasesTab(); @override State<_CasesTab> createState()=>_CasesTabState(); }
class _CasesTabState extends State<_CasesTab> {
  final service=DocumentManagementService.instance; Future<List<Map<String,Object?>>>? future; final search=TextEditingController();
  @override void initState(){super.initState();reload();} void reload()=>setState(()=>future=service.listCases(search:search.text));
  @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(16),child:Column(children:[
    Wrap(spacing:10,runSpacing:10,children:[SizedBox(width:330,child:TextField(controller:search,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Buscar expediente'),onSubmitted:(_)=>reload())),FilledButton.icon(onPressed:_canRadicate?()=>_create(context):null,icon:const Icon(Icons.create_new_folder),label:const Text('Nuevo expediente')),IconButton(tooltip:'Actualizar expedientes',onPressed:reload,icon:const Icon(Icons.refresh))]),
    const SizedBox(height:12),Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:future,builder:(context,snapshot){if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());final rows=snapshot.data!;if(rows.isEmpty)return const Center(child:Text('No hay expedientes.'));return ListView.separated(itemCount:rows.length,separatorBuilder:(_,_)=>const Divider(height:1),itemBuilder:(context,i){final r=rows[i];return ListTile(leading:const Icon(Icons.folder_copy_outlined),title:Text('${r['code']} · ${r['title']}'),subtitle:Text('${r['current_archive_stage']} · ${r['status']} · abierto ${_date(r['opened_at'])}'),trailing:const Icon(Icons.chevron_right),onTap:()=>_detail(context,r));});}))
  ]));
  Future<void> _create(BuildContext context) async {final title=await _ask(context,'Nombre / asunto del expediente');if(title==null||title.trim().isEmpty)return;try{await service.createCase(title:title);reload();}catch(e){if(context.mounted)_error(context,e);}}
  Future<void> _detail(BuildContext context,Map<String,Object?> row) async {await showDialog(context:context,builder:(_)=>_CaseDetailDialog(row:row));reload();}
}

class _CaseDetailDialog extends StatefulWidget {
  const _CaseDetailDialog({required this.row});
  final Map<String, Object?> row;
  @override
  State<_CaseDetailDialog> createState() => _CaseDetailDialogState();
}

class _CaseDetailDialogState extends State<_CaseDetailDialog> {
  final service = DocumentManagementService.instance;
  Future<List<Map<String, Object?>>>? docs;
  Future<List<Map<String, Object?>>>? radicados;

  int get caseId => (widget.row['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => setState(() {
        docs = service.documentsFor(caseId: caseId);
        radicados = service.radicadosForCase(caseId);
      });

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.row['code']} · ${widget.row['title']}'),
        content: SizedBox(
          width: EnterpriseDialogSizing.width(context, 760),
          height: EnterpriseDialogSizing.height(context, 520),
          child: ListView(
            children: [
              Text(
                'Etapa archivística: ${widget.row['current_archive_stage']} · Estado: ${widget.row['status']}',
              ),
              if (widget.row['transfer_due_at'] != null)
                Text('Transferencia prevista: ${_date(widget.row['transfer_due_at'])}'),
              if (widget.row['disposition_due_at'] != null)
                Text('Disposición prevista: ${_date(widget.row['disposition_due_at'])}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _canRadicate ? _linkRadicado : null,
                    icon: const Icon(Icons.link),
                    label: const Text('Vincular radicado'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _canArchive ? _location : null,
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('Ubicación física'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _canArchive ? _loan : null,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('Préstamo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _canArchive ? _transfer : null,
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: const Text('Transferir'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _canArchive ? _disposition : null,
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('Disposición'),
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Text('Radicados vinculados', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: reload, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
                ],
              ),
              FutureBuilder<List<Map<String, Object?>>>(
                future: radicados,
                builder: (context, s) {
                  if (!s.hasData) return const LinearProgressIndicator();
                  if (s.data!.isEmpty) return const Text('Sin radicados vinculados.');
                  return Column(
                    children: [
                      for (final r in s.data!)
                        ListTile(
                          dense: true,
                          leading: Icon(_directionIcon(r['direction']?.toString())),
                          title: Text('${r['number']} · ${r['subject']}'),
                          subtitle: Text('${_statusLabel(r['status']?.toString())} · ${r['relation_type']}'),
                        ),
                    ],
                  );
                },
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Text('Documentos', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_canRadicate)
                    TextButton.icon(
                      onPressed: _attach,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Adjuntar'),
                    ),
                ],
              ),
              FutureBuilder<List<Map<String, Object?>>>(
                future: docs,
                builder: (context, s) {
                  if (!s.hasData) return const LinearProgressIndicator();
                  if (s.data!.isEmpty) return const Text('Sin documentos adjuntos.');
                  return Column(
                    children: [
                      for (final d in s.data!)
                        ListTile(
                          dense: true,
                          leading: Icon(d['is_signed'] == 1 ? Icons.verified : Icons.description),
                          title: Text(d['title']?.toString() ?? ''),
                          subtitle: Text(
                            'v${d['version_number']} · ${_shortHash(d['sha256'])}'
                            '${d['is_signed'] == 1 ? ' · Firmado' : ''}',
                          ),
                          trailing: _DocumentActions(doc: d, service: service),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          if (widget.row['status'] == 'open')
            TextButton.icon(
              onPressed: _canArchive ? _close : null,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Cerrar expediente'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      );

  Future<void> _attach() async {
    final pick = await FilePicker.platform.pickFiles();
    final path = pick?.files.single.path;
    if (path == null) return;
    try {
      await service.attachFile(sourcePath: path, title: pick!.files.single.name, caseId: caseId);
      reload();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _linkRadicado() async {
    final number = await _ask(context, 'Número o texto del radicado a vincular');
    if (number == null || number.isEmpty) return;
    final rows = await service.listRadicados(search: number, limit: 30);
    if (!mounted) return;
    final selected = await _chooseRow(
      context,
      'Seleccionar radicado',
      rows,
      title: (r) => '${r['number']} · ${r['subject']}',
      subtitle: (r) => '${_statusLabel(r['status']?.toString())} · ${_date(r['received_at'])}',
    );
    if (selected == null) return;
    await service.linkRadicadoToCase(radicadoId: (selected['id'] as num).toInt(), caseId: caseId);
    reload();
  }

  Future<void> _location() async {
    final rows = await service.physicalLocations();
    if (!mounted) return;
    final selected = await _chooseRow(
      context,
      'Asignar ubicación física',
      rows,
      title: (r) => (r['label']?.toString().trim().isNotEmpty ?? false)
          ? r['label'].toString()
          : '${r['box_code'] ?? ''} / ${r['folder_code'] ?? ''}',
      subtitle: (r) => '${r['archive_stage']} · ${r['building'] ?? ''} ${r['room'] ?? ''}',
    );
    if (selected == null) return;
    await service.assignCasePhysicalLocation(caseId, (selected['id'] as num).toInt());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ubicación asignada.')));
  }

  Future<void> _loan() async {
    final borrower = await _twoFields(context, 'Registrar préstamo', 'Identificación / usuario', 'Nombre del prestatario');
    if (borrower == null || borrower.$1.isEmpty || borrower.$2.isEmpty) return;
    if (!mounted) return;
    final purpose = await _ask(context, 'Finalidad del préstamo');
    if (purpose == null || purpose.isEmpty || !mounted) return;
    final due = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: DateTime.now().add(const Duration(days: 8)),
    );
    if (due == null) return;
    await service.loan(
      caseId: caseId,
      borrowerUserId: borrower.$1,
      borrowerName: borrower.$2,
      purpose: purpose,
      dueAt: due.add(const Duration(hours: 23, minutes: 59)),
    );
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Préstamo registrado y trazado.')));
  }

  Future<void> _transfer() async {
    final rows = (await service.transfers()).where((r) => r['status'] == 'draft').toList();
    if (!mounted) return;
    final selected = await _chooseRow(
      context,
      'Agregar a transferencia',
      rows,
      title: (r) => '${r['transfer_number']} · ${r['from_stage']} → ${r['to_stage']}',
      subtitle: (r) => '${r['transfer_type']} · ${_date(r['requested_at'])}',
    );
    if (selected == null) return;
    await service.addCaseToTransfer((selected['id'] as num).toInt(), caseId);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expediente agregado a la transferencia.')));
  }

  Future<void> _disposition() async {
    if (!mounted) return;
    final disposition = await _chooseString(context, 'Proponer disposición final', const {
      'total_conservation': 'Conservación total',
      'selection': 'Selección',
      'elimination': 'Eliminación autorizada',
      'reproduction': 'Reproducción / medio técnico',
    });
    if (disposition == null || !mounted) return;
    final notes = await _ask(context, 'Justificación / observaciones de la propuesta');
    await service.proposeDisposition(caseId: caseId, disposition: disposition, notes: notes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disposición propuesta; requiere autorización para ejecutarse.')));
  }

  Future<void> _close() async {
    try {
      await service.closeCase(caseId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }
}

class _ArchiveTab extends StatefulWidget { const _ArchiveTab(); @override State<_ArchiveTab> createState()=>_ArchiveTabState(); }
class _ArchiveTabState extends State<_ArchiveTab>{
  final service=DocumentManagementService.instance; int view=0;
  @override Widget build(BuildContext context)=>Column(children:[Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<int>(segments:const [ButtonSegment(value:0,label:Text('Ubicaciones'),icon:Icon(Icons.warehouse)),ButtonSegment(value:1,label:Text('Préstamos'),icon:Icon(Icons.assignment_return)),ButtonSegment(value:2,label:Text('Transferencias'),icon:Icon(Icons.move_to_inbox)),ButtonSegment(value:3,label:Text('Disposición'),icon:Icon(Icons.rule_folder))],selected:{view},onSelectionChanged:(s)=>setState(()=>view=s.first))),Expanded(child:switch(view){0=>_Locations(service:service),1=>_Loans(service:service),2=>_Transfers(service:service),_=>_Dispositions(service:service)})]);
}
class _Locations extends StatefulWidget{const _Locations({required this.service});final DocumentManagementService service;@override State<_Locations>createState()=>_LocationsState();}
class _LocationsState extends State<_Locations>{Future<List<Map<String,Object?>>>? future;@override void initState(){super.initState();reload();}void reload()=>setState(()=>future=widget.service.physicalLocations());@override Widget build(BuildContext context)=>Column(children:[Padding(padding:const EdgeInsets.all(12),child:Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_canArchive?()=>_new(context):null,icon:const Icon(Icons.add_location_alt),label:const Text('Nueva ubicación')))),Expanded(child:FutureBuilder<List<Map<String,Object?>>>(future:future,builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(children:[for(final r in s.data!)ListTile(leading:const Icon(Icons.inventory_2_outlined),title:Text(r['label']?.toString().isNotEmpty==true?r['label'].toString():'${r['box_code']??''} / ${r['folder_code']??''}'),subtitle:Text('${r['archive_stage']} · ${r['building']??''} ${r['room']??''} · estante ${r['shelf']??''} · cuerpo ${r['body']??''}'))]);}))]);Future<void>_new(BuildContext context)async{final data=await showDialog<Map<String,String>>(context:context,builder:(_)=>const _LocationDialog());if(data==null)return;await widget.service.createPhysicalLocation(archiveStage:data['stage']!,building:data['building'],room:data['room'],shelf:data['shelf'],body:data['body'],tray:data['tray'],boxCode:data['box'],folderCode:data['folder'],label:data['label']);reload();}}
class _LocationDialog extends StatefulWidget{const _LocationDialog();@override State<_LocationDialog>createState()=>_LocationDialogState();}
class _LocationDialogState extends State<_LocationDialog>{String stage='management';final fields={for(final k in ['building','room','shelf','body','tray','box','folder','label'])k:TextEditingController()};@override Widget build(BuildContext context)=>AlertDialog(title:const Text('Ubicación física'),content:SizedBox(width:500,child:SingleChildScrollView(child:Column(children:[DropdownButtonFormField<String>(initialValue:stage,decoration:const InputDecoration(labelText:'Etapa'),items:const [DropdownMenuItem(value:'management',child:Text('Archivo de gestión')),DropdownMenuItem(value:'central',child:Text('Archivo central')),DropdownMenuItem(value:'historical',child:Text('Archivo histórico'))],onChanged:(v)=>stage=v??stage),for(final e in fields.entries)TextField(controller:e.value,decoration:InputDecoration(labelText:_fieldLabel(e.key)))]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,{...{for(final e in fields.entries)e.key:e.value.text.trim()},'stage':stage}),child:const Text('Guardar'))]);}
class _Loans extends StatefulWidget{const _Loans({required this.service});final DocumentManagementService service;@override State<_Loans>createState()=>_LoansState();}
class _LoansState extends State<_Loans>{Future<List<Map<String,Object?>>>?future;@override void initState(){super.initState();reload();}void reload()=>setState(()=>future=widget.service.loans(activeOnly:false));@override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,Object?>>>(future:future,builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());return ListView(padding:const EdgeInsets.all(12),children:[const Padding(padding:EdgeInsets.all(8),child:Text('Los préstamos se registran desde el expediente/documento seleccionado. Esta vista controla vencimientos y devoluciones.',style:TextStyle(fontWeight:FontWeight.w600))),for(final r in s.data!)ListTile(leading:Icon(r['status']=='active'?Icons.schedule:Icons.check_circle_outline),title:Text('${r['borrower_name']??r['borrower_user_id']} · ${r['purpose']}'),subtitle:Text('Prestado ${_date(r['loaned_at'])} · vence ${_date(r['due_at'])}'),trailing:r['status']=='active'?TextButton(onPressed:_canArchive?()async{await widget.service.returnLoan((r['id']as num).toInt());reload();}:null,child:const Text('Devolver')):Text(r['status'].toString()))]);});}
class _Transfers extends StatefulWidget {
  const _Transfers({required this.service});
  final DocumentManagementService service;
  @override
  State<_Transfers> createState() => _TransfersState();
}

class _TransfersState extends State<_Transfers> {
  Future<List<Map<String, Object?>>>? future;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() => future = widget.service.transfers());

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(onPressed: _canArchive ? _new : null, icon: const Icon(Icons.add), label: const Text('Nueva transferencia')),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: future,
            builder: (context, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              if (s.data!.isEmpty) return const Center(child: Text('No hay transferencias registradas.'));
              return ListView(children: [
                for (final r in s.data!)
                  ListTile(
                    leading: const Icon(Icons.move_to_inbox),
                    title: Text('${r['transfer_number']} · ${r['from_stage']} → ${r['to_stage']}'),
                    subtitle: Text('${r['status']} · ${_date(r['requested_at'])}${r['act_reference'] == null ? '' : ' · ${r['act_reference']}'}'),
                    onTap: () => _detail(r),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'pdf') _print(r);
                        if (value == 'complete') _complete(r);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('FUID / inventario'))),
                        if (r['status'] == 'draft')
                          const PopupMenuItem(value: 'complete', child: ListTile(leading: Icon(Icons.verified), title: Text('Completar transferencia'))),
                      ],
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]);

  Future<void> _new() async {
    final type = await _chooseString(context, 'Tipo de transferencia', const {'primary': 'Primaria · Gestión → Central', 'secondary': 'Secundaria · Central → Histórico'});
    if (type == null) return;
    await widget.service.createTransfer(type: type, fromStage: type == 'secondary' ? 'central' : 'management', toStage: type == 'secondary' ? 'historical' : 'central');
    reload();
  }

  Future<void> _detail(Map<String, Object?> transfer) async {
    final id = (transfer['id'] as num).toInt();
    final items = await widget.service.transferItems(id);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Inventario · ${transfer['transfer_number']}'),
        content: SizedBox(
          width: EnterpriseDialogSizing.width(context, 720),
          height: EnterpriseDialogSizing.height(context, 440),
          child: items.isEmpty
              ? const Center(child: Text('Todavía no se han agregado expedientes. Hazlo desde el expediente.'))
              : ListView(children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(item['accepted'] == 1 ? Icons.verified : Icons.folder_outlined),
                      title: Text('${item['expediente_code']} · ${item['expediente_title']}'),
                      subtitle: Text('${item['current_archive_stage']} · ${item['observation'] ?? ''}'),
                      trailing: transfer['status'] == 'draft' && _canArchive
                          ? PopupMenuButton<String>(
                              onSelected: (value) async {
                                final obs = await _ask(context, 'Observación del inventario', initial: item['observation']?.toString());
                                await widget.service.updateTransferItem((item['id'] as num).toInt(), accepted: value == 'accept', observation: obs);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'accept', child: Text('Aceptar ítem')),
                                PopupMenuItem(value: 'observe', child: Text('Registrar observación')),
                              ],
                            )
                          : null,
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
    reload();
  }

  Future<void> _complete(Map<String, Object?> transfer) async {
    final act = await _ask(context, 'Acta / referencia de transferencia');
    if (act == null || act.isEmpty) return;
    try {
      await widget.service.completeTransfer((transfer['id'] as num).toInt(), actReference: act);
      reload();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }

  Future<void> _print(Map<String, Object?> r) async {
    final items = await widget.service.transferItems((r['id'] as num).toInt());
    final bytes = await DocumentReportsService.fuid(transfer: r, items: items);
    await Printing.layoutPdf(onLayout: (_) => bytes, name: 'FUID_${r['transfer_number']}.pdf');
  }
}

class _Dispositions extends StatefulWidget {
  const _Dispositions({required this.service});
  final DocumentManagementService service;
  @override
  State<_Dispositions> createState() => _DispositionsState();
}

class _DispositionsState extends State<_Dispositions> {
  Future<List<Map<String, Object?>>>? future;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() => future = widget.service.dispositions());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          if (s.data!.isEmpty) return const Center(child: Text('No hay acciones de disposición final registradas.'));
          return ListView(children: [
            for (final r in s.data!)
              ListTile(
                leading: const Icon(Icons.rule_folder_outlined),
                title: Text('${r['expediente_code']} · ${_dispositionLabel(r['disposition']?.toString())}'),
                subtitle: Text('${r['status']} · ${r['expediente_title']}${r['authorization_reference'] == null ? '' : ' · ${r['authorization_reference']}'}'),
                trailing: r['status'] == 'proposed'
                    ? FilledButton(onPressed: _canArchive ? () => _execute(r) : null, child: const Text('Ejecutar'))
                    : const Icon(Icons.verified),
              ),
          ]);
        },
      );

  Future<void> _execute(Map<String, Object?> row) async {
    final auth = await _ask(context, 'Acto / autorización de disposición');
    if (auth == null || auth.isEmpty || !mounted) return;
    final committee = await _ask(context, 'Acta de comité / aprobación (si aplica)');
    String? elimination;
    if (row['disposition'] == 'elimination' && mounted) {
      elimination = await _ask(context, 'Acta específica de eliminación documental');
      if (elimination == null || elimination.isEmpty) return;
    }
    try {
      await widget.service.executeDisposition(
        (row['id'] as num).toInt(),
        authorizationReference: auth,
        committeeAct: committee,
        eliminationAct: elimination,
      );
      reload();
    } catch (e) {
      if (mounted) _error(context, e);
    }
  }
}


class _RetentionTab extends StatefulWidget{const _RetentionTab();@override State<_RetentionTab>createState()=>_RetentionTabState();}
class _RetentionTabState extends State<_RetentionTab>{final service=DocumentManagementService.instance;int mode=0;@override Widget build(BuildContext context)=>Column(children:[Padding(padding:const EdgeInsets.all(12),child:SegmentedButton<int>(segments:const [ButtonSegment(value:0,label:Text('TRD')),ButtonSegment(value:1,label:Text('TVD')),ButtonSegment(value:2,label:Text('Series / dependencias'))],selected:{mode},onSelectionChanged:(v)=>setState(()=>mode=v.first))),Expanded(child:switch(mode){0=>_TrdView(service:service),1=>_TvdView(service:service),_=>_ClassificationView(service:service)})]);}
class _TrdView extends StatefulWidget {
  const _TrdView({required this.service});
  final DocumentManagementService service;
  @override
  State<_TrdView> createState() => _TrdViewState();
}

class _TrdViewState extends State<_TrdView> {
  Future<List<Map<String, Object?>>>? versions;
  Future<List<Map<String, Object?>>>? entries;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() {
        versions = widget.service.trdVersions();
        entries = widget.service.trdEntries();
      });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(child: Text('Tablas de Retención Documental', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: _canAdminDocs ? _newEntry : null, icon: const Icon(Icons.playlist_add), label: const Text('Entrada TRD')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _canAdminDocs ? _newVersion : null, icon: const Icon(Icons.add), label: const Text('Versión TRD')),
          ]),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, Object?>>>(
            future: versions,
            builder: (context, s) => Column(children: [
              for (final r in s.data ?? [])
                ListTile(
                  leading: Icon(r['status'] == 'adopted' || r['status'] == 'registered' ? Icons.verified_outlined : Icons.edit_document),
                  title: Text('${r['version_code']} · ${r['status']}'),
                  subtitle: Text([
                    if (r['adoption_act'] != null) 'Adopción ${r['adoption_act']}',
                    if (r['convalidation_act'] != null) 'Convalidación ${r['convalidation_act']}',
                    if (r['rusd_certificate'] != null) 'RUSD ${r['rusd_certificate']}',
                  ].join(' · ')),
                  trailing: IconButton(onPressed: _canAdminDocs ? () => _editVersion(r) : null, icon: const Icon(Icons.tune), tooltip: 'Estado y actos'),
                ),
            ]),
          ),
          const Divider(height: 28),
          Text('Entradas de retención', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          FutureBuilder<List<Map<String, Object?>>>(
            future: entries,
            builder: (context, s) {
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No hay entradas TRD configuradas.'));
              return Column(children: [
                for (final r in s.data!)
                  ListTile(
                    leading: const Icon(Icons.account_tree),
                    title: Text('${r['series_code']} · ${r['series_name']}${r['subseries_name'] == null ? '' : ' / ${r['subseries_code']} · ${r['subseries_name']}'}'),
                    subtitle: Text('${r['dependency_name'] ?? 'General'} · Gestión ${r['management_retention_years']} años · Central ${r['central_retention_years']} años · ${r['final_disposition']} · ${r['medium']}'),
                  ),
              ]);
            },
          ),
        ],
      );

  Future<void> _newVersion() async {
    final code = await _ask(context, 'Código / versión TRD');
    if (code == null || code.isEmpty || !mounted) return;
    final desc = await _ask(context, 'Descripción de la versión');
    await widget.service.createTrdVersion(code: code, description: desc);
    reload();
  }

  Future<void> _editVersion(Map<String, Object?> row) async {
    final status = await _chooseString(context, 'Estado de la TRD', const {
      'draft': 'Borrador', 'adopted': 'Adoptada', 'convalidated': 'Convalidada', 'registered': 'Registrada / vigente',
    });
    if (status == null || !mounted) return;
    String? adoptionAct;
    DateTime? adoptionDate;
    String? convalidationAct;
    DateTime? convalidationDate;
    String? rusd;
    if (status != 'draft') {
      adoptionAct = await _ask(context, 'Acto de adopción', initial: row['adoption_act']?.toString());
      if (!mounted) return;
      adoptionDate = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: DateTime.tryParse(row['adoption_date']?.toString() ?? '')?.toLocal() ?? DateTime.now());
    }
    if ((status == 'convalidated' || status == 'registered') && mounted) {
      convalidationAct = await _ask(context, 'Acto / certificado de convalidación', initial: row['convalidation_act']?.toString());
      if (!mounted) return;
      convalidationDate = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: DateTime.tryParse(row['convalidation_date']?.toString() ?? '')?.toLocal() ?? DateTime.now());
    }
    if (status == 'registered' && mounted) rusd = await _ask(context, 'Certificado / referencia RUSD', initial: row['rusd_certificate']?.toString());
    await widget.service.updateTrdVersion((row['id'] as num).toInt(), status: status, adoptionAct: adoptionAct, adoptionDate: adoptionDate, convalidationAct: convalidationAct, convalidationDate: convalidationDate, rusdCertificate: rusd);
    reload();
  }

  Future<void> _newEntry() async {
    final versionRows = await widget.service.trdVersions();
    final seriesRows = await widget.service.series();
    if (!mounted) return;
    final version = await _chooseRow(context, 'Versión TRD', versionRows, title: (r) => '${r['version_code']} · ${r['status']}');
    if (version == null || !mounted) return;
    final serie = await _chooseRow(context, 'Serie documental', seriesRows, title: (r) => '${r['code']} · ${r['name']}');
    if (serie == null) return;
    final subRows = await widget.service.subseries((serie['id'] as num).toInt());
    Map<String, Object?>? subserie;
    if (subRows.isNotEmpty && mounted) subserie = await _chooseOptionalRow(context, 'Subserie (opcional)', subRows, title: (r) => '${r['code']} · ${r['name']}');
    final depRows = await widget.service.dependencies();
    Map<String, Object?>? dep;
    if (depRows.isNotEmpty && mounted) dep = await _chooseOptionalRow(context, 'Dependencia productora (opcional)', depRows, title: (r) => '${r['code']} · ${r['name']}');
    if (!mounted) return;
    final mg = int.tryParse(await _ask(context, 'Años en archivo de gestión') ?? '') ?? 0;
    if (!mounted) return;
    final central = int.tryParse(await _ask(context, 'Años en archivo central') ?? '') ?? 0;
    if (!mounted) return;
    final disposition = await _chooseString(context, 'Disposición final', const {
      'total_conservation': 'Conservación total', 'selection': 'Selección', 'elimination': 'Eliminación', 'reproduction': 'Reproducción / medio técnico',
    });
    if (disposition == null || !mounted) return;
    final medium = await _chooseString(context, 'Soporte', const {'electronic': 'Electrónico', 'physical': 'Físico', 'mixed': 'Mixto'}) ?? 'mixed';
    final procedure = mounted ? await _ask(context, 'Procedimiento / observaciones') : null;
    await widget.service.saveTrdEntry(
      versionId: (version['id'] as num).toInt(),
      seriesId: (serie['id'] as num).toInt(),
      subseriesId: subserie == null ? null : (subserie['id'] as num).toInt(),
      dependencyId: dep == null ? null : (dep['id'] as num).toInt(),
      managementYears: mg,
      centralYears: central,
      finalDisposition: disposition,
      medium: medium,
      procedure: procedure,
    );
    reload();
  }
}

class _TvdView extends StatefulWidget {
  const _TvdView({required this.service});
  final DocumentManagementService service;
  @override
  State<_TvdView> createState() => _TvdViewState();
}

class _TvdViewState extends State<_TvdView> {
  Future<List<Map<String, Object?>>>? versions;
  Future<List<Map<String, Object?>>>? entries;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() { versions = widget.service.tvdVersions(); entries = widget.service.tvdEntries(); });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Expanded(child: Text('Tablas de Valoración Documental', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            TextButton.icon(onPressed: _canAdminDocs ? _newEntry : null, icon: const Icon(Icons.playlist_add), label: const Text('Entrada TVD')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: _canAdminDocs ? _newVersion : null, icon: const Icon(Icons.add), label: const Text('Versión TVD')),
          ]),
          FutureBuilder<List<Map<String, Object?>>>(
            future: versions,
            builder: (context, s) => Column(children: [
              for (final r in s.data ?? [])
                ListTile(
                  leading: const Icon(Icons.history_edu),
                  title: Text('${r['version_code']} · ${r['status']}'),
                  subtitle: Text('${r['adoption_act'] ?? ''}${r['convalidation_act'] == null ? '' : ' · ${r['convalidation_act']}'}${r['rusd_certificate'] == null ? '' : ' · RUSD ${r['rusd_certificate']}'}'),
                  trailing: IconButton(tooltip: 'Editar versión', onPressed: _canAdminDocs ? () => _editVersion(r) : null, icon: const Icon(Icons.tune)),
                ),
            ]),
          ),
          const Divider(height: 28),
          FutureBuilder<List<Map<String, Object?>>>(
            future: entries,
            builder: (context, s) {
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No hay entradas TVD configuradas.'));
              return Column(children: [for (final r in s.data!) ListTile(leading: const Icon(Icons.history_edu), title: Text('${r['series_name']}${r['subseries_name'] == null ? '' : ' / ${r['subseries_name']}'}'), subtitle: Text('${r['source_office'] ?? ''} · ${r['start_year'] ?? ''}-${r['end_year'] ?? ''} · Central ${r['central_retention_years']} años · ${r['final_disposition']}'))]);
            },
          ),
        ],
      );

  Future<void> _newVersion() async {
    final code = await _ask(context, 'Código / versión TVD');
    if (code == null || code.isEmpty) return;
    await widget.service.createTvdVersion(code: code);
    reload();
  }

  Future<void> _editVersion(Map<String, Object?> row) async {
    final status = await _chooseString(context, 'Estado de la TVD', const {'draft': 'Borrador', 'adopted': 'Adoptada', 'convalidated': 'Convalidada', 'registered': 'Registrada / vigente'});
    if (status == null || !mounted) return;
    String? act;
    DateTime? actDate;
    String? convalidation;
    DateTime? convalidationDate;
    String? rusd;
    if (status != 'draft') {
      act = await _ask(context, 'Acto de adopción', initial: row['adoption_act']?.toString());
      if (!mounted) return;
      actDate = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: DateTime.now());
    }
    if ((status == 'convalidated' || status == 'registered') && mounted) {
      convalidation = await _ask(context, 'Acto / certificado de convalidación', initial: row['convalidation_act']?.toString());
      if (!mounted) return;
      convalidationDate = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime(2100), initialDate: DateTime.now());
    }
    if (status == 'registered' && mounted) rusd = await _ask(context, 'Certificado / referencia RUSD', initial: row['rusd_certificate']?.toString());
    await widget.service.updateTvdVersion((row['id'] as num).toInt(), status: status, adoptionAct: act, adoptionDate: actDate, convalidationAct: convalidation, convalidationDate: convalidationDate, rusdCertificate: rusd);
    reload();
  }

  Future<void> _newEntry() async {
    final versionsRows = await widget.service.tvdVersions();
    if (!mounted) return;
    final version = await _chooseRow(context, 'Versión TVD', versionsRows, title: (r) => '${r['version_code']} · ${r['status']}');
    if (version == null || !mounted) return;
    final names = await _twoFields(context, 'Serie a valorar', 'Serie', 'Subserie (opcional)');
    if (names == null || names.$1.isEmpty || !mounted) return;
    final office = await _ask(context, 'Oficina / dependencia productora');
    if (!mounted) return;
    final start = int.tryParse(await _ask(context, 'Año inicial') ?? '');
    if (!mounted) return;
    final end = int.tryParse(await _ask(context, 'Año final') ?? '');
    if (!mounted) return;
    final years = int.tryParse(await _ask(context, 'Años de retención en archivo central') ?? '') ?? 0;
    if (!mounted) return;
    final disposition = await _chooseString(context, 'Disposición final', const {'total_conservation': 'Conservación total', 'selection': 'Selección', 'elimination': 'Eliminación', 'reproduction': 'Reproducción / medio técnico'});
    if (disposition == null) return;
    final procedure = mounted ? await _ask(context, 'Procedimiento / observaciones') : null;
    await widget.service.saveTvdEntry(versionId: (version['id'] as num).toInt(), seriesName: names.$1, subseriesName: names.$2.isEmpty ? null : names.$2, sourceOffice: office, startYear: start, endYear: end, centralRetentionYears: years, finalDisposition: disposition, procedure: procedure);
    reload();
  }
}

class _ClassificationView extends StatefulWidget {
  const _ClassificationView({required this.service});
  final DocumentManagementService service;
  @override
  State<_ClassificationView> createState() => _ClassificationViewState();
}

class _ClassificationViewState extends State<_ClassificationView> {
  Future<List<Map<String, Object?>>>? deps;
  Future<List<Map<String, Object?>>>? series;
  Future<List<Map<String, Object?>>>? types;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() { deps = widget.service.dependencies(); series = widget.service.series(); types = widget.service.documentTypes(); });

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: _canAdminDocs ? _dep : null, icon: const Icon(Icons.add_business), label: const Text('Dependencia')),
            TextButton.icon(onPressed: _canAdminDocs ? _subseries : null, icon: const Icon(Icons.account_tree), label: const Text('Subserie')),
            TextButton.icon(onPressed: _canAdminDocs ? _type : null, icon: const Icon(Icons.description_outlined), label: const Text('Tipo documental')),
            FilledButton.icon(onPressed: _canAdminDocs ? _series : null, icon: const Icon(Icons.add), label: const Text('Serie')),
          ]),
          const SizedBox(height: 12),
          Text('Dependencias', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, Object?>>>(future: deps, builder: (context, s) => Wrap(spacing: 8, runSpacing: 8, children: [for (final r in s.data ?? []) Chip(label: Text('${r['code']} · ${r['name']}'))])),
          const Divider(),
          Text('Series', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, Object?>>>(future: series, builder: (context, s) => Column(children: [for (final r in s.data ?? []) ListTile(leading: const Icon(Icons.account_tree_outlined), title: Text('${r['code']} · ${r['name']}'), subtitle: Text('Dependencia ${r['dependency_id'] ?? 'general'}'))])),
          const Divider(),
          Text('Tipos documentales', style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder<List<Map<String, Object?>>>(future: types, builder: (context, s) => Wrap(spacing: 8, runSpacing: 8, children: [for (final r in s.data ?? []) Chip(label: Text('${r['code'] ?? ''}${r['code'] == null ? '' : ' · '}${r['name']}'))])),
        ],
      );

  Future<void> _dep() async {
    final val = await _twoFields(context, 'Nueva dependencia', 'Código', 'Nombre');
    if (val == null || val.$1.isEmpty || val.$2.isEmpty) return;
    await widget.service.createDependency(code: val.$1, name: val.$2);
    reload();
  }

  Future<void> _series() async {
    final val = await _twoFields(context, 'Nueva serie', 'Código', 'Nombre');
    if (val == null || val.$1.isEmpty || val.$2.isEmpty) return;
    final depRows = await widget.service.dependencies();
    if (!mounted) return;
    final dep = await _chooseOptionalRow(context, 'Dependencia productora (opcional)', depRows, title: (r) => '${r['code']} · ${r['name']}');
    await widget.service.createSeries(code: val.$1, name: val.$2, dependencyId: dep == null ? null : (dep['id'] as num).toInt());
    reload();
  }

  Future<void> _subseries() async {
    final seriesRows = await widget.service.series();
    if (!mounted) return;
    final serie = await _chooseRow(context, 'Serie principal', seriesRows, title: (r) => '${r['code']} · ${r['name']}');
    if (serie == null || !mounted) return;
    final val = await _twoFields(context, 'Nueva subserie', 'Código', 'Nombre');
    if (val == null || val.$1.isEmpty || val.$2.isEmpty) return;
    await widget.service.createSubseries(seriesId: (serie['id'] as num).toInt(), code: val.$1, name: val.$2);
    reload();
  }

  Future<void> _type() async {
    final val = await _twoFields(context, 'Nuevo tipo documental', 'Código (opcional)', 'Nombre');
    if (val == null || val.$2.isEmpty) return;
    final desc = mounted ? await _ask(context, 'Descripción / alcance') : null;
    await widget.service.createDocumentType(name: val.$2, code: val.$1.isEmpty ? null : val.$1, description: desc);
    reload();
  }
}


class _InstrumentsTab extends StatefulWidget {
  const _InstrumentsTab();
  @override
  State<_InstrumentsTab> createState() => _InstrumentsTabState();
}

class _InstrumentsTabState extends State<_InstrumentsTab> {
  final service = DocumentManagementService.instance;
  Future<List<Map<String, Object?>>>? future;
  @override
  void initState() { super.initState(); reload(); }
  void reload() => setState(() => future = service.instruments());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
        future: future,
        builder: (context, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'La entidad parametriza sus instrumentos archivísticos, versión, estado, acto y fecha de adopción, responsable y soporte. MerkaERP conserva la evidencia y trazabilidad sin sustituir la aprobación institucional.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final r in s.data!)
                ListTile(
                  leading: Icon(r['status'] == 'adopted' || r['status'] == 'current' ? Icons.verified : Icons.pending_actions),
                  title: Text(r['name']?.toString() ?? ''),
                  subtitle: Text([
                    r['status']?.toString() ?? 'pending',
                    r['version_code']?.toString() ?? 'sin versión',
                    if (r['adoption_act'] != null) r['adoption_act'].toString(),
                    if (r['adoption_date'] != null) _date(r['adoption_date']),
                    if (r['responsible_dependency'] != null) r['responsible_dependency'].toString(),
                  ].join(' · ')),
                  trailing: Wrap(children: [
                    IconButton(onPressed: _canAdminDocs ? () => _attach(r) : null, icon: const Icon(Icons.attach_file), tooltip: 'Adjuntar instrumento'),
                    IconButton(onPressed: _canAdminDocs ? () => _edit(r) : null, icon: const Icon(Icons.edit), tooltip: 'Parametrizar'),
                  ]),
                ),
            ],
          );
        },
      );

  Future<void> _attach(Map<String, Object?> r) async {
    final pick = await FilePicker.platform.pickFiles();
    final path = pick?.files.single.path;
    if (path == null) return;
    await service.attachInstrumentFile((r['id'] as num).toInt(), path);
    reload();
  }

  Future<void> _edit(Map<String, Object?> r) async {
    final status = await _chooseString(context, 'Estado del instrumento', const {
      'pending': 'Pendiente', 'draft': 'Borrador', 'adopted': 'Adoptado', 'current': 'Vigente', 'obsolete': 'Histórico / sustituido',
    });
    if (status == null || !mounted) return;
    final version = await _ask(context, 'Versión / código del instrumento', initial: r['version_code']?.toString());
    if (version == null || !mounted) return;
    String? act;
    DateTime? date;
    if (status == 'adopted' || status == 'current' || status == 'obsolete') {
      act = await _ask(context, 'Acto de adopción / actualización', initial: r['adoption_act']?.toString());
      if (!mounted) return;
      date = await showDatePicker(
        context: context,
        firstDate: DateTime(1950),
        lastDate: DateTime(2100),
        initialDate: DateTime.tryParse(r['adoption_date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
    }
    if (!mounted) return;
    final responsible = await _ask(context, 'Dependencia responsable', initial: r['responsible_dependency']?.toString());
    if (!mounted) return;
    final notes = await _ask(context, 'Observaciones / alcance', initial: r['notes']?.toString());
    await service.updateInstrument(
      id: (r['id'] as num).toInt(),
      status: status,
      versionCode: version,
      adoptionAct: act,
      adoptionDate: date,
      responsibleDependency: responsible,
      notes: notes,
    );
    reload();
  }
}


class _DocumentActions extends StatelessWidget {
  const _DocumentActions({required this.doc, required this.service});
  final Map<String, Object?> doc;
  final DocumentManagementService service;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones del documento',
      onSelected: (value) => _run(context, value),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'verify', child: Text('Verificar integridad')),
        const PopupMenuItem(value: 'request_signature', child: Text('Solicitar firma / sello')),
        const PopupMenuItem(value: 'register_signature', child: Text('Registrar evidencia de firma')),
        if (doc['is_signed'] == 1)
          const PopupMenuItem(value: 'signature_info', child: Text('Ver evidencia de firma')),
      ],
    );
  }

  Future<void> _run(BuildContext context, String action) async {
    try {
      final id = doc['id']?.toString() ?? '';
      if (id.isEmpty) return;
      if (action == 'verify') {
        final ok = await service.verifyDocumentIntegrity(id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok ? 'Integridad SHA-256 verificada.' : 'ALERTA: la huella del archivo no coincide.'),
            backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      if (action == 'request_signature') {
        final signer = await _twoFields(context, 'Solicitar firma / sello', 'Identificación del firmante', 'Nombre del firmante');
        if (signer == null || signer.$2.isEmpty || !context.mounted) return;
        final purpose = await _ask(context, 'Finalidad / descripción de la firma');
        final result = await service.requestConfiguredSignature(
          documentId: id,
          signerIdentification: signer.$1,
          signerName: signer.$2,
          purpose: purpose,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result['message'] ?? 'Solicitud aceptada.'}${result['external_reference'] == null ? '' : ' Ref: ${result['external_reference']}'}')),
        );
        return;
      }
      if (action == 'register_signature') {
        final signer = await _twoFields(context, 'Evidencia de firma confirmada', 'Identificación del firmante', 'Nombre del firmante');
        if (signer == null || signer.$2.isEmpty || !context.mounted) return;
        final provider = await _ask(context, 'Proveedor / mecanismo de firma');
        if (provider == null || provider.isEmpty || !context.mounted) return;
        final reference = await _ask(context, 'Referencia externa / certificado / transacción');
        if (reference == null || reference.isEmpty) return;
        await service.registerSignatureEvidence(
          documentId: id,
          provider: provider,
          signerName: signer.$2,
          signerIdentification: signer.$1,
          externalReference: reference,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Evidencia registrada. El hash del original quedó congelado como firmado.')));
        return;
      }
      if (action == 'signature_info') {
        Map<String, Object?> metadata = {};
        try {
          final decoded = jsonDecode(doc['signature_metadata_json']?.toString() ?? '{}');
          if (decoded is Map) metadata = decoded.map((k, v) => MapEntry(k.toString(), v));
        } catch (_) {}
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Evidencia de firma'),
            content: SelectableText([
              'Proveedor: ${doc['signature_provider'] ?? metadata['provider'] ?? '—'}',
              'Firmante: ${metadata['signer_name'] ?? '—'}',
              'Identificación: ${metadata['signer_identification'] ?? '—'}',
              'Referencia: ${metadata['external_reference'] ?? '—'}',
              'Sello de tiempo: ${metadata['timestamp_reference'] ?? '—'}',
              'Fecha: ${metadata['signed_at'] ?? '—'}',
              'SHA-256 firmado: ${metadata['signed_sha256'] ?? doc['sha256'] ?? '—'}',
            ].join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cerrar'))],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }
}


class _DocumentSettingsTab extends StatefulWidget{const _DocumentSettingsTab();@override State<_DocumentSettingsTab>createState()=>_DocumentSettingsTabState();}
class _DocumentSettingsTabState extends State<_DocumentSettingsTab>{final service=DocumentManagementService.instance;Future<Map<String,String>>?future;@override void initState(){super.initState();reload();}void reload()=>setState(()=>future=service.settings());@override Widget build(BuildContext context)=>FutureBuilder<Map<String,String>>(future:future,builder:(context,s){if(!s.hasData)return const Center(child:CircularProgressIndicator());final data=s.data!;return ListView(padding:const EdgeInsets.all(18),children:[Text('Parametrización institucional',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('La organización define consecutivos, calendario, términos y políticas sin modificar el código del ERP.'),const SizedBox(height:18),for(final item in [('incoming_pattern','Radicados recibidos'),('outgoing_pattern','Radicados enviados'),('internal_pattern','Radicados internos'),('case_pattern','Expedientes'),('transfer_pattern','Transferencias'),('work_weekdays','Días hábiles (1=lunes ... 7=domingo)')])Card(child:ListTile(title:Text(item.$2),subtitle:Text(data[item.$1]??''),trailing:IconButton(tooltip:'Editar parámetro',onPressed:_canAdminDocs?()async{final value=await _ask(context,item.$2,initial:data[item.$1]);if(value==null)return;await service.saveSetting(item.$1,value);reload();}:null,icon:const Icon(Icons.edit)))),const SizedBox(height:18),Row(children:[Expanded(child:Text('Días no hábiles adicionales',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold))),FilledButton.icon(onPressed:_canAdminDocs?()async{final date=await showDatePicker(context:context,firstDate:DateTime(2000),lastDate:DateTime(2100),initialDate:DateTime.now());if(date==null)return;await service.addNonWorkingDay(date);setState((){});}:null,icon:const Icon(Icons.event_busy),label:const Text('Agregar'))]),FutureBuilder<List<Map<String,Object?>>>(future:service.nonWorkingDays(),builder:(context,h)=>Wrap(spacing:8,children:[for(final r in h.data??[])Chip(label:Text('${r['day']}${r['description']==null?'':' · ${r['description']}'}'))]))]);});}

Future<String?> _chooseString(
  BuildContext context,
  String dialogTitle,
  Map<String, String> options,
) => showDialog<String>(
  context: context,
  builder: (_) => SimpleDialog(
    title: Text(dialogTitle),
    children: [
      for (final entry in options.entries)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, entry.key),
          child: Text(entry.value),
        ),
    ],
  ),
);

Future<Map<String, Object?>?> _chooseOptionalRow(
  BuildContext context,
  String dialogTitle,
  List<Map<String, Object?>> rows, {
  required String Function(Map<String, Object?> row) title,
  String Function(Map<String, Object?> row)? subtitle,
}) => showDialog<Map<String, Object?>>(
  context: context,
  builder: (_) => AlertDialog(
    title: Text(dialogTitle),
    content: SizedBox(
      width: 620,
      height: 420,
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.not_interested),
            title: const Text('Sin asignar / no aplica'),
            onTap: () => Navigator.pop(context),
          ),
          const Divider(),
          for (final row in rows)
            ListTile(
              title: Text(title(row)),
              subtitle: subtitle == null ? null : Text(subtitle(row)),
              onTap: () => Navigator.pop(context, row),
            ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
  ),
);

Future<Map<String, Object?>?> _chooseRow(
  BuildContext context,
  String dialogTitle,
  List<Map<String, Object?>> rows, {
  required String Function(Map<String, Object?> row) title,
  String Function(Map<String, Object?> row)? subtitle,
}) async {
  if (rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay registros disponibles para seleccionar.')),
    );
    return null;
  }
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(dialogTitle),
      content: SizedBox(
        width: 620,
        height: 420,
        child: ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            return ListTile(
              title: Text(title(row)),
              subtitle: subtitle == null ? null : Text(subtitle(row)),
              onTap: () => Navigator.pop(context, row),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    ),
  );
}

String _dispositionLabel(String? value) => switch (value) {
  'total_conservation' => 'Conservación total',
  'selection' => 'Selección',
  'elimination' => 'Eliminación',
  'reproduction' => 'Reproducción / medio técnico',
  _ => value ?? '',
};

String? _required(String? value)=>(value??'').trim().isEmpty?'Campo obligatorio':null;
IconData _directionIcon(String? direction)=>switch(direction){'incoming'=>Icons.call_received,'outgoing'=>Icons.call_made,'internal'=>Icons.swap_horiz,_=>Icons.description};
String _statusLabel(String? status)=>switch(status){'registered'=>'Radicado','assigned'=>'Asignado','in_progress'=>'En trámite','for_signature'=>'Para firma','responded'=>'Respondido','closed'=>'Cerrado','archived'=>'Archivado','cancelled'=>'Anulado',_=>status??''};
bool _isOverdue(Map<String,Object?> row){final due=DateTime.tryParse(row['due_at']?.toString()??'');return due!=null&&due.isBefore(DateTime.now().toUtc())&&!{'closed','archived','cancelled'}.contains(row['status']);}
String _date(Object? value){final d=DateTime.tryParse(value?.toString()??'')?.toLocal();if(d==null)return value?.toString()??'';return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}
String _shortHash(Object? value){final s=value?.toString()??'';return s.length>16?'${s.substring(0,8)}…${s.substring(s.length-8)}':s;}
String _fieldLabel(String k)=>switch(k){'building'=>'Edificio / sede','room'=>'Depósito / sala','shelf'=>'Estante','body'=>'Cuerpo','tray'=>'Bandeja','box'=>'Caja','folder'=>'Carpeta','label'=>'Etiqueta',_=>k};
void _error(BuildContext context,Object error)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(error.toString().replaceFirst('Exception: ','')),backgroundColor:Theme.of(context).colorScheme.error));
Future<String?> _ask(BuildContext context,String title,{String? initial})async{final c=TextEditingController(text:initial??'');return showDialog<String>(context:context,builder:(_)=>AlertDialog(title:Text(title),content:TextField(controller:c,autofocus:true,maxLines:title.toLowerCase().contains('motivo')?3:1),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,c.text.trim()),child:const Text('Aceptar'))]));}
Future<(String,String)?> _twoFields(BuildContext context,String title,String a,String b)async{final c1=TextEditingController(),c2=TextEditingController();return showDialog<(String,String)>(context:context,builder:(_)=>AlertDialog(title:Text(title),content:SizedBox(width:420,child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:c1,decoration:InputDecoration(labelText:a)),TextField(controller:c2,decoration:InputDecoration(labelText:b))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(context,(c1.text.trim(),c2.text.trim())),child:const Text('Guardar'))]));}
