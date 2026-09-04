import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:sqflite/sqflite.dart';

import '../../db_helper.dart';

class FullBackupVerification {
  const FullBackupVerification({
    required this.ok,
    required this.message,
    this.entries = 0,
    this.bytes = 0,
    this.documentFiles = 0,
    this.databaseVersion,
  });

  final bool ok;
  final String message;
  final int entries;
  final int bytes;
  final int documentFiles;
  final int? databaseVersion;
}

class FullBackupDrillResult {
  const FullBackupDrillResult({
    required this.ok,
    required this.message,
    this.databaseVersion,
    this.tables = 0,
    this.documentReferences = 0,
    this.missingDocumentReferences = 0,
  });

  final bool ok;
  final String message;
  final int? databaseVersion;
  final int tables;
  final int documentReferences;
  final int missingDocumentReferences;
}

/// Respaldo integral MerkaERP.
///
/// Incluye la base SQLite y el repositorio de Gestión Documental. El formato
/// es secuencial, autocontenido y con SHA-256 por entrada; no depende de ZIP ni
/// de utilidades externas. El contenedor local se cifra por bloques con
/// AES-256-GCM y una clave custodiada por el almacén seguro del sistema.
class FullBackupService {
  FullBackupService._();
  static final FullBackupService instance = FullBackupService._();

  @visibleForTesting
  void configureEncryptionKeyForTests(List<int>? key) {
    _LocalBackupCrypto.instance.configureForTests(
      key == null ? null : Uint8List.fromList(key),
    );
  }

  @visibleForTesting
  Future<void> encryptFileForTests(File plain, File encrypted) =>
      _LocalBackupCrypto.instance.encrypt(plain, encrypted);

  @visibleForTesting
  Future<File> decryptFileForTests(File encrypted, String outputPath) async {
    final prepared = await _LocalBackupCrypto.instance.prepareForRead(encrypted);
    try {
      final output = File(outputPath);
      await prepared.file.copy(output.path);
      return output;
    } finally {
      await prepared.dispose();
    }
  }

  static const _magic = 'MERKAFULL1';
  static const _extension = '.mkbackup';

  Future<Directory> _backupDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'respaldos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _documentRoot() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory(p.join(root.path, 'gestion_documental'));
  }

  Future<List<File>> listBackups() async {
    final dir = await _backupDirectory();
    final files = await dir
        .list(followLinks: false)
        .where((entry) => entry is File && entry.path.endsWith(_extension))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  Future<File> createFullBackup({String label = 'merkaerp_full'}) async {
    final db = await DatabaseHelper.instance.database;
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    final backupDir = await _backupDirectory();
    final stamp = _timestamp(DateTime.now());
    final output = File(p.join(backupDir.path, '${label}_$stamp$_extension'));
    final plainOutput = File('${output.path}.plaintext.pending');
    final dbSource = File(await DatabaseHelper.instance.obtenerRutaBaseDatos());
    if (!await dbSource.exists()) {
      throw StateError('No se encontró la base de datos activa para respaldar.');
    }

    final sources = <_BackupSource>[
      _BackupSource(file: dbSource, relativePath: 'database/merkaerp.db', kind: 'database'),
    ];
    final documentRoot = await _documentRoot();
    if (await documentRoot.exists()) {
      await for (final entity in documentRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: documentRoot.path);
        if (!_isSafeRelative(relative)) continue;
        sources.add(
          _BackupSource(
            file: entity,
            relativePath: p.posix.joinAll(['gestion_documental', ...p.split(relative)]),
            kind: 'document',
          ),
        );
      }
    }

    final sink = await plainOutput.open(mode: FileMode.write);
    var totalBytes = 0;
    try {
      await sink.writeString('$_magic\n');
      await sink.writeString('${jsonEncode({
        'format': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'schema_version': DatabaseHelper.schemaVersion,
        'entries': sources.length,
      })}\n');
      for (final source in sources) {
        final length = await source.file.length();
        final digest = await crypto.sha256.bind(source.file.openRead()).first;
        await sink.writeString('${jsonEncode({
          'path': source.relativePath,
          'kind': source.kind,
          'length': length,
          'sha256': digest.toString(),
        })}\n');
        await for (final chunk in source.file.openRead()) {
          await sink.writeFrom(chunk);
        }
        await sink.writeByte(10);
        totalBytes += length;
      }
      await sink.writeString('${jsonEncode({'end': true, 'entries': sources.length})}\n');
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      if (await plainOutput.exists()) await plainOutput.delete();
      rethrow;
    }
    await sink.close();
    try {
      await _LocalBackupCrypto.instance.encrypt(plainOutput, output);
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      if (await plainOutput.exists()) await plainOutput.delete();
    }

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'CREAR_RESPALDO_INTEGRAL',
      entidad: 'backup',
      detalle: '${output.path}; entries=${sources.length}; payload_bytes=$totalBytes',
    );
    return output;
  }

  Future<FullBackupVerification> verify(File backup) async {
    if (!await backup.exists()) {
      return const FullBackupVerification(ok: false, message: 'El respaldo no existe.');
    }
    final prepared = await _LocalBackupCrypto.instance.prepareForRead(backup);
    final reader = await prepared.file.open(mode: FileMode.read);
    Directory? temp;
    var entries = 0;
    var documents = 0;
    var bytes = 0;
    int? dbVersion;
    int? declaredEntries;
    var databaseEntries = 0;
    final seenPaths = <String>{};
    try {
      final magic = await _readLine(reader);
      if (magic != _magic) {
        return const FullBackupVerification(ok: false, message: 'Formato de respaldo integral no reconocido.');
      }
      final metadataLine = await _readLine(reader);
      if (metadataLine == null) {
        return const FullBackupVerification(ok: false, message: 'El manifiesto del respaldo está incompleto.');
      }
      final metadata = jsonDecode(metadataLine);
      if (metadata is! Map || metadata['format'] != 1) {
        return const FullBackupVerification(ok: false, message: 'Versión de formato de respaldo no soportada.');
      }
      declaredEntries = (metadata['entries'] as num?)?.toInt();
      if (declaredEntries == null || declaredEntries < 1) {
        return const FullBackupVerification(ok: false, message: 'El manifiesto no declara entradas válidas.');
      }

      while (true) {
        final line = await _readLine(reader);
        if (line == null) {
          return const FullBackupVerification(ok: false, message: 'El respaldo terminó sin marcador de cierre.');
        }
        final header = jsonDecode(line);
        if (header is! Map) {
          return const FullBackupVerification(ok: false, message: 'Entrada de respaldo inválida.');
        }
        if (header['end'] == true) {
          final endEntries = (header['entries'] as num?)?.toInt();
          if (endEntries != declaredEntries || entries != declaredEntries) {
            return const FullBackupVerification(ok: false, message: 'El número de entradas no coincide con el manifiesto.');
          }
          break;
        }
        final path = header['path']?.toString() ?? '';
        final kind = header['kind']?.toString() ?? '';
        final length = (header['length'] as num?)?.toInt() ?? -1;
        final expectedHash = header['sha256']?.toString() ?? '';
        if (!_isSafeRelative(path) || length < 0 || expectedHash.length != 64 ||
            (kind != 'database' && kind != 'document')) {
          return const FullBackupVerification(ok: false, message: 'El manifiesto contiene una entrada insegura o corrupta.');
        }
        if (!seenPaths.add(path)) {
          return FullBackupVerification(ok: false, message: 'El respaldo contiene una ruta duplicada: $path.');
        }
        if (kind == 'database') {
          databaseEntries++;
          if (databaseEntries > 1 || path != 'database/merkaerp.db') {
            return const FullBackupVerification(ok: false, message: 'El respaldo contiene una definición de base de datos inválida.');
          }
        }

        final digestSink = AccumulatorSink<crypto.Digest>();
        final hashSink = crypto.sha256.startChunkedConversion(digestSink);
        File? dbTemp;
        IOSink? dbTempSink;
        if (kind == 'database') {
          temp ??= await Directory.systemTemp.createTemp('merkaerp_verify_');
          dbTemp = File(p.join(temp.path, 'database.db'));
          dbTempSink = dbTemp.openWrite();
        }
        var remaining = length;
        while (remaining > 0) {
          final chunk = await reader.read(remaining > 64 * 1024 ? 64 * 1024 : remaining);
          if (chunk.isEmpty) {
            return const FullBackupVerification(ok: false, message: 'Una entrada del respaldo está truncada.');
          }
          hashSink.add(chunk);
          dbTempSink?.add(chunk);
          remaining -= chunk.length;
        }
        hashSink.close();
        await dbTempSink?.flush();
        await dbTempSink?.close();
        final separator = await reader.readByte();
        if (separator != 10) {
          return const FullBackupVerification(ok: false, message: 'Separador interno de respaldo inválido.');
        }
        if (digestSink.events.single.toString() != expectedHash) {
          return FullBackupVerification(ok: false, message: 'Falló la integridad SHA-256 de $path.');
        }
        if (dbTemp != null) {
          final result = await DatabaseHelper.instance.verificarRespaldo(dbTemp.path);
          if (result['ok'] != true) {
            return FullBackupVerification(ok: false, message: 'La base incluida no es válida: ${result['message']}');
          }
          dbVersion = (result['user_version'] as num?)?.toInt();
        }
        entries++;
        if (kind == 'document') documents++;
        bytes += length;
      }
      if (entries == 0 || dbVersion == null || databaseEntries != 1) {
        return const FullBackupVerification(ok: false, message: 'El respaldo no contiene una única base SQLite verificable.');
      }
      return FullBackupVerification(
        ok: true,
        message: 'Base de datos y archivos documentales verificados.',
        entries: entries,
        bytes: bytes,
        documentFiles: documents,
        databaseVersion: dbVersion,
      );
    } catch (_) {
      return const FullBackupVerification(ok: false, message: 'El respaldo no pudo validarse completamente.');
    } finally {
      await reader.close();
      await prepared.dispose();
      if (temp != null && await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  /// Simulacro no destructivo de restauración.
  ///
  /// Extrae el contenedor a un directorio temporal, abre la copia de SQLite en
  /// solo lectura, ejecuta quick_check y valida que las referencias del SGDEA
  /// incluidas en la base existan dentro del respaldo. No reemplaza la base ni
  /// el repositorio activo del usuario.
  Future<FullBackupDrillResult> drillRestore(File backup) async {
    final verification = await verify(backup);
    if (!verification.ok) {
      return FullBackupDrillResult(ok: false, message: verification.message);
    }
    final temp = await Directory.systemTemp.createTemp('merkaerp_restore_drill_');
    Database? stagedDb;
    try {
      await _extract(backup, temp);
      final dbFile = File(p.join(temp.path, 'database', 'merkaerp.db'));
      if (!await dbFile.exists()) {
        return const FullBackupDrillResult(ok: false, message: 'El respaldo extraído no contiene la base esperada.');
      }
      stagedDb = await openDatabase(dbFile.path, readOnly: true, singleInstance: false);
      final quick = await stagedDb.rawQuery('PRAGMA quick_check');
      final quickOk = quick.expand((row) => row.values).every((value) => value?.toString().toLowerCase() == 'ok');
      if (!quickOk) {
        return const FullBackupDrillResult(ok: false, message: 'La copia extraída no supera PRAGMA quick_check.');
      }
      final version = Sqflite.firstIntValue(await stagedDb.rawQuery('PRAGMA user_version'));
      final tableCount = Sqflite.firstIntValue(await stagedDb.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )) ??
          0;

      var refs = 0;
      var missing = 0;
      for (final table in const ['gd_documents', 'gd_instruments']) {
        final exists = Sqflite.firstIntValue(await stagedDb.rawQuery(
              "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
              [table],
            )) ==
            1;
        if (!exists) continue;
        final rows = await stagedDb.query(table, columns: ['file_path'], where: 'file_path IS NOT NULL');
        for (final row in rows) {
          final raw = row['file_path']?.toString();
          if (raw == null || raw.trim().isEmpty) continue;
          refs++;
          final normalized = raw.replaceAll('\\', '/');
          const marker = '/gestion_documental/';
          final markerIndex = normalized.indexOf(marker);
          final relative = markerIndex >= 0
              ? normalized.substring(markerIndex + marker.length)
              : (p.isAbsolute(normalized) ? p.basename(normalized) : normalized);
          if (!_isSafeRelative(relative)) {
            missing++;
            continue;
          }
          final candidate = File(p.joinAll([temp.path, 'gestion_documental', ...p.posix.split(relative)]));
          if (!await candidate.exists()) missing++;
        }
      }
      final ok = missing == 0;
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'SIMULACRO_RESTAURACION_RESPALDO',
        entidad: 'backup',
        detalle: 'backup=${p.basename(backup.path)}; ok=$ok; tables=$tableCount; document_refs=$refs; missing=$missing',
      );
      return FullBackupDrillResult(
        ok: ok,
        message: ok
            ? 'La copia se extrajo, abrió en solo lectura y sus referencias documentales fueron verificadas.'
            : 'La base es legible, pero faltan $missing de $refs referencias documentales en el respaldo.',
        databaseVersion: version,
        tables: tableCount,
        documentReferences: refs,
        missingDocumentReferences: missing,
      );
    } catch (error) {
      return FullBackupDrillResult(ok: false, message: 'El simulacro no pudo completarse: $error');
    } finally {
      await stagedDb?.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<void> restore(File backup) async {
    final verification = await verify(backup);
    if (!verification.ok) throw StateError(verification.message);
    final rollback = await createFullBackup(label: 'merkaerp_rollback');
    try {
      await _restoreVerified(backup);
      await DatabaseHelper.instance.registrarEventoAuditoria(
        accion: 'RESTAURAR_RESPALDO_INTEGRAL',
        entidad: 'backup',
        detalle: '${backup.path}; rollback=${rollback.path}',
      );
    } catch (_) {
      try {
        await _restoreVerified(rollback);
        await DatabaseHelper.instance.registrarEventoAuditoria(
          accion: 'RESTAURAR_RESPALDO_INTEGRAL_REVERTIDO',
          entidad: 'backup',
          detalle: 'Se recuperó automáticamente ${rollback.path}',
        );
      } catch (_) {
        // Conservamos el rollback para recuperación manual; no ocultar el error original.
      }
      rethrow;
    }
  }

  Future<void> _restoreVerified(File backup) async {
    final appRoot = await getApplicationDocumentsDirectory();
    final temp = await Directory(p.join(appRoot.path, '.merka_restore_${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);
    try {
      await _extract(backup, temp);
      final databaseFile = File(p.join(temp.path, 'database', 'merkaerp.db'));
      final stagedDocs = Directory(p.join(temp.path, 'gestion_documental'));
      final activeDocs = await _documentRoot();
      final oldDocs = Directory('${activeDocs.path}.previous_restore');
      if (await oldDocs.exists()) await oldDocs.delete(recursive: true);

      if (await activeDocs.exists()) await activeDocs.rename(oldDocs.path);
      try {
        if (await stagedDocs.exists()) {
          await stagedDocs.rename(activeDocs.path);
        } else {
          await activeDocs.create(recursive: true);
        }
        await DatabaseHelper.instance.restaurarRespaldo(databaseFile.path);
        await _repairDocumentPaths(activeDocs);
        if (await oldDocs.exists()) await oldDocs.delete(recursive: true);
      } catch (_) {
        if (await activeDocs.exists()) await activeDocs.delete(recursive: true);
        if (await oldDocs.exists()) await oldDocs.rename(activeDocs.path);
        rethrow;
      }
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<void> _extract(File backup, Directory destination) async {
    final prepared = await _LocalBackupCrypto.instance.prepareForRead(backup);
    final reader = await prepared.file.open(mode: FileMode.read);
    try {
      if (await _readLine(reader) != _magic) throw StateError('Formato de respaldo no reconocido.');
      final metadataLine = await _readLine(reader);
      if (metadataLine == null) throw StateError('Manifiesto incompleto.');
      final metadata = jsonDecode(metadataLine);
      if (metadata is! Map || metadata['format'] != 1) throw StateError('Formato de manifiesto inválido.');
      final expectedEntries = (metadata['entries'] as num?)?.toInt() ?? -1;
      if (expectedEntries < 1) throw StateError('Cantidad de entradas inválida.');
      final seenPaths = <String>{};
      var extractedEntries = 0;
      while (true) {
        final line = await _readLine(reader);
        if (line == null) throw StateError('Respaldo truncado.');
        final header = jsonDecode(line);
        if (header is! Map) throw StateError('Entrada inválida.');
        if (header['end'] == true) {
          final declaredEnd = (header['entries'] as num?)?.toInt();
          if (declaredEnd != expectedEntries || extractedEntries != expectedEntries) {
            throw StateError('El número de entradas no coincide con el manifiesto.');
          }
          break;
        }
        final relative = header['path']?.toString() ?? '';
        final length = (header['length'] as num?)?.toInt() ?? -1;
        final expectedHash = header['sha256']?.toString() ?? '';
        if (!_isSafeRelative(relative) || length < 0 || expectedHash.length != 64) {
          throw StateError('Ruta o entrada insegura en respaldo.');
        }
        if (!seenPaths.add(relative)) throw StateError('Ruta duplicada en respaldo: $relative');
        final target = File(p.joinAll([destination.path, ...p.posix.split(relative)]));
        if (!await target.parent.exists()) await target.parent.create(recursive: true);
        final sink = target.openWrite();
        final digestSink = AccumulatorSink<crypto.Digest>();
        final hashSink = crypto.sha256.startChunkedConversion(digestSink);
        var remaining = length;
        try {
          while (remaining > 0) {
            final chunk = await reader.read(remaining > 64 * 1024 ? 64 * 1024 : remaining);
            if (chunk.isEmpty) throw StateError('Entrada truncada.');
            sink.add(chunk);
            hashSink.add(chunk);
            remaining -= chunk.length;
          }
          hashSink.close();
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (digestSink.events.single.toString() != expectedHash) {
          throw StateError('Falló la integridad SHA-256 de $relative.');
        }
        if (await reader.readByte() != 10) throw StateError('Separador interno inválido.');
        extractedEntries++;
      }
    } finally {
      await reader.close();
      await prepared.dispose();
    }
  }

  Future<void> _repairDocumentPaths(Directory root) async {
    final db = await DatabaseHelper.instance.database;
    for (final table in const ['gd_documents', 'gd_instruments']) {
      final exists = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
            [table],
          )) ==
          1;
      if (!exists) continue;
      final rows = await db.query(
        table,
        columns: ['id', 'company_id', 'file_path'],
        where: 'file_path IS NOT NULL',
      );
      for (final row in rows) {
        final raw = row['file_path']?.toString();
        if (raw == null || raw.isEmpty) continue;
        final normalized = raw.replaceAll('\\', '/');
        final marker = '/gestion_documental/';
        final index = normalized.indexOf(marker);
        if (index < 0) continue;
        final relative = normalized.substring(index + marker.length);
        if (!_isSafeRelative(relative)) continue;
        final repaired = p.joinAll([root.path, ...p.posix.split(relative)]);
        await db.update(
          table,
          {'file_path': repaired},
          where: 'company_id = ? AND id = ?',
          whereArgs: [row['company_id'], row['id']],
        );
      }
    }
  }

  Future<int> applyRetention({int keep = 30}) async {
    final safeKeep = keep.clamp(1, 365).toInt();
    final backups = await listBackups();
    var deleted = 0;
    for (final file in backups.skip(safeKeep)) {
      // Los rollback recientes también cuentan dentro de la retención: son
      // respaldos integrales válidos y pueden recuperarse manualmente.
      try {
        await file.delete();
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  bool _isSafeRelative(String raw) {
    if (raw.trim().isEmpty || p.isAbsolute(raw)) return false;
    final normalized = p.posix.normalize(raw.replaceAll('\\', '/'));
    return normalized != '..' && !normalized.startsWith('../') && !normalized.contains('/../');
  }

  Future<String?> _readLine(RandomAccessFile file) async {
    final bytes = <int>[];
    while (true) {
      final value = await file.readByte();
      if (value == -1) return bytes.isEmpty ? null : utf8.decode(bytes);
      if (value == 10) return utf8.decode(bytes);
      if (value != 13) bytes.add(value);
      if (bytes.length > 1024 * 1024) throw StateError('Cabecera de respaldo excesiva.');
    }
  }

  String _timestamp(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}${value.second.toString().padLeft(2, '0')}';
}

class _BackupSource {
  const _BackupSource({required this.file, required this.relativePath, required this.kind});
  final File file;
  final String relativePath;
  final String kind;
}

class _PreparedBackup {
  const _PreparedBackup(this.file, {this.temporary = false});

  final File file;
  final bool temporary;

  Future<void> dispose() async {
    if (temporary && await file.parent.exists()) {
      await file.parent.delete(recursive: true);
    }
  }
}

/// Cifrado autenticado por bloques para no cargar respaldos grandes en RAM.
/// Cada registro autentica su posición y tipo; el registro final autenticado
/// evita aceptar truncamientos en límites de bloque.
class _LocalBackupCrypto {
  _LocalBackupCrypto._();

  static final _LocalBackupCrypto instance = _LocalBackupCrypto._();
  static const _magic = 'MERKALOC2';
  static const _secureKeyName = 'merka_local_backup_aes_key_v1';
  static const _chunkSize = 1024 * 1024;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  Uint8List? _testKey;

  // Se mantiene privado al archivo: los tests de respaldo pueden inyectar la
  // clave mediante FullBackupService.configureEncryptionKeyForTests.
  void configureForTests(Uint8List? key) => _testKey = key;

  Future<void> encrypt(File plain, File encrypted) async {
    final key = await _key();
    final input = await plain.open(mode: FileMode.read);
    final output = await encrypted.open(mode: FileMode.write);
    var index = 0;
    try {
      await output.writeFrom(utf8.encode(_magic));
      while (true) {
        final chunk = await input.read(_chunkSize);
        if (chunk.isEmpty) break;
        await _writeRecord(
          output,
          type: 1,
          index: index++,
          plain: Uint8List.fromList(chunk),
          key: key,
        );
      }
      await _writeRecord(
        output,
        type: 2,
        index: index,
        plain: Uint8List(0),
        key: key,
      );
      await output.flush();
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<_PreparedBackup> prepareForRead(File source) async {
    final input = await source.open(mode: FileMode.read);
    try {
      final prefix = await input.read(utf8.encode(_magic).length);
      if (utf8.decode(prefix, allowMalformed: true) != _magic) {
        return _PreparedBackup(source);
      }
    } finally {
      await input.close();
    }

    final tempDir = await Directory.systemTemp.createTemp('merkaerp_backup_plain_');
    final output = File(p.join(tempDir.path, 'backup.plain'));
    try {
      await _decrypt(source, output);
      return _PreparedBackup(output, temporary: true);
    } catch (_) {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _decrypt(File encrypted, File plain) async {
    final key = await _key();
    final input = await encrypted.open(mode: FileMode.read);
    final output = await plain.open(mode: FileMode.write);
    var index = 0;
    var finalSeen = false;
    try {
      final magic = await input.read(utf8.encode(_magic).length);
      if (utf8.decode(magic, allowMalformed: true) != _magic) {
        throw StateError('Formato de respaldo cifrado no reconocido.');
      }
      while (!finalSeen) {
        final type = await input.readByte();
        if (type != 1 && type != 2) {
          throw StateError('Registro cifrado inválido o truncado.');
        }
        final lengthBytes = await input.read(4);
        if (lengthBytes.length != 4) throw StateError('Respaldo cifrado truncado.');
        final length = ByteData.sublistView(Uint8List.fromList(lengthBytes)).getUint32(0);
        if (length < 16 || length > _chunkSize + 16) {
          throw StateError('Longitud de bloque cifrado inválida.');
        }
        final nonce = await input.read(12);
        final cipherText = await input.read(length);
        if (nonce.length != 12 || cipherText.length != length) {
          throw StateError('Respaldo cifrado truncado.');
        }
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(
              KeyParameter(key),
              128,
              Uint8List.fromList(nonce),
              _aad(index, type),
            ),
          );
        final decoded = cipher.process(Uint8List.fromList(cipherText));
        if (type == 2) {
          if (decoded.isNotEmpty || await input.position() != await input.length()) {
            throw StateError('Marcador final cifrado inválido.');
          }
          finalSeen = true;
        } else {
          await output.writeFrom(decoded);
          index++;
        }
      }
      await output.flush();
    } catch (_) {
      throw StateError(
        'El respaldo no superó la autenticación AES-256-GCM o usa otra clave de instalación.',
      );
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<void> _writeRecord(
    RandomAccessFile output, {
    required int type,
    required int index,
    required Uint8List plain,
    required Uint8List key,
  }) async {
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, _aad(index, type)),
      );
    final cipherText = cipher.process(plain);
    final length = ByteData(4)..setUint32(0, cipherText.length);
    await output.writeByte(type);
    await output.writeFrom(length.buffer.asUint8List());
    await output.writeFrom(nonce);
    await output.writeFrom(cipherText);
  }

  Uint8List _aad(int index, int type) {
    final data = ByteData(5)
      ..setUint32(0, index)
      ..setUint8(4, type);
    return Uint8List.fromList([...utf8.encode(_magic), ...data.buffer.asUint8List()]);
  }

  Future<Uint8List> _key() async {
    final injected = _testKey;
    if (injected != null) {
      if (injected.length != 32) throw StateError('La clave de prueba debe tener 32 bytes.');
      return injected;
    }
    final stored = await _storage.read(key: _secureKeyName);
    if (stored != null && stored.isNotEmpty) {
      final decoded = base64Decode(stored);
      if (decoded.length != 32) throw StateError('La clave segura de respaldo es inválida.');
      return Uint8List.fromList(decoded);
    }
    final generated = _randomBytes(32);
    await _storage.write(key: _secureKeyName, value: base64Encode(generated));
    return generated;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
