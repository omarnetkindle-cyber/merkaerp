import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:flutter/foundation.dart';
import '../db_helper.dart';
import 'api_auth_service.dart';
import 'api_router.dart';

class ApiServer {
  ApiServer._();

  static final ApiServer instance = ApiServer._();

  HttpServer? _server;
  static const int _defaultPort = 8080;
  bool get isRunning => _server != null;

  Future<void> iniciar({int port = _defaultPort}) async {
    if (isRunning) {
      debugPrint('API Server ya está corriendo en el puerto $port');
      return;
    }

    try {
      final router = await ApiRouter.instance.crearRouter();
      final handler = const Pipeline()
          .addMiddleware(ApiAuthService.instance.authMiddleware())
          .addMiddleware(ApiAuthService.instance.rateLimitMiddleware())
          .addMiddleware(ApiAuthService.instance.corsMiddleware())
          .addMiddleware(logRequests())
          .addHandler(router.call);

      _server = await shelf_io.serve(handler, 'localhost', port);

      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'API_SERVER_INICIADO',
        entidad: 'api_server',
        detalle: 'Puerto: $port',
      );

      debugPrint('API Server iniciado en http://localhost:$port');
    } catch (e) {
      debugPrint('Error al iniciar API Server: $e');
      rethrow;
    }
  }

  Future<void> detener() async {
    if (_server == null) return;

    await _server!.close();
    _server = null;

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'API_SERVER_DETENIDO',
      entidad: 'api_server',
      detalle: '',
    );

    debugPrint('API Server detenido');
  }

  Future<int> obtenerPuerto() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['api_server_port'],
      limit: 1,
    );
    if (rows.isEmpty) return _defaultPort;
    final valor = rows.first['valor']?.toString();
    return valor != null ? int.tryParse(valor) ?? _defaultPort : _defaultPort;
  }

  Future<void> configurarPuerto(int port) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'app_config',
      {'clave': 'api_server_port', 'valor': port.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'API_SERVER_PUERTO_CONFIGURADO',
      entidad: 'api_server',
      detalle: 'Puerto: $port',
    );
  }

  Future<bool> estaHabilitado() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'app_config',
      where: 'clave = ?',
      whereArgs: ['api_server_enabled'],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final valor = rows.first['valor']?.toString();
    return valor == '1';
  }

  Future<void> habilitar(bool habilitado) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert(
      'app_config',
      {'clave': 'api_server_enabled', 'valor': habilitado ? '1' : '0'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'API_SERVER_HABILITADO',
      entidad: 'api_server',
      detalle: habilitado ? 'Habilitado' : 'Deshabilitado',
    );
  }
}
