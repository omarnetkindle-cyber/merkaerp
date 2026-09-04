import 'package:flutter/material.dart';

import '../application/audit_risk_service.dart';

class AuditRiskPage extends StatefulWidget {
  const AuditRiskPage({super.key});

  @override
  State<AuditRiskPage> createState() => _AuditRiskPageState();
}

class _AuditRiskPageState extends State<AuditRiskPage> {
  late Future<AuditRiskSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = AuditRiskService.instance.analyze();
  }

  void _reload() => setState(() => _future = AuditRiskService.instance.analyze());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operaciones para revisión'),
        actions: [IconButton(tooltip: 'Actualizar análisis', onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<AuditRiskSummary>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('No fue posible ejecutar el análisis: ${snapshot.error}'));
          }
          final summary = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auditoría de operaciones sospechosas', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      const Text('MerkaERP detecta señales que merecen revisión humana. Una alerta NO significa fraude ni responsabilidad disciplinaria, fiscal o penal.'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _metric(context, 'Alta prioridad', summary.high, Icons.error_outline),
                          _metric(context, 'Prioridad media', summary.medium, Icons.warning_amber),
                          _metric(context, 'Informativas', summary.low, Icons.info_outline),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (summary.findings.isEmpty)
                const Card(child: ListTile(leading: Icon(Icons.verified), title: Text('No se detectaron señales de riesgo en el período analizado.')))
              else
                for (final finding in summary.findings)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        finding.severity == 'high' ? Icons.gpp_maybe : finding.severity == 'medium' ? Icons.manage_search : Icons.info_outline,
                      ),
                      title: Text(finding.title),
                      subtitle: Text('${finding.detail}\nUsuario: ${finding.user} · ${finding.date.toLocal()} · Fuente: ${finding.source}'),
                      isThreeLine: true,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(BuildContext context, String label, int value, IconData icon) {
    return SizedBox(
      width: 180,
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(value.toString(), style: Theme.of(context).textTheme.headlineSmall),
        subtitle: Text(label),
      ),
    );
  }
}
