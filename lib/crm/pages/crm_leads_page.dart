// lib/crm/pages/crm_leads_page.dart
//
// Módulo de Leads CRM: alta, calificación y conversión a oportunidad.
// Reutiliza CrmLeadService, CrmAccountService, CrmContactService,
// CrmOpportunityService (todos ya implementados).

import 'package:flutter/material.dart';

import '../../core/currency/currency.dart';
import '../../core/currency/money_currency_resolver.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../../numeric_input.dart';
import '../../ui/merka_theme_tokens.dart';
import '../application/crm_account_service.dart';
import '../application/crm_contact_service.dart';
import '../application/crm_lead_service.dart';
import '../application/crm_opportunity_service.dart';
import '../domain/crm_account.dart';
import '../domain/crm_contact.dart';
import '../domain/crm_lead.dart';
import '../domain/crm_opportunity.dart';

class CrmLeadsPage extends StatefulWidget {
  const CrmLeadsPage({super.key});

  @override
  State<CrmLeadsPage> createState() => _CrmLeadsPageState();
}

class _CrmLeadsPageState extends State<CrmLeadsPage> {
  final _service = CrmLeadService();
  late Future<_LeadsData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_LeadsData> _load() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency =
        await MoneyCurrencyResolver.resolve(db, companyId: companyId);
    final leads = await _service.list();
    return _LeadsData(
        companyId: companyId, currency: currency, leads: leads);
  }

  void _reload() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM — Leads'),
        actions: [
          IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _reload),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nuevo lead'),
        onPressed: () => _openNewLead(context),
      ),
      body: FutureBuilder<_LeadsData>(
        future: _data,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final data = snapshot.data!;
          final leads = data.leads;
          if (leads.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search,
                      size: 56, color: MerkaThemeTokens.graphite600),
                  const SizedBox(height: 12),
                  const Text('Sin leads registrados'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Crear el primer lead'),
                    onPressed: () => _openNewLead(context),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: leads.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) =>
                _leadTile(context, leads[i], data),
          );
        },
      ),
    );
  }

  Widget _leadTile(
      BuildContext context, CrmLead lead, _LeadsData data) {
    final converted = lead.converted;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: converted
            ? MerkaThemeTokens.success
            : _statusColor(lead.status),
        child: Icon(
          converted ? Icons.check : Icons.person_pin_outlined,
          color: Colors.white,
          size: 20,
        ),
      ),
      title: Text(
        lead.accountName ?? 'Sin nombre',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          lead.status,
          lead.leadSource,
          lead.opportunityAmount.format(),
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
      ),
      trailing: converted
          ? const Chip(label: Text('Convertido'))
          : TextButton(
              child: const Text('Convertir'),
              onPressed: () => _openConvert(context, lead, data),
            ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'nuevo' => MerkaThemeTokens.navy700,
        'contactado' => MerkaThemeTokens.gold500,
        'calificado' => MerkaThemeTokens.success,
        'descartado' || 'rechazado' => MerkaThemeTokens.danger,
        _ => MerkaThemeTokens.graphite600,
      };

  Future<void> _openNewLead(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _NewLeadDialog(service: _service),
    );
    if (saved == true) _reload();
  }

  Future<void> _openConvert(
      BuildContext context, CrmLead lead, _LeadsData data) async {
    final converted = await showDialog<bool>(
      context: context,
      builder: (_) => _ConvertLeadDialog(
        lead: lead,
        companyId: data.companyId,
        currency: data.currency,
        leadService: _service,
        accountService: CrmAccountService(),
        contactService: CrmContactService(),
        opportunityService: CrmOpportunityService(),
      ),
    );
    if (converted == true) _reload();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo nuevo lead
// ─────────────────────────────────────────────────────────────────────────────
class _NewLeadDialog extends StatefulWidget {
  const _NewLeadDialog({required this.service});

  final CrmLeadService service;

  @override
  State<_NewLeadDialog> createState() => _NewLeadDialogState();
}

class _NewLeadDialogState extends State<_NewLeadDialog> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '0');
  String _source = 'web';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo lead'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Empresa / nombre *',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [NumericInput.decimal],
              decoration: const InputDecoration(
                  labelText: 'Monto estimado',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _source,
              decoration: const InputDecoration(
                  labelText: 'Fuente',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(value: 'web', child: Text('Web')),
                DropdownMenuItem(value: 'referido', child: Text('Referido')),
                DropdownMenuItem(value: 'llamada', child: Text('Llamada')),
                DropdownMenuItem(value: 'evento', child: Text('Evento')),
                DropdownMenuItem(value: 'otro', child: Text('Otro')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _source = v);
              },
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
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
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
      final db = await DatabaseHelper.instance.database;
      final companyId =
          await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final currency =
          await MoneyCurrencyResolver.resolve(db, companyId: companyId);
      final amountStr =
          _amountCtrl.text.trim().replaceAll(',', '.').isEmpty
              ? '0'
              : _amountCtrl.text.trim().replaceAll(',', '.');
      await widget.service.create(
        CrmLead(
          companyId: companyId,
          accountName: _nameCtrl.text.trim(),
          leadSource: _source,
          opportunityAmount:
              MoneyValue.fromMajorUnits(amountStr, currency: currency),
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

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo conversión de lead → cuenta + contacto + oportunidad
// ─────────────────────────────────────────────────────────────────────────────
class _ConvertLeadDialog extends StatefulWidget {
  const _ConvertLeadDialog({
    required this.lead,
    required this.companyId,
    required this.currency,
    required this.leadService,
    required this.accountService,
    required this.contactService,
    required this.opportunityService,
  });

  final CrmLead lead;
  final int companyId;
  final Currency currency;
  final CrmLeadService leadService;
  final CrmAccountService accountService;
  final CrmContactService contactService;
  final CrmOpportunityService opportunityService;

  @override
  State<_ConvertLeadDialog> createState() => _ConvertLeadDialogState();
}

class _ConvertLeadDialogState extends State<_ConvertLeadDialog> {
  late final TextEditingController _accountCtrl;
  final _contactFirstCtrl = TextEditingController();
  final _contactLastCtrl = TextEditingController();
  final _oppNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountCtrl =
        TextEditingController(text: widget.lead.accountName ?? '');
    _oppNameCtrl.text =
        'Oportunidad — ${widget.lead.accountName ?? 'Lead'}';
    _amountCtrl.text = widget.lead.opportunityAmount.toMajorUnitsString();
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _contactFirstCtrl.dispose();
    _contactLastCtrl.dispose();
    _oppNameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Convertir lead: ${widget.lead.accountName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Cuenta nueva',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _field('Nombre de la cuenta *', _accountCtrl),
              const SizedBox(height: 10),
              const Text('Contacto',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _field('Nombre', _contactFirstCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('Apellido', _contactLastCtrl)),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Oportunidad',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _field('Nombre oportunidad *', _oppNameCtrl),
              _field('Monto (${widget.currency.code})', _amountCtrl,
                  type: const TextInputType.numberWithOptions(decimal: true)),
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
            child: const Text('Cancelar')),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.transform, size: 16),
          label: const Text('Convertir'),
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType type = TextInputType.text}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: type,
          inputFormatters:
              type == const TextInputType.numberWithOptions(decimal: true)
                  ? [NumericInput.decimal]
                  : null,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Future<void> _submit() async {
    if (_accountCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nombre de cuenta requerido.');
      return;
    }
    if (_oppNameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Nombre de oportunidad requerido.');
      return;
    }
    if (widget.lead.id == null) {
      setState(() => _error = 'El lead no tiene id válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final amountStr =
          _amountCtrl.text.trim().replaceAll(',', '.').isEmpty
              ? '0'
              : _amountCtrl.text.trim().replaceAll(',', '.');
      final amount = MoneyValue.fromMajorUnits(
          amountStr, currency: widget.currency);

      final account = CrmAccount(
        companyId: widget.companyId,
        name: _accountCtrl.text.trim(),
      );
      final contact = CrmContact(
        companyId: widget.companyId,
        accountId: 0, // será sobreescrito por leadService.convert()
        firstName: _contactFirstCtrl.text.trim().isEmpty
            ? account.name
            : _contactFirstCtrl.text.trim(),
        lastName: _contactLastCtrl.text.trim(),
      );
      final opportunity = CrmOpportunity(
        id: '',
        companyId: widget.companyId,
        accountId: 0,
        accountName: account.name,
        name: _oppNameCtrl.text.trim(),
        amount: amount,
        salesStage: CrmSalesStage.qualification,
        nextFollowUpAt:
            DateTime.now().add(const Duration(days: 7)),
      );

      await widget.leadService.convert(
        leadId: widget.lead.id!,
        account: account,
        contact: contact,
        opportunity: opportunity,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lead convertido — cuenta, contacto y oportunidad creados.'),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _LeadsData {
  const _LeadsData(
      {required this.companyId,
      required this.currency,
      required this.leads});

  final int companyId;
  final Currency currency;
  final List<CrmLead> leads;
}
