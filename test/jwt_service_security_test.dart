import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/api/jwt_service.dart';

void main() {
  test('JWT local falla cerrado mientras no haya secreto configurado', () {
    final service = JWTService.instance;

    expect(() => service.generateToken({'sub': 'usuario'}), throwsStateError);
    expect(service.validateToken('cabecera.payload.firma'), isFalse);
  });

  test('JWT local acepta una clave explicita y rechaza clave vacia', () {
    final service = JWTService.instance;
    service.setSecretKey('secreto-de-prueba-efimero');

    final token = service.generateAccessToken(
      userId: 'U-1',
      companyId: 'E-1',
      role: 'contador',
    );

    expect(service.validateToken(token), isTrue);
    expect(() => service.setSecretKey('   '), throwsArgumentError);
  });
}
