import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'sync_auth.dart';
import 'sync_event.dart';
import 'sync_event_store.dart';

class MerkaSyncApi {
  MerkaSyncApi({required SyncAuthVerifier auth, required SyncEventStore store})
      : _auth = auth,
        _store = store;

  final SyncAuthVerifier _auth;
  final SyncEventStore _store;

  Handler get handler {
    final router = Router()
      ..get('/health', _health)
      ..get('/api/sync/events', _pullEvents)
      ..post('/api/sync/events', _pushEvent);
    return Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_jsonErrorMiddleware())
        .addHandler(router.call);
  }

  Future<Response> _health(Request request) async {
    return _json(200, {
      'ok': true,
      'service': 'merka_sync_server',
      'time': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Response> _pullEvents(Request request) async {
    final auth = await _auth.verify(request.headers['authorization']);
    final query = request.requestedUri.queryParameters;
    final cursor = _intQuery(query['cursor'], defaultValue: 0, min: 0);
    final limit =
        _intQuery(query['limit'], defaultValue: 100, min: 1, max: 500);
    final includeSelf = query['include_self']?.toLowerCase() == 'true' ||
        query['includeSelf']?.toLowerCase() == 'true';

    final events = await _store.listEvents(
      tenantKind: auth.tenantKind,
      tenantId: auth.tenantId,
      afterCursor: cursor,
      limit: limit,
      excludeSourceDeviceId: includeSelf ? null : auth.deviceId,
    );
    final nextCursor = events.isEmpty ? cursor.toString() : events.last.cursor;

    return _json(200, {
      'accepted': true,
      'tenant_kind': auth.tenantKind,
      'tenant_id': auth.tenantId,
      'cursor': nextCursor,
      'has_more': events.length == limit,
      'events': events.map((event) => event.toJson()).toList(),
    });
  }

  Future<Response> _pushEvent(Request request) async {
    final auth = await _auth.verify(request.headers['authorization']);
    final body = await request.readAsString();
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const SyncEventValidationException('Body debe ser objeto JSON.');
    }
    final event = SyncEvent.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    event.authorize(auth);

    final stored = await _store.append(event);
    return _json(stored.duplicate ? 200 : 202, {
      'accepted': true,
      'duplicate': stored.duplicate,
      'remote_event_id': stored.remoteEventId,
      'remote_cursor': stored.cursor,
    });
  }

  Middleware _jsonErrorMiddleware() {
    return (innerHandler) {
      return (request) async {
        try {
          return await innerHandler(request);
        } on SyncAuthException catch (error) {
          return _json(401, {'accepted': false, 'error': error.message});
        } on SyncEventValidationException catch (error) {
          return _json(400, {'accepted': false, 'error': error.message});
        } on FormatException catch (error) {
          return _json(400, {'accepted': false, 'error': error.message});
        } catch (error) {
          return _json(500, {
            'accepted': false,
            'error': 'Error interno procesando evento sync.',
          });
        }
      };
    };
  }

  Response _json(int statusCode, Map<String, Object?> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  int _intQuery(String? raw, {required int defaultValue, int? min, int? max}) {
    if (raw == null || raw.trim().isEmpty) return defaultValue;
    final parsed = int.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Parámetro entero inválido: $raw');
    }
    if (min != null && parsed < min) return min;
    if (max != null && parsed > max) return max;
    return parsed;
  }
}
