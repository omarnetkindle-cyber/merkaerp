// Deprecated compatibility surface.
//
// Sales writes must go through CreateSaleUseCase so stock, kardex, cartera,
// caja and accounting remain atomic. The canonical API already does that in
// services/api_router.dart / core/api/api_dispatcher.dart.

import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

@Deprecated('Use ApiRouter / ApiDispatcher; this alternate API was retired.')
class SalesAPI {
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
              'Esta API alternativa fue retirada. Use /api/v1/orders del servidor local canónico.',
        }),
        headers: {'Content-Type': 'application/json'},
      );
}
