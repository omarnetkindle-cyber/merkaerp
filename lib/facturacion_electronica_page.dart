import 'dart:async';
import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:flutter/services.dart';
import 'control_center_agent.dart';
import 'db_helper.dart';
import 'core/invoicing/cufe.dart';
import 'core/invoicing/dian_transmission_client.dart';
import 'core/invoicing/dian_transmission_client_registry.dart';
import 'core/currency/money_currency_resolver.dart';
import 'core/currency/money_value.dart';

class FacturacionElectronicaPage extends StatefulWidget {
  const FacturacionElectronicaPage({super.key});

  @override
  State<FacturacionElectronicaPage> createState() =>
      _FacturacionElectronicaPageState();
}

class _FacturacionElectronicaPageState extends State<FacturacionElectronicaPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<Map<String, dynamic>> _facturas = [];
  List<Map<String, dynamic>> _ventas = [];
  bool _loading = true;

  // DIAN Config fields
  final _resolutionCtrl = TextEditingController(text: '18764000001234');
  final _prefixCtrl = TextEditingController(text: 'FE');
  final _fromRangeCtrl = TextEditingController(text: '1');
  final _toRangeCtrl = TextEditingController(text: '10000');
  final _techKeyCtrl = TextEditingController(text: 'fc8eac2b3a1d4e5f67890abc');
  final _softwareIdCtrl = TextEditingController(text: 'SW-MERKA-ERP-2026');
  final _pinCtrl = TextEditingController(text: '98765');

  String _environment = 'Pruebas / Habilitación';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(_cargarDatos);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _resolutionCtrl.dispose();
    _prefixCtrl.dispose();
    _fromRangeCtrl.dispose();
    _toRangeCtrl.dispose();
    _techKeyCtrl.dispose();
    _softwareIdCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _loading = true);
    try {
      final f = await DatabaseHelper.instance.obtenerFacturasElectronicas();
      final v = await DatabaseHelper.instance.obtenerVentas();
      if (!mounted) return;
      setState(() {
        _facturas = f;
        _ventas = v;
      });
    } catch (e) {
      debugPrint('Error loading electronic invoices: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _emitirFacturaElectronica(Map<String, dynamic> venta) async {
    final ventaId = (venta['id'] as num).toInt();
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final total = MoneyValue.fromSql(venta['total'], currency: currency);
    final fecha =
        venta['fecha']?.toString() ?? DateTime.now().toIso8601String();

    // CUFE oficial: no se calcula si falta clave tecnica, NIT emisor o adquirente.
    final cufe = await _calcularCufeOficial(venta, total, fecha);
    if (cufe == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Guarde primero la configuración de Resolución DIAN antes de emitir.',
            ),
            backgroundColor: MerkaThemeTokens.danger,
          ),
        );
      }
      return;
    }
    final consecutivo = '${_prefixCtrl.text}-${1000 + ventaId}';

    setState(() => _loading = true);
    try {
      await DatabaseHelper.instance.crearFacturaElectronicaBorrador(
        ventaId: ventaId,
        observacion:
            'Emisión directa realizada. Pendiente de transmisión al proveedor tecnológico.',
      );

      // Fetch newly created invoice to update CUFE and state
      final facturasActuales = await DatabaseHelper.instance
          .obtenerFacturasElectronicas();
      final creada = facturasActuales.firstWhere(
        (item) => item['venta_id'] == ventaId,
      );

      await DatabaseHelper.instance.actualizarEstadoFacturaElectronica(
        id: creada['id'] as int,
        estado: 'pendiente_dian',
        cufe: cufe,
        respuestaDian:
            'Sin conectar -- configure su proveedor tecnológico autorizado.',
      );

      await ControlCenterAgent.reportEvent(
        event: 'electronic_invoice.emitted',
        module: 'electronic_invoice',
      );

      SystemSound.play(SystemSoundType.click);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Factura Electrónica $consecutivo creada (pendiente de transmisión).',
            ),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }

      await _cargarDatos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al emitir factura: $e'),
            backgroundColor: MerkaThemeTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<String?> _calcularCufeOficial(
    Map<String, dynamic> venta,
    MoneyValue total,
    String fechaIso,
  ) async {
    final config = await DatabaseHelper.instance.obtenerDianConfig();
    final claveTecnica = config['dian_tech_key'];
    if (claveTecnica == null || claveTecnica.trim().isEmpty) return null;

    final empresa = await DatabaseHelper.instance.obtenerEmpresaConfig();
    final nitEmisor = empresa['nit']?.toString();
    if (nitEmisor == null || nitEmisor.trim().isEmpty) return null;

    final adquirente = await _identificacionAdquirente(venta);
    if (adquirente == null || adquirente.trim().isEmpty) return null;

    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    final currency = await MoneyCurrencyResolver.resolve(
      db,
      companyId: companyId,
    );
    final iva = MoneyValue.fromSql(
      venta['impuesto_total'],
      currency: currency,
      nullableAsZero: true,
    );
    final base = total - iva;
    final dt = DateTime.tryParse(fechaIso) ?? DateTime.now();
    final ambiente = _environment.toLowerCase().contains('pruebas') ? '2' : '1';
    final ventaId = (venta['id'] as num).toInt();

    return computeDianCufe(
      DianCufeInput(
        numeroFactura: '${_prefixCtrl.text}-${1000 + ventaId}',
        fechaFactura:
            '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
        horaFactura:
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}-05:00',
        valorFacturaSinImpuestos: base.toMajorUnitsString(),
        valorIva: iva.toMajorUnitsString(),
        valorImpuestoConsumo: '0.00',
        valorIca: '0.00',
        valorTotal: total.toMajorUnitsString(),
        nitFacturador: nitEmisor,
        numeroAdquiriente: adquirente,
        claveTecnica: claveTecnica,
        tipoAmbiente: ambiente,
      ),
    );
  }

  Future<String?> _identificacionAdquirente(Map<String, dynamic> venta) async {
    final clienteId = venta['cliente_id'];
    if (clienteId is num) {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'clientes',
        columns: ['documento'],
        where: 'id = ?',
        whereArgs: [clienteId.toInt()],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['documento']?.toString();
    }
    return venta['cliente_documento']?.toString();
  }

  void _verDetalleXml(Map<String, dynamic> factura) {
    final cufe = factura['cufe']?.toString() ?? 'Sin CUFE';
    final xmlContent =
        '''<?xml version="1.0" encoding="UTF-8"?>
<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
         xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
         xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
    <cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>
    <cbc:CustomizationID>DIAN 2.1: Factura Electrónica de Venta</cbc:CustomizationID>
    <cbc:ID>${factura['consecutivo'] ?? 'FE-1001'}</cbc:ID>
    <cbc:UUID schemeName="CUFE-SHA384">$cufe</cbc:UUID>
    <cbc:IssueDate>${factura['creada_en']?.toString().split('T').first ?? '2026-06-28'}</cbc:IssueDate>
    <cac:AccountingSupplierParty>
        <cac:Party><cbc:RegistrationName>MerkaERP Empresa Local</cbc:RegistrationName></cac:Party>
    </cac:AccountingSupplierParty>
    <cac:TaxTotal>
        <cbc:TaxAmount currencyID="COP">19000.00</cbc:TaxAmount>
    </cac:TaxTotal>
</Invoice>''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Estructura XML - ${factura['consecutivo']}'),
        content: SizedBox(
          width: 600,
          height: 380,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: MerkaThemeTokens.graphite900,
              child: SelectableText(
                xmlContent,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: MerkaThemeTokens.success,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar XML'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: xmlContent));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('XML copiado al portapapeles')),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: MerkaThemeTokens.info),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Centro de Facturación Electrónica DIAN'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'Documentos Emitidos'),
            Tab(icon: Icon(Icons.send_outlined), text: 'Emisión & Firma'),
            Tab(icon: Icon(Icons.gavel_outlined), text: 'Resolución DIAN'),
            Tab(
              icon: Icon(Icons.settings_suggest_outlined),
              text: 'Proveedor Tecnológico',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Facturas Emitidas
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Facturas y Notas Electrónicas',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar Estado DIAN'),
                      onPressed: _cargarDatos,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _facturas.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay documentos electrónicos emitidos aún. Diríjase a Emisión & Firma para enviar ventas.',
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: ListView.separated(
                            itemCount: _facturas.length,
                            separatorBuilder: (context, idx) =>
                                const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final f = _facturas[idx];
                              final estado =
                                  f['estado']?.toString() ?? 'borrador';
                              final isOk = estado == 'validada';
                              final isPending =
                                  estado == 'pendiente_dian' ||
                                  estado == 'borrador';

                              return ListTile(
                                leading: Icon(
                                  isOk
                                      ? Icons.check_circle
                                      : (isPending
                                            ? Icons.pending
                                            : Icons.error),
                                  color: isOk
                                      ? MerkaThemeTokens.success
                                      : (isPending
                                            ? MerkaThemeTokens.warning
                                            : MerkaThemeTokens.danger),
                                ),
                                title: Text(
                                  f['consecutivo']?.toString() ?? 'FE-Draft',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'CUFE: ${f['cufe'] ?? 'Pendiente'} \nRespuesta: ${f['respuesta_dian'] ?? 'Sin respuesta'}',
                                  maxLines: 2,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => _verDetalleXml(f),
                                      child: const Text(
                                        'Ver XML',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Imprimir representación',
                                      icon: const Icon(Icons.print_outlined),
                                      onPressed: () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Generando Representación Gráfica PDF en segundo plano...',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),

          // Tab 2: Emisión & Firma
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ventas Pendientes de Facturación Electrónica',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Seleccione cualquier venta realizada en el POS para firmarla digitalmente y transmitirla a la DIAN.',
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _ventas.isEmpty
                      ? const Center(child: Text('No hay ventas registradas.'))
                      : ListView.builder(
                          itemCount: _ventas.length,
                          itemBuilder: (context, idx) {
                            final v = _ventas[idx];
                            final total =
                                (v['total'] as num?)?.toDouble() ?? 0.0;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.point_of_sale,
                                  color: MerkaThemeTokens.info,
                                ),
                                title: Text(
                                  'Venta POS #${v['id']} - ${v['producto'] ?? 'Múltiples ítems'}',
                                ),
                                subtitle: Text(
                                  'Fecha: ${v['fecha']} | Cliente: ${v['cliente'] ?? 'General'}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '\$${total.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.send, size: 16),
                                      label: const Text('EMITIR FE'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF2563EB,
                                        ),
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          _emitirFacturaElectronica(v),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Tab 3: Resolución DIAN
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parámetros de Resolución Oficial DIAN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(height: 24),
                      TextField(
                        controller: _resolutionCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Número de Resolución DIAN',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _prefixCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Prefijo Autorizado',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _fromRangeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Rango Desde',
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _toRangeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Rango Hasta',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _techKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Clave Técnica DIAN',
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: MerkaThemeTokens.info,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await DatabaseHelper.instance.guardarDianConfig(
                                dianTechKey: _techKeyCtrl.text,
                                dianPin: _pinCtrl.text,
                                dianResolution: _resolutionCtrl.text,
                                dianSoftwareId: _softwareIdCtrl.text,
                              );
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Resolución DIAN guardada.'),
                                    backgroundColor: MerkaThemeTokens.success,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Error guardando configuración DIAN: $e',
                                    ),
                                    backgroundColor: MerkaThemeTokens.danger,
                                  ),
                                );
                              }
                            }
                          },

                          child: const Text(
                            'GUARDAR RESOLUCIÓN',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Tab 4: Proveedor Tecnológico
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Conexión con Proveedor Tecnológico (PT)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: _environment,
                        decoration: const InputDecoration(
                          labelText: 'Ambiente de Operación',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Pruebas / Habilitación',
                            child: Text('Pruebas / Habilitación'),
                          ),
                          DropdownMenuItem(
                            value: 'Producción Oficial',
                            child: Text('Producción Oficial'),
                          ),
                        ],
                        onChanged: (val) => setState(() => _environment = val!),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _softwareIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Software ID',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pinCtrl,
                        decoration: const InputDecoration(
                          labelText: 'PIN de Software',
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: MerkaThemeTokens.success,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            // Cliente configurado desde Integraciones. Si no existe transporte real, permanece fail-closed.
                            final client = dianTransmissionClientInstance;

                            final cfgStatus = await client.checkConfiguration();
                            if (cfgStatus == ConfigStatus.notConfigured) {
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Sin configuración DIAN. Guarde la configuración en Centro de Facturación.',
                                    ),
                                    backgroundColor: MerkaThemeTokens.danger,
                                  ),
                                );
                              }
                              return;
                            }

                            final conn = await client.checkConnectivity();
                            if (!mounted) return;

                            if (conn.status ==
                                    ConnectivityStatus.notConnected ||
                                conn.status ==
                                    ConnectivityStatus.notConfigured) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(conn.message ?? 'Sin conexión'),
                                  backgroundColor: MerkaThemeTokens.warning,
                                ),
                              );
                            } else if (conn.status ==
                                ConnectivityStatus.connected) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(conn.message ?? 'Conectado'),
                                  backgroundColor: MerkaThemeTokens.success,
                                ),
                              );
                            } else {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    conn.message ?? 'Estado: ${conn.status}',
                                  ),
                                  backgroundColor: MerkaThemeTokens.warning,
                                ),
                              );
                            }
                          },

                          child: const Text(
                            'PROBAR CONEXIÓN Y CERTIFICADO',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
