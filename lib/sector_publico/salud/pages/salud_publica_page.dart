/// Página de Salud Pública
/// RIPS + Contratos EPS/ADRES + Facturación de Salud + Glosas
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/rips_service.dart';
import '../services/glosas_service.dart';
import '../services/facturacion_salud_service.dart';
import '../models/rips.dart';
import '../models/glosa.dart';
import '../models/contrato_eps.dart';
import '../models/factura_salud.dart';
import '../../../core/currency/public_sector_money.dart';

class SaludPublicaPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;

  const SaludPublicaPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<SaludPublicaPage> createState() => _SaludPublicaPageState();
}

class _SaludPublicaPageState extends State<SaludPublicaPage> {
  int _selectedIndex = 0;
  bool _cargando = true;

  RIPSService? _ripsService;
  GlosasService? _glosasService;
  FacturacionSaludService? _facturacionService;

  List<RIPS> _rips = [];
  List<Glosa> _glosas = [];
  List<ContratoEPS> _contratos = [];
  List<FacturaSalud> _facturas = [];

  @override
  void initState() {
    super.initState();
    _inicializarServicios();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _cargando = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoria = AuditoriaService(db);

      _ripsService = RIPSService(db: db, auditoriaService: auditoria);
      _glosasService = GlosasService(db: db, auditoriaService: auditoria);
      _facturacionService = FacturacionSaludService(
        db: db,
        auditoriaService: auditoria,
      );

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al inicializar servicios de Salud Pública: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_ripsService == null ||
        _glosasService == null ||
        _facturacionService == null) {
      return;
    }
    try {
      final ripsList = await _ripsService!.consultarRIPS(
        entidadId: widget.entidadId,
      );
      final glosasList = await _glosasService!.consultarGlosas(
        entidadId: widget.entidadId,
      );
      final contratosList = await _facturacionService!.consultarContratos(
        entidadId: widget.entidadId,
      );
      final facturasList = await _facturacionService!.consultarFacturas(
        entidadId: widget.entidadId,
      );

      setState(() {
        _rips = ripsList;
        _glosas = glosasList;
        _contratos = contratosList;
        _facturas = facturasList;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos de Salud Pública: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salud Pública (RIPS / EPS / ADRES)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(tooltip: 'Actualizar información', icon: Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildEpsAdresBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildRIPSTab(),
                      _buildContratosTab(),
                      _buildFacturasTab(),
                      _buildGlosasTab(),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'RIPS'),
          BottomNavigationBarItem(
            icon: Icon(Icons.handshake),
            label: 'Contratos EPS',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt),
            label: 'Facturación',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.warning), label: 'Glosas'),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoAccion,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildEpsAdresBanner() {
    return Container(
      color: MerkaThemeTokens.gold200,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.verified,
            color: MerkaThemeTokens.success,
          ), // teal.shade800 — contraste suficiente sobre teal.shade100
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Gestión integral ESE / Salud: ${_contratos.length} contratos EPS/ADRES activos, ${_facturas.length} facturas emitidas y RIPS/Glosas consolidados.',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRIPSTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _registrarRIPSDialog,
                  icon: Icon(Icons.add),
                  label: const Text('Registrar RIPS'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generarArchivoPlanoDialog,
                  icon: Icon(Icons.file_download),
                  label: const Text('Consultar RIPS JSON FEV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _rips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Registros RIPS',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Registros Individuales de Prestación de Servicios de Salud',
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _rips.length,
                  itemBuilder: (context, index) {
                    final item = _rips[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: Icon(
                            Icons.local_hospital,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          '${item.nombrePaciente} (${item.tipoIdentificacion}: ${item.numeroIdentificacion})',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Factura #${item.numeroFactura} | Servicio: ${item.nombreServicio} | Neto: ${publicMoneyForDisplay(item.valorNeto)}',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildContratosTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _registrarContratoEPSDialog,
              icon: Icon(Icons.add),
              label: const Text('Registrar Contrato EPS / ADRES'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: _contratos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.handshake, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Contratos EPS / ADRES',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Contratación por Capitación y Evento para ESE Hospital',
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _contratos.length,
                  itemBuilder: (context, index) {
                    final c = _contratos[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: Icon(Icons.business, color: Colors.white),
                        ),
                        title: Text(
                          'Contrato #${c.numeroContrato} - ${c.epsAdresNombre}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Régimen: ${c.regimen.name} | Contratado: ${publicMoneyForDisplay(c.montoContrato)} | Facturado: ${publicMoneyForDisplay(c.montoFacturado)}',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFacturasTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generarFacturaSaludDialog,
              icon: Icon(Icons.receipt_long),
              label: const Text('Generar Factura de Servicios de Salud'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: _facturas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Facturación de Servicios de Salud',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text('Venta de servicios de salud a EPS y ADRES'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _facturas.length,
                  itemBuilder: (context, index) {
                    final f = _facturas[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          child: Icon(Icons.receipt, color: Colors.white),
                        ),
                        title: Text(
                          'Factura #${f.numeroFactura} - Periodo: ${f.periodo}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Total: ${publicMoneyForDisplay(f.montoTotal)} | Glosado: ${publicMoneyForDisplay(f.montoGlosado)} | Estado: ${f.estado}',
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.picture_as_pdf,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          tooltip: 'Exportar Factura Plano',
                          onPressed: () => _exportarFacturaPlano(f),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildGlosasTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generarGlosaDialog,
              icon: Icon(Icons.add_alert),
              label: const Text('Generar Glosa EPS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
        Expanded(
          child: _glosas.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'Gestión de Glosas EPS',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Auditaje y respuesta de glosas de facturas de salud',
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _glosas.length,
                  itemBuilder: (context, index) {
                    final glosa = _glosas[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: glosa.estado == EstadoGlosa.aceptada
                              ? Colors.green
                              : Colors.orange,
                          child: Icon(Icons.rule, color: Colors.white),
                        ),
                        title: Text(
                          'Glosa #${glosa.numeroGlosa} - EPS: ${glosa.eps}',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Factura #${glosa.numeroFactura} | Glosado: ${publicMoneyForDisplay(glosa.valorGlosado)} | Estado: ${glosa.estado.name}',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _mostrarDialogoAccion() {
    switch (_selectedIndex) {
      case 0:
        _registrarRIPSDialog();
        break;
      case 1:
        _registrarContratoEPSDialog();
        break;
      case 2:
        _generarFacturaSaludDialog();
        break;
      case 3:
        _generarGlosaDialog();
        break;
    }
  }

  void _registrarContratoEPSDialog() {
    if (_facturacionService == null) return;
    final numContratoCtrl = TextEditingController();
    final epsNombreCtrl = TextEditingController();
    final epsNitCtrl = TextEditingController();
    final montoCtrl = TextEditingController();
    RegimenSalud regimenSeleccionado = RegimenSalud.subsidiado;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Contrato EPS / ADRES'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: numContratoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de Contrato',
                    hintText: 'ej. CNT-EPS-2026-001',
                  ),
                ),
                TextField(
                  controller: epsNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre EPS / ADRES',
                    hintText: 'ej. Nueva EPS S.A.',
                  ),
                ),
                TextField(
                  controller: epsNitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'NIT EPS',
                    hintText: 'ej. 900156877-1',
                  ),
                ),
                DropdownButtonFormField<RegimenSalud>(
                  initialValue: regimenSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Régimen de Salud',
                  ),
                  items: RegimenSalud.values.map((r) {
                    return DropdownMenuItem(
                      value: r,
                      child: Text(r.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => regimenSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: montoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monto Total Contratado',
                    hintText: 'ej. 500000000',
                  ),
                  keyboardType: TextInputType.number,
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
                if (numContratoCtrl.text.isEmpty ||
                    epsNombreCtrl.text.isEmpty ||
                    epsNitCtrl.text.isEmpty ||
                    montoCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _facturacionService!.registrarContratoEPS(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    numeroContrato: numContratoCtrl.text,
                    epsAdresNombre: epsNombreCtrl.text,
                    epsAdresNit: epsNitCtrl.text,
                    regimen: regimenSeleccionado,
                    montoContrato: publicMoneyFromMajor(montoCtrl.text),
                    fechaInicio: DateTime.now(),
                    fechaFin: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contrato EPS registrado')),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Registrar Contrato'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarFacturaSaludDialog() {
    if (_facturacionService == null || _contratos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se requiere al menos un contrato EPS para expedir facturas de salud.',
          ),
        ),
      );
      return;
    }

    String contratoSeleccionadoId = _contratos.first.id;
    final numFacCtrl = TextEditingController(
      text:
          'FAC-SALUD-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
    );
    final periodoCtrl = TextEditingController(
      text:
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );
    final montoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Factura Venta de Salud'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: contratoSeleccionadoId,
                  decoration: const InputDecoration(
                    labelText: 'Seleccionar Contrato EPS / ADRES',
                  ),
                  items: _contratos.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.numeroContrato} - ${c.epsAdresNombre}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => contratoSeleccionadoId = val);
                    }
                  },
                ),
                TextField(
                  controller: numFacCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de Factura',
                    hintText: 'ej. FAC-2026-001',
                  ),
                ),
                TextField(
                  controller: periodoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periodo de Facturación',
                    hintText: 'ej. 2026-03',
                  ),
                ),
                TextField(
                  controller: montoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monto Total Facturado',
                    hintText: 'ej. 25000000',
                  ),
                  keyboardType: TextInputType.number,
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
                if (numFacCtrl.text.isEmpty ||
                    periodoCtrl.text.isEmpty ||
                    montoCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _facturacionService!.generarFacturaSalud(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    contratoId: contratoSeleccionadoId,
                    numeroFactura: numFacCtrl.text,
                    periodo: periodoCtrl.text,
                    montoTotal: publicMoneyFromMajor(montoCtrl.text),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Factura de Salud expedida'),
                      ),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Expedir Factura'),
            ),
          ],
        ),
      ),
    );
  }

  void _exportarFacturaPlano(FacturaSalud factura) async {
    if (_facturacionService == null) return;
    try {
      final plano = await _facturacionService!.exportarFacturaAPlano(
        factura.id,
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Factura Salud #${factura.numeroFactura} (.txt Plano)'),
            content: SingleChildScrollView(child: SelectableText(plano)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _registrarRIPSDialog() {
    if (_ripsService == null) return;
    final prestadorCodigoCtrl = TextEditingController();
    final prestadorNombreCtrl = TextEditingController();
    final facturaCtrl = TextEditingController();
    final pacienteIdCtrl = TextEditingController();
    final pacienteNombreCtrl = TextEditingController();
    final tipoIdCtrl = TextEditingController();
    final codigoServicioCtrl = TextEditingController();
    final servicioNombreCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final copagoCtrl = TextEditingController();
    TipoRIPS tipoRIPSSeleccionado = TipoRIPS.ac;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar RIPS'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TipoRIPS>(
                  initialValue: tipoRIPSSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Registro RIPS',
                  ),
                  items: TipoRIPS.values.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(t.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoRIPSSeleccionado = val);
                    }
                  },
                ),
                TextField(
                  controller: prestadorCodigoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código Prestador (REPS)',
                    hintText: 'ej. 11001001',
                  ),
                ),
                TextField(
                  controller: prestadorNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Prestador / ESE',
                    hintText: 'ej. ESE Hospital Municipal',
                  ),
                ),
                TextField(
                  controller: facturaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de Factura',
                    hintText: 'ej. FAC-SALUD-001',
                  ),
                ),
                TextField(
                  controller: tipoIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo Identificación (CC/TI/CE)',
                    hintText: 'ej. CC',
                  ),
                ),
                TextField(
                  controller: pacienteIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Identificación Paciente',
                    hintText: 'ej. 1018222333',
                  ),
                ),
                TextField(
                  controller: pacienteNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Completo Paciente',
                    hintText: 'ej. Juan Pérez',
                  ),
                ),
                TextField(
                  controller: codigoServicioCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Código Servicio CUPS',
                    hintText: 'ej. 890201',
                  ),
                ),
                TextField(
                  controller: servicioNombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre Servicio / Consulta',
                    hintText: 'ej. Consulta Medicina General',
                  ),
                ),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Servicio',
                    hintText: 'ej. 60000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: copagoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Copago / Cuota Moderadora',
                    hintText: 'ej. 5000',
                  ),
                  keyboardType: TextInputType.number,
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
                if (facturaCtrl.text.isEmpty ||
                    pacienteIdCtrl.text.isEmpty ||
                    valorCtrl.text.isEmpty ||
                    prestadorCodigoCtrl.text.isEmpty ||
                    servicioNombreCtrl.text.isEmpty ||
                    prestadorNombreCtrl.text.isEmpty ||
                    tipoIdCtrl.text.isEmpty ||
                    pacienteNombreCtrl.text.isEmpty ||
                    codigoServicioCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final valor = publicMoneyFromMajor(valorCtrl.text);
                  final copago = copagoCtrl.text.isNotEmpty
                      ? publicMoneyFromMajor(copagoCtrl.text)
                      : publicMoneyZero();
                  await _ripsService!.registrarRIPS(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    tipoRIPS: tipoRIPSSeleccionado,
                    codigoPrestador: prestadorCodigoCtrl.text,
                    nombrePrestador: prestadorNombreCtrl.text,
                    numeroFactura: facturaCtrl.text,
                    fechaFactura: DateTime.now(),
                    fechaInicio: DateTime.now(),
                    fechaFin: DateTime.now(),
                    codigoPaciente: pacienteIdCtrl.text,
                    nombrePaciente: pacienteNombreCtrl.text,
                    tipoIdentificacion: tipoIdCtrl.text,
                    numeroIdentificacion: pacienteIdCtrl.text,
                    codigoServicio: codigoServicioCtrl.text,
                    nombreServicio: servicioNombreCtrl.text,
                    valorServicio: valor,
                    valorCopago: copago,
                    valorModera: publicMoneyZero(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('RIPS registrado exitosamente'),
                      ),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarArchivoPlanoDialog() {
    if (_ripsService == null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Consultar RIPS JSON FEV'),
        content: const Text(
          'Se consolidará el archivo plano de registros RIPS en formato oficial Ministerio de Salud para envío a la EPS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final plano = await _ripsService!.obtenerUltimoRipsJson(
                  entidadId: widget.entidadId,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('RIPS JSON FEV'),
                      content: SingleChildScrollView(
                        child: SelectableText(plano),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al generar plano: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Ver JSON'),
          ),
        ],
      ),
    );
  }

  void _generarGlosaDialog() {
    if (_glosasService == null || _rips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se requiere al menos un RIPS registrado para generar glosa.',
          ),
        ),
      );
      return;
    }

    final ripsItem = _rips.first;
    final epsCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();
    final valorGlosadoCtrl = TextEditingController();
    TipoGlosa tipoGlosaSeleccionada = TipoGlosa.errorFacturacion;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Generar Glosa EPS - Factura #${ripsItem.numeroFactura}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: epsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre EPS',
                    hintText: 'ej. Nueva EPS',
                  ),
                ),
                DropdownButtonFormField<TipoGlosa>(
                  initialValue: tipoGlosaSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Tipo / Causal de Glosa',
                  ),
                  items: TipoGlosa.values.map((g) {
                    return DropdownMenuItem(value: g, child: Text(g.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoGlosaSeleccionada = val);
                    }
                  },
                ),
                TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de Glosa',
                    hintText: 'ej. Inconsistencia en código CUPS',
                  ),
                ),
                TextField(
                  controller: valorGlosadoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Valor Glosado',
                    hintText: 'ej. 20000',
                  ),
                  keyboardType: TextInputType.number,
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
                if (epsCtrl.text.isEmpty ||
                    valorGlosadoCtrl.text.isEmpty ||
                    motivoCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final valorGlosado = publicMoneyFromMajor(
                    valorGlosadoCtrl.text,
                  );
                  await _glosasService!.generarGlosa(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    ripsId: ripsItem.id,
                    numeroFactura: ripsItem.numeroFactura,
                    eps: epsCtrl.text,
                    tipoGlosa: tipoGlosaSeleccionada,
                    motivo: motivoCtrl.text,
                    valorGlosado: valorGlosado,
                    valorAceptado: publicMoneyZero(),
                    valorRechazado: valorGlosado,
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Glosa radicada exitosamente'),
                      ),
                    );
                  }
                  _cargarDatos();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Radicar Glosa'),
            ),
          ],
        ),
      ),
    );
  }
}
