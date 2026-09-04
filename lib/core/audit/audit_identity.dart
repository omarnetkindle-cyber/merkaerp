class AuditIdentity {
  AuditIdentity._();

  static String _current = 'sin_sesion';

  static String get current => _current;

  static void setFromUser(Map<String, dynamic> user) {
    final id = user['id']?.toString().trim();
    final username = user['usuario']?.toString().trim();
    final name = user['nombre']?.toString().trim();
    _current = [
      if (id != null && id.isNotEmpty) id,
      if (username != null && username.isNotEmpty) username,
      if (name != null && name.isNotEmpty) name,
    ].join(':');
    if (_current.isEmpty) _current = 'usuario_local';
  }

  static void clear() {
    _current = 'sin_sesion';
  }
}
