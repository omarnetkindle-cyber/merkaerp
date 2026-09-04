import 'package:flutter/material.dart';

import '../application/accounting_diagnostic_service.dart';

class AccountingDiagnosticPage extends StatefulWidget {
  const AccountingDiagnosticPage({super.key});
  @override
  State<AccountingDiagnosticPage> createState() => _AccountingDiagnosticPageState();
}

class _AccountingDiagnosticPageState extends State<AccountingDiagnosticPage> {
  late Future<AccountingDiagnosticReport> _future;
  @override
  void initState() { super.initState(); _future = AccountingDiagnosticService.instance.run(); }
  void _reload() => setState(() => _future = AccountingDiagnosticService.instance.run());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico contable'), actions: [
        IconButton(tooltip: 'Ejecutar diagnóstico nuevamente', onPressed: _reload, icon: const Icon(Icons.refresh)),
      ]),
      body: FutureBuilder<AccountingDiagnosticReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('No fue posible ejecutar el diagnóstico: ${snapshot.error}'));
          final report = snapshot.data!;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Integridad contable', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Busca asientos descuadrados, cuentas inexistentes, falta de terceros, ventas/compras sin contabilizar y señales de inventario que requieren conciliación.'),
              const SizedBox(height: 12),
              Wrap(spacing: 16, children: [Chip(label: Text('Críticos: ${report.critical}')), Chip(label: Text('Advertencias: ${report.warnings}'))]),
            ]))),
            const SizedBox(height: 12),
            if (report.issues.isEmpty)
              const Card(child: ListTile(leading: Icon(Icons.verified), title: Text('No se detectaron inconsistencias en los controles ejecutados.')))
            else for (final issue in report.issues)
              Card(child: ListTile(
                leading: Icon(issue.severity == 'critical' ? Icons.error_outline : Icons.warning_amber),
                title: Text(issue.title), subtitle: Text(issue.detail),
              )),
            const SizedBox(height: 8),
            const Text('Este diagnóstico comprueba controles estructurales; no sustituye conciliaciones, revisión tributaria ni criterio profesional del contador.'),
          ]);
        },
      ),
    );
  }
}
