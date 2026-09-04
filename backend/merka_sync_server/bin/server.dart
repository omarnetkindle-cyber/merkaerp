import 'dart:io';

import 'package:args/args.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart';

import 'package:merka_sync_server/src/sync_auth.dart';
import 'package:merka_sync_server/src/sync_event_store.dart';
import 'package:merka_sync_server/src/sync_routes.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('host', defaultsTo: '0.0.0.0')
    ..addOption('port', defaultsTo: Platform.environment['PORT'] ?? '8080');
  final parsed = parser.parse(args);

  final databaseUrl = Platform.environment['DATABASE_URL'];
  if (databaseUrl == null || databaseUrl.trim().isEmpty) {
    stderr.writeln('DATABASE_URL requerido.');
    exitCode = 64;
    return;
  }

  final publicKey = Platform.environment['MERKA_SYNC_PUBLIC_KEY_PEM'] ??
      Platform.environment['MERKA_LICENSE_PUBLIC_KEY_PEM'];
  if (publicKey == null || publicKey.trim().isEmpty) {
    stderr.writeln('MERKA_SYNC_PUBLIC_KEY_PEM requerido.');
    exitCode = 64;
    return;
  }

  final connection = await Connection.openFromUrl(databaseUrl);
  final store = PostgresSyncEventStore(connection: connection);
  await store.ensureSchema();

  final api = MerkaSyncApi(
    auth: JwtRs256SyncAuthVerifier(
      publicKeyPem: publicKey,
      expectedIssuer: Platform.environment['MERKA_SYNC_EXPECTED_ISSUER'] ??
          'MerkaERP-ControlCenter',
    ),
    store: store,
  );

  final port = int.parse(parsed['port'].toString());
  final server = await serve(api.handler, parsed['host'].toString(), port);
  stdout.writeln(
    'Merka Sync Server escuchando en http://${server.address.host}:${server.port}',
  );
}
