// ============================================================
// gdpr_service.dart
// Servicio de cumplimiento GDPR y protección de datos
// ============================================================

import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GDPRService {
  static final GDPRService instance = GDPRService._internal();
  
  GDPRService._internal();
  
  /// Crea las tablas necesarias para GDPR
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_consent (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        consent_type TEXT NOT NULL,
        consent_given INTEGER DEFAULT 0,
        consent_date TEXT,
        ip_address TEXT,
        user_agent TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(company_id, user_id, consent_type)
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_access_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        requested_by TEXT NOT NULL,
        data_subject TEXT NOT NULL,
        access_type TEXT NOT NULL,
        purpose TEXT,
        accessed_at TEXT NOT NULL,
        ip_address TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_deletion_requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        user_id TEXT NOT NULL,
        request_type TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        requested_at TEXT NOT NULL,
        processed_at TEXT,
        notes TEXT
      )
    ''');
    
    // Índices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_consent_user ON data_consent(user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_access_user ON data_access_log(data_subject)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_deletion_user ON data_deletion_requests(user_id)');
  }
  
  /// Registra consentimiento de tratamiento de datos
  Future<int> recordConsent(
    Database db,
    int companyId,
    String userId,
    String consentType,
    bool consentGiven, {
    String? ipAddress,
    String? userAgent,
  }) async {
    final now = DateTime.now().toIso8601String();
    
    final data = {
      'company_id': companyId,
      'user_id': userId,
      'consent_type': consentType,
      'consent_given': consentGiven ? 1 : 0,
      'consent_date': now,
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'created_at': now,
      'updated_at': now,
    };
    
    final id = await db.insert(
      'data_consent',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    return id;
  }
  
  /// Verifica si el usuario ha dado consentimiento
  Future<bool> hasConsent(Database db, String userId, String consentType) async {
    final result = await db.query(
      'data_consent',
      where: 'user_id = ? AND consent_type = ?',
      whereArgs: [userId, consentType],
      limit: 1,
    );
    
    if (result.isEmpty) return false;
    
    return (result.first['consent_given'] as int) == 1;
  }
  
  /// Obtiene todos los consentimientos de un usuario
  Future<List<Map<String, dynamic>>> getUserConsents(Database db, String userId) async {
    final maps = await db.query(
      'data_consent',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'consent_date DESC',
    );
    
    return maps;
  }
  
  /// Revoca consentimiento
  Future<void> revokeConsent(Database db, String userId, String consentType) async {
    await db.update(
      'data_consent',
      {
        'consent_given': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'user_id = ? AND consent_type = ?',
      whereArgs: [userId, consentType],
    );
  }
  
  /// Registra acceso a datos personales
  Future<void> logDataAccess(
    Database db,
    int companyId,
    String requestedBy,
    String dataSubject,
    String accessType, {
    String? purpose,
    String? ipAddress,
  }) async {
    await db.insert('data_access_log', {
      'company_id': companyId,
      'requested_by': requestedBy,
      'data_subject': dataSubject,
      'access_type': accessType,
      'purpose': purpose,
      'accessed_at': DateTime.now().toIso8601String(),
      'ip_address': ipAddress,
    });
  }
  
  /// Solicita eliminación de datos (derecho al olvido)
  Future<int> requestDataDeletion(
    Database db,
    int companyId,
    String userId,
    String requestType,
  ) async {
    final id = await db.insert('data_deletion_requests', {
      'company_id': companyId,
      'user_id': userId,
      'request_type': requestType,
      'status': 'pending',
      'requested_at': DateTime.now().toIso8601String(),
    });
    
    return id;
  }
  
  /// Procesa solicitud de eliminación
  Future<void> processDeletionRequest(
    Database db,
    int requestId,
    String status, {
    String? notes,
  }) async {
    await db.update(
      'data_deletion_requests',
      {
        'status': status,
        'processed_at': DateTime.now().toIso8601String(),
        'notes': notes,
      },
      where: 'id = ?',
      whereArgs: [requestId],
    );
  }
  
  /// Exporta todos los datos personales de un usuario
  Future<Map<String, dynamic>> exportUserData(Database db, String userId) async {
    final userData = <String, dynamic>{};
    
    // Datos de usuario
    final userResult = await db.query(
      'usuarios',
      where: 'usuario = ?',
      whereArgs: [userId],
    );
    
    if (userResult.isNotEmpty) {
      userData['user'] = userResult.first;
    }
    
    // Consentimientos
    userData['consents'] = await getUserConsents(db, userId);
    
    // Historial de accesos
    final accessResult = await db.query(
      'data_access_log',
      where: 'data_subject = ?',
      whereArgs: [userId],
      orderBy: 'accessed_at DESC',
    );
    userData['access_log'] = accessResult;
    
    // Ventas asociadas
    final salesResult = await db.query(
      'ventas',
      where: 'created_by = ?',
      whereArgs: [userId],
    );
    userData['sales'] = salesResult;
    
    // Auditoría
    final auditResult = await db.query(
      'auditoria',
      where: 'usuario = ?',
      whereArgs: [userId],
    );
    userData['audit'] = auditResult;
    
    return userData;
  }
  
  /// Anonimiza datos de un usuario (elimina identificadores directos)
  Future<void> anonymizeUserData(Database db, String userId) async {
    // Anonimizar usuario
    await db.update(
      'usuarios',
      {
        'usuario': 'deleted_${DateTime.now().millisecondsSinceEpoch}',
        'nombre': 'Usuario Eliminado',
        'email': null,
        'telefono': null,
      },
      where: 'usuario = ?',
      whereArgs: [userId],
    );
    
    // Anonimizar ventas
    await db.update(
      'ventas',
      {'created_by': null},
      where: 'created_by = ?',
      whereArgs: [userId],
    );
    
    // Anonimizar auditoría
    await db.update(
      'auditoria',
      {'usuario': 'deleted_user'},
      where: 'usuario = ?',
      whereArgs: [userId],
    );
  }
  
  /// Elimina completamente datos de un usuario
  Future<void> deleteUserData(Database db, String userId) async {
    // Eliminar de usuarios
    await db.delete('usuarios', where: 'usuario = ?', whereArgs: [userId]);
    
    // Eliminar consentimientos
    await db.delete('data_consent', where: 'user_id = ?', whereArgs: [userId]);
    
    // Eliminar logs de acceso (opcional, según política de retención)
    // await db.delete('data_access_log', where: 'data_subject = ?', whereArgs: [userId]);
  }
  
  /// Obtiene política de retención de datos
  Duration getDataRetentionPeriod(String dataType) {
    switch (dataType.toLowerCase()) {
      case 'transaction':
        return const Duration(days: 365 * 10); // 10 años
      case 'audit':
        return const Duration(days: 365 * 5); // 5 años
      case 'consent':
        return const Duration(days: 365 * 2); // 2 años
      case 'access_log':
        return const Duration(days: 365); // 1 año
      default:
        return const Duration(days: 365 * 7); // 7 años por defecto
    }
  }
  
  /// Elimina datos antiguos según política de retención
  Future<void> applyDataRetentionPolicy(Database db) async {
    final now = DateTime.now();
    
    // Eliminar logs de acceso antiguos
    final accessRetention = getDataRetentionPeriod('access_log');
    final accessCutoff = now.subtract(accessRetention);
    await db.delete(
      'data_access_log',
      where: 'accessed_at < ?',
      whereArgs: [accessCutoff.toIso8601String()],
    );
    
    // Eliminar consentimientos antiguos
    final consentRetention = getDataRetentionPeriod('consent');
    final consentCutoff = now.subtract(consentRetention);
    await db.delete(
      'data_consent',
      where: 'consent_date < ?',
      whereArgs: [consentCutoff.toIso8601String()],
    );
  }
  
  /// Verifica cumplimiento de GDPR
  Future<Map<String, dynamic>> checkGDPRCompliance(Database db, int companyId) async {
    final checks = <String, bool>{};
    
    // Verificar consentimientos registrados
    final consentCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) as count FROM data_consent WHERE company_id = ?', [companyId]),
    ) ?? 0;
    checks['consents_recorded'] = consentCount > 0;
    
    // Verificar logs de acceso
    final accessLogCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) as count FROM data_access_log WHERE company_id = ?', [companyId]),
    ) ?? 0;
    checks['access_logging'] = accessLogCount > 0;
    
    // Verificar solicitudes de eliminación pendientes
    final pendingDeletions = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) as count FROM data_deletion_requests WHERE company_id = ? AND status = ?',
        [companyId, 'pending'],
      ),
    ) ?? 0;
    checks['pending_deletions'] = pendingDeletions == 0;
    
    return {
      'compliant': checks.values.every((v) => v),
      'checks': checks,
      'pending_deletions': pendingDeletions,
    };
  }
  
  /// Guarda preferencia de privacidad en SharedPreferences
  Future<void> setPrivacyPreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_$key', value);
  }
  
  /// Obtiene preferencia de privacidad
  Future<bool?> getPrivacyPreference(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('privacy_$key');
  }
  
  /// Enmascara datos sensibles para visualización
  String maskSensitiveData(String data, String dataType) {
    switch (dataType.toLowerCase()) {
      case 'email':
        if (data.contains('@')) {
          final parts = data.split('@');
          final username = parts[0];
          final domain = parts[1];
          final maskedUsername = username.length > 2
              ? '${username.substring(0, 2)}***'
              : '***';
          return '$maskedUsername@$domain';
        }
        return data;
      
      case 'phone':
        if (data.length >= 4) {
          return '${data.substring(0, 2)}***${data.substring(data.length - 2)}';
        }
        return '***';
      
      case 'identification':
        if (data.length >= 4) {
          return '${data.substring(0, 2)}${'*' * (data.length - 4)}${data.substring(data.length - 2)}';
        }
        return '***';
      
      case 'bank_account':
        if (data.length >= 4) {
          return '****${data.substring(data.length - 4)}';
        }
        return '****';
      
      default:
        return data;
    }
  }
}
