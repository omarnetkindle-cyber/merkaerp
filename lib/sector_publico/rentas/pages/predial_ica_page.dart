/// Página de Rentas - Predial e ICA
/// Impuesto Predial + Industria y Comercio + Intereses Moratorios + Cobro Coactivo
library;

import 'package:flutter/material.dart';
import '../../../ui/merka_theme_tokens.dart';
import 'package:merka_erp/pdf_output_dialog.dart';
import '../../../db_helper.dart';
import '../../security/auditoria_service.dart';
import '../services/predial_service.dart';
import '../services/ica_service.dart';
import '../services/cobro_coactivo_service.dart';
import '../services/intereses_moratorios_service.dart';
import '../models/predio.dart';
import '../models/liquidacion_predial.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/currency/public_sector_money.dart';

class PredialICAPage extends StatefulWidget {
  final String entidadId;
  final String usuarioId;
  /// Índice de tab inicial: 0 = Predial, 1 = ICA.
  final int initialTabIndex;

  const PredialICAPage({
    super.key,
    required this.entidadId,
    required this.usuarioId,
    this.initialTabIndex = 0,
  });

  @override
  State<PredialICAPage> createState() => _PredialICAPageState();
}

class _PredialICAPageState extends State<PredialICAPage>
    with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  int _predialSubIndex = 0;
  bool _cargando = true;

  PredialService? _predialService;
  ICAService? _icaService;
  CobroCoactivoService? _cobroCoactivoService;

  List<Predio> _predios = [];
  List<LiquidacionPredial> _liquidaciones = [];
  List<Map<String, dynamic>> _censoICA = [];
  List<Map<String, dynamic>> _declaracionesICA = [];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _inicializarServicios();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    super.dispose();
  }

  Future<void> _inicializarServicios() async {
    setState(() => _cargando = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final auditoria = AuditoriaService(db);
      final intereses = InteresesMoratoriosService();

      _predialService = PredialService(
        db: db,
        interesesService: intereses,
        auditoriaService: auditoria,
      );
      _icaService = ICAService(db: db, auditoriaService: auditoria);
      _cobroCoactivoService = CobroCoactivoService(
        db: db,
        interesesService: intereses,
        auditoriaService: auditoria,
      );

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo inicializar el módulo de Rentas. Verifica la conexión e intenta de nuevo.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error al inicializar servicios de Rentas: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarDatos() async {
    if (_predialService == null || _icaService == null) return;
    try {
      final predios = await _predialService!.consultarPredios(
        entidadId: widget.entidadId,
      );

      final liquidaciones = await _predialService!.consultarLiquidaciones(
        entidadId: widget.entidadId,
        vigencia: DateTime.now().year.toString(),
      );

      final censo = await _icaService!.consultarCensoICA(
        entidadId: widget.entidadId,
      );
      final declaraciones = await _icaService!.consultarDeclaracionesICA(
        entidadId: widget.entidadId,
      );

      setState(() {
        _predios = predios;
        _liquidaciones = liquidaciones;
        _censoICA = censo;
        _declaracionesICA = declaraciones;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron cargar los datos de Rentas. Intenta de nuevo.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error al cargar datos de Rentas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentas - Predial e Industria y Comercio (ICA)'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(tooltip: 'Actualizar información', icon: Icon(Icons.refresh), onPressed: _cargarDatos),
        ],
        bottom: TabBar(
          controller: _mainTabController,
          indicatorColor: Colors.amber,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: 'Impuesto Predial'),
            Tab(icon: Icon(Icons.store), text: 'Industria y Comercio (ICA)'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _mainTabController,
              children: [_buildPredialSection(), _buildICASection()],
            ),
    );
  }

  // --- SECCIÓN PREDIAL ---
  Widget _buildPredialSection() {
    return Scaffold(
      body: IndexedStack(
        index: _predialSubIndex,
        children: [
          _buildPrediosTab(),
          _buildLiquidacionesTab(),
          _buildAcuerdosTab(),
          _buildCobroCoactivoTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _predialSubIndex,
        onTap: (index) => setState(() => _predialSubIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Predios'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt),
            label: 'Liquidaciones',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handshake),
            label: 'Acuerdos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.gavel),
            label: 'Cobro Coactivo',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _mostrarDialogoPredial,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildPrediosTab() {
    if (_predios.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Gestión de Predios Catastrales',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Ley 44/1990 + Catastro Multipropósito IGAC'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _registrarPredioDialog,
              icon: Icon(Icons.add),
              label: const Text('Cargar Catastro IGAC'),
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
      padding: const EdgeInsets.all(16.0),
      itemCount: _predios.length,
      itemBuilder: (context, index) {
        final p = _predios[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.location_city, color: Colors.white),
            ),
            title: Text(
              'Predio: ${p.numeroPredial}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Dirección: ${p.direccion} | Avalúo: ${publicMoneyForDisplay(p.avaluoCatastral)} | Uso: ${p.usoSuelo.name}',
            ),
            trailing: ElevatedButton(
              onPressed: () => _liquidarPredioIndividualDialog(p),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Liquidar', style: TextStyle(fontSize: 11)),
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
            Icon(Icons.receipt, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Liquidaciones Prediales',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Liquidación masiva e individual según Ley 44/1990'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _liquidacionMasivaDialog,
              icon: Icon(Icons.playlist_add_check),
              label: const Text('Liquidación Masiva'),
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
      padding: const EdgeInsets.all(16.0),
      itemCount: _liquidaciones.length,
      itemBuilder: (context, index) {
        final l = _liquidaciones[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.receipt_long, color: Colors.white),
            ),
            title: Text(
              'Liquidación #${l.numeroLiquidacion}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Vigencia: ${l.vigencia} | Total: ${publicMoneyForDisplay(l.totalPagar)} | Estado: ${l.estado.name}',
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.picture_as_pdf,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: 'Exportar Declaración Plano',
              onPressed: () => _exportarPredialPlano(l),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAcuerdosTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.handshake, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Acuerdos de Pago Predial',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Acuerdos de pago para deudores morosos (ET Art. 814)'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _crearAcuerdoDialog,
            icon: Icon(Icons.add),
            label: const Text('Crear Acuerdo de Pago'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCobroCoactivoTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gavel, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Cobro Coactivo Predial',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Etapas del cobro coactivo con plazos legales'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _iniciarCobroCoactivoDialog,
            icon: Icon(Icons.gavel),
            label: const Text('Iniciar Cobro Coactivo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // --- SECCIÓN INDUSTRIA Y COMERCIO (ICA) ---
  Widget _buildICASection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildExportDeclarationBanner(),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Censo de Contribuyentes ICA',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _registrarContribuyenteCensoDialog,
                        icon: Icon(Icons.person_add),
                        label: const Text('Registrar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  _censoICA.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No hay contribuyentes censados en ICA.'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _censoICA.length,
                          itemBuilder: (context, idx) {
                            final c = _censoICA[idx];
                            return ListTile(
                              leading: Icon(
                                Icons.store,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                '${c['razon_social']} (NIT: ${c['nit']})',
                              ),
                              subtitle: Text(
                                'Actividad: ${c['actividad_economica']} | Tipo: ${c['tipo_actividad']}',
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _generarDeclaracionICADialog(
                                  c['id'].toString(),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text(
                                  'Declarar',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Declaraciones Bimestrales ICA Registradas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _declaracionesICA.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No hay declaraciones bimestrales presentadas.',
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _declaracionesICA.length,
                          itemBuilder: (context, idx) {
                            final d = _declaracionesICA[idx];
                            return ListTile(
                              leading: Icon(
                                Icons.description,
                                color: MerkaThemeTokens.info,
                              ),
                              title: Text(
                                'Periodo: ${d['periodo']} - Impuesto ICA: ${publicMoneyForDisplay(publicMoneyFromSql(d['impuesto_ica']))}',
                              ),
                              subtitle: Text(
                                'Base Gravable: ${publicMoneyForDisplay(publicMoneyFromSql(d['base_gravable']))} | Total Pagar: ${publicMoneyForDisplay(publicMoneyFromSql(d['total_pagar']))}',
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.picture_as_pdf,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'Exportar Declaración ICA Plano',
                                onPressed: () => _exportarICA(d),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _registrarReteICADialog,
                  icon: Icon(Icons.receipt_long),
                  label: const Text('Registrar ReteICA'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _generarAvisoTableroDialog,
                  icon: Icon(Icons.branding_watermark),
                  label: const Text('Avisos y Tableros'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Exportacion local basada en Formulario Unico Nacional ICA; el cargue
  /// final puede variar segun el portal tributario de cada municipio.
  Widget _buildExportDeclarationBanner() {
    return Container(
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Exportacion ICA PDF/XML activa. Formato local basado en Formulario Unico Nacional MinHacienda; '
              'el cargue final puede variar segun el portal tributario municipal.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // --- DIÁLOGOS Y ACCIONES ---
  void _mostrarDialogoPredial() {
    switch (_predialSubIndex) {
      case 0:
        _registrarPredioDialog();
        break;
      case 1:
        _liquidacionMasivaDialog();
        break;
      case 2:
        _crearAcuerdoDialog();
        break;
      case 3:
        _iniciarCobroCoactivoDialog();
        break;
    }
  }

  void _registrarPredioDialog() {
    if (_predialService == null) return;
    final numPredialCtrl = TextEditingController();
    final matriculaCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    final barrioCtrl = TextEditingController();
    final municipioCtrl = TextEditingController();
    final departamentoCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final avaluoCatastralCtrl = TextEditingController();
    final avaluoAnteriorCtrl = TextEditingController();
    final usoSueloCtrl = TextEditingController();
    final estratoCtrl = TextEditingController();
    final zonaCtrl = TextEditingController();
    final propIdCtrl = TextEditingController();
    final propNombreCtrl = TextEditingController();
    final propIdentificacionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cargar Predio Catastral IGAC'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numPredialCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número Predial NUPRE (30 dígitos)',
                  hintText: 'ej. 010100010002000000000000000000',
                ),
              ),
              TextField(
                controller: matriculaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Matrícula Inmobiliaria SNR',
                  hintText: 'ej. 50N-123456',
                ),
              ),
              TextField(
                controller: direccionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección del Predio',
                  hintText: 'ej. Calle 10 # 5-20',
                ),
              ),
              TextField(
                controller: barrioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Barrio / Vereda',
                  hintText: 'ej. Centro',
                ),
              ),
              TextField(
                controller: municipioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Municipio',
                  hintText: 'ej. Soacha',
                ),
              ),
              TextField(
                controller: departamentoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Departamento',
                  hintText: 'ej. Cundinamarca',
                ),
              ),
              TextField(
                controller: areaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Área (m²)',
                  hintText: 'ej. 150.0',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: avaluoCatastralCtrl,
                decoration: const InputDecoration(
                  labelText: 'Avalúo Catastral Vigente',
                  hintText: 'ej. 150000000',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: avaluoAnteriorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Avalúo Catastral Anterior',
                  hintText: 'ej. 140000000',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: usoSueloCtrl,
                decoration: const InputDecoration(
                  labelText: 'Uso de Suelo (residencial/comercial/industrial)',
                  hintText: 'ej. residencial',
                ),
              ),
              TextField(
                controller: estratoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Estrato (uno/dos/tres/cuatro/cinco/seis)',
                  hintText: 'ej. tres',
                ),
              ),
              TextField(
                controller: zonaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Zona (urbana/rural)',
                  hintText: 'ej. urbana',
                ),
              ),
              TextField(
                controller: propIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'ID Propietario',
                  hintText: 'ej. PROP-001',
                ),
              ),
              TextField(
                controller: propNombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre Completo Propietario',
                  hintText: 'ej. Juan Pérez',
                ),
              ),
              TextField(
                controller: propIdentificacionCtrl,
                decoration: const InputDecoration(
                  labelText: 'NIT / Cédula Propietario',
                  hintText: 'ej. 80123456',
                ),
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
              if (numPredialCtrl.text.isEmpty ||
                  avaluoCatastralCtrl.text.isEmpty ||
                  propNombreCtrl.text.isEmpty ||
                  propIdentificacionCtrl.text.isEmpty ||
                  propIdCtrl.text.isEmpty ||
                  matriculaCtrl.text.isEmpty ||
                  direccionCtrl.text.isEmpty ||
                  barrioCtrl.text.isEmpty ||
                  municipioCtrl.text.isEmpty ||
                  departamentoCtrl.text.isEmpty ||
                  areaCtrl.text.isEmpty) {
                return;
              }
              try {
                final avaluoCatastral = publicMoneyFromMajor(
                  avaluoCatastralCtrl.text,
                );
                final avaluoAnterior = avaluoAnteriorCtrl.text.isNotEmpty
                    ? publicMoneyFromMajor(avaluoAnteriorCtrl.text)
                    : avaluoCatastral;
                await _predialService!.cargarCatastroIGAC(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  datosCatastro: [
                    {
                      'numero_predial': numPredialCtrl.text,
                      'numero_matricula': matriculaCtrl.text,
                      'direccion': direccionCtrl.text,
                      'barrio': barrioCtrl.text,
                      'municipio': municipioCtrl.text,
                      'departamento': departamentoCtrl.text,
                      'area': double.parse(areaCtrl.text),
                      'avaluo_catastral': avaluoCatastral,
                      'avaluo_anterior': avaluoAnterior,
                      'uso_suelo': usoSueloCtrl.text,
                      'estrato': estratoCtrl.text,
                      'zona': zonaCtrl.text,
                      'propietario_id': propIdCtrl.text,
                      'propietario_nombre': propNombreCtrl.text,
                      'propietario_identificacion': propIdentificacionCtrl.text,
                    },
                  ],
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Catastro cargado con éxito')),
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
            child: const Text('Cargar'),
          ),
        ],
      ),
    );
  }

  void _liquidarPredioIndividualDialog(Predio predio) async {
    if (_predialService == null) return;
    try {
      final liq = await _predialService!.liquidarPredio(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        vigencia: DateTime.now().year.toString(),
        predioId: predio.id,
        ipcAnual: 0.05,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Liquidación realizada. Total a Pagar: ${publicMoneyForDisplay(liq.totalPagar)}',
            ),
          ),
        );
      }
      _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al liquidar predio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _liquidacionMasivaDialog() {
    if (_predialService == null) return;
    final vigenciaCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liquidación Masiva Predial'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se liquidarán todos los predios activos de la entidad. Ingrese la vigencia:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vigenciaCtrl,
              decoration: const InputDecoration(
                labelText: 'Vigencia Fiscal',
                hintText: 'ej. 2026',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (vigenciaCtrl.text.isEmpty) return;
              try {
                final resultado = await _predialService!.liquidacionMasiva(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  vigencia: vigenciaCtrl.text,
                  ipcAnual: 0.05,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Liquidación masiva completada: ${resultado.length} predios procesados.',
                      ),
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
            child: const Text('Ejecutar Masivo'),
          ),
        ],
      ),
    );
  }

  void _crearAcuerdoDialog() {
    if (_predialService == null || _liquidaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay liquidaciones pendientes/vencidas para crear acuerdo de pago.',
          ),
        ),
      );
      return;
    }
    final cuotasCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Acuerdo de Pago (ET Art. 814)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Crear acuerdo de pago para liquidación #${_liquidaciones.first.numeroLiquidacion}:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cuotasCtrl,
              decoration: const InputDecoration(
                labelText: 'Número de Cuotas',
                hintText: 'ej. 6',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (cuotasCtrl.text.isEmpty) return;
              try {
                await _predialService!.crearAcuerdoPago(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  liquidacionId: _liquidaciones.first.id,
                  numeroCuotas: int.parse(cuotasCtrl.text),
                  periodicidadDias: 30,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Acuerdo de pago formalizado'),
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
            child: const Text('Crear Acuerdo'),
          ),
        ],
      ),
    );
  }

  void _iniciarCobroCoactivoDialog() {
    if (_cobroCoactivoService == null || _liquidaciones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay liquidaciones en mora para cobro coactivo.'),
        ),
      );
      return;
    }
    final resolucionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Iniciar Cobro Coactivo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Se iniciará Mandamiento de Pago sobre la liquidación #${_liquidaciones.first.numeroLiquidacion}.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: resolucionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Resolución Mandamiento',
                  hintText: 'ej. RES-CC-2026-001',
                ),
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
              if (resolucionCtrl.text.isEmpty) return;
              try {
                await _cobroCoactivoService!.iniciarCobroCoactivo(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  liquidacionId: _liquidaciones.first.id,
                  numeroResolucion: resolucionCtrl.text,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cobro Coactivo iniciado')),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Iniciar Mandamiento'),
          ),
        ],
      ),
    );
  }

  void _registrarContribuyenteCensoDialog() {
    if (_icaService == null) return;
    final nitCtrl = TextEditingController();
    final razonSocialCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final actividadEconCtrl = TextEditingController();
    final ingresosCtrl = TextEditingController();
    TipoActividadICA tipoActividadSeleccionada = TipoActividadICA.comercial;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Registrar Contribuyente en Censo ICA'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'NIT Contribuyente',
                    hintText: 'ej. 900123456',
                  ),
                ),
                TextField(
                  controller: razonSocialCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Razón Social / Nombre',
                    hintText: 'ej. Comercializadora SOP S.A.S.',
                  ),
                ),
                DropdownButtonFormField<TipoActividadICA>(
                  initialValue: tipoActividadSeleccionada,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Actividad ICA',
                  ),
                  items: TipoActividadICA.values.map((t) {
                    return DropdownMenuItem(value: t, child: Text(t.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => tipoActividadSeleccionada = val);
                    }
                  },
                ),
                TextField(
                  controller: direccionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dirección Comercial',
                    hintText: 'ej. Carrera 15 # 20-30',
                  ),
                ),
                TextField(
                  controller: telefonoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono Contacto',
                    hintText: 'ej. 3101234567',
                  ),
                ),
                TextField(
                  controller: actividadEconCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Actividad Económica CIIU',
                    hintText: 'ej. Comercio al por menor',
                  ),
                ),
                TextField(
                  controller: ingresosCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ingresos Anuales Estimados',
                    hintText: 'ej. 200000000',
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
                if (nitCtrl.text.isEmpty ||
                    razonSocialCtrl.text.isEmpty ||
                    ingresosCtrl.text.isEmpty ||
                    actividadEconCtrl.text.isEmpty ||
                    direccionCtrl.text.isEmpty ||
                    telefonoCtrl.text.isEmpty) {
                  return;
                }
                try {
                  await _icaService!.registrarContribuyenteCenso(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    nit: nitCtrl.text,
                    razonSocial: razonSocialCtrl.text,
                    direccion: direccionCtrl.text,
                    telefono: telefonoCtrl.text,
                    tipoActividad: tipoActividadSeleccionada,
                    actividadEconomica: actividadEconCtrl.text,
                    ingresosAnualesEstimados: publicMoneyFromMajor(
                      ingresosCtrl.text,
                    ),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Contribuyente registrado en Censo ICA'),
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
              child: const Text('Registrar Censo'),
            ),
          ],
        ),
      ),
    );
  }

  void _generarDeclaracionICADialog(String contribuyenteId) {
    if (_icaService == null) return;
    final periodoCtrl = TextEditingController();
    final ingresosGravablesCtrl = TextEditingController();
    final ingresosNoGravablesCtrl = TextEditingController();
    final ingresosExentosCtrl = TextEditingController();
    PeriodoDeclaracionICA periodoDeclaracionSeleccionado =
        PeriodoDeclaracionICA.bimestral;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Generar Declaración Bimestral ICA'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: periodoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periodo (AAAA-MM)',
                    hintText: 'ej. 2026-01',
                  ),
                ),
                DropdownButtonFormField<PeriodoDeclaracionICA>(
                  initialValue: periodoDeclaracionSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Periodicidad de Declaración',
                  ),
                  items: PeriodoDeclaracionICA.values.map((p) {
                    return DropdownMenuItem(value: p, child: Text(p.name));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(
                        () => periodoDeclaracionSeleccionado = val,
                      );
                    }
                  },
                ),
                TextField(
                  controller: ingresosGravablesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ingresos Gravables',
                    hintText: 'ej. 50000000',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: ingresosNoGravablesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ingresos No Gravables',
                    hintText: 'ej. 0',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: ingresosExentosCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ingresos Exentos',
                    hintText: 'ej. 0',
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
                if (periodoCtrl.text.isEmpty ||
                    ingresosGravablesCtrl.text.isEmpty) {
                  return;
                }
                try {
                  final result = await _icaService!.generarDeclaracionICA(
                    entidadId: widget.entidadId,
                    usuarioId: widget.usuarioId,
                    contribuyenteId: contribuyenteId,
                    periodo: periodoCtrl.text,
                    periodoDeclaracion: periodoDeclaracionSeleccionado,
                    ingresosGravables: publicMoneyFromMajor(
                      ingresosGravablesCtrl.text,
                    ),
                    ingresosNoGravables: ingresosNoGravablesCtrl.text.isNotEmpty
                        ? publicMoneyFromMajor(ingresosNoGravablesCtrl.text)
                        : publicMoneyZero(),
                    ingresosExentos: ingresosExentosCtrl.text.isNotEmpty
                        ? publicMoneyFromMajor(ingresosExentosCtrl.text)
                        : publicMoneyZero(),
                  );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Declaración ICA generada. Impuesto: ${CurrencyFormatter.format((result['impuesto_ica'] as num))}',
                        ),
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
              child: const Text('Generar Declaración'),
            ),
          ],
        ),
      ),
    );
  }

  void _registrarReteICADialog() {
    if (_icaService == null) return;
    final nitRetenedorCtrl = TextEditingController();
    final nitRetenidoCtrl = TextEditingController();
    final numeroFacturaCtrl = TextEditingController();
    final periodoCtrl = TextEditingController();
    final valorCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Retención ReteICA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nitRetenedorCtrl,
                decoration: const InputDecoration(
                  labelText: 'NIT Retenedor',
                  hintText: 'ej. 800999888',
                ),
              ),
              TextField(
                controller: nitRetenidoCtrl,
                decoration: const InputDecoration(
                  labelText: 'NIT Retenido',
                  hintText: 'ej. 900123456',
                ),
              ),
              TextField(
                controller: numeroFacturaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Número de Factura',
                  hintText: 'ej. FAC-2026-001',
                ),
              ),
              TextField(
                controller: periodoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Periodo (AAAA-MM)',
                  hintText: 'ej. 2026-01',
                ),
              ),
              TextField(
                controller: valorCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor Retenido',
                  hintText: 'ej. 150000',
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
              if (nitRetenedorCtrl.text.isEmpty ||
                  valorCtrl.text.isEmpty ||
                  numeroFacturaCtrl.text.isEmpty ||
                  periodoCtrl.text.isEmpty ||
                  nitRetenidoCtrl.text.isEmpty) {
                return;
              }
              try {
                await _icaService!.registrarReteICA(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  nitRetenedor: nitRetenedorCtrl.text,
                  nitRetenido: nitRetenidoCtrl.text,
                  periodo: periodoCtrl.text,
                  valorRetenido: publicMoneyFromMajor(valorCtrl.text),
                  numeroFactura: numeroFacturaCtrl.text,
                  fechaFactura: DateTime.now(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ReteICA registrado con éxito'),
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
            child: const Text('Registrar ReteICA'),
          ),
        ],
      ),
    );
  }

  void _generarAvisoTableroDialog() {
    if (_icaService == null || _censoICA.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se requiere al menos un contribuyente registrado en el censo de ICA.',
          ),
        ),
      );
      return;
    }
    final contribId = _censoICA.first['id'].toString();
    final periodoCtrl = TextEditingController();
    final tipoAvisoCtrl = TextEditingController();
    final ubicacionCtrl = TextEditingController();
    final areaMetrosCtrl = TextEditingController();
    final valorAvisoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generar Impuesto Avisos y Tableros'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: periodoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Periodo (AAAA-MM)',
                  hintText: 'ej. 2026-01',
                ),
              ),
              TextField(
                controller: tipoAvisoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Aviso',
                  hintText: 'ej. Valla Publicitaria',
                ),
              ),
              TextField(
                controller: ubicacionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Ubicación de Impresión',
                  hintText: 'ej. Fachada Principal',
                ),
              ),
              TextField(
                controller: areaMetrosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Área (m²)',
                  hintText: 'ej. 12.5',
                ),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: valorAvisoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Valor Comercial del Aviso',
                  hintText: 'ej. 5000000',
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
              if (valorAvisoCtrl.text.isEmpty ||
                  periodoCtrl.text.isEmpty ||
                  tipoAvisoCtrl.text.isEmpty ||
                  ubicacionCtrl.text.isEmpty ||
                  areaMetrosCtrl.text.isEmpty) {
                return;
              }
              try {
                await _icaService!.generarAvisoTablero(
                  entidadId: widget.entidadId,
                  usuarioId: widget.usuarioId,
                  contribuyenteId: contribId,
                  periodo: periodoCtrl.text,
                  tipoAviso: tipoAvisoCtrl.text,
                  valorAviso: publicMoneyFromMajor(valorAvisoCtrl.text),
                  ubicacion: ubicacionCtrl.text,
                  areaMetros: double.parse(areaMetrosCtrl.text),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Impuesto de Avisos y Tableros generado'),
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
            child: const Text('Generar Impuesto Aviso'),
          ),
        ],
      ),
    );
  }

  void _exportarPredialPlano(LiquidacionPredial liquidacion) async {
    if (_predialService == null) return;
    try {
      final plano = await _predialService!.exportarDeclaracionPredialAPlano(
        liquidacion.id,
      );
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'Declaración Predial #${liquidacion.numeroLiquidacion}',
            ),
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

  // ignore: unused_element
  void _exportarICAPlano(Map<String, dynamic> declaracion) async {
    if (_icaService == null) return;
    try {
      final id = declaracion['id'] as String;
      final plano = await _icaService!.exportarDeclaracionICAAPlano(id);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Declaración ICA Exportada (.txt)'),
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

  void _exportarICA(Map<String, dynamic> declaracion) async {
    if (_icaService == null) return;
    final id = declaracion['id'] as String;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exportar Declaracion ICA'),
        content: const Text(
          'Genera PDF local o XML estructurado con datos del censo, ReteICA y liquidacion.',
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.code),
            label: const Text('Ver XML'),
            onPressed: () async {
              Navigator.pop(context);
              await _mostrarICAXml(id);
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
            onPressed: () async {
              Navigator.pop(context);
              await PdfOutputDialog.mostrar(
                context: this.context,
                titulo: 'Declaracion ICA ${declaracion['periodo']}',
                generarBytes: () =>
                    _icaService!.exportarDeclaracionICAPdfBytes(id),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarICAXml(String declaracionId) async {
    try {
      final xml = await _icaService!.exportarDeclaracionICAXml(declaracionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Declaracion ICA XML'),
          content: SingleChildScrollView(child: SelectableText(xml)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
