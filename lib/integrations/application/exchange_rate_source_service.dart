import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import '../domain/integration_definition.dart';
import 'integration_settings_service.dart';

class ExchangeRateSourceResult {
  const ExchangeRateSourceResult({
    required this.currencyCode,
    required this.baseCurrency,
    required this.rate,
    required this.date,
  });

  final String currencyCode;
  final String baseCurrency;
  final double rate;
  final DateTime date;
}

class ExchangeRateSourceService {
  ExchangeRateSourceService._();
  static final ExchangeRateSourceService instance = ExchangeRateSourceService._();

  Future<ExchangeRateSourceResult> fetchAndStore() async {
    final settings = IntegrationSettingsService.instance;
    final profile = await settings.load('trm_source');
    if (!profile.enabled) {
      throw StateError('La fuente de TRM/tasas no está habilitada en Integraciones.');
    }
    final values = await settings.loadValues(IntegrationRegistry.byKey('trm_source'));
    final rawUrl = (values['base_url'] ?? '').trim();
    final jsonPath = (values['json_path'] ?? '').trim();
    final currency = (values['currency_code'] ?? 'USD').trim().toUpperCase();
    final base = (values['base_currency'] ?? 'COP').trim().toUpperCase();
    if (rawUrl.isEmpty || jsonPath.isEmpty || currency.isEmpty || base.isEmpty) {
      throw StateError('La fuente de tasas está incompleta.');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      throw StateError('La URL de la fuente de tasas es inválida.');
    }
    final local = const {'localhost', '127.0.0.1', '::1'}.contains(uri.host.toLowerCase());
    if (uri.scheme.toLowerCase() != 'https' && !(local && uri.scheme.toLowerCase() == 'http')) {
      throw StateError('La fuente remota de tasas exige HTTPS.');
    }
    final headers = <String, String>{'Accept': 'application/json'};
    final auth = (values['auth_type'] ?? 'NONE').trim().toUpperCase();
    final token = (values['api_key'] ?? '').trim();
    if ((auth == 'BEARER' || auth == 'API_KEY') && token.isEmpty) {
      throw StateError('La autenticación configurada para la fuente requiere una credencial.');
    }
    if (auth == 'BEARER') {
      headers['Authorization'] = 'Bearer $token';
    } else if (auth == 'API_KEY') {
      final header = (values['api_key_header'] ?? '').trim();
      headers[header.isEmpty ? 'X-API-Key' : header] = token;
    }

    final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('La fuente de tasas respondió HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    final rawValue = _valueAtPath(decoded, jsonPath);
    final rate = rawValue is num ? rawValue.toDouble() : double.tryParse(rawValue?.toString() ?? '');
    if (rate == null || !rate.isFinite || rate <= 0) {
      throw StateError('La fuente respondió una tasa no válida en "$jsonPath".');
    }

    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final db = await DatabaseHelper.instance.database;
    final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(db);
    await db.transaction((txn) async {
      await txn.delete(
        'exchange_rates',
        where: 'date = ? AND currency_code = ? AND company_id = ?',
        whereArgs: [day.toIso8601String().split('T').first, currency, companyId],
      );
      await txn.insert('exchange_rates', {
        'date': day.toIso8601String().split('T').first,
        'currency_code': currency,
        'rate_to_base': rate,
        'company_id': companyId,
      });

      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='currency_exchange_rates'",
      );
      if (tables.isNotEmpty) {
        await txn.insert(
          'currency_exchange_rates',
          {
            'company_id': companyId,
            'from_currency': currency,
            'to_currency': base,
            'rate': rate,
            'effective_date': day.toIso8601String(),
            'expiry_date': day.add(const Duration(days: 1)).toIso8601String(),
            'source': 'configured_integration',
            'created_at': now.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'TRM_CONFIGURADA_ACTUALIZADA',
      entidad: 'exchange_rates',
      detalle: '$currency/$base; rate=$rate; source=configured_integration',
    );
    return ExchangeRateSourceResult(
      currencyCode: currency,
      baseCurrency: base,
      rate: rate,
      date: day,
    );
  }

  Object? _valueAtPath(Object? root, String path) {
    Object? current = root;
    for (final segment in path.split('.').where((s) => s.trim().isNotEmpty)) {
      if (current is Map) {
        current = current[segment];
      } else if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }
}
