// lib/hrm/payroll/pages/payroll_parameters_panel.dart
//
// Panel de gestión de parámetros legales de nómina (SMMLV, auxilio, UVT,
// tasas de aportes). Versionado por vigencia/año. RBAC: solo admin/nómina.
// Se embebe dentro del tab de Nómina en HRM.

import 'package:flutter/material.dart';

import '../../../app_session.dart';
import '../../../core/security/action_permission.dart';
import '../../../db_helper.dart';
import '../../../numeric_input.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../application/payroll_parameters_service.dart';

/// Widget que muestra y permite editar los parámetros de nómina por vigencia.
class PayrollParametersPanel extends StatefulWidget {
  const PayrollParametersPanel({super.key});

  @override
  State<PayrollParametersPanel> createState() => _PayrollParametersPanelState();
}

class _PayrollParametersPanelState extends State<PayrollParametersPanel> {
  final _svc = PayrollParametersService.instance;
  late Future<_PanelData> _loading;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loading = _load();
  }

  Future<_PanelData> _load() async {
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final configuredYears = await _svc.configuredYears(companyId);
    final params = await _svc.find(companyId, _selectedYear);
    return _PanelData(
      companyId: companyId,
      configuredYears: configuredYears,
      params: params,
    );
  }

  void _reload() => setState(() => _loading = _load());

  @override
  Widget build(BuildContext context) {
    final canEdit = AppSession.puedeEjecutarAccion('hrm', AppAction.configure);
    return FutureBuilder<_PanelData>(
      future: _loading,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error al cargar parámetros: ${snapshot.error}'));
        }
        final data = snapshot.data!;
        return _buildContent(context, data, canEdit);
      },
    );
  }

  Widget _buildContent(BuildContext context, _PanelData data, bool canEdit) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Selector de vigencia
        Row(
          children: [
            const Text(
              'Parámetros de nómina',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (canEdit) ...[
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Nueva vigencia'),
                onPressed: () => _openEditor(context, data.companyId, null, null),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Chips de años configurados
        if (data.configuredYears.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            children: data.configuredYears.map((year) {
              final isSelected = year == _selectedYear;
              return ChoiceChip(
                label: Text('$year'),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedYear = year);
                  _reload();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        // Contenido del año seleccionado
        if (data.params == null)
          _noParamsCard(context, data.companyId)
        else
          _paramsCard(context, data),
      ],
    );
  }

  Widget _noParamsCard(BuildContext context, int companyId) {
    final officialSeed = PayrollParametersService.officialSeed(_selectedYear);
    return Card(
      color: MerkaThemeTokens.warning.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: MerkaThemeTokens.warning, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No existen parámetros de nómina para $_selectedYear.',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Para liquidar la nómina de $_selectedYear primero debes '
              'configurar los parámetros de esa vigencia.',
              style: const TextStyle(color: MerkaThemeTokens.graphite600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (officialSeed != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: Text('Cargar valores oficiales $_selectedYear'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MerkaThemeTokens.success,
                    ),
                    onPressed: () async {
                      await _svc.seedOfficialIfAbsent(companyId, _selectedYear);
                      _reload();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Parámetros oficiales $_selectedYear cargados. '
                            'Verifica y ajusta antes de liquidar.',
                          ),
                          backgroundColor: MerkaThemeTokens.success,
                        ),
                      );
                    },
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Configurar manualmente'),
                  onPressed: () =>
                      _openEditor(context, companyId, _selectedYear, null),
                ),
              ],
            ),
            if (officialSeed != null) ...[
              const SizedBox(height: 8),
              Text(
                'Fuente: Decretos 1469/1470 de 2025 (SMMLV/Auxilio) '
                'y Resolución DIAN 000238/2025 (UVT).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paramsCard(BuildContext context, _PanelData data) {
    final p = data.params!;
    final canEdit = AppSession.puedeEjecutarAccion('hrm', AppAction.configure);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined,
                    color: MerkaThemeTokens.success, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Vigencia $_selectedYear',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (canEdit)
                  IconButton(
                    tooltip: 'Editar parámetros',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        _openEditor(context, data.companyId, _selectedYear, p),
                  ),
              ],
            ),
            const Divider(),
            _paramGroup('Valores monetarios (COP)', [
              _row('SMMLV', _fmtCop(p['smmlv']),
                  'Decreto 1469/2025'),
              _row('Auxilio de transporte', _fmtCop(p['transportation_allowance']),
                  'Decreto 1470/2025'),
              _row('UVT', _fmtCop(p['uvt']),
                  'Resolución DIAN 000238/2025'),
            ]),
            _paramGroup('Salud (% del IBC)', [
              _row('Aporte trabajador', _fmtPct(p['health_employee_rate'])),
              _row('Aporte empleador', _fmtPct(p['health_employer_rate'])),
              _row('Exonerado de parafiscales',
                  p['health_exonerated'] == 1 ? 'Sí (Ley 1607)' : 'No'),
            ]),
            _paramGroup('Pensión (% del IBC)', [
              _row('Aporte trabajador', _fmtPct(p['pension_employee_rate'])),
              _row('Aporte empleador', _fmtPct(p['pension_employer_rate'])),
              _row('Disparo FSP (× SMMLV)',
                  '${p['fsp_trigger_smmlv']}×'),
            ]),
            _paramGroup('ARL (% por clase de riesgo)', [
              _row('Clase I', _fmtPct(p['arl_level_1_rate'])),
              _row('Clase II', _fmtPct(p['arl_level_2_rate'])),
              _row('Clase III', _fmtPct(p['arl_level_3_rate'])),
              _row('Clase IV', _fmtPct(p['arl_level_4_rate'])),
              _row('Clase V', _fmtPct(p['arl_level_5_rate'])),
            ]),
            _paramGroup('Parafiscales (% del IBC)', [
              _row('SENA', _fmtPct(p['parafiscal_sena_rate'])),
              _row('ICBF', _fmtPct(p['parafiscal_icbf_rate'])),
              _row('Caja de compensación', _fmtPct(p['parafiscal_caja_rate'])),
            ]),
            _paramGroup('Prestaciones sociales', [
              _row('Cesantías', _fmtPct(p['severance_rate'])),
              _row('Intereses cesantías', _fmtPct(p['severance_interest_rate'])),
              _row('Prima de servicios', _fmtPct(p['service_bonus_rate'])),
              _row('Vacaciones', _fmtPct(p['vacation_rate'])),
            ]),
            if ((p['updated_at'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Última actualización: ${p['updated_at']?.toString().substring(0, 10) ?? '-'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paramGroup(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: MerkaThemeTokens.navy700)),
      ...rows,
    ],
  );

  Widget _row(String label, String value, [String? hint]) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label,
              style: const TextStyle(color: MerkaThemeTokens.graphite600)),
        ),
        Expanded(
          flex: 2,
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        if (hint != null)
          Flexible(
            child: Text(hint,
                style: Theme.of(context as BuildContext? ?? context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: MerkaThemeTokens.graphite600)),
          ),
      ],
    ),
  );

  String _fmtCop(Object? v) {
    if (v == null) return '-';
    final n = (v as num).toInt();
    // Formato simple COP sin importar locale.
    final s = n.toString();
    final buffer = StringBuffer('\$');
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  String _fmtPct(Object? v) {
    if (v == null) return '-';
    final d = (v as num).toDouble();
    return '${(d * 100).toStringAsFixed(d * 100 == (d * 100).roundToDouble() ? 0 : 3)}%';
  }

  // ── Editor de parámetros ───────────────────────────────────────────────────

  Future<void> _openEditor(
    BuildContext context,
    int companyId,
    int? initialYear,
    Map<String, dynamic>? existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _PayrollParametersEditor(
        companyId: companyId,
        initialYear: initialYear ?? _selectedYear,
        existing: existing,
        service: _svc,
      ),
    );
    if (saved == true) {
      _reload();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diálogo editor de parámetros
// ─────────────────────────────────────────────────────────────────────────────
class _PayrollParametersEditor extends StatefulWidget {
  const _PayrollParametersEditor({
    required this.companyId,
    required this.initialYear,
    required this.existing,
    required this.service,
  });

  final int companyId;
  final int initialYear;
  final Map<String, dynamic>? existing;
  final PayrollParametersService service;

  @override
  State<_PayrollParametersEditor> createState() =>
      _PayrollParametersEditorState();
}

class _PayrollParametersEditorState extends State<_PayrollParametersEditor> {
  late int _year;
  late final TextEditingController _smmlvCtrl;
  late final TextEditingController _auxCtrl;
  late final TextEditingController _uvtCtrl;
  late final TextEditingController _healthEmpCtrl;
  late final TextEditingController _healthEmrCtrl;
  late bool _healthExonerated;
  late final TextEditingController _penEmpCtrl;
  late final TextEditingController _penEmrCtrl;
  late final TextEditingController _fspTrigCtrl;
  late final TextEditingController _arlL1Ctrl;
  late final TextEditingController _arlL2Ctrl;
  late final TextEditingController _arlL3Ctrl;
  late final TextEditingController _arlL4Ctrl;
  late final TextEditingController _arlL5Ctrl;
  late final TextEditingController _senaCtrl;
  late final TextEditingController _icbfCtrl;
  late final TextEditingController _cajaCtrl;
  late final TextEditingController _sevCtrl;
  late final TextEditingController _sevIntCtrl;
  late final TextEditingController _bonusCtrl;
  late final TextEditingController _vacCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _year = widget.initialYear;
    _smmlvCtrl = TextEditingController(
        text: _cop(p?['smmlv'] ?? _kSeedFor(_year)?['smmlv']));
    _auxCtrl = TextEditingController(
        text: _cop(p?['transportation_allowance'] ??
            _kSeedFor(_year)?['transportation_allowance']));
    _uvtCtrl = TextEditingController(
        text: _cop(p?['uvt'] ?? _kSeedFor(_year)?['uvt']));
    _healthEmpCtrl = TextEditingController(
        text: _pct(p?['health_employee_rate'] ??
            _kSeedFor(_year)?['health_employee_rate']));
    _healthEmrCtrl = TextEditingController(
        text: _pct(p?['health_employer_rate'] ??
            _kSeedFor(_year)?['health_employer_rate']));
    _healthExonerated = (p?['health_exonerated'] ?? 0) == 1;
    _penEmpCtrl = TextEditingController(
        text: _pct(p?['pension_employee_rate'] ??
            _kSeedFor(_year)?['pension_employee_rate']));
    _penEmrCtrl = TextEditingController(
        text: _pct(p?['pension_employer_rate'] ??
            _kSeedFor(_year)?['pension_employer_rate']));
    _fspTrigCtrl = TextEditingController(
        text: (p?['fsp_trigger_smmlv'] ?? 4.0).toString());
    _arlL1Ctrl = TextEditingController(
        text: _pct(p?['arl_level_1_rate'] ??
            _kSeedFor(_year)?['arl_level_1_rate']));
    _arlL2Ctrl = TextEditingController(
        text: _pct(p?['arl_level_2_rate'] ??
            _kSeedFor(_year)?['arl_level_2_rate']));
    _arlL3Ctrl = TextEditingController(
        text: _pct(p?['arl_level_3_rate'] ??
            _kSeedFor(_year)?['arl_level_3_rate']));
    _arlL4Ctrl = TextEditingController(
        text: _pct(p?['arl_level_4_rate'] ??
            _kSeedFor(_year)?['arl_level_4_rate']));
    _arlL5Ctrl = TextEditingController(
        text: _pct(p?['arl_level_5_rate'] ??
            _kSeedFor(_year)?['arl_level_5_rate']));
    _senaCtrl = TextEditingController(
        text: _pct(p?['parafiscal_sena_rate'] ??
            _kSeedFor(_year)?['parafiscal_sena_rate']));
    _icbfCtrl = TextEditingController(
        text: _pct(p?['parafiscal_icbf_rate'] ??
            _kSeedFor(_year)?['parafiscal_icbf_rate']));
    _cajaCtrl = TextEditingController(
        text: _pct(p?['parafiscal_caja_rate'] ??
            _kSeedFor(_year)?['parafiscal_caja_rate']));
    _sevCtrl = TextEditingController(
        text: _pct(p?['severance_rate'] ??
            _kSeedFor(_year)?['severance_rate']));
    _sevIntCtrl = TextEditingController(
        text: _pct(p?['severance_interest_rate'] ??
            _kSeedFor(_year)?['severance_interest_rate']));
    _bonusCtrl = TextEditingController(
        text: _pct(p?['service_bonus_rate'] ??
            _kSeedFor(_year)?['service_bonus_rate']));
    _vacCtrl = TextEditingController(
        text: _pct(p?['vacation_rate'] ?? _kSeedFor(_year)?['vacation_rate']));
  }

  Map<String, Object>? _kSeedFor(int year) =>
      PayrollParametersService.officialSeed(year);

  String _cop(Object? v) => v == null ? '' : (v as num).toInt().toString();
  String _pct(Object? v) {
    if (v == null) return '';
    final d = (v as num).toDouble();
    // Mostrar como porcentaje (0.04 → "4")
    return (d * 100).toStringAsFixed(
        (d * 100 == (d * 100).roundToDouble()) ? 1 : 4);
  }

  int _parseCop(String s) =>
      int.tryParse(s.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;
  double _parsePct(String s) =>
      (double.tryParse(s.replaceAll(',', '.').trim()) ?? 0) / 100;

  @override
  void dispose() {
    for (final c in [
      _smmlvCtrl, _auxCtrl, _uvtCtrl, _healthEmpCtrl, _healthEmrCtrl,
      _penEmpCtrl, _penEmrCtrl, _fspTrigCtrl,
      _arlL1Ctrl, _arlL2Ctrl, _arlL3Ctrl, _arlL4Ctrl, _arlL5Ctrl,
      _senaCtrl, _icbfCtrl, _cajaCtrl,
      _sevCtrl, _sevIntCtrl, _bonusCtrl, _vacCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Nuevos parámetros de nómina'
          : 'Editar parámetros de nómina'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vigencia
              if (widget.existing == null) ...[
                TextFormField(
                  initialValue: '$_year',
                  keyboardType: TextInputType.number,
                  inputFormatters: [NumericInput.integer],
                  decoration: const InputDecoration(
                    labelText: 'Año / Vigencia *',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _year = int.tryParse(v) ?? _year,
                ),
                const SizedBox(height: 12),
              ],
              // Valores monetarios
              _section('Valores monetarios (COP enteros)'),
              _field('SMMLV *', _smmlvCtrl,
                  hint: 'Decreto 1469/2025: \$1.750.905'),
              _field('Auxilio de transporte *', _auxCtrl,
                  hint: 'Decreto 1470/2025: \$249.095'),
              _field('UVT *', _uvtCtrl,
                  hint: 'Resolución DIAN 000238/2025: \$52.374'),
              // Salud
              _section('Salud (ingresa % — ej.: 4 para el 4%)'),
              _field('Aporte salud trabajador % *', _healthEmpCtrl),
              _field('Aporte salud empleador % *', _healthEmrCtrl),
              SwitchListTile(
                title: const Text('Exonerado de parafiscales (Ley 1607)'),
                subtitle: const Text(
                    'Solo aplica a empleadores con ≥2 empleados y salario < 10 SMMLV'),
                value: _healthExonerated,
                onChanged: (v) => setState(() => _healthExonerated = v),
                dense: true,
              ),
              // Pensión
              _section('Pensión (ingresa % — ej.: 4 para el 4%)'),
              _field('Aporte pensión trabajador % *', _penEmpCtrl),
              _field('Aporte pensión empleador % *', _penEmrCtrl),
              _field('Disparo FSP (× SMMLV)', _fspTrigCtrl,
                  hint: 'Default 4 (= 4 SMMLV)'),
              // ARL
              _section(
                  'ARL por clase de riesgo (ingresa % — ej.: 0.522 para Clase I)'),
              _field('Clase I %', _arlL1Ctrl),
              _field('Clase II %', _arlL2Ctrl),
              _field('Clase III %', _arlL3Ctrl),
              _field('Clase IV %', _arlL4Ctrl),
              _field('Clase V %', _arlL5Ctrl),
              // Parafiscales
              _section('Parafiscales (ingresa %)'),
              _field('SENA %', _senaCtrl),
              _field('ICBF %', _icbfCtrl),
              _field('Caja de compensación %', _cajaCtrl),
              // Prestaciones
              _section('Prestaciones (ingresa %)'),
              _field('Cesantías %', _sevCtrl,
                  hint: 'Default 8.33 (=1/12)'),
              _field('Intereses de cesantías %', _sevIntCtrl,
                  hint: 'Default 1'),
              _field('Prima de servicios %', _bonusCtrl,
                  hint: 'Default 8.33 (=1/12)'),
              _field('Vacaciones %', _vacCtrl,
                  hint: 'Default 4.17 (=1/24)'),
              const SizedBox(height: 8),
              Text(
                'Los porcentajes usan la base estipulada legalmente '
                '(IBC, IBL, salario, según el concepto). '
                'Consúltalos con tu asesor laboral si tienes dudas.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(label,
        style: const TextStyle(
            fontWeight: FontWeight.w600, color: MerkaThemeTokens.navy700)),
  );

  Widget _field(String label, TextEditingController ctrl, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [NumericInput.decimal],
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Future<void> _save() async {
    final smmlv = _parseCop(_smmlvCtrl.text);
    final aux = _parseCop(_auxCtrl.text);
    final uvt = _parseCop(_uvtCtrl.text);
    if (smmlv <= 0 || uvt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMMLV y UVT son obligatorios y deben ser > 0.'),
          backgroundColor: MerkaThemeTokens.danger,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.save(
        companyId: widget.companyId,
        year: _year,
        smmlv: smmlv,
        transportationAllowance: aux,
        uvt: uvt,
        healthEmployeeRate: _parsePct(_healthEmpCtrl.text),
        healthEmployerRate: _parsePct(_healthEmrCtrl.text),
        healthExonerated: _healthExonerated,
        pensionEmployeeRate: _parsePct(_penEmpCtrl.text),
        pensionEmployerRate: _parsePct(_penEmrCtrl.text),
        fspTriggerSmmlv:
            double.tryParse(_fspTrigCtrl.text.replaceAll(',', '.')) ?? 4.0,
        arlLevel1Rate: _parsePct(_arlL1Ctrl.text),
        arlLevel2Rate: _parsePct(_arlL2Ctrl.text),
        arlLevel3Rate: _parsePct(_arlL3Ctrl.text),
        arlLevel4Rate: _parsePct(_arlL4Ctrl.text),
        arlLevel5Rate: _parsePct(_arlL5Ctrl.text),
        parafiscalSenaRate: _parsePct(_senaCtrl.text),
        parafiscalIcbfRate: _parsePct(_icbfCtrl.text),
        parafiscalCajaRate: _parsePct(_cajaCtrl.text),
        severanceRate: _parsePct(_sevCtrl.text),
        serviceBonusRate: _parsePct(_bonusCtrl.text),
        severanceInterestRate: _parsePct(_sevIntCtrl.text),
        vacationRate: _parsePct(_vacCtrl.text),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar: $e'),
          backgroundColor: MerkaThemeTokens.danger,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _PanelData {
  const _PanelData({
    required this.companyId,
    required this.configuredYears,
    required this.params,
  });
  final int companyId;
  final List<int> configuredYears;
  final Map<String, dynamic>? params;
}
