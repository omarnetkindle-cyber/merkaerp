import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/invoicing/dian_transmission_client_noop.dart';
import 'package:merka_erp/core/invoicing/dian_transmission_client.dart';

void main() {
  test('NoOp checkConfiguration returns notConfigured when no keys', () async {
    final client = NoOpDianTransmissionClient(configReader: () async => {});
    final status = await client.checkConfiguration();
    expect(status, ConfigStatus.notConfigured);
  });

  test('NoOp checkConfiguration returns configuredPartial when some keys present', () async {
    final client = NoOpDianTransmissionClient(configReader: () async => {'dian_tech_key': 'abc'});
    final status = await client.checkConfiguration();
    expect(status, ConfigStatus.configuredPartial);
  });

  test('NoOp checkConfiguration returns configuredComplete when all keys present', () async {
    final client = NoOpDianTransmissionClient(configReader: () async => {
      'dian_tech_key': 'abc',
      'dian_pin': '123',
      'dian_software_id': 'SW-1',
    });
    final status = await client.checkConfiguration();
    expect(status, ConfigStatus.configuredComplete);
  });
}
