import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';
import 'local_llm_client.dart';

class CopilotConfigurationService {
  CopilotConfigurationService({DatabaseHelper? databaseHelper})
    : _db = databaseHelper ?? DatabaseHelper.instance;

  final DatabaseHelper _db;

  Future<LocalLlmConfiguration> load() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_config',
      where: 'clave IN (?, ?, ?)',
      whereArgs: const [
        'copilot_local_llm_enabled',
        'copilot_local_llm_endpoint',
        'copilot_local_llm_model',
      ],
    );
    final values = {
      for (final row in rows)
        row['clave']?.toString() ?? '': row['valor']?.toString() ?? '',
    };
    final endpoint = Uri.tryParse(
      values['copilot_local_llm_endpoint'] ??
          'http://127.0.0.1:8080/v1/chat/completions',
    );
    return LocalLlmConfiguration(
      enabled: values['copilot_local_llm_enabled'] == '1',
      endpoint:
          endpoint ?? Uri.parse('http://127.0.0.1:8080/v1/chat/completions'),
      model: values['copilot_local_llm_model']?.trim().isNotEmpty == true
          ? values['copilot_local_llm_model']!.trim()
          : 'local-model',
    );
  }

  Future<void> save(LocalLlmConfiguration configuration) async {
    if (!configuration.isLoopback) {
      throw StateError('El modelo debe ejecutarse localmente en este equipo.');
    }
    if (configuration.endpoint.scheme != 'http') {
      throw StateError('El endpoint local debe usar http sobre loopback.');
    }
    if (configuration.model.trim().isEmpty) {
      throw StateError('Indica el nombre del modelo local.');
    }
    final db = await _db.database;
    final values = {
      'copilot_local_llm_enabled': configuration.enabled ? '1' : '0',
      'copilot_local_llm_endpoint': configuration.endpoint.toString(),
      'copilot_local_llm_model': configuration.model.trim(),
    };
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await txn.insert('app_config', {
          'clave': entry.key,
          'valor': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
