// lib/sector_publico/rentas_departamentales/pages/rentas_departamentales_page.dart
//
// Interfaz de Rentas Departamentales conectada a RentasDepartamentalesService.
// Cubre: contribuyentes, declaraciones, pagos y reporte de recaudo.
// Antes, el módulo abría PredialICAPage — circuito equivocado y completamente
// desconectado del servicio.

import 'package:flutter/material.dart';

import '../../../core/currency/public_sector_money.dart';
import '../../../db_helper.dart';
import '../../../numeric_input.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../security/auditoria_service.dart';
import '../services/rentas_departamentales_service.dart';

class RentasDepartamentalesPage extends StatefulWidget {
  const RentasDepartamentalesPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  final String entidadId;
  final String usuarioId;

  @override
  State<RentasDepartamentalesPage> createState() =>
      _RentasDepartamentalesPageState();
}

class _RentasDepartamentalesPageState extends State<RentasDepartamentalesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  RentasDepartamentalesService? _svc;
  late Future<List<Map<String, dynamic>>> _contribuyentes;
  late Future<List<Map<String, dynamic>>> _declaraciones;

  @override
  void initState() {
    super.initState();
    _contribuyentes = _init();
    _declaraciones = _loadDeclaraciones();
  }

  Future<List<Map<String, dynamic>>> _init() async {
    final db = await DatabaseHelper.instance.database;
    _svc = RentasDepartamentalesService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );
    return _svc!.consultarContribuyentes(entidadId: widget.entidadId);
  }

  Future<List<Map<String, dynamic>>> _loadDeclaraciones() async {
    if (_svc == null) await _init();
    return _svc!.consultarDeclaraciones(entidadId: widget.entidadId);
  }

  void _reload() {
    setState(() {
      _contribuyentes = _init();
      _declaraciones = _loadDeclaraciones();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Rentas Departamentales'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Contribuyentes'),
          Tab(text: 'Declaraciones'),
          Tab(text: 'Reporte de recaudo'),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
      ],
    ),
    body: TabBarView(
      controller: _tabs,
      children: [_tabContribuyentes(), _tabDeclaraciones(), _tabReporte()],
    ),
  );

  // ── Tab contribuyentes ────────────────────────────────────────────────────

  Widget _tabContribuyentes() {
    return Stack(
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _contribuyentes,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('${snapshot.error}'));
            }
            final rows = snapshot.data ?? const [];
            if (rows.isEmpty) {
              return const Center(
                child: Text('Sin contribuyentes registrados.'),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.business, size: 18),
                    ),
                    title: Text(row['razon_social']?.toString() ?? '-'),
                    subtitle: Text(
                      'NIT: ${row['nit']}  |  '
                      '${_tipoLabel(row['tipo_impuesto'])}  |  '
                      '${row['municipio']}',
                    ),
                    trailing: Chip(
                      label: Text(row['estado']?.toString() ?? '-'),
                    ),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            heroTag: 'rd_contribuyente',
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Nuevo contribuyente'),
            onPressed: _abrirNuevoContribuyente,
          ),
        ),
      ],
    );
  }

  // ── Tab declaraciones ─────────────────────────────────────────────────────

  Widget _tabDeclaraciones() {
    return Stack(
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _declaraciones,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('${snap.error}'));
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return const Center(child: Text('Sin declaraciones.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final impuesto = publicMoneyForDisplay(
                  publicMoneyFromSql(row['impuesto']),
                );
                final estado = row['estado']?.toString() ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _estadoAvatar(estado),
                    title: Text(
                      '${_tipoLabel(row['tipo_impuesto'])} — '
                      '${row['periodo']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('Impuesto: $impuesto'),
                    trailing: estado == 'pendiente_pago'
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.payment, size: 16),
                            label: const Text('Registrar pago'),
                            onPressed: () => _abrirRegistrarPago(row),
                          )
                        : Chip(
                            label: Text(
                              estado,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            heroTag: 'rd_declaracion',
            icon: const Icon(Icons.description_outlined),
            label: const Text('Nueva declaración'),
            onPressed: _abrirNuevaDeclaracion,
          ),
        ),
      ],
    );
  }

  // ── Tab reporte ───────────────────────────────────────────────────────────

  Widget _tabReporte() {
    final periodoCtrl = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );
    return StatefulBuilder(
      builder: (context, setInner) {
        Map<String, dynamic>? reporte;
        bool loading = false;
        String? error;

        Future<void> cargar() async {
          if (_svc == null) return;
          setInner(() => loading = true);
          try {
            final r = await _svc!.generarReporteRecaudo(
              entidadId: widget.entidadId,
              periodo: periodoCtrl.text.trim(),
            );
            setInner(() {
              reporte = r;
              loading = false;
              error = null;
            });
          } catch (e) {
            setInner(() {
              error = e.toString();
              loading = false;
            });
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: periodoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Período (YYYY-MM)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    icon: const Icon(Icons.query_stats, size: 16),
                    label: const Text('Generar'),
                    onPressed: cargar,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (loading)
                const Center(child: CircularProgressIndicator())
              else if (error != null)
                Text(
                  error!,
                  style: const TextStyle(color: MerkaThemeTokens.danger),
                )
              else if (reporte == null)
                const Text(
                  'Ingresa el período y presiona "Generar".',
                  style: TextStyle(color: MerkaThemeTokens.graphite600),
                )
              else
                _buildReporte(reporte!),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReporte(Map<String, dynamic> r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card('Total declarado', r['total_declarado']?.toString() ?? '-'),
        _card('Total recaudado', r['total_recaudado']?.toString() ?? '-'),
        _card('Saldo pendiente', r['saldo_pendiente']?.toString() ?? '-'),
        _card(
          '% de recaudo',
          '${(r['porcentaje_recaudo'] as num?)?.toStringAsFixed(1) ?? '0'}%',
        ),
        const SizedBox(height: 12),
        if (r['por_tipo'] is Map) ...[
          const Text(
            'Por tipo de impuesto',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...(r['por_tipo'] as Map).entries.map(
            (e) => _card(_tipoLabel(e.key.toString()), e.value.toString()),
          ),
        ],
      ],
    );
  }

  Widget _card(String label, String value) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ),
  );

  // ── Formularios ───────────────────────────────────────────────────────────

  Future<void> _abrirNuevoContribuyente() async {
    final nitCtrl = TextEditingController();
    final razonCtrl = TextEditingController();
    final dirCtrl = TextEditingController();
    final munCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    TipoImpuestoDepartamental tipo =
        TipoImpuestoDepartamental.impuestoAlConsumo;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Nuevo contribuyente'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tf('NIT / Identificación *', nitCtrl),
                  _tf('Razón social *', razonCtrl),
                  _tf('Dirección', dirCtrl),
                  _tf('Municipio *', munCtrl),
                  _tf(
                    'Correo electrónico',
                    emailCtrl,
                    type: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TipoImpuestoDepartamental>(
                    value: tipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de impuesto *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: TipoImpuestoDepartamental.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(_tipoLabel(t.toString())),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => tipo = v);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dlg, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    for (final c in [nitCtrl, razonCtrl, dirCtrl, munCtrl, emailCtrl]) {
      c.dispose();
    }
    if (ok != true || _svc == null) return;
    try {
      await _svc!.registrarContribuyente(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        nit: nitCtrl.text.trim(),
        razonSocial: razonCtrl.text.trim(),
        direccion: dirCtrl.text.trim(),
        municipio: munCtrl.text.trim(),
        tipoImpuesto: tipo,
        email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contribuyente registrado.'),
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

  Future<void> _abrirNuevaDeclaracion() async {
    final contribs =
        await _svc?.consultarContribuyentes(entidadId: widget.entidadId) ??
        const [];
    if (contribs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Registra al menos un contribuyente antes de generar una declaración.',
            ),
            backgroundColor: MerkaThemeTokens.warning,
          ),
        );
      }
      return;
    }

    String contribId = contribs.first['id'].toString();
    final periodoCtrl = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );
    final baseCtrl = TextEditingController();
    final noGravCtrl = TextEditingController(text: '0');
    final exentCtrl = TextEditingController(text: '0');
    TipoImpuestoDepartamental tipo =
        TipoImpuestoDepartamental.impuestoAlConsumo;

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Nueva declaración'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: contribId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Contribuyente *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: contribs
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id'].toString(),
                            child: Text(
                              c['razon_social'].toString(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => contribId = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TipoImpuestoDepartamental>(
                    value: tipo,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de impuesto *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: TipoImpuestoDepartamental.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(_tipoLabel(t.toString())),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlg(() => tipo = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  _tf('Período (YYYY-MM) *', periodoCtrl),
                  _tf(
                    'Ingresos gravables *',
                    baseCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _tf(
                    'Ingresos no gravables',
                    noGravCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  _tf(
                    'Ingresos exentos',
                    exentCtrl,
                    type: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlg, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dlg, true),
              child: const Text('Generar declaración'),
            ),
          ],
        ),
      ),
    );
    for (final c in [periodoCtrl, baseCtrl, noGravCtrl, exentCtrl]) {
      c.dispose();
    }
    if (ok != true || _svc == null) return;
    try {
      await _svc!.generarDeclaracion(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        contribuyenteId: contribId,
        tipoImpuesto: tipo,
        periodo: periodoCtrl.text.trim(),
        baseGravable: publicMoneyFromMajor(
          baseCtrl.text.replaceAll(',', '.').trim().isEmpty
              ? '0'
              : baseCtrl.text.replaceAll(',', '.').trim(),
        ),
        ingresosNoGravables: publicMoneyFromMajor(
          noGravCtrl.text.replaceAll(',', '.').trim().isEmpty
              ? '0'
              : noGravCtrl.text.replaceAll(',', '.').trim(),
        ),
        ingresosExentos: publicMoneyFromMajor(
          exentCtrl.text.replaceAll(',', '.').trim().isEmpty
              ? '0'
              : exentCtrl.text.replaceAll(',', '.').trim(),
        ),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Declaración generada.'),
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

  Future<void> _abrirRegistrarPago(Map<String, dynamic> declaracion) async {
    final montoCtrl = TextEditingController();
    final refCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Registrar pago'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Impuesto declarado: '
                '${publicMoneyForDisplay(publicMoneyFromSql(declaracion['impuesto']))}',
              ),
              const SizedBox(height: 10),
              _tf(
                'Valor pagado *',
                montoCtrl,
                type: const TextInputType.numberWithOptions(decimal: true),
              ),
              _tf('Referencia de pago *', refCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    montoCtrl.dispose();
    refCtrl.dispose();
    if (ok != true || _svc == null) return;
    try {
      await _svc!.registrarPago(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        declaracionId: declaracion['id'].toString(),
        valorPagado: publicMoneyFromMajor(
          montoCtrl.text.replaceAll(',', '.').trim().isEmpty
              ? '0'
              : montoCtrl.text.replaceAll(',', '.').trim(),
        ),
        fechaPago: DateTime.now(),
        referenciaPago: refCtrl.text.trim().isEmpty
            ? 'S/R'
            : refCtrl.text.trim(),
      );
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago registrado.'),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _tf(
    String label,
    TextEditingController ctrl, {
    TextInputType type = TextInputType.text,
  }) => Padding(
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

  Widget _estadoAvatar(String estado) => CircleAvatar(
    backgroundColor: switch (estado) {
      'pagado' => MerkaThemeTokens.success,
      'parcialmente_pagado' => MerkaThemeTokens.warning,
      _ => MerkaThemeTokens.danger,
    },
    child: Icon(
      switch (estado) {
        'pagado' => Icons.check,
        'parcialmente_pagado' => Icons.hourglass_top,
        _ => Icons.pending,
      },
      color: Colors.white,
      size: 18,
    ),
  );

  String _tipoLabel(String key) => switch (key) {
    'impuestoAlConsumo' => 'Consumo (8%)',
    'impuestoAlJuegos' => 'Juegos (15%)',
    'impuestoTasaUsoAeroportuario' => 'Uso aeroportuario (4%)',
    'impuestoDegradacion' => 'Degradación (2%)',
    _ => key,
  };
}
