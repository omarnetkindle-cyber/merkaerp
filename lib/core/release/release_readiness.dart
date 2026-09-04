enum ReleaseCheckStatus { pass, warning, fail }

class ReleaseCheck {
  const ReleaseCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.detail,
    this.blocking = false,
  });

  final String id;
  final String title;
  final ReleaseCheckStatus status;
  final String detail;
  final bool blocking;

  bool get ok => status == ReleaseCheckStatus.pass;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'status': status.name,
    'detail': detail,
    'blocking': blocking,
  };
}

class ReleaseReadinessReport {
  const ReleaseReadinessReport({
    required this.generatedAt,
    required this.checks,
  });

  final DateTime generatedAt;
  final List<ReleaseCheck> checks;

  List<ReleaseCheck> get blockingIssues =>
      checks.where((check) => check.blocking && !check.ok).toList();

  List<ReleaseCheck> get warnings => checks
      .where((check) => check.status == ReleaseCheckStatus.warning)
      .toList();

  bool get readyForProduction => blockingIssues.isEmpty && warnings.isEmpty;

  bool get readyForPilot => blockingIssues.isEmpty;

  Map<String, Object?> toMap() => {
    'generated_at': generatedAt.toIso8601String(),
    'ready_for_pilot': readyForPilot,
    'ready_for_production': readyForProduction,
    'blocking_issues': blockingIssues.length,
    'warnings': warnings.length,
    'checks': checks.map((check) => check.toMap()).toList(),
  };
}

class ReleaseReadinessService {
  const ReleaseReadinessService();

  ReleaseReadinessReport evaluate({
    required bool releaseBuild,
    required bool analyzerClean,
    required bool testsPassing,
    required bool databaseHealthClean,
    bool productionSignature = false,
    bool backupRestoreVerified = false,
    bool versionIncremented = false,
    bool privacyReviewed = false,
  }) {
    return ReleaseReadinessReport(
      generatedAt: DateTime.now(),
      checks: [
        _check(
          id: 'release_build',
          title: 'APK/AAB de produccion',
          ok: releaseBuild,
          blocking: true,
          pass: 'La aplicacion corre en modo release.',
          fail: 'Compila un build release antes de distribuir en produccion.',
        ),
        _check(
          id: 'production_signature',
          title: 'Firma de produccion',
          ok: productionSignature,
          blocking: true,
          pass: 'La firma de produccion esta configurada.',
          fail:
              'Configura keystore propio y versionado formal antes de publicar.',
        ),
        _check(
          id: 'static_analysis',
          title: 'Analisis estatico',
          ok: analyzerClean,
          blocking: true,
          pass: 'El analizador no reporta errores.',
          fail: 'Corrige errores de analyzer antes de liberar.',
        ),
        _check(
          id: 'automated_tests',
          title: 'Pruebas automatizadas',
          ok: testsPassing,
          blocking: true,
          pass: 'Las pruebas automatizadas pasan.',
          fail: 'Ejecuta y corrige la suite de pruebas.',
        ),
        _check(
          id: 'data_health',
          title: 'Salud de datos',
          ok: databaseHealthClean,
          blocking: true,
          pass: 'No hay inconsistencias bloqueantes de datos.',
          fail:
              'Resuelve inventario negativo, asientos descuadrados u orfandad.',
        ),
        _check(
          id: 'backup_restore',
          title: 'Respaldo y restauracion',
          ok: backupRestoreVerified,
          blocking: false,
          pass: 'Respaldo y restauracion verificados.',
          fail: 'Verifica restauracion real antes de actualizar empresas.',
        ),
        _check(
          id: 'versioning',
          title: 'Versionado',
          ok: versionIncremented,
          blocking: false,
          pass: 'VersionCode/versionName fueron incrementados.',
          fail: 'Incrementa version antes de distribuir el build.',
        ),
        _check(
          id: 'privacy',
          title: 'Privacidad y datos',
          ok: privacyReviewed,
          blocking: false,
          pass: 'Uso de datos revisado para operacion empresarial.',
          fail: 'Documenta responsabilidades de datos, respaldos y usuarios.',
        ),
      ],
    );
  }

  ReleaseReadinessReport localRuntimeReport({
    bool databaseHealthClean = false,
    bool backupRestoreVerified = false,
  }) {
    const isRelease = bool.fromEnvironment('dart.vm.product');
    const analyzerClean = bool.fromEnvironment('MERKA_ANALYZER_CLEAN', defaultValue: false);
    const testsPassing = bool.fromEnvironment('MERKA_TESTS_PASSING', defaultValue: false);
    const productionSignature = bool.fromEnvironment('MERKA_PRODUCTION_SIGNATURE', defaultValue: false);
    const versionIncremented = bool.fromEnvironment('MERKA_VERSION_INCREMENTED', defaultValue: false);
    const privacyReviewed = bool.fromEnvironment('MERKA_PRIVACY_REVIEWED', defaultValue: false);
    return evaluate(
      releaseBuild: isRelease,
      analyzerClean: analyzerClean,
      testsPassing: testsPassing,
      databaseHealthClean: databaseHealthClean,
      productionSignature: productionSignature,
      backupRestoreVerified: backupRestoreVerified,
      versionIncremented: versionIncremented,
      privacyReviewed: privacyReviewed,
    );
  }

  ReleaseCheck _check({
    required String id,
    required String title,
    required bool ok,
    required bool blocking,
    required String pass,
    required String fail,
  }) {
    if (ok) {
      return ReleaseCheck(
        id: id,
        title: title,
        status: ReleaseCheckStatus.pass,
        detail: pass,
        blocking: blocking,
      );
    }
    return ReleaseCheck(
      id: id,
      title: title,
      status: blocking ? ReleaseCheckStatus.fail : ReleaseCheckStatus.warning,
      detail: fail,
      blocking: blocking,
    );
  }
}
