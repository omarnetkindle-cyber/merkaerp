import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/startup/startup_flow.dart';

void main() {
  test('licencia se evalúa antes de onboarding', () async {
    final calls = <String>[];

    final route = await StartupFlow.resolve(
      licenseIsValid: () async {
        calls.add('license');
        return false;
      },
      needsOnboarding: () async {
        calls.add('onboarding');
        return true;
      },
    );

    expect(route, StartupRoute.needsLicense);
    expect(calls, ['license']);
  });

  test('licencia válida lleva a onboarding si falta configuración', () async {
    final route = await StartupFlow.resolve(
      licenseIsValid: () async => true,
      needsOnboarding: () async => true,
    );

    expect(route, StartupRoute.needsOnboarding);
  });

  test('licencia válida y configuración completa llevan al login', () async {
    final route = await StartupFlow.resolve(
      licenseIsValid: () async => true,
      needsOnboarding: () async => false,
    );

    expect(route, StartupRoute.login);
  });
}
