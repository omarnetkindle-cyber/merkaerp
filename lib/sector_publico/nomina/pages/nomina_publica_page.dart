import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/nomina_service.dart';
import '../services/pila_service.dart';
import '../services/retroactivos_service.dart';
import '../services/horas_extra_service.dart';
import '../models/empleado.dart';
import '../models/liquidacion_nomina.dart';
import '../models/retroactivo.dart';
import 'horas_extra_form_page.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';

class NominaPublicaPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  final int tabInicial;

  const NominaPublicaPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.tabInicial = 0,
  });

  @override
  State<NominaPublicaPage> createState() => _NominaPublicaPageState();
}

class _NominaPublicaPageState extends State<NominaPublicaPage> {
  int _selectedIndex = 0;
  bool _loading = true;
  late NominaService _nominaService;
  late PILAService _pilaService;
  late RetroactivosService _retroactivosService;
  late HorasExtraService _horasExtraService;

  List<Empleado> _empleados = [];
  List<LiquidacionNomina> _liquidaciones = [];
  List<Retroactivo> _retroactivos = [];
  Map<String, dynamic>? _pilaReporte;

  // Configuración Legal (SMMLV y Auxilio de Transporte)
  MoneyValue _smmlvConfig = publicMoneyFromMajor('1300000');
  MoneyValue _auxilioTransporteConfig = publicMoneyFromMajor('162000');

  final List<String> _titulos = [
    'Gestión de Empleados',
    'Liquidaciones de Nómina',
    'Retroactivos',
    'Planilla PILA',
    'Configuración Legal',
    'Horas Extra',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.tabInicial.clamp(0, _titulos.length - 1).toInt();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoriaService = AuditoriaService(db);

      _nominaService = NominaService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _pilaService = PILAService(db: db, auditoriaService: auditoriaService);
      _retroactivosService = RetroactivosService(
        db: db,
        auditoriaService: auditoriaService,
      );
      _horasExtraService = HorasExtraService(
        db: db,
        auditoriaService: auditoriaService,
      );

      await _cargarConfiguracion();
      await _cargarDatos();
    } catch (e) {
      _mostrarError('Error al inicializar: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final configResult = await db.query(
        'configuracion_entidad',
        where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
        whereArgs: [widget.entidadId, 'configuracion_legal'],
      );

      if (configResult.isNotEmpty) {
        final Map<String, dynamic> config = jsonDecode(
          configResult.first['valor'] as String,
        );
        if (!mounted) return;
        setState(() {
          if (config.containsKey('smmlv')) {
            _smmlvConfig = publicMoneyFromMajor(config['smmlv'].toString());
          }
          if (config.containsKey('auxilio_transporte')) {
            _auxilioTransporteConfig = publicMoneyFromMajor(
              config['auxilio_transporte'].toString(),
            );
          }
        });
      }
    } catch (e) {
      _mostrarError('Error al cargar configuración: $e');
    }
  }

  Future<void> _cargarDatos() async {
    try {
      final db = await DatabaseHelper.instance.database;

      // 1. Cargar Empleados
      final empleadosResult = await db.query(
        'empleados_sp',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'nombre_completo',
      );
      _empleados = empleadosResult.map((r) => Empleado.fromJson(r)).toList();

      // 2. Cargar Liquidaciones
      _liquidaciones = await _nominaService.consultarLiquidaciones(
        entidadId: widget.entidadId,
      );

      // 3. Cargar Retroactivos
      _retroactivos = await _retroactivosService.consultarRetroactivos(
        entidadId: widget.entidadId,
      );
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
                _buildEmpleadosTab(),
                _buildLiquidacionesTab(),
                _buildRetroactivosTab(),
                _buildPILATab(),
                _buildConfiguracionTab(),
                _buildHorasExtraTab(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Empleados'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Nómina',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Retroactivos',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'PILA'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Config'),
          BottomNavigationBarItem(icon: Icon(Icons.schedule), label: 'Extras'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _registrarEmpleado,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.person_add),
            )
          : _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: _liquidarNomina,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.calculate),
            )
          : _selectedIndex == 2
          ? FloatingActionButton(
              onPressed: _calcularRetroactivo,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildEmpleadosTab() {
    if (_empleados.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay empleados registrados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _registrarEmpleado,
              icon: Icon(Icons.person_add),
              label: const Text('Registrar Empleado'),
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
      itemCount: _empleados.length,
      itemBuilder: (context, index) {
        final emp = _empleados[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text(emp.nombreCompleto),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identificación: ${emp.numeroIdentificacion}'),
                Text('Cargo: ${emp.cargo} | Dependencia: ${emp.dependencia}'),
                Text('Salario: ${publicMoneyForDisplay(emp.salarioBasico)}'),
              ],
            ),
            trailing: Chip(
              label: Text(emp.activo ? 'ACTIVO' : 'RETIRO'),
              backgroundColor: emp.activo ? Colors.green : Colors.red,
              labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiquidacionesTab() {
    if (_liquidaciones.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay liquidaciones generadas',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _liquidarNomina,
              icon: Icon(Icons.calculate),
              label: const Text('Liquidar Nómina'),
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
      itemCount: _liquidaciones.length,
      itemBuilder: (context, index) {
        final liq = _liquidaciones[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(liq.numeroLiquidacion),
            subtitle: Text('${liq.empleadoNombre} | Periodo: ${liq.periodo}'),
            trailing: Text(
              '${publicMoneyForDisplay(liq.netoPagar)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Salario Básico: ${publicMoneyForDisplay(liq.salarioBasico)}',
                    ),
                    Text(
                      'Salario Devengado: ${publicMoneyForDisplay(liq.salarioDevengado)}',
                    ),
                    Text(
                      'Auxilio Transporte: ${publicMoneyForDisplay(liq.auxilioTransporte)}',
                    ),
                    Text(
                      'Horas Extra / Recargo Nocturno: ${publicMoneyForDisplay(liq.horasExtra + liq.recargoNocturno)}',
                    ),
                    const Divider(),
                    Text(
                      'Deducción Salud (8.5%): ${publicMoneyForDisplay(liq.salud)}',
                    ),
                    Text(
                      'Deducción Pensión (12%): ${publicMoneyForDisplay(liq.pension)}',
                    ),
                    Text(
                      'Deducción Solidaridad: ${publicMoneyForDisplay(liq.fondoSolidaridad)}',
                    ),
                    Text(
                      'Riesgos Laborales: ${publicMoneyForDisplay(liq.riesgosLaborales)}',
                    ),
                    const Divider(),
                    Text(
                      'Aporte Caja Compensación: ${publicMoneyForDisplay(liq.cajaCompensacion)}',
                    ),
                    Text(
                      'Aporte SENA / ICBF: ${publicMoneyForDisplay(liq.sena + liq.icbf)}',
                    ),
                    const Divider(),
                    Text(
                      'Neto a Pagar: ${publicMoneyForDisplay(liq.netoPagar)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    if (liq.observaciones != null &&
                        liq.observaciones!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning, color: Colors.amber, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                liq.observaciones!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: MerkaThemeTokens.graphite600,
                                ),
                              ),
                            ),
                          ],
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

  Widget _buildRetroactivosTab() {
    if (_retroactivos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay retroactivos calculados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _calcularRetroactivo,
              icon: Icon(Icons.add),
              label: const Text('Calcular Retroactivo'),
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
      itemCount: _retroactivos.length,
      itemBuilder: (context, index) {
        final ret = _retroactivos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(ret.numeroRetroactivo),
            subtitle: Text(
              '${ret.empleadoNombre} | Total: ${publicMoneyForDisplay(ret.valorTotal)}',
            ),
            trailing: Chip(
              label: Text(ret.estado.toString().split('.').last.toUpperCase()),
              backgroundColor: ret.estado == EstadoRetroactivo.pagado
                  ? Colors.green
                  : Colors.orange,
              labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Motivo: ${ret.motivo}'),
                    Text(
                      'Rango: ${DateFormatter.format(ret.fechaInicio)} a ${DateFormatter.format(ret.fechaFin)} (${ret.meses} meses)',
                    ),
                    Text(
                      'Salario Anterior: ${publicMoneyForDisplay(ret.salarioAnterior)} | Nuevo: ${publicMoneyForDisplay(ret.salarioNuevo)}',
                    ),
                    Text(
                      'Diferencia Mensual: ${publicMoneyForDisplay(ret.diferenciaMensual)}',
                    ),
                    if (ret.actoAdministrativo != null)
                      Text('Acto Administrativo: ${ret.actoAdministrativo}'),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (ret.estado == EstadoRetroactivo.calculado)
                          TextButton.icon(
                            icon: Icon(Icons.check_circle),
                            label: const Text('Aprobar'),
                            onPressed: () => _aprobarRetroactivo(ret),
                          ),
                        if (ret.estado == EstadoRetroactivo.aprobado)
                          TextButton.icon(
                            icon: Icon(Icons.payment),
                            label: const Text('Registrar Pago'),
                            onPressed: () => _registrarPagoRetroactivo(ret),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHorasExtraTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.schedule,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Registro de Horas Extra',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Registre horas extra y recargos para los empleados de la entidad.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _abrirRegistroHorasExtra,
                icon: const Icon(Icons.add),
                label: const Text('Registrar Horas Extra'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirRegistroHorasExtra() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HorasExtraFormPage(
          horasExtraService: _horasExtraService,
          entidadId: widget.entidadId,
          usuarioId: widget.usuarioId,
        ),
      ),
    );
  }

  Widget _buildPILATab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Planilla Integrada de Liquidación de Aportes (PILA)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Consolida y reporta los aportes parafiscales y de seguridad social calculados en el periodo de nómina correspondiente.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generarReportePILA,
            icon: Icon(Icons.calculate),
            label: const Text('Generar Liquidación PILA'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
          if (_pilaReporte != null) ...[
            const SizedBox(height: 24),
            const Divider(),
            const Text(
              'Resultados de Liquidación de Planilla',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text('Periodo: ${_pilaReporte!['periodo']}'),
            Text('Total Empleados: ${_pilaReporte!['total_empleados']}'),
            const SizedBox(height: 8),
            Text(
              'Aporte Salud: ${CurrencyFormatter.format((_pilaReporte!['total_salud'] as double))}',
            ),
            Text(
              'Aporte Pensión: ${CurrencyFormatter.format((_pilaReporte!['total_pension'] as double))}',
            ),
            Text(
              'Fondo Solidaridad: ${CurrencyFormatter.format((_pilaReporte!['total_fondo_solidaridad'] as double))}',
            ),
            Text(
              'Riesgos Laborales: ${CurrencyFormatter.format((_pilaReporte!['total_riesgos_laborales'] as double))}',
            ),
            Text(
              'Caja Compensación: ${CurrencyFormatter.format((_pilaReporte!['total_caja_compensacion'] as double))}',
            ),
            Text(
              'SENA: ${CurrencyFormatter.format((_pilaReporte!['total_sena'] as double))} | ICBF: ${CurrencyFormatter.format((_pilaReporte!['total_icbf'] as double))}',
            ),
            const Divider(),
            Text(
              'Gran Total Planilla: ${CurrencyFormatter.format((_pilaReporte!['gran_total'] as double))}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: MerkaThemeTokens.info,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _enviarOperadorPILA,
                  icon: Icon(Icons.send),
                  label: const Text('Enviar a Operador'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exportarPlanoPILA,
                  icon: Icon(Icons.file_download),
                  label: const Text('Exportar Formato Plano'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfiguracionTab() {
    final formKey = GlobalKey<FormState>();
    final smmlvController = TextEditingController(
      text: _smmlvConfig.toMajorUnitsString(),
    );
    final auxilioController = TextEditingController(
      text: _auxilioTransporteConfig.toMajorUnitsString(),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Parámetros Legales de Nómina',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure los valores legales que rigen el cálculo de aportes, auxilios y retenciones en la liquidación.',
              style: TextStyle(color: Colors.grey),
            ),
            const Divider(height: 32),
            TextFormField(
              controller: smmlvController,
              decoration: const InputDecoration(
                labelText: 'Salario Mínimo Legal Vigente (SMMLV)',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: auxilioController,
              decoration: const InputDecoration(
                labelText: 'Valor Mensual Auxilio de Transporte',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  setState(() => _loading = true);
                  try {
                    final db = await DatabaseHelper.instance.database;
                    final valorJson = jsonEncode({
                      'smmlv': publicMoneyFromMajor(
                        smmlvController.text,
                      ).toMajorUnitsString(),
                      'auxilio_transporte': publicMoneyFromMajor(
                        auxilioController.text,
                      ).toMajorUnitsString(),
                    });

                    final existente = await db.query(
                      'configuracion_entidad',
                      where: 'entidad_id = ? AND parametro = ? AND vigente = 1',
                      whereArgs: [widget.entidadId, 'configuracion_legal'],
                    );

                    if (existente.isEmpty) {
                      await db.insert('configuracion_entidad', {
                        'id': const Uuid().v4(),
                        'entidad_id': widget.entidadId,
                        'parametro': 'configuracion_legal',
                        'valor': valorJson,
                        'fecha_actualizacion': DateTime.now().toIso8601String(),
                        'actualizado_por': widget.usuarioId,
                      });
                    } else {
                      await db.update(
                        'configuracion_entidad',
                        {
                          'valor': valorJson,
                          'fecha_actualizacion': DateTime.now()
                              .toIso8601String(),
                          'actualizado_por': widget.usuarioId,
                        },
                        where:
                            'entidad_id = ? AND parametro = ? AND vigente = 1',
                        whereArgs: [widget.entidadId, 'configuracion_legal'],
                      );
                    }

                    _mostrarExito(
                      'Parámetros guardados y sincronizados correctamente',
                    );
                    await _cargarConfiguracion();
                  } catch (e) {
                    _mostrarError('Error al guardar configuración: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              icon: Icon(Icons.save),
              label: const Text('Guardar Parámetros'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarEmpleado() {
    final formKey = GlobalKey<FormState>();
    final identificacionController = TextEditingController();
    final nombreController = TextEditingController();
    final cargoController = TextEditingController();
    final dependenciaController = TextEditingController();
    final salarioController = TextEditingController();
    final bancoController = TextEditingController();
    final cuentaController = TextEditingController();
    final epsController = TextEditingController();
    final pensionController = TextEditingController();

    TipoContrato contratoSeleccionado = TipoContrato.indefinido;
    TipoVinculacion vinculacionSeleccionada = TipoVinculacion.carrera;
    RegimenNominaPublica regimenSeleccionado =
        RegimenNominaPublica.carreraAdministrativa;
    int claseRiesgoArl = 1;
    DateTime fechaIngreso = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Empleado Público'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: identificacionController,
                    decoration: const InputDecoration(
                      labelText: 'Identificación NIT/CC',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: nombreController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre Completo',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: cargoController,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: dependenciaController,
                    decoration: const InputDecoration(labelText: 'Dependencia'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  DropdownButtonFormField<TipoContrato>(
                    initialValue: contratoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Contrato',
                    ),
                    items: TipoContrato.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => contratoSeleccionado = val);
                      }
                    },
                  ),
                  DropdownButtonFormField<TipoVinculacion>(
                    initialValue: vinculacionSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Vinculación',
                    ),
                    items: TipoVinculacion.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => vinculacionSeleccionada = val);
                      }
                    },
                  ),
                  DropdownButtonFormField<RegimenNominaPublica>(
                    initialValue: regimenSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Régimen de Nómina',
                    ),
                    items: RegimenNominaPublica.values.map((regimen) {
                      return DropdownMenuItem(
                        value: regimen,
                        child: Text(regimen.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (valor) {
                      if (valor != null) {
                        setDialogState(() => regimenSeleccionado = valor);
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: claseRiesgoArl,
                    decoration: const InputDecoration(
                      labelText: 'Clase de Riesgo ARL',
                    ),
                    items: List.generate(5, (indice) => indice + 1)
                        .map(
                          (clase) => DropdownMenuItem(
                            value: clase,
                            child: Text('Clase $clase'),
                          ),
                        )
                        .toList(),
                    onChanged: (valor) {
                      if (valor != null) {
                        setDialogState(() => claseRiesgoArl = valor);
                      }
                    },
                  ),
                  TextFormField(
                    controller: salarioController,
                    decoration: const InputDecoration(
                      labelText: 'Salario Básico Mensual',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Fecha Ingreso: ${fechaIngreso.toString().split(' ')[0]}',
                      ),
                      TextButton(
                        onPressed: () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: fechaIngreso,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (selected != null) {
                            setDialogState(() => fechaIngreso = selected);
                          }
                        },
                        child: const Text('Seleccionar'),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: bancoController,
                    decoration: const InputDecoration(
                      labelText: 'Banco (Para Transferencia)',
                    ),
                  ),
                  TextFormField(
                    controller: cuentaController,
                    decoration: const InputDecoration(
                      labelText: 'Cuenta Bancaria',
                    ),
                  ),
                  TextFormField(
                    controller: epsController,
                    decoration: const InputDecoration(labelText: 'EPS'),
                  ),
                  TextFormField(
                    controller: pensionController,
                    decoration: const InputDecoration(
                      labelText: 'Fondo de Pensión',
                    ),
                  ),
                ],
              ),
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
                    final db = await DatabaseHelper.instance.database;
                    final id = const Uuid().v4();

                    final emp = Empleado(
                      id: id,
                      entidadId: widget.entidadId,
                      numeroIdentificacion: identificacionController.text,
                      nombreCompleto: nombreController.text,
                      cargo: cargoController.text,
                      dependencia: dependenciaController.text,
                      tipoContrato: contratoSeleccionado,
                      tipoVinculacion: vinculacionSeleccionada,
                      regimenNomina: regimenSeleccionado,
                      claseRiesgoArl: claseRiesgoArl,
                      salarioBasico: publicMoneyFromMajor(
                        salarioController.text,
                      ),
                      fechaIngreso: fechaIngreso,
                      activo: true,
                      banco: bancoController.text.isEmpty
                          ? null
                          : bancoController.text,
                      cuentaBancaria: cuentaController.text.isEmpty
                          ? null
                          : cuentaController.text,
                      eps: epsController.text.isEmpty
                          ? null
                          : epsController.text,
                      fondoPension: pensionController.text.isEmpty
                          ? null
                          : pensionController.text,
                    );

                    await db.insert('empleados_sp', emp.toJson());

                    _mostrarExito('Empleado público registrado');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al registrar: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _liquidarNomina() {
    if (_empleados.isEmpty) {
      _mostrarError('Registre al menos un empleado antes de liquidar.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final periodoController = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );
    final diasController = TextEditingController(text: '30');
    final horasExtraController = TextEditingController(text: '0.0');
    final recargoController = TextEditingController(text: '0.0');
    Empleado? empleadoSeleccionado;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Liquidar Nómina'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Empleado>(
                    initialValue: empleadoSeleccionado,
                    decoration: const InputDecoration(labelText: 'Empleado'),
                    items: _empleados.where((e) => e.activo).map((e) {
                      return DropdownMenuItem(
                        value: e,
                        child: Text(e.nombreCompleto),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => empleadoSeleccionado = val);
                    },
                    validator: (value) => value == null ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: periodoController,
                    decoration: const InputDecoration(
                      labelText: 'Periodo (YYYY-MM)',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: diasController,
                    decoration: const InputDecoration(
                      labelText: 'Días Trabajados (1-30)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: horasExtraController,
                    decoration: const InputDecoration(
                      labelText: 'Horas Extra (\$)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  TextFormField(
                    controller: recargoController,
                    decoration: const InputDecoration(
                      labelText: 'Recargo Nocturno (\$)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate() &&
                    empleadoSeleccionado != null) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _nominaService.liquidarNomina(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      empleadoId: empleadoSeleccionado!.id,
                      periodo: periodoController.text,
                      diasTrabajados: int.parse(diasController.text),
                      horasExtra: publicMoneyFromMajor(
                        horasExtraController.text,
                      ),
                      recargoNocturno: publicMoneyFromMajor(
                        recargoController.text,
                      ),
                    );
                    _mostrarExito('Nómina liquidada correctamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al liquidar: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Liquidar'),
            ),
          ],
        ),
      ),
    );
  }

  void _calcularRetroactivo() {
    if (_empleados.isEmpty) {
      _mostrarError('Debe registrar empleados antes de calcular retroactivos.');
      return;
    }

    final formKey = GlobalKey<FormState>();
    final motivoController = TextEditingController();
    final nuevoSalarioController = TextEditingController();
    final anteriorSalarioController = TextEditingController();
    Empleado? empleadoSeleccionado;
    TipoRetroactivo tipoSeleccionado = TipoRetroactivo.ajusteSalarial;

    DateTime fechaInicio = DateTime(DateTime.now().year, 1, 1);
    DateTime fechaFin = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Calcular Retroactivo'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Empleado>(
                    initialValue: empleadoSeleccionado,
                    decoration: const InputDecoration(labelText: 'Empleado'),
                    items: _empleados.map((e) {
                      return DropdownMenuItem(
                        value: e,
                        child: Text(e.nombreCompleto),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        empleadoSeleccionado = val;
                        if (val != null) {
                          anteriorSalarioController.text = val.salarioBasico
                              .toMajorUnitsString();
                        }
                      });
                    },
                    validator: (value) => value == null ? 'Requerido' : null,
                  ),
                  DropdownButtonFormField<TipoRetroactivo>(
                    initialValue: tipoSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de Retroactivo',
                    ),
                    items: TipoRetroactivo.values.map((t) {
                      return DropdownMenuItem(
                        value: t,
                        child: Text(t.toString().split('.').last),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tipoSeleccionado = val);
                      }
                    },
                  ),
                  TextFormField(
                    controller: motivoController,
                    decoration: const InputDecoration(
                      labelText: 'Motivo / Justificación del Ajuste',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: anteriorSalarioController,
                    decoration: const InputDecoration(
                      labelText: 'Salario Anterior Mensual',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: nuevoSalarioController,
                    decoration: const InputDecoration(
                      labelText: 'Nuevo Salario Mensual',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 8),
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
                            setDialogState(() => fechaInicio = selected);
                          }
                        },
                        child: const Text('Fecha Inicio'),
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
                            setDialogState(() => fechaFin = selected);
                          }
                        },
                        child: const Text('Fecha Fin'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate() &&
                    empleadoSeleccionado != null) {
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _retroactivosService.calcularRetroactivo(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      empleadoId: empleadoSeleccionado!.id,
                      motivo: motivoController.text,
                      fechaInicio: fechaInicio,
                      fechaFin: fechaFin,
                      salarioAnterior: publicMoneyFromMajor(
                        anteriorSalarioController.text,
                      ),
                      salarioNuevo: publicMoneyFromMajor(
                        nuevoSalarioController.text,
                      ),
                      tipoRetroactivo: tipoSeleccionado,
                    );
                    _mostrarExito('Retroactivo calculado exitosamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al calcular: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Calcular'),
            ),
          ],
        ),
      ),
    );
  }

  void _aprobarRetroactivo(Retroactivo ret) {
    final formKey = GlobalKey<FormState>();
    final actoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprobar Retroactivo'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Empleado: ${ret.empleadoNombre}'),
              Text('Total a Pagar: ${publicMoneyForDisplay(ret.valorTotal)}'),
              const Divider(),
              TextFormField(
                controller: actoController,
                decoration: const InputDecoration(
                  labelText: 'Acto Administrativo (Decreto / Resolución #)',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
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
                  await _retroactivosService.aprobarRetroactivo(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    retroactivoId: ret.id,
                    actoAdministrativo: actoController.text,
                  );
                  _mostrarExito('Retroactivo aprobado exitosamente');
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al aprobar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  void _registrarPagoRetroactivo(Retroactivo ret) {
    final formKey = GlobalKey<FormState>();
    final montoController = TextEditingController(
      text: ret.saldoPendiente.toMajorUnitsString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Pago de Retroactivo'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Empleado: ${ret.empleadoNombre}'),
              Text(
                'Saldo Pendiente: ${publicMoneyForDisplay(ret.saldoPendiente)}',
              ),
              const Divider(),
              TextFormField(
                controller: montoController,
                decoration: const InputDecoration(labelText: 'Monto de Pago'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
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
                  await _retroactivosService.registrarPago(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    retroactivoId: ret.id,
                    montoPago: publicMoneyFromMajor(montoController.text),
                  );
                  _mostrarExito('Pago registrado correctamente');
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al pagar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Registrar Pago'),
          ),
        ],
      ),
    );
  }

  void _generarReportePILA() {
    final formKey = GlobalKey<FormState>();
    final periodoController = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar Liquidación PILA'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: periodoController,
            decoration: const InputDecoration(labelText: 'Periodo (YYYY-MM)'),
            validator: (value) =>
                value == null || value.isEmpty ? 'Requerido' : null,
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
                  final result = await _pilaService.generarReportePILA(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    periodo: periodoController.text,
                  );
                  setState(() {
                    _pilaReporte = result;
                  });
                  _mostrarExito('Liquidación PILA calculada correctamente');
                } catch (e) {
                  _mostrarError('Error al generar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Calcular'),
          ),
        ],
      ),
    );
  }

  void _enviarOperadorPILA() {
    if (_pilaReporte == null) return;

    final formKey = GlobalKey<FormState>();
    final nitController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enviar Reporte PILA'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Se transmitirá la planilla al operador de información gubernamental.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: nitController,
                decoration: const InputDecoration(
                  labelText: 'NIT de la Entidad',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
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
                  await _pilaService.enviarReportePILA(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    periodo: _pilaReporte!['periodo'] as String,
                    nitEntidad: nitController.text,
                  );
                  _mostrarExito(
                    'Planilla PILA enviada y radicada con el operador exitosamente',
                  );
                } catch (e) {
                  _mostrarError('Error al enviar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  void _exportarPlanoPILA() async {
    if (_pilaReporte == null) return;
    setState(() => _loading = true);
    try {
      final contenidoPlano = await _pilaService.exportarFormatoPlano(
        entidadId: widget.entidadId,
        periodo: _pilaReporte!['periodo'] as String,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Formato Plano PILA (Archivo de Salida)'),
          content: SingleChildScrollView(
            child: Text(
              contenidoPlano,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
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
      _mostrarError('Error al exportar: $e');
    } finally {
      setState(() => _loading = false);
    }
  }
}
