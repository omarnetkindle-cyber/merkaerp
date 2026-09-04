class ControlCenterEndpoint {
  const ControlCenterEndpoint._();

  static const String apiVersion = 'api/v1';
  static const String defaultEndpoint =
      'https://merkaerp-control-center-backend-3a5r.onrender.com';

  static String normalize(String? value) {
    var endpoint = (value ?? '').trim();
    if (endpoint.isEmpty) {
      return defaultEndpoint;
    }

    endpoint = endpoint.replaceAll(RegExp(r'\s+'), '');
    endpoint = endpoint.replaceFirst(RegExp(r'/+$'), '');

    if (endpoint.toLowerCase().endsWith('/$apiVersion')) {
      endpoint = endpoint.substring(0, endpoint.length - apiVersion.length - 1);
    }

    if (endpoint.toLowerCase().endsWith('/api')) {
      endpoint = endpoint.substring(0, endpoint.length - 4);
    }

    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException(
        'El endpoint del Control Center debe ser una URL absoluta válida.',
      );
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException(
        'El endpoint del Control Center no admite credenciales, query ni fragmentos en la URL.',
      );
    }

    final host = uri.host.toLowerCase();
    final isLoopback = host == 'localhost' || host == '127.0.0.1' || host == '::1';
    final isSecure = uri.scheme.toLowerCase() == 'https';
    final isLocalDevelopment = isLoopback && uri.scheme.toLowerCase() == 'http';
    if (!isSecure && !isLocalDevelopment) {
      throw const FormatException(
        'El Control Center requiere HTTPS. HTTP solo se permite en localhost para desarrollo.',
      );
    }

    return endpoint;
  }

  static String buildUrl(String? endpoint, String path) {
    final base = normalize(endpoint);
    final cleanPath = path.replaceFirst(RegExp(r'^/'), '');
    return '$base/$apiVersion/$cleanPath';
  }

  static String activationUrl(String? endpoint) {
    return buildUrl(endpoint, 'licenses/activate');
  }
}
