import 'package:flutter/material.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'numeric_input.dart';
import 'ui/enterprise_design_system.dart';

class BancosPage extends StatefulWidget {
  const BancosPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<BancosPage> createState() => _BancosPageState();
}

class _BancosPageState extends State<BancosPage> {
  List<Map<String, dynamic>> _bancos = [];
  bool _cargando = true;
  Currency? _currency;

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
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final data = await DatabaseHelper.instance.obtenerBancos();
    if (!mounted) return;
    setState(() {
      _bancos = data;
      _currency = currency;
      _cargando = false;
    });
  }

  Future<void> _formulario({Map<String, dynamic>? banco}) async {
    final nombreCtrl = TextEditingController(
      text: banco?['nombre']?.toString() ?? '',
    );
    final cuentaCtrl = TextEditingController(
      text: banco?['numero_cuenta']?.toString() ?? '',
    );
    final saldoCtrl = TextEditingController(
      text: banco == null
          ? '0'
          : _fromSql(banco['saldo_inicial']).toMajorUnitsString(),
    );
    final pucCtrl = TextEditingController(
      text: banco?['cuenta_puc']?.toString() ?? '111005',
    );
    var tipo = banco?['tipo']?.toString() ?? 'Ahorros';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(banco == null ? 'Nueva cuenta bancaria' : 'Editar banco'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Banco / Alias'),
                ),
                TextField(
                  controller: cuentaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de cuenta',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de cuenta',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Ahorros', child: Text('Ahorros')),
                    DropdownMenuItem(
                      value: 'Corriente',
                      child: Text('Corriente'),
                    ),
                  ],
                  onChanged: (v) => setDlg(() => tipo = v ?? tipo),
                ),
                TextField(
                  controller: saldoCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [NumericInput.decimal],
                  decoration: const InputDecoration(labelText: 'Saldo inicial'),
                ),
                TextField(
                  controller: pucCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta PUC (ej. 111005)',
                  ),
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
                final currency = _currency;
                if (currency == null) return;
                final saldo = MoneyValue.fromMajorUnits(
                  saldoCtrl.text.replaceAll(',', '.'),
                  currency: currency,
                );
                if (banco == null) {
                  await DatabaseHelper.instance.guardarBanco(
                    nombre: nombreCtrl.text.trim(),
                    numeroCuenta: cuentaCtrl.text.trim(),
                    tipo: tipo,
                    saldoInicial: saldo,
                    cuentaPuc: pucCtrl.text.trim(),
                  );
                } else {
                  await DatabaseHelper.instance.actualizarBanco(
                    id: banco['id'] as int,
                    nombre: nombreCtrl.text.trim(),
                    numeroCuenta: cuentaCtrl.text.trim(),
                    tipo: tipo,
                    saldoInicial: saldo,
                    cuentaPuc: pucCtrl.text.trim(),
                  );
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _cargar();
  }

  MoneyValue _fromSql(Object? value) =>
      MoneyValue.fromSql(value, currency: _currency, nullableAsZero: true);

  @override
  Widget build(BuildContext context) {
    final body = _cargando
        ? const Center(child: CircularProgressIndicator())
        : _bancos.isEmpty
        ? const Center(child: Text('No hay cuentas bancarias registradas'))
        : RefreshIndicator(
            onRefresh: _cargar,
            child: ListView.builder(
              padding: const EdgeInsets.all(EnterpriseSpacing.md),
              itemCount: _bancos.length,
              itemBuilder: (_, i) {
                final b = _bancos[i];
                final id = b['id'] as int;
                return FutureBuilder<MoneyValue>(
                  future: DatabaseHelper.instance.obtenerSaldoBanco(id),
                  builder: (context, snap) {
                    final saldo = snap.data;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.account_balance,
                          color: AppBrand.secondary,
                        ),
                        title: Text(b['nombre']?.toString() ?? ''),
                        subtitle: Text(
                          '${b['tipo']} · ${b['numero_cuenta']} · PUC ${b['cuenta_puc']}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              saldo?.format() ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar banco',
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _formulario(banco: b),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar banco',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                  ),
                                  onPressed: () async {
                                    await DatabaseHelper.instance.eliminarBanco(
                                      id,
                                    );
                                    await _cargar();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );

    if (widget.embedded) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.all(EnterpriseSpacing.sm),
              child: FilledButton.icon(
                onPressed: () => _formulario(),
                icon: const Icon(Icons.add),
                label: const Text('Agregar banco'),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de bancos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _formulario(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo banco'),
      ),
      body: body,
    );
  }
}
