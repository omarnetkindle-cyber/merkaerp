import 'package:flutter/material.dart';
import 'core/currency/money_value.dart';
import 'db_helper.dart';
import 'numeric_input.dart';

class TransferenciasPage extends StatefulWidget {
  const TransferenciasPage({super.key});

  @override
  State<TransferenciasPage> createState() => _TransferenciasPageState();
}

class _TransferenciasPageState extends State<TransferenciasPage> {
  String origen = 'caja';
  String destino = 'banco';

  final montoCtrl = TextEditingController();
  final conceptoCtrl = TextEditingController();

  bool loading = false;
  MoneyValue? saldoOrigen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarSaldoOrigen);
      }
    });
  }

  Future<void> _cargarSaldoOrigen() async {
    final saldo = await DatabaseHelper.instance.obtenerSaldoPorCuenta(origen);
    if (!mounted) return;
    setState(() => saldoOrigen = saldo);
  }

  Future<void> transferir() async {
    final saldo = saldoOrigen;
    if (saldo == null) return;
    MoneyValue monto;
    try {
      monto = MoneyValue.fromMajorUnits(
        montoCtrl.text.replaceAll(',', '.'),
        currency: saldo.currency,
      );
    } on FormatException {
      return;
    }

    if (monto.minorUnits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El monto debe ser mayor a 0'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (monto > saldo) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saldo insuficiente en origen. Disponible: ${saldo.format()}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (origen == destino) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Origen y destino deben ser diferentes'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await DatabaseHelper.instance.transferirEntreCuentas(
        origen: origen,
        destino: destino,
        monto: monto,
        concepto: conceptoCtrl.text.trim().isEmpty
            ? 'Transferencia interna'
            : conceptoCtrl.text.trim(),
      );

      setState(() => loading = false);

      montoCtrl.clear();
      conceptoCtrl.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transferencia realizada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      await _cargarSaldoOrigen();

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      setState(() => loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    montoCtrl.dispose();
    conceptoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferencias entre cuentas')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Saldo disponible en origen (Mejora 9)
            Card(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Saldo disponible en origen'),
                trailing: Text(
                  saldoOrigen?.format() ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField(
              initialValue: origen,
              items: const [
                DropdownMenuItem(value: 'caja', child: Text('Caja (Efectivo)')),
                DropdownMenuItem(
                  value: 'banco',
                  child: Text('Banco (Transferencias)'),
                ),
                DropdownMenuItem(
                  value: 'cartera',
                  child: Text('Cartera (Crédito)'),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => origen = v);
                  _cargarSaldoOrigen();
                }
              },
              decoration: const InputDecoration(
                labelText: 'Cuenta de origen',
                border: OutlineInputBorder(),
                helperText: 'Seleccione la cuenta de donde saldrá el dinero',
              ),
            ),

            const SizedBox(height: 16),

            DropdownButtonFormField(
              initialValue: destino,
              items: const [
                DropdownMenuItem(value: 'caja', child: Text('Caja (Efectivo)')),
                DropdownMenuItem(
                  value: 'banco',
                  child: Text('Banco (Transferencias)'),
                ),
                DropdownMenuItem(
                  value: 'cartera',
                  child: Text('Cartera (Crédito)'),
                ),
              ],
              onChanged: (v) => setState(() => destino = v as String),
              decoration: const InputDecoration(
                labelText: 'Cuenta de destino',
                border: OutlineInputBorder(),
                helperText: 'Seleccione la cuenta donde llegará el dinero',
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [NumericInput.decimal],
              decoration: InputDecoration(
                labelText: 'Monto a transferir',
                border: const OutlineInputBorder(),
                helperText:
                    'Máximo disponible: ${saldoOrigen?.format() ?? '-'}',
                suffixText: '\$',
              ),
            ),

            const SizedBox(height: 16),

            TextField(
              controller: conceptoCtrl,
              decoration: const InputDecoration(
                labelText: 'Concepto (opcional)',
                border: OutlineInputBorder(),
                helperText: 'Descripción de la transferencia',
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: loading ? null : transferir,
                icon: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  loading ? 'Procesando...' : 'Realizar transferencia',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
