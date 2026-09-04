import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'ui/merka_theme_tokens.dart';

class FinancialDashboard extends StatefulWidget {
  const FinancialDashboard({super.key});

  @override
  State<FinancialDashboard> createState() => _FinancialDashboardState();
}

class _FinancialDashboardState extends State<FinancialDashboard> {
  double caja = 0;
  double banco = 0;
  double cartera = 0;
  double disponibleReal = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !DatabaseHelper.disableAutoLoadsForTests) {
        Future.microtask(cargarSaldos);
      }
    });
  }

  Future<void> cargarSaldos() async {
    final c = await DatabaseHelper.instance.obtenerSaldoPorCuenta('caja');
    final b = await DatabaseHelper.instance.obtenerSaldoPorCuenta('banco');
    final k = await DatabaseHelper.instance.obtenerSaldoPorCuenta('cartera');

    if (!mounted) return;

    setState(() {
      caja = c.toMajorUnitsDoubleForDisplay();
      banco = b.toMajorUnitsDoubleForDisplay();
      cartera = k.toMajorUnitsDoubleForDisplay();

      // 💰 dinero realmente utilizable
      disponibleReal = caja + banco;

      loading = false;
    });
  }

  Widget _card(String titulo, double valor, Color color, IconData icono) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  '\$${valor.toStringAsFixed(0)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 700 ? 4 : 2;
          final spacing = 10.0;
          final cardWidth =
              (constraints.maxWidth - (spacing * (columns - 1))) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: cardWidth,
                child: _card('Caja', caja, MerkaThemeTokens.success, Icons.attach_money),
              ),
              SizedBox(
                width: cardWidth,
                child: _card(
                  'Banco',
                  banco,
                  MerkaThemeTokens.info,
                  Icons.account_balance,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _card('Cartera', cartera, MerkaThemeTokens.warning, Icons.person),
              ),
              SizedBox(
                width: cardWidth,
                child: _card(
                  'Disponible real',
                  disponibleReal,
                  MerkaThemeTokens.gold500,
                  Icons.account_balance_wallet,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
