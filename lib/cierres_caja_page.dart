import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'core/currency/currency.dart';
import 'core/currency/money_value.dart';
import 'app_session.dart';
import 'cash/application/cash_shift_service.dart';
import 'db_helper.dart';
import 'numeric_input.dart';

class CierresCajaPage extends StatefulWidget {
  const CierresCajaPage({super.key});

  @override
  State<CierresCajaPage> createState() => _CierresCajaPageState();
}

class _CierresCajaPageState extends State<CierresCajaPage> {
  List<Map<String, dynamic>> cierres = [];
  double saldoSistema = 0;
  double saldoBanco = 0;
  double saldoCartera = 0;
  bool bloqueada = false;
  Currency? _currency;
  CashShift? _currentShift;
  List<CashShift> _shiftHistory = const [];

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
    final data = await DatabaseHelper.instance.obtenerCierresCaja();
    final saldo = await DatabaseHelper.instance.obtenerSaldoPorCuenta('caja');
    final banco = await DatabaseHelper.instance.obtenerSaldoPorCuenta('banco');
    final cartera = await DatabaseHelper.instance.obtenerSaldoPorCuenta(
      'cartera',
    );
    final bloqueo = await DatabaseHelper.instance.operacionBloqueadaPorCierre();
    final shift = await CashShiftService.instance.currentShift(saldo.currency);
    final shiftHistory = await CashShiftService.instance.history(saldo.currency);
    if (!mounted) return;
    setState(() {
      cierres = data;
      _currency = saldo.currency;
      saldoSistema = saldo.toMajorUnitsDoubleForDisplay();
      saldoBanco = banco.toMajorUnitsDoubleForDisplay();
      saldoCartera = cartera.toMajorUnitsDoubleForDisplay();
      bloqueada = bloqueo;
      _currentShift = shift;
      _shiftHistory = shiftHistory;
    });
  }

  Future<void> _reabrirOperacion() async {
    if (AppSession.rol != 'administrador') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solo un administrador puede autorizar una reapertura.')),
      );
      return;
    }
    final reasonCtrl = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Autorizar reapertura de caja'),
        content: TextField(
          controller: reasonCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo obligatorio',
            helperText: 'La reapertura queda registrada en auditoría y no borra el cierre anterior.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Autorizar')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await CashShiftService.instance.reopenLastShift(reason: reasonCtrl.text);
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _abrirTurno() async {
    final currency = _currency;
    if (currency == null) return;
    final fundCtrl = TextEditingController(text: '100000');
    final notesCtrl = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abrir turno de caja'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Responsable: ${AppSession.nombre}'),
              const SizedBox(height: 12),
              TextField(
                controller: fundCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumericInput.decimal],
                decoration: const InputDecoration(
                  labelText: 'Fondo inicial declarado',
                  helperText: 'Este dato identifica el fondo del turno; no duplica el saldo contable de caja.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Observaciones', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Abrir turno')),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      final fund = MoneyValue.fromMajorUnits(fundCtrl.text.replaceAll(',', '.'), currency: currency);
      await CashShiftService.instance.openShift(openingFund: fund, notes: notesCtrl.text);
      await _cargar();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _abrirDesgloseCaja(
    TextEditingController contadoCtrl,
    TextEditingController obsCtrl,
  ) async {
    final Map<int, TextEditingController> ctrls = {
      100000: TextEditingController(),
      50000: TextEditingController(),
      20000: TextEditingController(),
      10000: TextEditingController(),
      5000: TextEditingController(),
      2000: TextEditingController(),
      1000: TextEditingController(),
      500: TextEditingController(),
      200: TextEditingController(),
      100: TextEditingController(),
      50: TextEditingController(),
    };

    double totalDesglose = 0.0;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void recalculate() {
            double sum = 0;
            for (final entry in ctrls.entries) {
              final val = int.tryParse(entry.value.text) ?? 0;
              sum += val * entry.key;
            }
            setDialogState(() {
              totalDesglose = sum;
            });
          }

          Widget denominationInput(int val, String type) {
            final formattedVal = val >= 1000
                ? '\$${(val / 1000).toStringAsFixed(0)}k'
                : '\$$val';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text('$type de $formattedVal:')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: ctrls[val],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => recalculate(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Total: \$${((int.tryParse(ctrls[val]!.text) ?? 0) * val).toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            title: const Text('Desglose de Moneda Colombiana (COP)'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Billetes',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: MerkaThemeTokens.info,
                      ),
                    ),
                    const Divider(),
                    denominationInput(100000, 'Billete'),
                    denominationInput(50000, 'Billete'),
                    denominationInput(20000, 'Billete'),
                    denominationInput(10000, 'Billete'),
                    denominationInput(5000, 'Billete'),
                    denominationInput(2000, 'Billete'),
                    const SizedBox(height: 12),
                    const Text(
                      'Monedas',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: MerkaThemeTokens.info,
                      ),
                    ),
                    const Divider(),
                    denominationInput(1000, 'Moneda'),
                    denominationInput(500, 'Moneda'),
                    denominationInput(200, 'Moneda'),
                    denominationInput(100, 'Moneda'),
                    denominationInput(50, 'Moneda'),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Contado:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '\$${totalDesglose.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  contadoCtrl.text = totalDesglose.toStringAsFixed(0);

                  final List<String> detailList = [];
                  for (final entry in ctrls.entries) {
                    final qty = int.tryParse(entry.value.text) ?? 0;
                    if (qty > 0) {
                      final fmt = entry.key >= 1000
                          ? '${entry.key ~/ 1000}k'
                          : '${entry.key}';
                      detailList.add('${qty}x\$$fmt');
                    }
                  }
                  if (detailList.isNotEmpty) {
                    obsCtrl.text =
                        'Desglose: [${detailList.join(', ')}]. ${obsCtrl.text}';
                  }

                  Navigator.pop(ctx);
                },
                child: const Text('Confirmar y Aplicar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _registrarCierre() async {
    if (_currentShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abre tu turno de caja antes de registrar el cierre.')),
      );
      return;
    }
    final contadoCtrl = TextEditingController(
      text: saldoSistema.toStringAsFixed(0),
    );
    final baseCtrl = TextEditingController(text: '100000');
    final obsCtrl = TextEditingController();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final contado =
              double.tryParse(contadoCtrl.text.replaceAll(',', '.')) ?? 0;
          final diferencia = contado - saldoSistema;

          return AlertDialog(
            title: const Text('Cierre de caja'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Resumen de saldos por método de pago (Mejora 16)
                    Card(
                      color: MerkaThemeTokens.paper50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Saldos por método de pago',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Caja (Efectivo):'),
                                Text(
                                  _fmt(saldoSistema),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Banco (Transferencias):'),
                                Text(
                                  _fmt(saldoBanco),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Cartera (Crédito):'),
                                Text(
                                  _fmt(saldoCartera),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _fmt(
                                    saldoSistema + saldoBanco + saldoCartera,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Saldo sistema (Caja): \$${saldoSistema.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: contadoCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [NumericInput.decimal],
                            decoration: const InputDecoration(
                              labelText: 'Efectivo contado',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Desglosar billetes y monedas',
                          icon: const Icon(Icons.calculate, color: MerkaThemeTokens.info),
                          onPressed: () =>
                              _abrirDesgloseCaja(contadoCtrl, obsCtrl),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Mostrar diferencia en tiempo real (Mejora 15)
                    Card(
                      color: diferencia.abs() < 0.01
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Diferencia:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _fmt(diferencia),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: diferencia.abs() < 0.01
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: baseCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [NumericInput.decimal],
                      decoration: const InputDecoration(
                        labelText: 'Base apertura siguiente día (COP)',
                        border: OutlineInputBorder(),
                        helperText:
                            'El excedente se trasladará automáticamente a bancos',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: obsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Observación',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final currency = _currency;
                  if (currency == null) return;
                  final contado = MoneyValue.fromMajorUnits(
                    contadoCtrl.text.replaceAll(',', '.'),
                    currency: currency,
                  );
                  final base = MoneyValue.fromMajorUnits(
                    baseCtrl.text.replaceAll(',', '.'),
                    currency: currency,
                  );
                  final closeId = await DatabaseHelper.instance.registrarCierreCaja(
                    efectivoContado: contado,
                    observacion: obsCtrl.text.trim(),
                    baseAperturaSiguiente: base,
                  );
                  await CashShiftService.instance.closeCurrentShift(
                    closeId: closeId,
                    currency: currency,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('Cerrar caja'),
              ),
            ],
          );
        },
      ),
    );

    if (guardado == true) {
      await _cargar();
    }
  }

  String _fmt(num valor) => '\$${valor.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cierres de caja')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: bloqueada
            ? _reabrirOperacion
            : (_currentShift == null ? _abrirTurno : _registrarCierre),
        icon: Icon(bloqueada
            ? Icons.admin_panel_settings
            : (_currentShift == null ? Icons.play_circle : Icons.lock_clock)),
        label: Text(bloqueada
            ? 'Reabrir con autorización'
            : (_currentShift == null ? 'Abrir turno' : 'Cerrar turno')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_currentShift == null ? Icons.person_off : Icons.badge),
              title: Text(_currentShift == null
                  ? 'No hay turno abierto para ${AppSession.nombre}'
                  : 'Turno activo · ${_currentShift!.userName}'),
              subtitle: Text(_currentShift == null
                  ? 'Abre un turno antes de operar el cierre.'
                  : 'Desde ${_currentShift!.openedAt.toLocal()} · Fondo ${_currentShift!.openingFund.format()}'),
              trailing: _currentShift == null
                  ? TextButton.icon(onPressed: bloqueada ? null : _abrirTurno, icon: const Icon(Icons.play_arrow), label: const Text('Abrir'))
                  : const Chip(label: Text('ABIERTO')),
            ),
          ),
          if (_shiftHistory.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.history),
              title: const Text('Historial de turnos'),
              subtitle: Text('${_shiftHistory.length} turnos recientes'),
              children: [
                for (final shift in _shiftHistory.take(10))
                  ListTile(
                    dense: true,
                    leading: Icon(shift.isOpen ? Icons.lock_open : Icons.lock),
                    title: Text('${shift.userName} · ${shift.status == 'open' ? 'Abierto' : 'Cerrado'}'),
                    subtitle: Text('Apertura ${shift.openedAt.toLocal()}${shift.closedAt == null ? '' : ' · cierre ${shift.closedAt!.toLocal()}'}'),
                    trailing: Text(shift.openingFund.format()),
                  ),
              ],
            ),
          Card(
            child: ListTile(
              leading: Icon(
                bloqueada ? Icons.lock : Icons.point_of_sale,
                color: bloqueada ? Colors.orange : null,
              ),
              title: Text(
                bloqueada
                    ? 'Operacion bloqueada por cierre'
                    : 'Saldo actual del sistema',
              ),
              trailing: Text(
                _fmt(saldoSistema),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (cierres.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay cierres registrados')),
            )
          else
            ...cierres.map((c) {
              final diferencia = MoneyValue.fromSql(
                c['diferencia'],
                currency: _currency,
                nullableAsZero: true,
              ).toMajorUnitsDoubleForDisplay();
              return Card(
                child: ListTile(
                  leading: Icon(
                    diferencia.abs() < 0.01
                        ? Icons.check_circle
                        : Icons.warning,
                    color: diferencia.abs() < 0.01 ? Colors.green : Colors.red,
                  ),
                  title: Text(c['fecha']?.toString() ?? ''),
                  subtitle: Text(c['observacion']?.toString() ?? ''),
                  trailing: Text(
                    'Dif. ${_fmt(diferencia)}',
                    style: TextStyle(
                      color: diferencia.abs() < 0.01
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
