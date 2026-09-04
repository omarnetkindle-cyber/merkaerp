import 'package:flutter_test/flutter_test.dart';

import '../tool/audit_schema_queries.dart' as audit;

void main() {
  test('auditoría de consultas contra esquema actual', () async {
    await audit.runAudit();
  });
}
