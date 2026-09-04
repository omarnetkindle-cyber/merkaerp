import 'package:flutter/material.dart';

import '../../app_session.dart';
import '../../core/security/action_permission.dart';
import '../../db_helper.dart';
import '../../ui/merka_theme_tokens.dart';
import '../application/crm_account_service.dart';
import '../application/crm_contact_service.dart';
import '../application/crm_interaction_service.dart';
import '../application/crm_opportunity_service.dart';
import '../domain/crm_account.dart';
import '../domain/crm_contact.dart';
import '../domain/crm_opportunity.dart';
import '../domain/customer_interaction.dart';
import 'crm_intelligence_page.dart';

class CrmAccountsPage extends StatefulWidget {
  const CrmAccountsPage({super.key});

  @override
  State<CrmAccountsPage> createState() => _CrmAccountsPageState();
}

class _CrmAccountsPageState extends State<CrmAccountsPage> {
  final _service = CrmAccountService();
  late Future<List<CrmAccount>> _accounts;
  String _search = '';

  bool get _canCreate =>
      AppSession.puedeEjecutarAccion('crm', AppAction.create);
  bool get _canEdit => AppSession.puedeEjecutarAccion('crm', AppAction.update);

  @override
  void initState() {
    super.initState();
    _accounts = _service.list();
  }

  void _reload() => setState(() => _accounts = _service.list());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas CRM'),
        actions: [
          IconButton(
            tooltip: 'Inteligencia CRM: VIP, recompra, inactivos y cartera',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CrmIntelligencePage()),
            ),
            icon: const Icon(Icons.auto_graph),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar cuenta...',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(),
                filled: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
        ),
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Nueva cuenta'),
              onPressed: () => _openAccountForm(context, null),
            )
          : null,
      body: FutureBuilder<List<CrmAccount>>(
        future: _accounts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final all = snapshot.data ?? const <CrmAccount>[];
          final accounts = _search.isEmpty
              ? all
              : all
                    .where(
                      (a) =>
                          a.name.toLowerCase().contains(_search) ||
                          (a.email ?? '').toLowerCase().contains(_search) ||
                          (a.document ?? '').toLowerCase().contains(_search),
                    )
                    .toList();
          if (accounts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.business_center_outlined,
                    size: 56,
                    color: MerkaThemeTokens.graphite600,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _search.isEmpty
                        ? 'Sin cuentas CRM'
                        : 'Sin resultados para "$_search"',
                  ),
                  if (_canCreate && _search.isEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Crear la primera cuenta'),
                      onPressed: () => _openAccountForm(context, null),
                    ),
                  ],
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: account.status == 'activo'
                      ? MerkaThemeTokens.navy700
                      : MerkaThemeTokens.graphite600,
                  child: Text(
                    account.name.isNotEmpty
                        ? account.name[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(account.name),
                subtitle: Text(
                  [
                    account.email,
                    account.phone,
                    account.document,
                    if (account.status != 'activo') account.status,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                ),
                trailing: _canEdit
                    ? IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Editar',
                        onPressed: () => _openAccountForm(context, account),
                      )
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CrmAccountPage(accountId: account.id!),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openAccountForm(
    BuildContext context,
    CrmAccount? existing,
  ) async {
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountFormDialog(
        existing: existing,
        companyId: companyId,
        service: _service,
      ),
    );
    if (saved == true) _reload();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulario de cuenta CRM
// ─────────────────────────────────────────────────────────────────────────────
class _AccountFormDialog extends StatefulWidget {
  const _AccountFormDialog({
    required this.companyId,
    required this.service,
    this.existing,
  });

  final int companyId;
  final CrmAccountService service;
  final CrmAccount? existing;

  @override
  State<_AccountFormDialog> createState() => _AccountFormDialogState();
}

class _AccountFormDialogState extends State<_AccountFormDialog> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _status = 'activo';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _emailCtrl.text = e.email ?? '';
      _phoneCtrl.text = e.phone ?? '';
      _docCtrl.text = e.document ?? '';
      _addressCtrl.text = e.address ?? '';
      _status = e.status;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _docCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar cuenta CRM' : 'Nueva cuenta CRM'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Nombre *', _nameCtrl),
              _field(
                'Correo electrónico',
                _emailCtrl,
                type: TextInputType.emailAddress,
              ),
              _field('Teléfono', _phoneCtrl, type: TextInputType.phone),
              _field('Documento / NIT', _docCtrl),
              _field('Dirección', _addressCtrl),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'activo', child: Text('Activo')),
                  DropdownMenuItem(value: 'inactivo', child: Text('Inactivo')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
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
              : Text(isEdit ? 'Actualizar' : 'Crear'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

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
      final account = CrmAccount(
        id: widget.existing?.id,
        companyId: widget.companyId,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        document: _docCtrl.text.trim().isEmpty ? null : _docCtrl.text.trim(),
        address: _addressCtrl.text.trim().isEmpty
            ? null
            : _addressCtrl.text.trim(),
        status: _status,
      );
      if (widget.existing == null) {
        await widget.service.create(account);
      } else {
        await widget.service.update(account);
      }
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

class CrmAccountPage extends StatefulWidget {
  const CrmAccountPage({super.key, required this.accountId});

  final int accountId;

  @override
  State<CrmAccountPage> createState() => _CrmAccountPageState();
}

class _CrmAccountPageState extends State<CrmAccountPage> {
  late Future<_AccountHistory> _history;

  @override
  void initState() {
    super.initState();
    _history = _load();
  }

  Future<_AccountHistory> _load() async {
    final accountService = CrmAccountService();
    final account = await accountService.findById(widget.accountId);
    if (account == null) throw StateError('La cuenta CRM no existe.');
    final contacts = await CrmContactService().listForAccount(widget.accountId);
    final interactions = await CrmInteractionService().listForCustomer(
      widget.accountId,
    );
    final opportunities = await CrmOpportunityService().listForAccount(
      widget.accountId,
    );
    return _AccountHistory(account, contacts, interactions, opportunities);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha de cuenta')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo contacto'),
        onPressed: () => _openContactForm(context),
      ),
      body: FutureBuilder<_AccountHistory>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                data.account.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(data.account.email ?? 'Sin correo'),
              const SizedBox(height: 16),
              _section('Contactos', data.contacts.map(_contactTile).toList()),
              _section(
                'Oportunidades',
                data.opportunities.map(_opportunityTile).toList(),
              ),
              _section(
                'Historial de interacciones',
                data.interactions.map(_interactionTile).toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(title),
      children: children.isEmpty
          ? [const ListTile(title: Text('Sin registros'))]
          : children,
    );
  }

  Widget _contactTile(CrmContact contact) => ListTile(
    leading: const Icon(Icons.person_outline),
    title: Text('${contact.firstName} ${contact.lastName}'.trim()),
    subtitle: Text(contact.email ?? contact.phoneMobile ?? 'Sin datos'),
  );

  Widget _opportunityTile(CrmOpportunity opportunity) => ListTile(
    leading: const Icon(Icons.trending_up),
    title: Text(opportunity.name),
    subtitle: Text(
      '${opportunity.salesStage.value} - ${opportunity.amount.format()}',
    ),
    trailing: Text('${opportunity.effectiveProbability}%'),
  );

  Widget _interactionTile(CustomerInteraction interaction) => ListTile(
    leading: const Icon(Icons.history),
    title: Text(interaction.subject),
    subtitle: Text(
      '${interaction.interactionType} - ${interaction.interactionDate}',
    ),
  );

  // ── Formulario de nuevo contacto ──────────────────────────────────────────

  Future<void> _openContactForm(BuildContext context) async {
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ContactFormDialog(
        companyId: companyId,
        accountId: widget.accountId,
        service: CrmContactService(),
      ),
    );
    if (saved == true && mounted) {
      setState(() => _history = _load());
    }
  }
}

class _AccountHistory {
  const _AccountHistory(
    this.account,
    this.contacts,
    this.interactions,
    this.opportunities,
  );

  final CrmAccount account;
  final List<CrmContact> contacts;
  final List<CustomerInteraction> interactions;
  final List<CrmOpportunity> opportunities;
}

// ─────────────────────────────────────────────────────────────────────────────
// Formulario de contacto CRM
// ─────────────────────────────────────────────────────────────────────────────
class _ContactFormDialog extends StatefulWidget {
  const _ContactFormDialog({
    required this.companyId,
    required this.accountId,
    required this.service,
    // ignore: unused_element_parameter
    this.existing,
  });

  final int companyId;
  final int accountId;
  final CrmContactService service;
  final CrmContact? existing;

  @override
  State<_ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<_ContactFormDialog> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _firstCtrl.text = e.firstName;
      _lastCtrl.text = e.lastName;
      _emailCtrl.text = e.email ?? '';
      _mobileCtrl.text = e.phoneMobile ?? '';
      _roleCtrl.text = e.opportunityRole ?? '';
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _mobileCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo contacto'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _field('Nombre *', _firstCtrl)),
                  const SizedBox(width: 8),
                  Expanded(child: _field('Apellido', _lastCtrl)),
                ],
              ),
              _field(
                'Correo electrónico',
                _emailCtrl,
                type: TextInputType.emailAddress,
              ),
              _field('Teléfono móvil', _mobileCtrl, type: TextInputType.phone),
              _field('Rol / cargo', _roleCtrl),
              if (_error != null) ...[
                const SizedBox(height: 6),
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
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: ctrl,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    ),
  );

  Future<void> _submit() async {
    if (_firstCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El nombre es requerido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final contact = CrmContact(
        id: widget.existing?.id,
        companyId: widget.companyId,
        accountId: widget.accountId,
        firstName: _firstCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        phoneMobile: _mobileCtrl.text.trim().isEmpty
            ? null
            : _mobileCtrl.text.trim(),
        opportunityRole: _roleCtrl.text.trim().isEmpty
            ? null
            : _roleCtrl.text.trim(),
      );
      if (widget.existing == null) {
        await widget.service.create(contact);
      } else {
        await widget.service.update(contact);
      }
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
