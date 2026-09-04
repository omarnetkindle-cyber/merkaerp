// Deprecated compatibility surface.
//
// The active local API is implemented by services/api_router.dart and
// core/api/api_dispatcher.dart. This class remains only so legacy imports do
// not break; it never pretends that an unimplemented persistence operation
// succeeded.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

@Deprecated('Use ApiRouter / ApiDispatcher; this alternate API was retired.')
class InventoryAPI {
  Router get router {
    final router = Router();
    router.all('/<ignored|.*>', _gone);
    router.all('/', _gone);
    return router;
  }

  Response _gone(Request request, [String? ignored]) => Response(
        410,
        body: jsonEncode({
          'error': 'endpoint_retired',
          'message':
              'Esta API alternativa fue retirada. Use /api/v1/products del servidor local canónico.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
}
