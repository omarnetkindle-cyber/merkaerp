import 'database_bootstrap_stub.dart'
    if (dart.library.io) 'database_bootstrap_io.dart';

Future<void> configureLocalDatabaseRuntime() async {
  configureLocalDatabaseRuntimeImpl();
}
