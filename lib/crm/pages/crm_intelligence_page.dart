import 'package:flutter/material.dart';

import '../../ui/merka_theme_tokens.dart';
import '../../core/currency/money_value.dart';
import '../../db_helper.dart';
import '../application/crm_campaign_service.dart';
import '../domain/crm_campaign.dart';
import '../application/crm_customer_intelligence_service.dart';
import '../application/crm_sales_analytics_service.dart';

class CrmIntelligencePage extends StatefulWidget {
  const CrmIntelligencePage({super.key});

  @override
  State<CrmIntelligencePage> createState() => _CrmIntelligencePageState();
}

class _CrmIntelligencePageState extends State<CrmIntelligencePage> {
  Future<_CrmIntelligenceData>? _future;
  String _segment = 'Todos';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<_CrmIntelligenceData> _load() async {
    final customer = await const CrmCustomerIntelligenceService().analyze();
    final sales = CrmSalesAnalyticsService();
    final forecast = await sales.forecast();
    final funnel = await sales.funnel();
    return _CrmIntelligenceData(customer, forecast, funnel);
  }


  Future<void> _createCampaign(_CrmIntelligenceData data, List<CrmCustomerInsight> customers) async {
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El segmento seleccionado no tiene clientes.')));
      return;
    }
    final name = TextEditingController(text: 'Campaña ${_segment == 'Todos' ? 'CRM' : _segment}');
    final type = TextEditingController(text: _segment == 'Inactivo' ? 'reactivacion' : _segment == 'VIP' ? 'fidelizacion' : 'seguimiento');
    final budget = TextEditingController(text: '0');
    final expected = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Crear campaña · ${_segment == 'Todos' ? 'todos' : _segment}'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${customers.length} cliente(s) quedarán como público objetivo. MerkaERP no enviará comunicaciones automáticamente.'),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre de la campaña')),
          const SizedBox(height: 10),
          TextField(controller: type, decoration: const InputDecoration(labelText: 'Tipo / objetivo')),
          const SizedBox(height: 10),
          TextField(controller: budget, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Presupuesto')),
          const SizedBox(height: 10),
          TextField(controller: expected, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Ingreso esperado')),
        ]))),
        actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancelar')), FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('Crear campaña'))],
      ),
    );
    if (ok != true) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
      final campaign = CrmCampaign(
        companyId: companyId,
        name: name.text.trim(),
        campaignType: type.text.trim(),
        startDate: DateTime.now(),
        budget: MoneyValue.fromMajorUnits(budget.text.trim().replaceAll(',', '.'), currency: data.customer.currency),
        expectedRevenue: MoneyValue.fromMajorUnits(expected.text.trim().replaceAll(',', '.'), currency: data.customer.currency),
      );
      final id = await CrmCampaignService().createForCustomers(campaign, customers.map((c)=>c.clientId).toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Campaña #$id creada con ${customers.length} clientes objetivo.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo crear la campaña: $e'), backgroundColor: MerkaThemeTokens.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inteligencia CRM'),
        actions: [
          IconButton(
            tooltip: 'Actualizar análisis',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_CrmIntelligenceData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
          final data = snapshot.data!;
          final customers = _segment == 'Todos'
              ? data.customer.customers
              : data.customer.customers.where((c) => c.segment == _segment).toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Radar comercial',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Segmentación automática basada en frecuencia, valor, cartera y '
                'recencia. Las recomendaciones son informativas: ninguna campaña '
                'ni comunicación se envía sin intervención del usuario.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Kpi('VIP', '${data.customer.vipCount}', Icons.workspace_premium, MerkaThemeTokens.gold500),
                  _Kpi('En riesgo', '${data.customer.atRiskCount}', Icons.report_problem_outlined, MerkaThemeTokens.warning),
                  _Kpi('Inactivos', '${data.customer.inactiveCount}', Icons.person_off_outlined, MerkaThemeTokens.graphite600),
                  _Kpi('Frecuentes', '${data.customer.frequentCount}', Icons.repeat, MerkaThemeTokens.navy700),
                  _Kpi('Pipeline abierto', data.forecast.totalOpenPipeline.format(), Icons.trending_up, MerkaThemeTokens.navy600),
                  _Kpi('Pipeline ponderado', data.forecast.weightedOpenPipeline.format(), Icons.analytics_outlined, MerkaThemeTokens.success),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 24,
                    runSpacing: 12,
                    children: [
                      _ratio('Lead → oportunidad', data.funnel.leadToOpportunityRate),
                      _ratio('Oportunidad → ganada', data.funnel.opportunityToWonRate),
                      Text('Valor medio por cliente: ${data.customer.averageCustomerValue.format()}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  for (final segment in const ['Todos', 'VIP', 'Frecuente', 'En riesgo', 'Inactivo', 'Activo'])
                    ChoiceChip(
                      label: Text(segment),
                      selected: _segment == segment,
                      onSelected: (_) => setState(() => _segment = segment),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _createCampaign(data, customers),
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text('Crear campaña para ${_segment == 'Todos' ? 'todos' : _segment}'),
                ),
              ),
              const SizedBox(height: 12),
              if (customers.isEmpty)
                const Card(child: ListTile(title: Text('No hay clientes en este segmento.')))
              else
                ...customers.map((c) => _CustomerCard(c)),
            ],
          );
        },
      ),
    );
  }

  Widget _ratio(String label, double value) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: '),
          Text('${value.toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard(this.customer);
  final CrmCustomerInsight customer;

  @override
  Widget build(BuildContext context) {
    final color = switch (customer.segment) {
      'VIP' => MerkaThemeTokens.gold500,
      'En riesgo' => MerkaThemeTokens.warning,
      'Inactivo' => MerkaThemeTokens.graphite600,
      'Frecuente' => MerkaThemeTokens.navy700,
      _ => MerkaThemeTokens.success,
    };
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(Icons.person_outline, color: color),
        ),
        title: Row(
          children: [
            Expanded(child: Text(customer.name)),
            Chip(label: Text(customer.segment)),
          ],
        ),
        subtitle: Text(
          'Compras ${customer.salesCount} · Total ${customer.totalSales.format()} · '
          'Ticket ${customer.averageTicket.format()}\n'
          'Última ${_date(customer.lastPurchase)} · Próxima estimada ${_date(customer.nextExpectedPurchase)}'
          '${customer.outstanding.minorUnits > 0 ? ' · Cartera ${customer.outstanding.format()}' : ''}',
        ),
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return 'sin dato';
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

class _CrmIntelligenceData {
  const _CrmIntelligenceData(this.customer, this.forecast, this.funnel);
  final CrmCustomerIntelligenceSnapshot customer;
  final CrmForecastSummary forecast;
  final CrmFunnelSummary funnel;
}
