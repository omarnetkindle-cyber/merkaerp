import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import 'package:merka_erp/sector_publico/salud/database/schema_salud.dart';
import 'package:merka_erp/sector_publico/salud/models/glosa.dart';
import 'package:merka_erp/sector_publico/salud/models/rips.dart';
import 'package:merka_erp/sector_publico/salud/models/rips_fev.dart';
import 'package:merka_erp/sector_publico/salud/services/glosas_service.dart';
import 'package:merka_erp/sector_publico/salud/services/rips_service.dart';
import 'package:merka_erp/sector_publico/security/auditoria_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late RIPSService rips;
  late GlosasService glosas;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE entidades_territoriales (
        id TEXT PRIMARY KEY,
        nit TEXT NOT NULL,
        razon_social TEXT NOT NULL,
        tipo_entidad TEXT NOT NULL,
        fecha_creacion TEXT NOT NULL,
        plan_cuentas_cgc TEXT NOT NULL,
        configuracion_normativa TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE auditoria_registros (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        usuario_id TEXT NOT NULL,
        usuario_nombre TEXT,
        ip_direccion TEXT,
        fecha_hora TEXT NOT NULL,
        tipo_evento TEXT NOT NULL,
        modulo TEXT NOT NULL,
        accion TEXT NOT NULL,
        valor_anterior TEXT NOT NULL,
        valor_nuevo TEXT NOT NULL,
        hash_anterior TEXT,
        hash_actual TEXT NOT NULL,
        referencia_id TEXT,
        observaciones TEXT,
        archivado INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await SchemaSalud.crearTablas(db);
    await db.insert('entidades_territoriales', {
      'id': 'ESE-001',
      'nit': '900123456',
      'razon_social': 'ESE de prueba',
      'tipo_entidad': 'hospital_ese',
      'fecha_creacion': '2026-01-01',
      'plan_cuentas_cgc': '{}',
      'configuracion_normativa': '{}',
    });
    final auditoria = AuditoriaService(db);
    rips = RIPSService(db: db, auditoriaService: auditoria);
    glosas = GlosasService(db: db, auditoriaService: auditoria);
  });

  tearDown(() => db.close());

  test('genera RIPS-JSON 948 con CUPS y CIE-10 catalogados', () async {
    final contenido = await rips.generarRipsJson(
      entidadId: 'ESE-001',
      usuarioId: 'USR-001',
      documento: RipsFevDocumento(
        numDocumentoIdObligado: '900123456',
        numFactura: 'FEV-001',
        cucon: 'CUCON-2026-01',
        usuarios: [_usuarioConConsulta('890201', 'J00X')],
      ),
    );

    final json = jsonDecode(contenido) as Map<String, dynamic>;
    expect(json['numDocumentoIdObligado'], '900123456');
    expect(json['numFactura'], 'FEV-001');
    final usuario = (json['usuarios'] as List).single as Map<String, dynamic>;
    expect(usuario['servicios']['consultas'][0]['codConsulta'], '890201');
    expect(
      usuario['servicios']['consultas'][0]['codDiagnosticoPrincipal'],
      'J00X',
    );
    final persistido = await db.query('rips_fev_documentos');
    expect(persistido.single['cucon'], 'CUCON-2026-01');
  });

  test('rechaza RIPS-JSON con CUPS no catalogado', () async {
    final documento = RipsFevDocumento(
      numDocumentoIdObligado: '900123456',
      numFactura: 'FEV-002',
      usuarios: [_usuarioConConsulta('999999', 'J00X')],
    );
    expect(
      () => rips.generarRipsJson(
        entidadId: 'ESE-001',
        usuarioId: 'USR-001',
        documento: documento,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('alerta glosa pendiente al vencer cinco dias habiles', () async {
    final registro = await rips.registrarRIPS(
      entidadId: 'ESE-001',
      usuarioId: 'USR-001',
      tipoRIPS: TipoRIPS.ac,
      codigoPrestador: '110010000001',
      nombrePrestador: 'ESE de prueba',
      numeroFactura: 'FEV-003',
      fechaFactura: DateTime(2026, 5, 1),
      fechaInicio: DateTime(2026, 5, 1),
      fechaFin: DateTime(2026, 5, 1),
      codigoPaciente: '30303030',
      nombrePaciente: 'Paciente de prueba',
      tipoIdentificacion: 'CC',
      numeroIdentificacion: '30303030',
      codigoServicio: '890201',
      nombreServicio: 'Consulta',
      valorServicio: publicMoneyFromMajor('60000'),
    );
    await glosas.generarGlosa(
      entidadId: 'ESE-001',
      usuarioId: 'USR-001',
      ripsId: registro.id,
      numeroFactura: 'FEV-003',
      eps: 'EPS de prueba',
      tipoGlosa: TipoGlosa.errorFacturacion,
      motivo: 'Soporte pendiente',
      valorGlosado: publicMoneyFromMajor('60000'),
      valorAceptado: publicMoneyZero(),
      valorRechazado: publicMoneyZero(),
      fechaEnvio: DateTime(2026, 5, 1),
    );
    final fila = (await db.query('glosas')).single;
    expect(fila['fecha_limite_respuesta'], startsWith('2026-05-08'));
    expect(
      await glosas.consultarAlertasRespuestaGlosa(
        entidadId: 'ESE-001',
        fechaReferencia: DateTime(2026, 5, 9),
      ),
      hasLength(1),
    );
  });

  test(
    'migracion conserva glosas legadas y agrega fecha limite y catalogos',
    () async {
      final legacy = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await legacy.execute('DROP TABLE IF EXISTS glosas');
      await legacy.execute('''
      CREATE TABLE glosas (
        id TEXT PRIMARY KEY,
        entidad_id TEXT NOT NULL,
        numero_glosa TEXT NOT NULL,
        tipo_glosa TEXT NOT NULL,
        rips_id TEXT NOT NULL,
        numero_factura TEXT NOT NULL,
        eps TEXT NOT NULL,
        motivo TEXT NOT NULL,
        valor_glosado REAL NOT NULL,
        valor_aceptado REAL NOT NULL,
        valor_rechazado REAL NOT NULL,
        fecha_generacion TEXT NOT NULL,
        fecha_envio TEXT NOT NULL,
        fecha_respuesta TEXT,
        estado TEXT NOT NULL
      )
    ''');
      await legacy.insert('glosas', {
        'id': 'legacy-1',
        'entidad_id': 'ESE-001',
        'numero_glosa': 'GL-LEGACY',
        'tipo_glosa': 'otro',
        'rips_id': 'rips-legacy',
        'numero_factura': 'FAC-LEGACY',
        'eps': 'EPS',
        'motivo': 'Historico',
        'valor_glosado': 1,
        'valor_aceptado': 0,
        'valor_rechazado': 0,
        'fecha_generacion': '2026-01-01',
        'fecha_envio': '2026-01-01',
        'estado': 'generada',
      });
      await SchemaSalud.migrarRipsFevYGlosas(legacy);
      expect((await legacy.query('glosas')).single['id'], 'legacy-1');
      expect(
        await legacy.rawQuery("PRAGMA table_info(glosas)"),
        anyElement(
          predicate(
            (row) =>
                (row as Map<String, Object?>)['name'] ==
                'fecha_limite_respuesta',
          ),
        ),
      );
      expect(
        await legacy.query(
          'catalogo_cups',
          where: 'codigo = ?',
          whereArgs: ['890201'],
        ),
        hasLength(1),
      );
      final totalCups = await legacy.rawQuery(
        'SELECT COUNT(*) AS total FROM catalogo_cups',
      );
      expect(totalCups.single['total'], 13629);
      final totalCie10 = await legacy.rawQuery(
        'SELECT COUNT(*) AS total FROM catalogo_cie10',
      );
      expect(totalCie10.single['total'], 12545);
    },
  );
}

Map<String, dynamic> _usuarioConConsulta(String cups, String diagnostico) => {
  'tipoDocumentoIdentificacion': 'CC',
  'numDocumentoIdentificacion': '10101010',
  'tipoUsuario': '01',
  'fechaNacimiento': '1990-01-01',
  'codSexo': 'M',
  'codPaisResidencia': '170',
  'codMunicipioResidencia': '11001',
  'codZonaTerritorialResidencia': '01',
  'incapacidad': '02',
  'consecutivo': 1,
  'codPaisOrigen': '170',
  'servicios': {
    'consultas': [
      {
        'codPrestador': '110010000001',
        'fechaInicioAtencion': '2026-07-15 09:00',
        'numAutorizacion': null,
        'codConsulta': cups,
        'codDiagnosticoPrincipal': diagnostico,
        'vrServicio': 60000,
      },
    ],
  },
};
