import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';

import 'core/multi_company/company_transfer.dart';
import 'core/multi_company/financial_consolidation.dart';
import 'core/multi_company/transfer_service.dart';
import 'db_helper.dart';

class EmpresasPage extends StatefulWidget {
  const EmpresasPage({super.key});

  @override
  State<EmpresasPage> createState() => _EmpresasPageState();
}

class _EmpresasPageState extends State<EmpresasPage> {
  List<Map<String, dynamic>> empresas = [];
  List<Map<String, dynamic>> companies = [];
  List<CompanyTransfer> transferencias = [];
  Map<String, dynamic> activa = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargar);
      }
    });
  }

  Future<void> _cargar() async {
    final data = await DatabaseHelper.instance.obtenerEmpresas();
    final empresaActiva = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final db = await DatabaseHelper.instance.database;
    await CompanyTransferService.instance.createTables(db);
    final modernCompanies = await db.query('companies', orderBy: 'name ASC');
    final transfers = await CompanyTransferService.instance
        .getTransfersByStatus(db, 'pending');
    final approved = await CompanyTransferService.instance.getTransfersByStatus(
      db,
      'approved',
    );
    if (!mounted) return;
    setState(() {
      empresas = data;
      companies = modernCompanies;
      transferencias = [...transfers, ...approved];
      activa = empresaActiva;
    });
  }

  Future<void> _nuevaTransferenciaFondos() async {
    if (companies.length < 2) return;
    int fromId = companies.first['id'] as int;
    int toId = companies.skip(1).first['id'] as int;
    final amountCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transferencia intercompania'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: fromId,
              decoration: const InputDecoration(labelText: 'Empresa origen'),
              items: companies
                  .map(
                    (company) => DropdownMenuItem<int>(
                      value: company['id'] as int,
                      child: Text(company['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) fromId = value;
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: toId,
              decoration: const InputDecoration(labelText: 'Empresa destino'),
              items: companies
                  .map(
                    (company) => DropdownMenuItem<int>(
                      value: company['id'] as int,
                      child: Text(company['name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) toId = value;
              },
            ),
            TextField(
              controller: amountCtrl,
              decoration: const InputDecoration(labelText: 'Monto'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final amount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
    final db = await DatabaseHelper.instance.database;
    final number = await CompanyTransferService.instance.generateTransferNumber(
      db,
    );
    await CompanyTransferService.instance.createTransfer(
      db,
      CompanyTransfer(
        fromCompanyId: fromId,
        toCompanyId: toId,
        transferNumber: number,
        transferType: 'funds',
        items: const {},
        totalValue: amount,
        notes: notesCtrl.text.trim(),
        requestedBy: 'ui',
        requestedAt: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    await _cargar();
  }

  Future<void> _aprobarYCompletar(CompanyTransfer transfer) async {
    final db = await DatabaseHelper.instance.database;
    if (transfer.isPending) {
      await CompanyTransferService.instance.approveTransfer(
        db,
        transfer.id!,
        'ui',
      );
    }
    await CompanyTransferService.instance.completeTransfer(db, transfer.id!);
    await _cargar();
  }

  Future<void> _mostrarConsolidado() async {
    final db = await DatabaseHelper.instance.database;
    final ids = companies.map((company) => company['id'] as int).toList();
    final result = await FinancialConsolidationService.instance
        .getConsolidatedFinancials(db, ids);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Consolidado multiempresa'),
        content: SingleChildScrollView(child: Text(result.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _nueva({Map<String, dynamic>? empresa}) async {
    final nombreCtrl = TextEditingController(
      text: empresa?['nombre']?.toString() ?? '',
    );
    final nitCtrl = TextEditingController(
      text: empresa?['nit']?.toString() ?? '',
    );
    final ciudadCtrl = TextEditingController(
      text: empresa?['ciudad']?.toString() ?? '',
    );
    final monedaCtrl = TextEditingController(
      text: empresa?['moneda']?.toString() ?? 'COP',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(empresa == null ? 'Nueva empresa' : 'Editar empresa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: nitCtrl,
                decoration: const InputDecoration(labelText: 'NIT / documento'),
              ),
              TextField(
                controller: ciudadCtrl,
                decoration: const InputDecoration(labelText: 'Ciudad'),
              ),
              TextField(
                controller: monedaCtrl,
                decoration: const InputDecoration(labelText: 'Moneda'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (nombreCtrl.text.trim().isEmpty) return;
              if (empresa == null) {
                await DatabaseHelper.instance.guardarEmpresa({
                  'nombre': nombreCtrl.text.trim(),
                  'nit': nitCtrl.text.trim(),
                  'ciudad': ciudadCtrl.text.trim(),
                  'moneda': monedaCtrl.text.trim().isEmpty
                      ? 'COP'
                      : monedaCtrl.text.trim(),
                });
              } else {
                await DatabaseHelper.instance
                    .actualizarEmpresa(empresa['id'] as int, {
                      'nombre': nombreCtrl.text.trim(),
                      'nit': nitCtrl.text.trim(),
                      'ciudad': ciudadCtrl.text.trim(),
                      'moneda': monedaCtrl.text.trim().isEmpty
                          ? 'COP'
                          : monedaCtrl.text.trim(),
                    });
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _seleccionar(Map<String, dynamic> empresa) async {
    await DatabaseHelper.instance.seleccionarEmpresa(empresa);
    await _cargar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Empresa activa: ${empresa['nombre']}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreActivo = activa['nombre']?.toString() ?? 'MerkaERP';
    return Scaffold(
      appBar: AppBar(title: const Text('Empresas y Sucursales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nueva(),
        icon: const Icon(Icons.add_business),
        label: const Text('Empresa'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.domain),
              title: const Text('Empresa activa'),
              subtitle: Text(nombreActivo),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Transferencias y consolidacion multiempresa',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: companies.length < 2
                            ? null
                            : _nuevaTransferenciaFondos,
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Fondos'),
                      ),
                      TextButton.icon(
                        onPressed: companies.isEmpty
                            ? null
                            : _mostrarConsolidado,
                        icon: const Icon(Icons.account_tree),
                        label: const Text('Consolidar'),
                      ),
                    ],
                  ),
                  if (transferencias.isEmpty)
                    const Text('No hay transferencias pendientes o aprobadas.')
                  else
                    ...transferencias.map(
                      (transfer) => ListTile(
                        dense: true,
                        title: Text(transfer.transferNumber),
                        subtitle: Text(
                          '${transfer.status} · ${transfer.fromCompanyId} → ${transfer.toCompanyId} · ${transfer.totalValue}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () => _aprobarYCompletar(transfer),
                          child: Text(
                            transfer.isPending
                                ? 'Aprobar y completar'
                                : 'Completar',
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (empresas.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay empresas adicionales. El perfil actual se administra en Configuración.',
                textAlign: TextAlign.center,
              ),
            )
          else
            ...empresas.map(
              (empresa) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: MerkaThemeTokens.paper100,
                    child: Text(
                      (empresa['nombre']?.toString() ?? 'E')[0].toUpperCase(),
                      style: const TextStyle(
                        color: MerkaThemeTokens.info,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(empresa['nombre']?.toString() ?? ''),
                  subtitle: Text(
                    'NIT: ${empresa['nit'] ?? ''} · ${empresa['ciudad'] ?? ''} · ${empresa['moneda'] ?? 'COP'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _nueva(empresa: empresa),
                        tooltip: 'Editar empresa',
                      ),
                      IconButton(
                        tooltip: 'Eliminar empresa',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Eliminar empresa'),
                              content: const Text(
                                '¿Está seguro de eliminar esta empresa?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await DatabaseHelper.instance.eliminarEmpresa(
                              empresa['id'] as int,
                            );
                            await _cargar();
                          }
                        },
                      ),
                      FilledButton.tonal(
                        onPressed: () => _seleccionar(empresa),
                        child: const Text('Usar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
