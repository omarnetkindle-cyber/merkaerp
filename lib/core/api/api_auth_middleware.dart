// ============================================================
// api_auth_middleware.dart
// Middleware de autenticación para API REST
// ============================================================

import 'dart:convert';
import 'dart:developer';
import 'package:shelf/shelf.dart';
import 'jwt_service.dart';

class APIAuthMiddleware {
  static final JWTService _jwtService = JWTService.instance;
  
  /// Middleware que requiere autenticación JWT
  static Middleware requireAuth() {
    return (Handler innerHandler) {
      return (Request request) async {
        final authHeader = request.headers['Authorization'];
        
        if (authHeader == null || !authHeader.startsWith('Bearer ')) {
          return Response.unauthorized(
            jsonEncode({'error': 'Token de autenticación requerido'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        final token = authHeader.substring(7); // Remover 'Bearer '
        
        final payload = _jwtService.decodeAndValidateToken(token);
        if (payload == null) {
          return Response.unauthorized(
            jsonEncode({'error': 'Token inválido o expirado'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        // Agregar información del usuario al contexto de la request
        final modifiedRequest = request.change(
          context: {
            ...request.context,
            'user_id': payload['sub'],
            'company_id': payload['company_id'],
            'role': payload['role'],
          },
        );
        
        return innerHandler(modifiedRequest);
      };
    };
  }
  
  /// Middleware que requiere un rol específico
  static Middleware requireRole(String requiredRole) {
    return (Handler innerHandler) {
      return (Request request) async {
        final role = request.context['role'] as String?;
        
        if (role == null) {
          return Response.forbidden(
            jsonEncode({'error': 'Rol no encontrado en el contexto'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        if (role != requiredRole && role != 'administrador') {
          return Response.forbidden(
            jsonEncode({'error': 'Rol insuficiente: se requiere $requiredRole'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        return innerHandler(request);
      };
    };
  }
  
  /// Middleware que requiere uno de varios roles
  static Middleware requireAnyRole(List<String> allowedRoles) {
    return (Handler innerHandler) {
      return (Request request) async {
        final role = request.context['role'] as String?;
        
        if (role == null) {
          return Response.forbidden(
            jsonEncode({'error': 'Rol no encontrado en el contexto'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        if (!allowedRoles.contains(role) && role != 'administrador') {
          return Response.forbidden(
            jsonEncode({'error': 'Rol insuficiente: se requiere uno de ${allowedRoles.join(", ")}'}),
            headers: {'content-type': 'application/json'},
          );
        }
        
        return innerHandler(request);
      };
    };
  }
  
  /// Middleware de rate limiting
  static Middleware rateLimit({int maxRequests = 100, Duration window = const Duration(minutes: 1)}) {
    final requestCounts = <String, List<DateTime>>{};
    
    return (Handler innerHandler) {
      return (Request request) async {
        final clientIp = request.headers['x-forwarded-for'] ?? 
                          request.headers['x-real-ip'] ?? 
                          'unknown';
        
        final now = DateTime.now();
        final clientRequests = requestCounts.putIfAbsent(clientIp, () => []);
        
        // Remover solicitudes antiguas fuera de la ventana
        clientRequests.removeWhere((time) => now.difference(time) > window);
        
        // Verificar límite
        if (clientRequests.length >= maxRequests) {
          return Response(429, body: 'Too Many Requests');
        }
        
        // Agregar solicitud actual
        clientRequests.add(now);
        
        return innerHandler(request);
      };
    };
  }
  
  /// Middleware de CORS
  static Middleware cors({
    String allowedOrigin = '*',
    List<String> allowedMethods = const ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    List<String> allowedHeaders = const ['Content-Type', 'Authorization'],
    bool allowCredentials = false,
  }) {
    return (Handler innerHandler) {
      return (Request request) async {
        // Manejar preflight request
        if (request.method == 'OPTIONS') {
          return Response.ok(
            null,
            headers: {
              'Access-Control-Allow-Origin': allowedOrigin,
              'Access-Control-Allow-Methods': allowedMethods.join(', '),
              'Access-Control-Allow-Headers': allowedHeaders.join(', '),
              'Access-Control-Allow-Credentials': allowCredentials.toString(),
              'Access-Control-Max-Age': '86400',
            },
          );
        }
        
        final response = await innerHandler(request);
        
        return response.change(
          headers: {
            ...response.headers,
            'Access-Control-Allow-Origin': allowedOrigin,
            'Access-Control-Allow-Methods': allowedMethods.join(', '),
            'Access-Control-Allow-Headers': allowedHeaders.join(', '),
            'Access-Control-Allow-Credentials': allowCredentials.toString(),
          },
        );
      };
    };
  }
  
  /// Middleware de logging
  static Middleware logging() {
    return (Handler innerHandler) {
      return (Request request) async {
        final start = DateTime.now();
        
        log('[${start.toIso8601String()}] ${request.method} ${request.url.path}');
        
        final response = await innerHandler(request);
        
        final duration = DateTime.now().difference(start);
        log('[${DateTime.now().toIso8601String()}] ${request.method} ${request.url.path} - ${response.statusCode} (${duration.inMilliseconds}ms)');
        
        return response;
      };
    };
  }
  
  /// Obtiene el ID de usuario del contexto de la request
  static String? getUserId(Request request) {
    return request.context['user_id'] as String?;
  }
  
  /// Obtiene el ID de empresa del contexto de la request
  static String? getCompanyId(Request request) {
    return request.context['company_id'] as String?;
  }
  
  /// Obtiene el rol del contexto de la request
  static String? getRole(Request request) {
    return request.context['role'] as String?;
  }
}
