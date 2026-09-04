// lib/sector_publico/contabilidad/pages/provisiones_nicsp_page.dart
//
// Pantalla de Provisiones y Contingencias NICSP 19.
// Conectada directamente a ProvisionesService — ningún botón es decorativo.
// UI → dominio → persistencia → asiento contable → auditoría → resultado.

import 'package:flutter/material.dart';

import '../../../core/currency/public_sector_money.dart';
import '../../../db_helper.dart';
import '../../../numeric_input.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../security/auditoria_service.dart';
import '../services/provisiones_service.dart';

class ProvisionesNICSPPage extends StatefulWidget {
  const ProvisionesNICSPPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  final String entidadId;
  final String usuarioId;

  @override
  State<ProvisionesNICSPPage> createState() => _ProvisionesNICSPPageState();
}

class _ProvisionesNICSPPageState extends State<ProvisionesNICSPPage> {
  ProvisionesService? _svc;
  late Future<List<Map<String, dynamic>>> _provisiones;
  String _filtroEstado = 'activa';

  @override
  void initState() {
    super.initState();
    _provisiones = _init();
  }

  Future<List<Map<String, dynamic>>> _init() async {
    final db = await DatabaseHelper.instance.database;
    _svc = ProvisionesService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );
    return _svc!.consultarProvisiones(
      entidadId: widget.entidadId,
      estado: _filtroEstado == 'todas' ? null : _filtroEstado,
    );
  }

  void _reload() => setState(() => _provisiones = _init());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisiones NICSP 19'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Nueva provisión'),
        onPressed: () => _abrirFormulario(context),
      ),
      body: Column(
        children: [
          // Filtro de estado
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Estado: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _filtroEstado,
                  items: const [
                    DropdownMenuItem(value: 'todas', child: Text('Todas')),
                    DropdownMenuItem(value: 'activa', child: Text('Activas')),
                    DropdownMenuItem(value: 'agotada', child: Text('Agotadas')),
                    DropdownMenuItem(
                        value: 'revertida', child: Text('Revertidas')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _filtroEstado = v);
                      _reload();
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _provisiones,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 56, color: MerkaThemeTokens.graphite600),
                        const SizedBox(height: 12),
                        Text('Sin provisiones $_filtroEstado'),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Crear primera provisión'),
                          onPressed: () => _abrirFormulario(context),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _provisionTile(context, rows[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _provisionTile(BuildContext context, Map<String, dynamic> row) {
    final estado = row['estado']?.toString() ?? 'activa';
    final tipo = row['tipo_provision']?.toString() ?? '';
    final descripcion = row['descripcion']?.toString() ?? '';
    final saldo = publicMoneyForDisplay(publicMoneyFromSql(row['saldo_disponible']));
    final total = publicMoneyForDisplay(publicMoneyFromSql(row['valor_provision']));
    final utilizado = publicMoneyForDisplay(publicMoneyFromSql(row['valor_utilizado']));
    // id se pasa directamente desde row a _ejecutarAccion — no se necesita variable local

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: _estadoAvatar(estado),
        title: Text(
          descripcion,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Tipo: $tipo  |  Total: $total  |  Utilizado: $utilizado  |  Saldo: $saldo',
        ),
        trailing: estado == 'activa'
            ? PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: (action) =>
                    _ejecutarAccion(context, action, row),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'utilizar',
                      child: Text('Utilizar provisión')),
                  PopupMenuItem(
                      value: 'revertir',
                      child: Text('Revertir provisión')),
                ],
              )
            : Chip(
                label: Text(estado,
                    style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
        isThreeLine: false,
      ),
    );
  }

  Widget _estadoAvatar(String estado) => CircleAvatar(
        backgroundColor: switch (estado) {
          'activa' => MerkaThemeTokens.success,
          'agotada' => MerkaThemeTokens.graphite600,
          'revertida' => MerkaThemeTokens.danger,
          _ => MerkaThemeTokens.warning,
        },
        child: Icon(
          switch (estado) {
            'activa' => Icons.check,
            'agotada' => Icons.inventory_2,
            'revertida' => Icons.undo,
            _ => Icons.warning,
          },
          color: Colors.white,
          size: 18,
        ),
      );

  // ── Acciones ──────────────────────────────────────────────────────────────

  Future<void> _ejecutarAccion(
    BuildContext context,
    String action,
    Map<String, dynamic> row,
  ) async {
    if (action == 'utilizar') {
      await _abrirUtilizar(context, row);
    } else if (action == 'revertir') {
      await _confirmarRevertir(context, row);
    }
  }

  Future<void> _abrirUtilizar(
      BuildContext context, Map<String, dynamic> row) async {
    final saldoDisp =
        publicMoneyFromSql(row['saldo_disponible']);
    final montoCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Utilizar provisión'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Saldo disponible: ${publicMoneyForDisplay(saldoDisp)}'),
              const SizedBox(height: 10),
              TextField(
                controller: montoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumericInput.decimal],
                decoration: const InputDecoration(
                  labelText: 'Monto a utilizar *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Utilizar'),
          ),
        ],
      ),
    );
    montoCtrl.dispose();
    motivoCtrl.dispose();
    if (ok != true || _svc == null) return;

    final monto = publicMoneyFromMajor(
        montoCtrl.text.replaceAll(',', '.').trim().isEmpty
            ? '0'
            : montoCtrl.text.replaceAll(',', '.').trim());
    if (monto <= publicMoneyZero()) return;

    try {
      await _svc!.utilizarProvision(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        provisionId: row['id'].toString(),
        valorUtilizar: monto,
        motivo: motivoCtrl.text.trim().isEmpty
            ? 'Sin motivo'
            : motivoCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Provisión utilizada y asiento generado.'),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: MerkaThemeTokens.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmarRevertir(
      BuildContext context, Map<String, dynamic> row) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Revertir provisión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se revertirá el saldo disponible y se generará el asiento contable inverso.'),
            const SizedBox(height: 10),
            TextField(
              controller: motivoCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo de la reversión *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: MerkaThemeTokens.danger),
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Revertir'),
          ),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (ok != true || _svc == null) return;
    try {
      await _svc!.revertirProvision(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        provisionId: row['id'].toString(),
        motivo: motivoCtrl.text.trim().isEmpty
            ? 'Reversión manual'
            : motivoCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Provisión revertida y asiento generado.'),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
              backgroundColor: MerkaThemeTokens.danger),
        );
      }
    }
  }

  // ── Formulario nueva provisión ────────────────────────────────────────────

  Future<void> _abrirFormulario(BuildContext context) async {
    final descCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    TipoProvision tipo = TipoProvision.litigios;
    DateTime? fechaVenc;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Nueva provisión NICSP 19'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<TipoProvision>(
                    value: tipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de provisión *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: TipoProvision.values
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(_tipoLabel(t)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => tipo = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Descripción *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valorCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [NumericInput.decimal],
                    decoration: const InputDecoration(
                      labelText: 'Valor de la provisión *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Referencia documento (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now()
                            .add(const Duration(days: 365)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2040),
                      );
                      if (d != null) setDlg(() => fechaVenc = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha de vencimiento (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon:
                            Icon(Icons.calendar_today, size: 18),
                      ),
                      child: Text(
                        fechaVenc == null
                            ? 'Sin vencimiento'
                            : '${fechaVenc!.day.toString().padLeft(2, '0')}/'
                                '${fechaVenc!.month.toString().padLeft(2, '0')}/'
                                '${fechaVenc!.year}',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlg, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () => Navigator.pop(dlg, true),
              child: const Text('Crear provisión'),
            ),
          ],
        ),
      ),
    );
    descCtrl.dispose();
    valorCtrl.dispose();
    refCtrl.dispose();

    if (ok != true || _svc == null) return;
    final valor = publicMoneyFromMajor(
        valorCtrl.text.replaceAll(',', '.').trim().isEmpty
            ? '0'
            : valorCtrl.text.replaceAll(',', '.').trim());
    if (valor <= publicMoneyZero()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El valor debe ser mayor a cero.'),
            backgroundColor: MerkaThemeTokens.warning,
          ),
        );
      }
      return;
    }
    try {
      await _svc!.crearProvision(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        tipo: tipo,
        descripcion: descCtrl.text.trim().isEmpty
            ? _tipoLabel(tipo)
            : descCtrl.text.trim(),
        valorProvision: valor,
        fechaVencimiento: fechaVenc,
        referenciaDocumento:
            refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Provisión creada. Asiento contable generado automáticamente.'),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: MerkaThemeTokens.danger),
        );
      }
    }
  }

  String _tipoLabel(TipoProvision t) => switch (t) {
        TipoProvision.litigios => 'Litigios',
        TipoProvision.garantias => 'Garantías',
        TipoProvision.beneficiosEmpleados => 'Beneficios a empleados',
        TipoProvision.contratosOnerosos => 'Contratos onerosos',
        TipoProvision.perdidasOperacionales => 'Pérdidas operacionales',
        TipoProvision.otros => 'Otros',
      };
}
