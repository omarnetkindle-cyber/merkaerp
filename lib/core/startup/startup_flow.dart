/// Resolución determinista de las pantallas críticas de arranque.
///
/// La licencia se valida antes de permitir configurar o usar la aplicación.
/// El resultado no depende de la última pantalla visitada ni de un estado de
/// navegación persistido.
enum StartupRoute { needsLicense, needsOnboarding, login }

class StartupFlow {
  const StartupFlow._();

  static Future<StartupRoute> resolve({
    required Future<bool> Function() licenseIsValid,
    required Future<bool> Function() needsOnboarding,
  }) async {
    if (!await licenseIsValid()) return StartupRoute.needsLicense;
    if (await needsOnboarding()) return StartupRoute.needsOnboarding;
    return StartupRoute.login;
  }
}
