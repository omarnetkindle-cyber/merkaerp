import 'package:flutter/material.dart';

import '../../core/commands/command_registry.dart';
import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../numeric_input.dart';
import '../../ui/merka_theme_tokens.dart';
import '../application/crm_account_service.dart';
import '../application/crm_opportunity_service.dart';
import '../domain/crm_account.dart';
import '../domain/crm_opportunity.dart';
import 'crm_account_page.dart';
import 'crm_opportunity_page.dart';

class CrmPipelinePage extends StatefulWidget {
  const CrmPipelinePage({super.key, this.service});

  final CrmOpportunityService? service;

  @override
  State<CrmPipelinePage> createState() => _CrmPipelinePageState();
}

class _CrmPipelinePageState extends State<CrmPipelinePage> {
  late final CrmOpportunityService _service;
  late Future<List<CrmOpportunity>> _opportunities;
  late final String _commandOwner;
  int? _assignedUserFilter;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? CrmOpportunityService();
    _commandOwner = 'crm.pipeline:${identityHashCode(this)}';
    _reload();
  }

  @override
  void dispose() {
    CommandRegistry.instance.clearContext(_commandOwner);
    super.dispose();
  }

  void _reload() {
    _opportunities = _service.list();
  }

  Future<void> _move(CrmOpportunity opportunity, CrmSalesStage stage) async {
    try {
      await _service.moveToStage(opportunity.id, stage);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo mover la oportunidad: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM - Pipeline'),
        actions: [
          FutureBuilder<List<CrmOpportunity>>(
            future: _opportunities,
            builder: (context, snapshot) {
              final users =
                  (snapshot.data ?? const <CrmOpportunity>[])
                      .map((item) => item.assignedUserId)
                      .whereType<int>()
                      .toSet()
                      .toList()
                    ..sort();
              return DropdownButtonHideUnderline(
                child: DropdownButton<int?>(
                  value: _assignedUserFilter,
                  hint: const Text('Vendedor'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...users.map(
                      (userId) => DropdownMenuItem<int?>(
                        value: userId,
                        child: Text('Usuario $userId'),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _assignedUserFilter = value),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Actualizar pipeline',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reload),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nueva oportunidad'),
        onPressed: () => _openNewOpportunity(context),
      ),
      body: FutureBuilder<List<CrmOpportunity>>(
        future: _opportunities,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('No se pudo cargar el pipeline: ${snapshot.error}'),
            );
          }
          final opportunities = (snapshot.data ?? const <CrmOpportunity>[])
              .where(
                (item) =>
                    _assignedUserFilter == null ||
                    item.assignedUserId == _assignedUserFilter,
              )
              .toList();
          return _PipelineBoard(
            opportunities: opportunities,
            onMove: _move,
            onSelectOpportunity: (opportunity) =>
                _activateOpportunityContext(context, opportunity),
            onOpenOpportunity: (opportunity) => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CrmOpportunityPage(opportunity: opportunity),
              ),
            ),
            onOpenAccount: (id) => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CrmAccountPage(accountId: id)),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openNewOpportunity(BuildContext context) async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(db, companyId: companyId);
    final accounts = await CrmAccountService().list();
    if (!context.mounted) return;
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea al menos una cuenta CRM antes de añadir oportunidades.'),
          backgroundColor: MerkaThemeTokens.warning,
        ),
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NewOpportunityDialog(
        companyId: companyId,
        accounts: accounts,
        currency: currency,
        service: _service,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  void _activateOpportunityContext(
    BuildContext context,
    CrmOpportunity opportunity,
  ) {
    final stages = CrmSalesStage.values;
    final currentIndex = stages.indexOf(opportunity.salesStage);
    final nextStage = currentIndex >= 0 && currentIndex < stages.length - 2
        ? stages[currentIndex + 1]
        : null;
    final actions = <String, CommandHandler>{};
    if (nextStage != null) {
      actions['advance'] = (commandContext, _) => _move(opportunity, nextStage);
    }
    CommandRegistry.instance.setContext(
      CommandContext(
        moduleId: 'crm_pipeline',
        recordType: 'crm_opportunity',
        recordId: opportunity.id,
        label: opportunity.name,
        ownerId: _commandOwner,
        actions: actions,
      ),
    );
  }
}

class _PipelineBoard extends StatefulWidget {
  const _PipelineBoard({
    required this.opportunities,
    required this.onMove,
    required this.onSelectOpportunity,
    required this.onOpenOpportunity,
    required this.onOpenAccount,
  });

  final List<CrmOpportunity> opportunities;
  final Future<void> Function(CrmOpportunity, CrmSalesStage) onMove;
  final ValueChanged<CrmOpportunity> onSelectOpportunity;
  final ValueChanged<CrmOpportunity> onOpenOpportunity;
  final ValueChanged<int> onOpenAccount;

  @override
  State<_PipelineBoard> createState() => _PipelineBoardState();
}

class _PipelineBoardState extends State<_PipelineBoard> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _stageTitle(CrmSalesStage stage) {
    switch (stage) {
      case CrmSalesStage.prospecting:
        return 'Prospecting';
      case CrmSalesStage.qualification:
        return 'Qualification';
      case CrmSalesStage.needsAnalysis:
        return 'Needs Analysis';
      case CrmSalesStage.valueProposition:
        return 'Value Proposition';
      case CrmSalesStage.negotiationReview:
        return 'Negotiation / Review';
      case CrmSalesStage.closedWon:
        return 'Closed Won';
      case CrmSalesStage.closedLost:
        return 'Closed Lost';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 1500 ? 220.0 : 260.0;
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: CrmSalesStage.values.map((stage) {
                final items = widget.opportunities
                    .where((opportunity) => opportunity.salesStage == stage)
                    .toList();
                return SizedBox(
                  width: width,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _StageColumn(
                      title: _stageTitle(stage),
                      probability: stage.probability,
                      stage: stage,
                      opportunities: items,
                      onMove: widget.onMove,
                      onSelectOpportunity: widget.onSelectOpportunity,
                      onOpenOpportunity: widget.onOpenOpportunity,
                      onOpenAccount: widget.onOpenAccount,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.title,
    required this.probability,
    required this.stage,
    required this.opportunities,
    required this.onMove,
    required this.onSelectOpportunity,
    required this.onOpenOpportunity,
    required this.onOpenAccount,
  });

  final String title;
  final int probability;
  final CrmSalesStage stage;
  final List<CrmOpportunity> opportunities;
  final Future<void> Function(CrmOpportunity, CrmSalesStage) onMove;
  final ValueChanged<CrmOpportunity> onSelectOpportunity;
  final ValueChanged<CrmOpportunity> onOpenOpportunity;
  final ValueChanged<int> onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return DragTarget<CrmOpportunity>(
      onWillAcceptWithDetails: (details) => details.data.salesStage != stage,
      onAcceptWithDetails: (details) => onMove(details.data, stage),
      builder: (context, candidates, rejected) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text('$probability% probability'),
                const SizedBox(height: 8),
                if (opportunities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Text('Suelta aqui una oportunidad'),
                  )
                else
                  ...opportunities.map(
                    (opportunity) => Draggable<CrmOpportunity>(
                      data: opportunity,
                      feedback: Material(
                        elevation: 4,
                        child: SizedBox(
                          width: 220,
                          child: ListTile(title: Text(opportunity.name)),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: .35,
                        child: _OpportunityCard(
                          opportunity: opportunity,
                          onSelectOpportunity: onSelectOpportunity,
                          onOpenOpportunity: onOpenOpportunity,
                          onOpenAccount: onOpenAccount,
                        ),
                      ),
                      child: _OpportunityCard(
                        opportunity: opportunity,
                        onSelectOpportunity: onSelectOpportunity,
                        onOpenOpportunity: onOpenOpportunity,
                        onOpenAccount: onOpenAccount,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OpportunityCard extends StatelessWidget {
  const _OpportunityCard({
    required this.opportunity,
    required this.onSelectOpportunity,
    required this.onOpenOpportunity,
    required this.onOpenAccount,
  });

  final CrmOpportunity opportunity;
  final ValueChanged<CrmOpportunity> onSelectOpportunity;
  final ValueChanged<CrmOpportunity> onOpenOpportunity;
  final ValueChanged<int> onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          onSelectOpportunity(opportunity);
          onOpenOpportunity(opportunity);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                opportunity.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(opportunity.accountName),
              Text(opportunity.amount.format()),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: opportunity.effectiveProbability / 100,
              ),
              Text('${opportunity.effectiveProbability}% probable'),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo: nueva oportunidad
// ─────────────────────────────────────────────────────────────────────────────
class _NewOpportunityDialog extends StatefulWidget {
  const _NewOpportunityDialog({
    required this.companyId,
    required this.accounts,
    required this.currency,
    required this.service,
  });

  final int companyId;
  final List<CrmAccount> accounts;
  final Currency currency;
  final CrmOpportunityService service;

  @override
  State<_NewOpportunityDialog> createState() => _NewOpportunityDialogState();
}

class _NewOpportunityDialogState extends State<_NewOpportunityDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '0');
  late int _accountId;
  late String _accountName;
  CrmSalesStage _stage = CrmSalesStage.prospecting;
  DateTime _followUp = DateTime.now().add(const Duration(days: 7));
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountId = widget.accounts.first.id!;
    _accountName = widget.accounts.first.name;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String _stageName(CrmSalesStage s) => switch (s) {
        CrmSalesStage.prospecting => 'Prospecting',
        CrmSalesStage.qualification => 'Qualification',
        CrmSalesStage.needsAnalysis => 'Needs Analysis',
        CrmSalesStage.valueProposition => 'Value Proposition',
        CrmSalesStage.negotiationReview => 'Negotiation / Review',
        CrmSalesStage.closedWon => 'Closed Won',
        CrmSalesStage.closedLost => 'Closed Lost',
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva oportunidad'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nombre
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la oportunidad *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              // Cuenta
              DropdownButtonFormField<int>(
                value: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cuenta CRM *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child:
                              Text(a.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final a = widget.accounts.firstWhere((a) => a.id == v);
                  setState(() {
                    _accountId = v;
                    _accountName = a.name;
                  });
                },
              ),
              const SizedBox(height: 10),
              // Monto
              TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumericInput.decimal],
                decoration: InputDecoration(
                  labelText: 'Monto estimado (${widget.currency.code})',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              // Etapa
              DropdownButtonFormField<CrmSalesStage>(
                value: _stage,
                decoration: const InputDecoration(
                  labelText: 'Etapa inicial',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: CrmSalesStage.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_stageName(s)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _stage = v);
                },
              ),
              const SizedBox(height: 10),
              // Seguimiento
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _followUp,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2035),
                  );
                  if (d != null) setState(() => _followUp = d);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Próximo seguimiento',
                    border: OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                    '${_followUp.day.toString().padLeft(2, '0')}/'
                    '${_followUp.month.toString().padLeft(2, '0')}/'
                    '${_followUp.year}',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: MerkaThemeTokens.danger, fontSize: 12)),
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
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Crear'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amountStr = _amountCtrl.text.trim().replaceAll(',', '.');
      final amount = MoneyValue.fromMajorUnits(
        amountStr.isEmpty ? '0' : amountStr,
        currency: widget.currency,
      );
      final id = 'CRM-${DateTime.now().microsecondsSinceEpoch}';
      await widget.service.create(
        CrmOpportunity(
          id: id,
          companyId: widget.companyId,
          accountId: _accountId,
          accountName: _accountName,
          name: _nameCtrl.text.trim(),
          amount: amount,
          salesStage: _stage,
          nextFollowUpAt: _followUp,
        ),
      );
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
