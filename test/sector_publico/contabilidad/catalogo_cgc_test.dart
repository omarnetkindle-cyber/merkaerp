import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/contabilidad/database/schema_contabilidad.dart';
import 'package:merka_erp/sector_publico/contabilidad/services/contabilidad_nicsp_service.dart';
import 'package:merka_erp/sector_publico/database/schema_multi_tenant.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entidadId = 'ENT-CGC-001';
const _usuarioId = 'USR-CGC-001';

late Database db;
late ContabilidadNICSPService contabilidad;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await SchemaMultiTenant.crearTablas(db);
    await SchemaContabilidad.crearTablas(db);
    await db.insert('entidades_territoriales', {
      'id': _entidadId,
      'nit': '901000002-1',
      'razon_social': 'Entidad CGC de Prueba',
      'tipo_entidad': 'municipio',
      'fecha_creacion': DateTime(2026, 1, 1).toIso8601String(),
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    await SchemaMultiTenant.insertarDatosSemillaCGC(db, _entidadId);
    contabilidad = ContabilidadNICSPService(
      db: db,
      auditoriaService: AuditoriaService(db),
    );
  });

  tearDown(() => db.close());

  test('siembra las cuentas CGC clave de las clases 1, 2, 3, 4, 5, 6, 8 y 9',
      () async {
    const cuentasEsperadas = {
      '1110': '1', '1415': '1', '1640': '1', '1920': '1',
      '2401': '2', '2410': '2', '2510': '2',
      '3105': '3', '3115': '3', '3120': '3',
      '4111': '4', '4115': '4', '4401': '4', '4802': '4',
      '5101': '5', '5111': '5', '5120': '5', '5310': '5',
      '6101': '6', '6310': '6',
      '8110': '8', '8390': '8',
      '9110': '9', '9390': '9',
    };

    for (final entry in cuentasEsperadas.entries) {
      final cuenta = await db.query(
        'plan_cuentas_cgc',
        where: 'entidad_id = ? AND codigo_cuenta = ?',
        whereArgs: [_entidadId, entry.key],
      );
      expect(cuenta, hasLength(1), reason: 'Falta cuenta ${entry.key}');
      expect(cuenta.single['clase'], entry.value);
    }
  });

  test('asientos NICSP de obligacion y pago usan cuentas del catalogo', () async {
    final obligacion = await contabilidad.generarAsientoObligacion(
      entidadId: _entidadId,
      usuarioId: _usuarioId,
      fechaReconocimiento: DateTime(2026, 7, 1),
      obligacionId: 'OBL-CGC-001',
      numeroObligacion: 'OBL-001',
      terceroNombre: 'Proveedor de prueba',
      valorObligacion: publicMoneyFromMajor('500'),
      cuentaGasto: '5101',
      nombreCuentaGasto: 'Servicios personales',
    );
    final pago = await contabilidad.generarAsientoPago(
      entidadId: _entidadId,
      usuarioId: _usuarioId,
      fechaPago: DateTime(2026, 7, 2),
      pagoId: 'PAG-CGC-001',
      numeroPago: 'PAG-001',
      terceroNombre: 'Proveedor de prueba',
      valorPago: publicMoneyFromMajor('500'),
      cuentaBanco: '1110',
      nombreCuentaBanco: 'Efectivo y equivalentes de efectivo',
    );

    final detalles = await db.query(
      'detalles_asientos',
      where: 'asiento_id IN (?, ?)',
      whereArgs: [obligacion.id, pago.id],
    );
    for (final detalle in detalles) {
      final codigo = detalle['cuenta_codigo'] as String;
      final catalogo = await db.query(
        'plan_cuentas_cgc',
        where: 'entidad_id = ? AND codigo_cuenta = ?',
        whereArgs: [_entidadId, codigo],
      );
      expect(catalogo, hasLength(1), reason: 'Cuenta $codigo fuera del CGC');
    }
  });
}
