import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'core/currency/currency.dart';
import 'core/currency/currency_service.dart';

class CurrencyConfigPage extends StatefulWidget {
  const CurrencyConfigPage({super.key});

  @override
  State<CurrencyConfigPage> createState() => _CurrencyConfigPageState();
}

class _CurrencyConfigPageState extends State<CurrencyConfigPage> {
  final CurrencyService _currencyService = CurrencyService.instance;
  List<Currency> _currencies = [];
  Currency? _defaultCurrency;
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final currencies = await _currencyService.getAllCurrencies(db);
      final defaultCurrency = await _currencyService.getDefaultCurrency(db);

      if (!mounted) return;
      setState(() {
        _currencies = currencies;
        _defaultCurrency = defaultCurrency;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar monedas: $e')));
    }
  }

  Future<void> _setDefaultCurrency(Currency currency) async {
    if (mounted) setState(() => _isUpdating = true);
    try {
      final db = await DatabaseHelper.instance.database;
      await _currencyService.setDefaultCurrency(db, currency.code);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${currency.code} establecida como moneda predeterminada',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al establecer moneda predeterminada: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Monedas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildDefaultCurrencySection(),
                _buildCurrenciesSection(),
              ],
            ),
    );
  }

  Widget _buildDefaultCurrencySection() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Moneda Predeterminada',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_defaultCurrency != null)
              ListTile(
                leading: CircleAvatar(child: Text(_defaultCurrency!.symbol)),
                title: Text(
                  '${_defaultCurrency!.code} - ${_defaultCurrency!.name}',
                ),
                subtitle: Text('Símbolo: ${_defaultCurrency!.symbol}'),
              )
            else
              const Text('No hay moneda predeterminada configurada'),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrenciesSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monedas Disponibles',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ..._currencies.map(
            (currency) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(currency.symbol)),
                title: Text('${currency.code} - ${currency.name}'),
                subtitle: Text(
                  'Símbolo: ${currency.symbol} - Decimales: ${currency.decimalPlaces}',
                ),
                trailing: _defaultCurrency?.code == currency.code
                    ? const Chip(
                        label: Text('Predeterminada'),
                        backgroundColor: Colors.green,
                        labelStyle: TextStyle(color: Colors.white),
                      )
                    : _isUpdating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.star_border),
                        onPressed: () => _setDefaultCurrency(currency),
                        tooltip: 'Establecer como predeterminada',
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
