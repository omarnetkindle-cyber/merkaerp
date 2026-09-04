import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/currency/currency.dart';
import '../core/currency/money_currency_resolver.dart';
import '../core/currency/money_value.dart';
import '../db_helper.dart';
import 'merka_theme_tokens.dart';

class FinanceModePanel extends StatefulWidget {
  const FinanceModePanel({
    super.key,
    required this.onOpenReceivables,
    required this.onOpenPayables,
    required this.onOpenCash,
    required this.onCommandPalette,
  });

  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenPayables;
  final VoidCallback onOpenCash;
  final VoidCallback onCommandPalette;

  @override
  State<FinanceModePanel> createState() => _FinanceModePanelState();
}

class _FinanceModePanelState extends State<FinanceModePanel> {
  double _receivables = 0.0;
  double _payables = 0.0;
  double _cashFlow = 0.0;

  double _incomeMonth = 0.0;
  double _expenseMonth = 0.0;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFinanceData();
  }

  Future<void> _loadFinanceData() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final currency = await MoneyCurrencyResolver.resolve(
        db,
        companyId: companyId,
      );

      // Receivables total
      final recRows = await db.rawQuery(
        "SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_cobrar WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'",
        [companyId],
      );
      _receivables = _major(recRows.first['total'], currency);

      // Payables total
      final payRows = await db.rawQuery(
        "SELECT COALESCE(SUM(saldo), 0) AS total FROM cuentas_por_pagar WHERE company_id = ? AND saldo > 0 AND estado != 'pagada'",
        [companyId],
      );
      _payables = _major(payRows.first['total'], currency);

      // Caja flows
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final monthEnd = DateTime(
        now.year,
        now.month + 1,
        0,
        23,
        59,
      ).toIso8601String();

      final incomeRows = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'ingreso' AND fecha BETWEEN ? AND ?",
        [companyId, monthStart, monthEnd],
      );
      final expenseRows = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'egreso' AND fecha BETWEEN ? AND ?",
        [companyId, monthStart, monthEnd],
      );

      _incomeMonth = _major(incomeRows.first['total'], currency);
      _expenseMonth = _major(expenseRows.first['total'], currency);

      // All-time cash balance simulation
      final allIncome = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'ingreso'",
        [companyId],
      );
      final allExpense = await db.rawQuery(
        "SELECT COALESCE(SUM(monto), 0) AS total FROM movimientos_caja WHERE company_id = ? AND tipo = 'egreso'",
        [companyId],
      );
      _cashFlow =
          _major(allIncome.first['total'], currency) -
          _major(allExpense.first['total'], currency);
    } catch (e) {
      debugPrint('Error loading finance mode data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatMoney(double val) {
    final rounded = val.round().toString();
    return '\$${rounded.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}';
  }

  double _major(Object? value, Currency currency) => MoneyValue.fromSql(
    value,
    currency: currency,
    nullableAsZero: true,
  ).toMajorUnitsDoubleForDisplay();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: MerkaThemeTokens.info),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        final kpisSection = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _FinanceKpiCard(
              title: 'Cuentas por Cobrar (AR)',
              value: _formatMoney(_receivables),
              icon: PhosphorIcons.wallet(),
              color: MerkaThemeTokens.success,
              onTap: widget.onOpenReceivables,
            ),
            _FinanceKpiCard(
              title: 'Cuentas por Pagar (AP)',
              value: _formatMoney(_payables),
              icon: PhosphorIcons.bank(),
              color: MerkaThemeTokens.danger,
              onTap: widget.onOpenPayables,
            ),
            _FinanceKpiCard(
              title: 'Saldo en Caja / Bancos',
              value: _formatMoney(_cashFlow),
              icon: PhosphorIcons.coins(),
              color: MerkaThemeTokens.info,
              onTap: widget.onOpenCash,
            ),
          ],
        );

        final leftColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            kpisSection,
            const SizedBox(height: 24),

            // Quick links
            Text(
              'Accesos Rápidos Financieros',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickLinkButton(
                  label: 'Conciliación Bancaria',
                  icon: PhosphorIcons.checkCircle(),
                  onTap: widget.onCommandPalette,
                ),
                _QuickLinkButton(
                  label: 'Comprobantes Diario',
                  icon: PhosphorIcons.fileText(),
                  onTap: widget.onCommandPalette,
                ),
                _QuickLinkButton(
                  label: 'Periodos Contables',
                  icon: PhosphorIcons.calendar(),
                  onTap: widget.onCommandPalette,
                ),
              ],
            ),
          ],
        );

        final rightColumn = Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MerkaThemeTokens.paper100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ingresos vs Gastos del Mes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Custom visual graph
              _FinanceProgressLine(
                label: 'Ingresos Operacionales',
                value: _incomeMonth,
                color: MerkaThemeTokens.success,
                max: _incomeMonth > _expenseMonth
                    ? _incomeMonth
                    : _expenseMonth,
                formatFn: _formatMoney,
              ),
              const SizedBox(height: 16),
              _FinanceProgressLine(
                label: 'Gastos y Costos',
                value: _expenseMonth,
                color: MerkaThemeTokens.danger,
                max: _incomeMonth > _expenseMonth
                    ? _incomeMonth
                    : _expenseMonth,
                formatFn: _formatMoney,
              ),
              const Divider(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Resultado del Ejercicio:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _formatMoney(_incomeMonth - _expenseMonth),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: (_incomeMonth - _expenseMonth) >= 0
                          ? MerkaThemeTokens.success
                          : MerkaThemeTokens.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        if (compact) {
          return SingleChildScrollView(
            child: Column(
              children: [leftColumn, const SizedBox(height: 16), rightColumn],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: leftColumn),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: rightColumn),
          ],
        );
      },
    );
  }
}

class _FinanceKpiCard extends StatelessWidget {
  const _FinanceKpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: MerkaThemeTokens.paper100),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: MerkaThemeTokens.graphite900,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 10,
                        color: MerkaThemeTokens.graphite900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickLinkButton extends StatelessWidget {
  const _QuickLinkButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: MerkaThemeTokens.info, size: 16),
      label: Text(label, style: const TextStyle(color: MerkaThemeTokens.graphite900)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: MerkaThemeTokens.paper100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _FinanceProgressLine extends StatelessWidget {
  const _FinanceProgressLine({
    required this.label,
    required this.value,
    required this.color,
    required this.max,
    required this.formatFn,
  });

  final String label;
  final double value;
  final Color color;
  final double max;
  final String Function(double) formatFn;

  @override
  Widget build(BuildContext context) {
    final pct = max == 0 ? 0.05 : (value / max).clamp(0.05, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: MerkaThemeTokens.graphite900,
              ),
            ),
            Text(
              formatFn(value),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            color: color,
            backgroundColor: MerkaThemeTokens.paper50,
            minHeight: 12,
          ),
        ),
      ],
    );
  }
}
