/// Sanitización común para datos técnicos que pueden salir de la instalación.
///
/// El Agent nunca debe reflejar secretos ni datos personales contenidos en
/// excepciones, parámetros o logs. Las claves sensibles se eliminan de forma
/// recursiva y los textos quedan acotados para evitar ACK desproporcionados.
abstract final class AgentDataSanitizer {
  static final RegExp _sensitiveKey = RegExp(
    r'(password|passwd|secret|token|authorization|cookie|api[_-]?key|client[_-]?secret|private[_-]?key|pin|credential|certificate|certificado|firma|hmac|bank|cuenta|iban)',
    caseSensitive: false,
  );

  static dynamic sanitize(dynamic value) {
    if (value is Map) {
      final output = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        output[key] = _sensitiveKey.hasMatch(key)
            ? '<redacted>'
            : sanitize(entry.value);
      }
      return output;
    }
    if (value is Iterable) return value.map(sanitize).toList(growable: false);
    if (value is String) return sanitizeText(value);
    return value;
  }

  static String sanitizeText(String value, {int maxLength = 2000}) {
    var result = value;
    result = result.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/]+=*', caseSensitive: false),
      'Bearer <redacted>',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(password|passwd|secret|token|api[_-]?key|client[_-]?secret|pin|credential)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=<redacted>',
    );
    result = result.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      '<jwt>',
    );
    result = result.replaceAll(
      RegExp(r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}', caseSensitive: false),
      '<email>',
    );
    result = result.replaceAll(
      RegExp(r'C:\\Users\\[^\\/\s]+', caseSensitive: false),
      r'C:\Users\<user>',
    );
    result = result.replaceAll(RegExp(r'/home/[^/\s]+'), '/home/<user>');
    result = result.replaceAllMapped(
      RegExp(
        r'([?&](?:access_token|token|api_key|apikey|key|secret)=)[^&\s]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}<redacted>',
    );
    return result.length > maxLength
        ? '${result.substring(0, maxLength)}…'
        : result;
  }
}
