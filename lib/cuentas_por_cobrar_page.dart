import 'package:flutter/material.dart';
import 'integrations/application/communication_service.dart';

import 'ui/widgets/expandable_record_card.dart';
import 'ui/widgets/remote_payment_button.dart';
import 'core/tracing/traceability_record_action.dart';
import 'ui/widgets/semantic_zoom_record_list.dart';

import 'core/currency/currency.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';
import 'core/financial/financial_ui_helpers.dart';
import 'db_helper.dart';
import 'numeric_input.dart';

class CuentasPorCobrarPage extends StatefulWidget {
  const CuentasPorCobrarPage({super.key});

  @override
  State<CuentasPorCobrarPage> createState() => _CuentasPorCobrarPageState();
}

class _CuentasPorCobrarPageState extends State<CuentasPorCobrarPage> {
  List<Map<String, dynamic>> cuentas = [];
  Currency? _currency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(cargar);
      }
    });
  }

  Future<void> cargar() async {
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final data = await DatabaseHelper.instance.obtenerCuentasPorCobrar();

    if (!mounted) return;

    setState(() {
      cuentas = data;
      _currency = currency;
    });
  }

  String _formatSql(Object? value) {
    final currency = _currency;
    if (currency == null) return '-';
    return MoneyValue.fromSql(
      value,
      currency: currency,
      nullableAsZero: true,
    ).format();
  }

  Color colorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'pagada':
        return Colors.green;
      case 'parcial':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  Future<void> _mostrarDialogoAbono(Map<String, dynamic> cuenta) async {
    final montoCtrl = TextEditingController();
    String metodoPago = 'EFECTIVO';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar cobro'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saldo actual: ${_formatSql(cuenta['saldo'])}'),
            const SizedBox(height: 12),
            TextField(
              controller: montoCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [NumericInput.decimal],
              decoration: const InputDecoration(
                labelText: 'Monto a cobrar',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: metodoPago,
              decoration: const InputDecoration(
                labelText: 'Método de pago',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'EFECTIVO', child: Text('EFECTIVO')),
                DropdownMenuItem(
                  value: 'TRANSFERENCIA',
                  child: Text('TRANSFERENCIA'),
                ),
                DropdownMenuItem(value: 'NEQUI', child: Text('NEQUI')),
                DropdownMenuItem(value: 'DAVIPLATA', child: Text('DAVIPLATA')),
              ],
              onChanged: (v) {
                if (v != null) metodoPago = v;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final currency = _currency;
              if (currency == null) return;
              MoneyValue monto;
              try {
                monto = MoneyValue.fromMajorUnits(
                  montoCtrl.text.replaceAll(',', '.'),
                  currency: currency,
                );
              } on FormatException {
                return;
              }
              if (monto.minorUnits <= 0) return;

              try {
                await DatabaseHelper.instance.registrarAbonoCXC(
                  cuentaId: cuenta['id'],
                  monto: monto,
                  metodoPago: metodoPago,
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(e.toString()),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);

              await cargar();

              if (!mounted) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cobro registrado'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  /// Abre el flujo de pago online verificado para una cuenta por cobrar.
  /// Solo registra el abono cuando el proveedor confirma el pago.
  Future<void> _mostrarPagoOnline(Map<String, dynamic> cuenta) async {
    final currency = _currency;
    if (currency == null) return;

    final saldo = MoneyValue.fromSql(
      cuenta['saldo'],
      currency: currency,
      nullableAsZero: true,
    );
    if (saldo.minorUnits <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta cuenta ya está saldada.')),
      );
      return;
    }

    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final reference = 'CXC-${cuenta['id']}-${cuenta['venta_id'] ?? 0}';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Pago en línea'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cliente: ${cuenta['cliente'] ?? '-'}'),
              Text('Saldo: ${saldo.format()}'),
              const SizedBox(height: 12),
              const Text(
                'El pago solo se registrará cuando el proveedor confirme '
                'la transacción. Un HTTP 200 de creación no equivale a acreditación.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              RemotePaymentButton(
                companyId: companyId,
                amount: saldo,
                reference: reference,
                description: 'Cobro CxC — ${cuenta['cliente']}',
                onPaymentConfirmed: (result) async {
                  // Solo llegamos aquí si provider_verified == true.
                  try {
                    await DatabaseHelper.instance.registrarAbonoCXC(
                      cuentaId: cuenta['id'],
                      monto: saldo,
                      metodoPago: result.provider.toUpperCase(),
                    );
                    await cargar();
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Pago ${result.provider} verificado y registrado.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error al registrar abono: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarHistorialAbonos(Map<String, dynamic> cuenta) async {
    final abonos = await DatabaseHelper.instance.obtenerAbonosCXC(cuenta['id']);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Venta #${cuenta['venta_id'] ?? '-'} - ${cuenta['cliente']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: abonos.isEmpty
              ? const Text('No hay cobros registrados')
              : SizedBox(
                  width: double.maxFinite,
                  height: 300,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: abonos.length,
                    itemBuilder: (context, i) {
                      final a = abonos[i];

                      return ListTile(
                        leading: const Icon(
                          Icons.payments,
                          color: Colors.green,
                        ),
                        title: Text(_formatSql(a['monto'])),
                        subtitle: Text('${a['metodo_pago']} · ${a['fecha']}'),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordarWhatsApp(Map<String, dynamic> cuenta) async {
    final clientId = (cuenta['cliente_id'] as num?)?.toInt();
    if (clientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La cuenta no está vinculada a un cliente con datos de contacto.')));
      return;
    }
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    final clients = await db.query('clientes', where: 'company_id = ? AND id = ?', whereArgs: [companyId, clientId], limit: 1);
    if (!mounted) return;
    if (clients.isEmpty || (clients.first['telefono']?.toString().trim() ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El cliente no tiene teléfono registrado.')));
      return;
    }
    final phone = clients.first['telefono'].toString();
    final name = cuenta['cliente']?.toString() ?? 'Cliente';
    final message = 'Hola $name. Te recordamos que tienes un saldo pendiente de ${_formatSql(cuenta['saldo'])}${cuenta['vencimiento'] == null ? '' : ' con vencimiento ${cuenta['vencimiento']}'}. Si ya realizaste el pago, puedes omitir este mensaje.';
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Recordatorio de cartera'), content: SelectableText(message),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Enviar por WhatsApp'))],
    ));
    if (confirm != true) return;
    final result = await CommunicationService.instance.sendWhatsAppText(recipient: phone, message: message);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas por cobrar')),
      body: cuentas.isEmpty
          ? const Center(child: Text('No hay cuentas por cobrar'))
          : SemanticZoomRecordList<Map<String, dynamic>>(
              records: cuentas,
              title: 'Zoom de cartera',
              statusOf: (row) => row['estado']?.toString() ?? 'Sin estado',
              itemBuilder: (context, c, {required initiallyExpanded}) {
                final estado = c['estado']?.toString() ?? '';

                return ExpandableRecordCard(
                  actions: [
                    if (c['venta_id'] != null)
                      traceabilityRecordAction(
                        rootEntityType: 'venta',
                        rootRecordId: c['venta_id'].toString(),
                      ),
                    RecordCardAction(
                      id: 'abonar',
                      label: 'Cobrar',
                      icon: Icons.payments,
                      onPressed: (_) async => _mostrarDialogoAbono(c),
                    ),
                    RecordCardAction(
                      id: 'pago_online',
                      label: 'Pago en línea',
                      icon: Icons.credit_card,
                      visible: (c['estado']?.toString() ?? '') != 'pagada',
                      onPressed: (_) async => _mostrarPagoOnline(c),
                    ),
                    RecordCardAction(
                      id: 'historial',
                      label: 'Ver historial',
                      icon: Icons.history,
                      onPressed: (_) async => _mostrarHistorialAbonos(c),
                    ),
                    RecordCardAction(
                      id: 'whatsapp',
                      label: 'Recordar por WhatsApp',
                      icon: Icons.chat_outlined,
                      onPressed: (_) async => _recordarWhatsApp(c),
                    ),
                  ],
                  criticalFields: [
                    RecordCardField(
                      label: 'Cliente',
                      value: c['cliente']?.toString() ?? 'Cliente general',
                      icon: Icons.person,
                      emphasized: true,
                    ),
                    RecordCardField(
                      label: 'Venta',
                      value: '#${c['venta_id'] ?? '-'}',
                      icon: Icons.receipt_long,
                    ),
                    RecordCardField(
                      label: 'Saldo',
                      value: _formatSql(c['saldo']),
                      icon: Icons.account_balance_wallet,
                      emphasized: true,
                    ),
                    RecordCardField(
                      label: 'Estado',
                      value: FinancialUiHelpers.accountStatusLabel(estado),
                      icon: Icons.flag,
                      emphasized: true,
                    ),
                  ],
                  secondaryFields: [
                    RecordCardField(
                      label: 'Total',
                      value: _formatSql(c['total']),
                    ),
                    RecordCardField(
                      label: 'Fecha',
                      value: c['fecha']?.toString() ?? '',
                    ),
                    RecordCardField(
                      label: 'Vencimiento',
                      value: c['vencimiento']?.toString() ?? '',
                    ),
                    RecordCardField(
                      label: 'Descripción',
                      value: c['descripcion']?.toString() ?? '',
                    ),
                  ],
                  initiallyExpanded: initiallyExpanded,
                );
              },
            ),
    );
  }
}
