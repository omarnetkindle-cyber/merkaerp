import 'package:flutter/material.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/contabilidad_nicsp_service.dart';
import '../services/cierre_vigencia_service.dart';
import '../services/flujo_efectivo_service.dart';
import '../models/asiento_contable.dart';
import '../models/cuenta_contable.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../../core/currency/money_value.dart';

class ContabilidadNICSPPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final int initialTabIndex;

  const ContabilidadNICSPPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.initialTabIndex = 0,
  });

  @override
  State<ContabilidadNICSPPage> createState() => _ContabilidadNICSPPageState();
}

class _ContabilidadNICSPPageState extends State<ContabilidadNICSPPage> {
  int _selectedIndex = 0;
  bool _loading = true;
  late ContabilidadNICSPService _contabilidadService;
  late CierreVigenciaService _cierreService;
  late FlujoEfectivoService _flujoEfectivoService;
  List<AsientoContable> _asientos = [];
  List<SaldoCuenta> _saldos = [];
  List<Map<String, dynamic>> _planCuentas = [];

  final List<String> _titulos = [
    'Asientos',
    'Saldos',
    'Estados Financieros',
    'Cierre Vigencia',
    'Flujos de Efectivo',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _inicializarServicio();
  }

  Future<void> _inicializarServicio() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoriaService = AuditoriaService(db);
      _contabilidadService = ContabilidadNICSPService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _cierreService = CierreVigenciaService(
        db: db,
        contabilidadService: _contabilidadService,
        auditoriaService: auditoriaService,
      );
      _flujoEfectivoService = FlujoEfectivoService(
        db: db,
        auditoriaService: auditoriaService,
      );

      // Cargar plan de cuentas para los formularios
      _planCuentas = await db.query(
        'plan_cuentas_cgc',
        where: 'entidad_id = ? AND activa = 1',
        whereArgs: [widget.entidadId],
        orderBy: 'codigo_cuenta',
      );

      await _cargarDatos();
    } catch (e) {
      _mostrarError('Error al inicializar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarDatos() async {
    try {
      // 1. Cargar Asientos
      _asientos = await _contabilidadService.consultarAsientos(
        entidadId: widget.entidadId,
      );

      // 2. Cargar Saldos
      final db = await DatabaseHelper.instance.database;
      final saldosResult = await db.query(
        'saldos_cuentas',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'cuenta_codigo',
      );
      _saldos = saldosResult
          .map(
            (r) => SaldoCuenta.fromJson({
              'cuenta_id': r['id'],
              'cuenta_codigo': r['cuenta_codigo'],
              'cuenta_nombre': r['cuenta_nombre'],
              'saldo_deudor': r['saldo_deudor'],
              'saldo_acreedor': r['saldo_acreedor'],
              'saldo_neto': r['saldo_neto'],
              'fecha_ultimo_movimiento': r['fecha_ultimo_movimiento'],
            }),
          )
          .toList();
    } catch (e) {
      _mostrarError('Error al cargar datos: $e');
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  void _mostrarExito(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titulos[_selectedIndex]),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildAsientosTab(),
                _buildSaldosTab(),
                _buildEstadosFinancierosTab(),
                _buildCierreVigenciaTab(),
                _buildFlujosEfectivoTab(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Asientos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance),
            label: 'Saldos',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'EEFF'),
          BottomNavigationBarItem(
            icon: Icon(Icons.lock_clock),
            label: 'Cierre',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.water), label: 'Flujos'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _crearAsientoManual,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildAsientosTab() {
    if (_asientos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay asientos contables registrados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _crearAsientoManual,
              icon: Icon(Icons.add),
              label: const Text('Crear Asiento Manual'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _asientos.length,
      itemBuilder: (context, index) {
        final asiento = _asientos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(asiento.numeroAsiento),
            subtitle: Text(
              '${asiento.descripcion} (${asiento.tipoAsiento.name})',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${publicMoneyForDisplay(asiento.totalDebito)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                Text(
                  DateFormatter.format(asiento.fechaAsiento),
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    const Divider(),
                    ...asiento.detalles.map(
                      (d) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                '${d.cuentaCodigo} - ${d.cuentaNombre}',
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                d.debito > publicMoneyZero()
                                    ? '${publicMoneyForDisplay(d.debito)}'
                                    : '',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: Colors.green),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                d.credito > publicMoneyZero()
                                    ? '${publicMoneyForDisplay(d.credito)}'
                                    : '',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (asiento.observaciones != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Observaciones: ${asiento.observaciones}',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSaldosTab() {
    if (_saldos.isEmpty) {
      return const Center(
        child: Text(
          'No hay saldos registrados. Ejecute transacciones primero.',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _saldos.length,
      itemBuilder: (context, index) {
        final saldo = _saldos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${saldo.cuentaCodigo} - ${saldo.cuentaNombre}'),
            subtitle: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Débito: ${publicMoneyForDisplay(saldo.saldoDeudor)}'),
                Text('Crédito: ${publicMoneyForDisplay(saldo.saldoAcreedor)}'),
              ],
            ),
            trailing: Text(
              '${publicMoneyForDisplay(saldo.saldoNeto)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: saldo.saldoNeto.minorUnits >= 0
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEstadosFinancierosTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              Icons.balance,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Estado de Situación Financiera'),
            subtitle: const Text('Generar balance general (NICSP 1)'),
            trailing: Icon(Icons.chevron_right),
            onTap: _mostrarConfiguracionSituacion,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.trending_up,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Estado de Resultados'),
            subtitle: const Text('Generar resultado operacional (NICSP 1)'),
            trailing: Icon(Icons.chevron_right),
            onTap: _mostrarConfiguracionResultados,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              Icons.payments,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Estado de Flujos de Efectivo'),
            subtitle: const Text('Generar flujos de efectivo (NICSP 2)'),
            trailing: Icon(Icons.chevron_right),
            onTap: _mostrarConfiguracionFlujos,
          ),
        ),
      ],
    );
  }

  Widget _buildCierreVigenciaTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_clock,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            const Text(
              'Cierre Anual de Vigencia',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Esta operación consolidará los saldos, calculará las reservas y generará los asientos contables de cierre y de apertura para la siguiente vigencia de acuerdo con el Art. 89 EOP y las normas NICSP.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _ejecutarCierre,
              icon: Icon(Icons.lock),
              label: const Text('Ejecutar Cierre Presupuestal y Contable'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlujosEfectivoTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.water,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 20),
            const Text(
              'Estado de Flujos de Efectivo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Genere el estado NICSP 2 para un periodo mensual y el metodo seleccionado.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _mostrarConfiguracionFlujoNICSP2,
              icon: const Icon(Icons.assessment),
              label: const Text('Seleccionar periodo y generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarConfiguracionFlujoNICSP2() {
    var anio = DateTime.now().year;
    var mes = DateTime.now().month;
    var metodo = MetodoFlujoEfectivo.directo;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Estado de Flujos de Efectivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: mes,
                decoration: const InputDecoration(labelText: 'Mes'),
                items: List.generate(
                  12,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1}'.padLeft(2, '0')),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) setDialogState(() => mes = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: anio,
                decoration: const InputDecoration(labelText: 'Vigencia'),
                items: List.generate(11, (index) {
                  final value = DateTime.now().year - 5 + index;
                  return DropdownMenuItem(value: value, child: Text('$value'));
                }),
                onChanged: (value) {
                  if (value != null) setDialogState(() => anio = value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<MetodoFlujoEfectivo>(
                initialValue: metodo,
                decoration: const InputDecoration(labelText: 'Metodo'),
                items: const [
                  DropdownMenuItem(
                    value: MetodoFlujoEfectivo.directo,
                    child: Text('Directo'),
                  ),
                  DropdownMenuItem(
                    value: MetodoFlujoEfectivo.indirecto,
                    child: Text('Indirecto'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => metodo = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generarEstadoFlujoNICSP2(
                  periodo: '$anio-${'$mes'.padLeft(2, '0')}',
                  metodo: metodo,
                );
              },
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generarEstadoFlujoNICSP2({
    required String periodo,
    required MetodoFlujoEfectivo metodo,
  }) async {
    setState(() => _loading = true);
    try {
      final estado = await _flujoEfectivoService.generarEstadoFlujosEfectivo(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        periodo: periodo,
        metodo: metodo,
      );
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estado de Flujos de Efectivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Periodo: ${estado['periodo']}'),
              Text('Metodo: ${estado['metodo']}'),
              const Divider(),
              Text(
                'Efectivo inicial: ${publicMoneyForDisplay(estado['efectivo_inicial'] as MoneyValue)}',
              ),
              Text(
                'Operacion: ${publicMoneyForDisplay(estado['actividades_operacion'] as MoneyValue)}',
              ),
              Text(
                'Inversion: ${publicMoneyForDisplay(estado['actividades_inversion'] as MoneyValue)}',
              ),
              Text(
                'Financiacion: ${publicMoneyForDisplay(estado['actividades_financiacion'] as MoneyValue)}',
              ),
              const Divider(),
              Text(
                'Efectivo final: ${publicMoneyForDisplay(estado['efectivo_final'] as MoneyValue)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al generar flujos de efectivo: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _crearAsientoManual() {
    showDialog(
      context: context,
      builder: (context) => _AsientoManualFormDialog(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        planCuentas: _planCuentas,
        contabilidadService: _contabilidadService,
        onSaved: () async {
          setState(() => _loading = true);
          await _cargarDatos();
          setState(() => _loading = false);
          _mostrarExito('Asiento creado correctamente');
        },
      ),
    );
  }

  void _mostrarConfiguracionSituacion() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    DateTime fechaCorte = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Estado Situación Financiera'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: vigenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Vigencia (Año)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fecha de Corte: ${fechaCorte.toString().split(' ')[0]}',
                    ),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: fechaCorte,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            fechaCorte = selected;
                          });
                        }
                      },
                      child: const Text('Seleccionar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _generarEstadoSituacion(vigenciaController.text, fechaCorte);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarEstadoSituacion(String vigencia, DateTime fechaCorte) async {
    setState(() => _loading = true);
    try {
      final esf = await _cierreService.generarEstadoSituacionFinanciera(
        entidadId: widget.entidadId,
        vigencia: vigencia,
        fechaCorte: fechaCorte,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estado Situación Financiera'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Entidad ID: ${esf.entidadId}'),
              Text('Vigencia: ${esf.vigencia}'),
              Text('Fecha Corte: ${esf.fechaCorte.toString().split(' ')[0]}'),
              const Divider(),
              Text('Total Activos: ${publicMoneyForDisplay(esf.totalActivo)}'),
              Text('Total Pasivos: ${publicMoneyForDisplay(esf.totalPasivo)}'),
              Text(
                'Total Patrimonio: ${publicMoneyForDisplay(esf.totalPatrimonio)}',
              ),
              const Divider(),
              Text(
                'Diferencia (Activo - Pasivo - Pat): ${publicMoneyForDisplay((esf.totalActivo - esf.totalPasivo - esf.totalPatrimonio).abs())}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al generar balance: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _mostrarConfiguracionResultados() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    DateTime fechaInicio = DateTime(DateTime.now().year, 1, 1);
    DateTime fechaFin = DateTime(DateTime.now().year, 12, 31);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Estado de Resultados'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: vigenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Vigencia (Año)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Inicio: ${fechaInicio.toString().split(' ')[0]}'),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: fechaInicio,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            fechaInicio = selected;
                          });
                        }
                      },
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Fin: ${fechaFin.toString().split(' ')[0]}'),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: fechaFin,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            fechaFin = selected;
                          });
                        }
                      },
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _generarEstadoResultado(
                    vigenciaController.text,
                    fechaInicio,
                    fechaFin,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarEstadoResultado(
    String vigencia,
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    setState(() => _loading = true);
    try {
      final er = await _cierreService.generarEstadoResultado(
        entidadId: widget.entidadId,
        vigencia: vigencia,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estado de Resultado Operacional'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vigencia: ${er.vigencia}'),
              Text(
                'Periodo: ${er.fechaInicio.toString().split(' ')[0]} a ${er.fechaFin.toString().split(' ')[0]}',
              ),
              const Divider(),
              Text(
                'Ingresos Fiscales: ${publicMoneyForDisplay(er.totalIngresos)}',
              ),
              Text(
                'Gastos de Operación: ${publicMoneyForDisplay(er.totalGastos)}',
              ),
              const Divider(),
              Text(
                'Resultado Operacional: ${publicMoneyForDisplay(er.resultadoOperacional)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: er.resultadoOperacional >= publicMoneyZero()
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al generar estado de resultados: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _mostrarConfiguracionFlujos() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    DateTime fechaInicio = DateTime(DateTime.now().year, 1, 1);
    DateTime fechaFin = DateTime(DateTime.now().year, 12, 31);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Estado de Flujos de Efectivo'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: vigenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Vigencia (Año)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Inicio: ${fechaInicio.toString().split(' ')[0]}'),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: fechaInicio,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            fechaInicio = selected;
                          });
                        }
                      },
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Fin: ${fechaFin.toString().split(' ')[0]}'),
                    TextButton(
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: fechaFin,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setDialogState(() {
                            fechaFin = selected;
                          });
                        }
                      },
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  _generarEstadoFlujos(
                    vigenciaController.text,
                    fechaInicio,
                    fechaFin,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Generar'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarEstadoFlujos(
    String vigencia,
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    setState(() => _loading = true);
    try {
      final efe = await _cierreService.generarEstadoFlujosEfectivo(
        entidadId: widget.entidadId,
        vigencia: vigencia,
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Estado de Flujos de Efectivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Vigencia: ${efe.vigencia}'),
              Text(
                'Periodo: ${efe.fechaInicio.toString().split(' ')[0]} a ${efe.fechaFin.toString().split(' ')[0]}',
              ),
              const Divider(),
              Text(
                'Flujos Operación: ${publicMoneyForDisplay(efe.totalActividadesOperacion)}',
              ),
              Text(
                'Flujos Inversión: ${publicMoneyForDisplay(efe.totalActividadesInversion)}',
              ),
              Text(
                'Flujos Financiación: ${publicMoneyForDisplay(efe.totalActividadesFinanciacion)}',
              ),
              const Divider(),
              Text(
                'Aumento/Disminución Neto: ${publicMoneyForDisplay(efe.variacionNetaEfectivo)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      _mostrarError('Error al generar flujos: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _ejecutarCierre() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: DateTime.now().year.toString(),
    );
    final motivoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Cierre de Vigencia'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: vigenciaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Vigencia (Año)'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: motivoController,
                decoration: const InputDecoration(
                  labelText: 'Motivo / Justificación Legal del Cierre',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'El motivo es obligatorio'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                setState(() => _loading = true);
                try {
                  final resultado = await _cierreService.ejecutarCierreVigencia(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    vigencia: vigenciaController.text,
                    motivo: motivoController.text,
                  );
                  _mostrarExito(
                    'Cierre ejecutado: Reservas ${publicMoneyForDisplay(resultado['reservas'] as MoneyValue)}, '
                    'Cuentas por pagar ${publicMoneyForDisplay(resultado['cuentas_por_pagar'] as MoneyValue)}',
                  );
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al ejecutar cierre: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ejecutar Cierre'),
          ),
        ],
      ),
    );
  }
}

class _AsientoManualFormDialog extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final List<Map<String, dynamic>> planCuentas;
  final ContabilidadNICSPService contabilidadService;
  final VoidCallback onSaved;

  const _AsientoManualFormDialog({
    required this.entidadId,
    required this.usuarioId,
    required this.planCuentas,
    required this.contabilidadService,
    required this.onSaved,
  });

  @override
  State<_AsientoManualFormDialog> createState() =>
      _AsientoManualFormDialogState();
}

class _AsientoManualFormDialogState extends State<_AsientoManualFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _observacionesController = TextEditingController();
  final List<_DetalleRow> _detalles = [];
  DateTime _fechaAsiento = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Iniciar con dos filas vacías por defecto (débito y crédito)
    _agregarFila();
    _agregarFila();
  }

  void _agregarFila() {
    setState(() {
      _detalles.add(
        _DetalleRow(
          cuentaController: TextEditingController(),
          debitoController: TextEditingController(text: '0.0'),
          creditoController: TextEditingController(text: '0.0'),
        ),
      );
    });
  }

  void _eliminarFila(int index) {
    if (_detalles.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Un asiento requiere mínimo 2 registros')),
      );
      return;
    }
    setState(() {
      _detalles.removeAt(index);
    });
  }

  MoneyValue get _totalDebitos {
    return _detalles.fold<MoneyValue>(publicMoneyZero(), (sum, row) {
      final val = row.debitoController.text.trim().isEmpty
          ? publicMoneyZero()
          : publicMoneyFromMajor(row.debitoController.text);
      return sum + val;
    });
  }

  MoneyValue get _totalCreditos {
    return _detalles.fold<MoneyValue>(publicMoneyZero(), (sum, row) {
      final val = row.creditoController.text.trim().isEmpty
          ? publicMoneyZero()
          : publicMoneyFromMajor(row.creditoController.text);
      return sum + val;
    });
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    if (_totalDebitos != _totalCreditos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El asiento no está cuadrado. '
            'Débitos: ${publicMoneyForDisplay(_totalDebitos)} | '
            'Créditos: ${publicMoneyForDisplay(_totalCreditos)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final detallesAsiento = _detalles.map((row) {
        // Encontrar cuenta en el plan
        final cuenta = widget.planCuentas.firstWhere(
          (c) => c['codigo_cuenta'] == row.cuentaController.text,
        );

        return DetalleAsiento(
          id: '', // Se genera en el servicio
          cuentaCodigo: cuenta['codigo_cuenta'] as String,
          cuentaNombre: cuenta['nombre_cuenta'] as String,
          debito: publicMoneyFromMajor(row.debitoController.text),
          credito: publicMoneyFromMajor(row.creditoController.text),
        );
      }).toList();

      await widget.contabilidadService.crearAsientoManual(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        fechaAsiento: _fechaAsiento,
        descripcion: _descripcionController.text,
        detalles: detallesAsiento,
        observaciones: _observacionesController.text.isEmpty
            ? null
            : _observacionesController.text,
      );

      widget.onSaved();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Crear Asiento Manual'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Concepto',
                  ),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Requerido' : null,
                ),
                TextFormField(
                  controller: _observacionesController,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones (Opcional)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Fecha de Asiento: ${_fechaAsiento.toString().split(' ')[0]}',
                    ),
                    TextButton.icon(
                      icon: Icon(Icons.calendar_month),
                      label: const Text('Seleccionar'),
                      onPressed: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: _fechaAsiento,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) {
                          setState(() {
                            _fechaAsiento = selected;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Detalle de Asiento (Partida Doble)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Divider(),
                ...List.generate(_detalles.length, (index) {
                  final row = _detalles[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            initialValue: row.cuentaController.text.isEmpty
                                ? null
                                : row.cuentaController.text,
                            decoration: const InputDecoration(
                              labelText: 'Cuenta',
                            ),
                            items: widget.planCuentas.map((c) {
                              return DropdownMenuItem<String>(
                                value: c['codigo_cuenta'] as String,
                                child: Text(
                                  '${c['codigo_cuenta']} - ${c['nombre_cuenta']}',
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              setState(() {
                                row.cuentaController.text = val ?? '';
                              });
                            },
                            validator: (value) =>
                                value == null ? 'Requerido' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: row.debitoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Débito',
                            ),
                            onChanged: (val) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: row.creditoController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Crédito',
                            ),
                            onChanged: (val) => setState(() {}),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Eliminar fila',
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarFila(index),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _agregarFila,
                  icon: Icon(Icons.add),
                  label: const Text('Agregar Fila'),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Débitos: ${publicMoneyForDisplay(_totalDebitos)}',
                    ),
                    Text(
                      'Total Créditos: ${publicMoneyForDisplay(_totalCreditos)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardar,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _DetalleRow {
  final TextEditingController cuentaController;
  final TextEditingController debitoController;
  final TextEditingController creditoController;

  _DetalleRow({
    required this.cuentaController,
    required this.debitoController,
    required this.creditoController,
  });
}
