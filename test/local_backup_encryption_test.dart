import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/backup/full_backup_service.dart';

void main() {
  late Directory temp;
  final service = FullBackupService.instance;
  final key = List<int>.generate(32, (index) => index + 1);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('merka_backup_crypto_test_');
    service.configureEncryptionKeyForTests(key);
  });

  tearDown(() async {
    service.configureEncryptionKeyForTests(null);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('AES-256-GCM cifra por bloques y recupera el contenido exacto', () async {
    final source = File('${temp.path}/source.bin');
    final original = List<int>.generate(
      2 * 1024 * 1024 + 137,
      (index) => (index * 31) & 0xff,
    );
    await source.writeAsBytes(original);
    final encrypted = File('${temp.path}/backup.mkbackup');

    await service.encryptFileForTests(source, encrypted);

    final prefix = await encrypted.openRead(0, 9).fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    expect(String.fromCharCodes(prefix), 'MERKALOC2');
    expect(await encrypted.readAsBytes(), isNot(original));

    final restored = await service.decryptFileForTests(
      encrypted,
      '${temp.path}/restored.bin',
    );
    expect(await restored.readAsBytes(), original);
  });

  test('rechaza alteración y truncamiento del respaldo', () async {
    final source = File('${temp.path}/source.bin');
    await source.writeAsBytes(List<int>.generate(4096, (index) => index & 0xff));
    final encrypted = File('${temp.path}/backup.mkbackup');
    await service.encryptFileForTests(source, encrypted);

    final tamperedBytes = await encrypted.readAsBytes();
    tamperedBytes[40] ^= 0x01;
    final tampered = File('${temp.path}/tampered.mkbackup');
    await tampered.writeAsBytes(tamperedBytes);
    await expectLater(
      service.decryptFileForTests(tampered, '${temp.path}/bad.bin'),
      throwsA(isA<StateError>()),
    );

    final truncated = File('${temp.path}/truncated.mkbackup');
    await truncated.writeAsBytes(tamperedBytes.sublist(0, tamperedBytes.length - 12));
    await expectLater(
      service.decryptFileForTests(truncated, '${temp.path}/short.bin'),
      throwsA(isA<StateError>()),
    );
  });
}
