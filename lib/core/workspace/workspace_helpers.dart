import 'package:sqflite/sqflite.dart';

import '../../features/module_definition.dart';
import '../../app_session.dart';
import '../../db_helper.dart';

/// Devuelve solo los módulos que la sesión actual puede abrir.
List<ModuleDefinition> visible(List<ModuleDefinition> modules) {
  return modules.where(AppSession.puedeAbrirModulo).toList();
}

/// Devuelve los módulos en el mismo orden de `ids` cuando existan en `modules`.
List<ModuleDefinition> modulesByIds(
  List<ModuleDefinition> modules,
  Iterable<String> ids,
) {
  final byId = {for (final module in modules) module.id: module};
  return [for (final id in ids) if (byId[id] != null) byId[id]!];
}

/// Persiste la preferencia de tema en la tabla `preferencias_usuario`.
/// `value` debe ser 'dark' o 'light'.
Future<void> persistThemePreference(String value, {String? usuario}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert(
    'preferencias_usuario',
    {
      'usuario': usuario ?? AppSession.nombre,
      'clave': 'theme_mode',
      'valor': value,
      'actualizado_en': DateTime.now().toIso8601String(),
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}
