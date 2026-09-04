import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/pac_service.dart';
import '../models/pac.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../../core/utils/date_formatter.dart';

class PACTesoreriaPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const PACTesoreriaPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<PACTesoreriaPage> createState() => _PACTesoreriaPageState();
}

class _PACTesoreriaPageState extends State<PACTesoreriaPage> {
  int _selectedIndex = 0;
  bool _loading = true;
  late PACService _pacService;
  List<PAC> _pacList = [];
  List<EmbargoJudicial> _embargos = [];
  List<Map<String, dynamic>> _rubros = [];
  Map<String, dynamic> _resumenEjecucion = {};

  final TextEditingController _vigenciaFiltroController = TextEditingController(
    text: DateTime.now().year.toString(),
  );

  final List<String> _titulos = [
    'Programación PAC',
    'Ejecución',
    'Traslados',
    'Embargos',
  ];

  @override
  void initState() {
    super.initState();
    _inicializarServicio();
  }

  Future<void> _inicializarServicio() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoriaService = AuditoriaService(db);
      _pacService = PACService(db: db, auditoriaService: auditoriaService);

      // Cargar rubros de apropiaciones para los selectores
      _rubros = await db.query(
        'apropiaciones',
        where: 'entidad_id = ? AND activo = 1',
        whereArgs: [widget.entidadId],
        orderBy: 'codigo_rubro',
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
      // 1. Cargar lista de PAC para la vigencia filtrada
      _pacList = await _pacService.consultarPAC(
        entidadId: widget.entidadId,
        vigencia: _vigenciaFiltroController.text,
      );

      // 2. Cargar Resumen de Ejecución
      _resumenEjecucion = await _pacService.consultarResumenEjecucionPAC(
        entidadId: widget.entidadId,
        vigencia: _vigenciaFiltroController.text,
      );

      // 3. Cargar Embargos
      final db = await DatabaseHelper.instance.database;
      final embargosResult = await db.query(
        'embargos_judiciales',
        where: 'entidad_id = ?',
        whereArgs: [widget.entidadId],
        orderBy: 'fecha_registro DESC',
      );
      _embargos = embargosResult
          .map(
            (r) => EmbargoJudicial(
              id: r['id'] as String,
              entidadId: r['entidad_id'] as String,
              numeroProceso: r['numero_proceso'] as String,
              juzgado: r['juzgado'] as String,
              terceroId: r['tercero_id'] as String?,
              terceroNombre: r['tercero_nombre'] as String,
              valorEmbargo: publicMoneyFromSql(r['valor_embargo']),
              fechaRegistro: DateTime.parse(r['fecha_registro'] as String),
              fechaLevantamiento: r['fecha_levantamiento'] != null
                  ? DateTime.parse(r['fecha_levantamiento'] as String)
                  : null,
              activo: r['activo'] == 1,
            ),
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
        actions: [
          if (_selectedIndex < 2) // Solo para Programación y Ejecución
            Container(
              width: 100,
              padding: const EdgeInsets.only(right: 16),
              alignment: Alignment.center,
              child: TextFormField(
                controller: _vigenciaFiltroController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Vigencia',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                ),
                onFieldSubmitted: (val) async {
                  setState(() => _loading = true);
                  await _cargarDatos();
                  setState(() => _loading = false);
                },
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildProgramacionTab(),
                _buildEjecucionTab(),
                _buildTrasladosTab(),
                _buildEmbargosTab(),
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
            icon: Icon(Icons.calendar_month),
            label: 'Programación',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Ejecución',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horiz),
            label: 'Traslados',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.gavel), label: 'Embargos'),
        ],
      ),
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _programarPAC,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : _selectedIndex == 2
          ? FloatingActionButton(
              onPressed: _trasladarCupo,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.compare_arrows),
            )
          : _selectedIndex == 3
          ? FloatingActionButton(
              onPressed: _registrarEmbargo,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildProgramacionTab() {
    if (_pacList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay PAC programado para esta vigencia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _programarPAC,
              icon: Icon(Icons.add),
              label: const Text('Programar PAC'),
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
      itemCount: _pacList.length,
      itemBuilder: (context, index) {
        final pac = _pacList[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('${pac.nombreMes} - Rubro: ${pac.codigoRubro}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Programado: ${CurrencyFormatter.format(publicMoneyForDisplay(pac.valorProgramado))}',
                ),
                Text(
                  'Saldo Disponible: ${CurrencyFormatter.format(publicMoneyForDisplay(pac.saldoDisponible))}',
                ),
                if (pac.actoAdministrativo != null)
                  Text('Acto Administrativo: ${pac.actoAdministrativo}'),
                const SizedBox(height: 4),
                Chip(
                  label: Text(
                    pac.estado.toString().split('.').last.toUpperCase(),
                  ),
                  backgroundColor: pac.estaAprobado()
                      ? Colors.green
                      : Colors.orange,
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pac.estado == EstadoPAC.borrador)
                  IconButton(
                    icon: Icon(Icons.check_circle, color: Colors.green),
                    tooltip: 'Aprobar PAC',
                    onPressed: () => _aprobarPAC(pac),
                  ),
                IconButton(
                  icon: Icon(Icons.edit, color: MerkaThemeTokens.info),
                  tooltip: 'Modificar PAC',
                  onPressed: () => _modificarPAC(pac),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEjecucionTab() {
    final resumenMensual = _resumenEjecucion['resumen_mensual'] as List? ?? [];
    if (resumenMensual.isEmpty) {
      return const Center(
        child: Text('No hay datos de ejecución presupuestal para mostrar.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade300),
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(2),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: const [
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Mes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Programado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Ejecutado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Saldo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          ...resumenMensual.map((row) {
            final mes = row['mes'] as int;
            final nombresMeses = [
              'Enero',
              'Febrero',
              'Marzo',
              'Abril',
              'Mayo',
              'Junio',
              'Julio',
              'Agosto',
              'Septiembre',
              'Octubre',
              'Noviembre',
              'Diciembre',
            ];
            final totalProgramado = publicMoneyFromSql(row['total_programado']);
            final totalEjecutado = publicMoneyFromSql(row['total_ejecutado']);
            final totalSaldo = publicMoneyFromSql(row['total_saldo']);

            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(nombresMeses[mes - 1]),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    CurrencyFormatter.format(
                      publicMoneyForDisplay(totalProgramado),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    CurrencyFormatter.format(
                      publicMoneyForDisplay(totalEjecutado),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    CurrencyFormatter.format(publicMoneyForDisplay(totalSaldo)),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTrasladosTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swap_horiz,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            'Traslado de Cupo PAC',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Los traslados permiten reasignar cupos mensuales entre periodos de la misma vigencia fiscal conforme al Art. 76 del EOP.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _trasladarCupo,
            icon: Icon(Icons.compare_arrows),
            label: const Text('Registrar Traslado de Cupo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmbargosTab() {
    if (_embargos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.gavel, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No hay embargos registrados',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _registrarEmbargo,
              icon: Icon(Icons.add),
              label: const Text('Registrar Embargo Judicial'),
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
      itemCount: _embargos.length,
      itemBuilder: (context, index) {
        final embargo = _embargos[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('Proceso: ${embargo.numeroProceso}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Juzgado: ${embargo.juzgado}'),
                Text('Demandante: ${embargo.terceroNombre}'),
                Text(
                  'Fecha Registro: ${DateFormatter.format(embargo.fechaRegistro)}',
                ),
                const SizedBox(height: 4),
                const Text(
                  'Nota: Las cuentas públicas son inembargables (Art. 19 EOP). Este registro es informativo y de control.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            trailing: Text(
              CurrencyFormatter.format(
                publicMoneyForDisplay(embargo.valorEmbargo),
              ),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ),
        );
      },
    );
  }

  void _programarPAC() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: _vigenciaFiltroController.text,
    );
    final valorController = TextEditingController();
    final funcionarioController = TextEditingController();
    int mesSeleccionado = 1;
    String? rubroSeleccionado;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Programar Cupo PAC'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  DropdownButtonFormField<int>(
                    initialValue: mesSeleccionado,
                    decoration: const InputDecoration(labelText: 'Mes'),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text((i + 1).toString()),
                      ),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => mesSeleccionado = val);
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: rubroSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Rubro Presupuestal',
                    ),
                    items: _rubros.map((r) {
                      return DropdownMenuItem<String>(
                        value: r['codigo_rubro'] as String,
                        child: Text(
                          '${r['codigo_rubro']} - ${r['nombre_rubro']}',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => rubroSeleccionado = val);
                    },
                    validator: (value) => value == null ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: valorController,
                    decoration: const InputDecoration(
                      labelText: 'Valor Programado',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: funcionarioController,
                    decoration: const InputDecoration(
                      labelText: 'Funcionario que Programa',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
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
                    await _pacService.programarPAC(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      vigencia: vigenciaController.text,
                      mes: mesSeleccionado,
                      codigoRubro: rubroSeleccionado!,
                      valorProgramado: publicMoneyFromMajor(
                        valorController.text,
                      ),
                      funcionarioProgramo: funcionarioController.text,
                    );
                    _mostrarExito('PAC programado exitosamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al programar: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Programar'),
            ),
          ],
        ),
      ),
    );
  }

  void _aprobarPAC(PAC pac) {
    final formKey = GlobalKey<FormState>();
    final funcionarioController = TextEditingController();
    final actoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprobar PAC'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mes: ${pac.nombreMes} | Rubro: ${pac.codigoRubro}'),
              Text(
                'Valor: ${CurrencyFormatter.format(publicMoneyForDisplay(pac.valorProgramado))}',
              ),
              const Divider(),
              TextFormField(
                controller: funcionarioController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario que Aprueba',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: actoController,
                decoration: const InputDecoration(
                  labelText: 'Acto Administrativo (Resolución #)',
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
                  await _pacService.aprobarPAC(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    pacId: pac.id,
                    funcionarioAprobo: funcionarioController.text,
                    actoAdministrativo: actoController.text,
                  );
                  _mostrarExito('PAC aprobado exitosamente');
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

  void _modificarPAC(PAC pac) {
    final formKey = GlobalKey<FormState>();
    final valorController = TextEditingController(
      text: pac.valorProgramado.toString(),
    );
    final funcionarioController = TextEditingController();
    final actoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modificar PAC'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mes: ${pac.nombreMes} | Rubro: ${pac.codigoRubro}'),
              const Divider(),
              TextFormField(
                controller: valorController,
                decoration: const InputDecoration(
                  labelText: 'Nuevo Valor Programado',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: funcionarioController,
                decoration: const InputDecoration(
                  labelText: 'Funcionario que Modifica',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: actoController,
                decoration: const InputDecoration(
                  labelText: 'Acto Administrativo (Resolución #)',
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
                  await _pacService.modificarPAC(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    pacId: pac.id,
                    nuevoValorProgramado: publicMoneyFromMajor(
                      valorController.text,
                    ),
                    funcionarioModifico: funcionarioController.text,
                    actoAdministrativo: actoController.text,
                  );
                  _mostrarExito('PAC modificado exitosamente');
                  await _cargarDatos();
                } catch (e) {
                  _mostrarError('Error al modificar: $e');
                } finally {
                  setState(() => _loading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Modificar'),
          ),
        ],
      ),
    );
  }

  void _trasladarCupo() {
    final formKey = GlobalKey<FormState>();
    final vigenciaController = TextEditingController(
      text: _vigenciaFiltroController.text,
    );
    final montoController = TextEditingController();
    final funcionarioController = TextEditingController();
    final actoController = TextEditingController();
    String? rubroSeleccionado;
    int mesOrigen = 1;
    int mesDestino = 2;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Trasladar Cupo PAC'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  DropdownButtonFormField<String>(
                    initialValue: rubroSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Rubro Presupuestal',
                    ),
                    items: _rubros.map((r) {
                      return DropdownMenuItem<String>(
                        value: r['codigo_rubro'] as String,
                        child: Text(
                          '${r['codigo_rubro']} - ${r['nombre_rubro']}',
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() => rubroSeleccionado = val);
                    },
                    validator: (value) => value == null ? 'Requerido' : null,
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: mesOrigen,
                    decoration: const InputDecoration(labelText: 'Mes Origen'),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text((i + 1).toString()),
                      ),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => mesOrigen = val);
                      }
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: mesDestino,
                    decoration: const InputDecoration(labelText: 'Mes Destino'),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text((i + 1).toString()),
                      ),
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => mesDestino = val);
                      }
                    },
                  ),
                  TextFormField(
                    controller: montoController,
                    decoration: const InputDecoration(
                      labelText: 'Monto a Trasladar',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: funcionarioController,
                    decoration: const InputDecoration(
                      labelText: 'Funcionario Autoriza',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
                  ),
                  TextFormField(
                    controller: actoController,
                    decoration: const InputDecoration(
                      labelText: 'Acto Administrativo (Resolución #)',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Requerido' : null,
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
                  if (mesOrigen == mesDestino) {
                    _mostrarError(
                      'El mes de origen y destino deben ser diferentes',
                    );
                    return;
                  }
                  Navigator.pop(context);
                  setState(() => _loading = true);
                  try {
                    await _pacService.trasladarCupoPAC(
                      entidadId: widget.entidadId,
                      usuarioId: widget.usuarioId,
                      vigencia: vigenciaController.text,
                      codigoRubro: rubroSeleccionado!,
                      mesOrigen: mesOrigen,
                      mesDestino: mesDestino,
                      montoTraslado: publicMoneyFromMajor(montoController.text),
                      funcionarioAutoriza: funcionarioController.text,
                      actoAdministrativo: actoController.text,
                    );
                    _mostrarExito('Traslado realizado exitosamente');
                    await _cargarDatos();
                  } catch (e) {
                    _mostrarError('Error al realizar traslado: $e');
                  } finally {
                    setState(() => _loading = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Trasladar'),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarEmbargo() {
    final formKey = GlobalKey<FormState>();
    final procesoController = TextEditingController();
    final juzgadoController = TextEditingController();
    final demandanteController = TextEditingController();
    final montoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Embargo Judicial'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: procesoController,
                decoration: const InputDecoration(
                  labelText: 'Número de Proceso',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: juzgadoController,
                decoration: const InputDecoration(labelText: 'Juzgado'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: demandanteController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Demandante',
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: montoController,
                decoration: const InputDecoration(
                  labelText: 'Valor del Embargo',
                ),
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
                  await _pacService.registrarEmbargoJudicial(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    numeroProceso: procesoController.text,
                    juzgado: juzgadoController.text,
                    terceroNombre: demandanteController.text,
                    valorEmbargo: publicMoneyFromMajor(montoController.text),
                  );
                  _mostrarExito('Embargo registrado exitosamente');
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
    );
  }
}
