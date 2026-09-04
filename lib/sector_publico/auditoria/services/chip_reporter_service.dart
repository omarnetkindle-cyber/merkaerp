/// Servicio de Reportes CHIP (Contaduría General de la Nación)
/// Generación de formularios CGN 2015_001 a 005 y CGN 2016C01
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/reporte_chip.dart';
import '../../../integrations/application/institutional_connector_service.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';
import '../../models/registro_auditoria.dart';
import '../../contabilidad/services/cierre_vigencia_service.dart';
import '../../contabilidad/services/contabilidad_nicsp_service.dart';

class CHIPReporterService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  CHIPReporterService({required this.db, required this.auditoriaService});

  Future<RolSectorPublico> _validarPermiso({
    required String entidadId,
    required String usuarioId,
    required Permiso permiso,
  }) async {
    final rol = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );

    if (rol == null) {
      throw Exception(
        'Acceso denegado: El usuario $usuarioId no tiene un rol asignado en la entidad $entidadId',
      );
    }

    if (!RolesPermisosService.tienePermiso(rol, permiso)) {
      throw Exception(
        'Acceso denegado: El rol ${rol.name} no tiene permiso para ${permiso.name}',
      );
    }

    return rol;
  }

  /// Genera los formularios cuyo origen esta persistido en MerkaERP.
  ///
  /// La nomenclatura 004/005 es el modelo local historico: 004 se alimenta de
  /// ejecucion presupuestal, 005 de saldos CGC de deuda publica y 2016C01 de
  /// variaciones significativas entre vigencias. No transmite al CHIP remoto.
  Future<Map<String, ReporteCHIP>> generarReportesDesdeDatosSistema({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.consultarAuditoria,
    );

    final datos001 = await _datosCGN2015_001DesdeSistema(entidadId);
    final datos002 = await _datosCGN2015_002DesdeSistema(entidadId, vigencia);
    final datos003 = await _datosCGN2015_003DesdeSistema(entidadId, vigencia);
    final datos004 = await _datosCGN2015_004DesdeSistema(entidadId, vigencia);
    final datos005 = await _datosCGN2015_005DesdeSistema(entidadId, vigencia);
    final datos2016 = await _datosCGN2016C01DesdeSistema(entidadId, vigencia);

    final reporte001 = await generarCGN2015_001(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos001,
    );
    final reporte002 = await generarCGN2015_002(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos002,
    );
    final reporte003 = await generarCGN2015_003(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos003,
    );
    final reporte004 = await generarCGN2015_004(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos004,
    );
    final reporte005 = await generarCGN2015_005(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos005,
    );
    final reporte2016 = await generarCGN2016C01(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datosConsolidados: datos2016,
    );

    return {
      'cgn2015_001': reporte001,
      'cgn2015_002': reporte002,
      'cgn2015_003': reporte003,
      'cgn2015_004': reporte004,
      'cgn2015_005': reporte005,
      'cgn2016C01': reporte2016,
    };
  }

  Future<DatosCGN2015_001> _datosCGN2015_001DesdeSistema(
    String entidadId,
  ) async {
    final entidades = await db.query(
      'entidades_territoriales',
      where: 'id = ? AND activo = 1',
      whereArgs: [entidadId],
    );
    if (entidades.length != 1) {
      throw StateError('No existe una entidad activa unica para CGN 2015_001');
    }
    final entidad = entidades.single;
    final funcionarios = await db.query(
      'funcionarios_entidad',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
    );
    final porCargo = <String, Map<String, dynamic>>{
      for (final funcionario in funcionarios)
        funcionario['cargo_clave'] as String: funcionario,
    };

    String entidadRequerida(String campo) {
      final valor = entidad[campo]?.toString().trim() ?? '';
      if (valor.isEmpty) {
        throw StateError(
          'Falta $campo en entidades_territoriales para CGN 2015_001',
        );
      }
      return valor;
    }

    String funcionarioRequerido(String cargo, String campo) {
      final funcionario = porCargo[cargo];
      final valor = funcionario?[campo]?.toString().trim() ?? '';
      if (valor.isEmpty) {
        throw StateError(
          'Falta $campo de $cargo en funcionarios_entidad para CGN 2015_001',
        );
      }
      return valor;
    }

    return DatosCGN2015_001(
      nit: entidadRequerida('nit'),
      razonSocial: entidadRequerida('razon_social'),
      tipoEntidad: entidadRequerida('tipo_entidad'),
      departamento: entidadRequerida('departamento'),
      municipio: entidadRequerida('municipio'),
      direccion: funcionarioRequerido('contacto_entidad', 'direccion'),
      telefono: funcionarioRequerido('contacto_entidad', 'telefono'),
      email: funcionarioRequerido('contacto_entidad', 'email'),
      representanteLegal: funcionarioRequerido(
        'representante_legal',
        'nombre_completo',
      ),
      identificacionRepresentante: funcionarioRequerido(
        'representante_legal',
        'identificacion',
      ),
      ordenadorGasto: funcionarioRequerido(
        'ordenador_gasto',
        'nombre_completo',
      ),
      identificacionOrdenador: funcionarioRequerido(
        'ordenador_gasto',
        'identificacion',
      ),
      contador: funcionarioRequerido('contador', 'nombre_completo'),
      identificacionContador: funcionarioRequerido(
        'contador',
        'identificacion',
      ),
      tarjetaProfesionalContador: funcionarioRequerido(
        'contador',
        'tarjeta_profesional',
      ),
    );
  }

  Future<DatosCGN2015_002> _datosCGN2015_002DesdeSistema(
    String entidadId,
    String vigencia,
  ) async {
    final saldos = await db.query(
      'saldos_cuentas',
      where: 'entidad_id = ? AND vigencia = ?',
      whereArgs: [entidadId, vigencia],
    );

    MoneyValue sumar(String prefijo, {required bool acreedora}) => saldos
        .where(
          (saldo) => (saldo['cuenta_codigo'] as String).startsWith(prefijo),
        )
        .fold<MoneyValue>(publicMoneyZero(), (total, saldo) {
          final neto = publicMoneyFromSql(saldo['saldo_neto']);
          return total + (acreedora ? -neto : neto);
        });

    final ingresosTributarios = sumar('41', acreedora: true);
    final ingresosNoTributarios = sumar('42', acreedora: true);
    final transferenciasSGP = sumar('4401', acreedora: true);
    final totalIngresos = sumar('4', acreedora: true);
    final otrosIngresos =
        totalIngresos -
        ingresosTributarios -
        ingresosNoTributarios -
        transferenciasSGP;

    final gastosPersonal = sumar('5101', acreedora: false);
    final gastosGenerales = sumar('5111', acreedora: false);
    final transferencias = sumar('54', acreedora: false);
    final totalGastos =
        sumar('5', acreedora: false) +
        sumar('6', acreedora: false) +
        sumar('7', acreedora: false);
    final otrosGastos =
        totalGastos - gastosPersonal - gastosGenerales - transferencias;

    return DatosCGN2015_002(
      ingresosTributarios: ingresosTributarios,
      ingresosNoTributarios: ingresosNoTributarios,
      transferenciasSGP: transferenciasSGP,
      // No existe una equivalencia CGC persistida para regalias; no se acepta
      // entrada manual. El valor queda pendiente de una taxonomia contable.
      regalias: publicMoneyZero(),
      otrosIngresos: otrosIngresos,
      totalIngresos: totalIngresos,
      gastosPersonal: gastosPersonal,
      gastosGenerales: gastosGenerales,
      transferencias: transferencias,
      // Presupuesto no conserva una clasificacion contable de inversion.
      gastosInversion: publicMoneyZero(),
      otrosGastos: otrosGastos,
      totalGastos: totalGastos,
      resultadoOperacional: totalIngresos - totalGastos,
    );
  }

  Future<DatosCGN2015_003> _datosCGN2015_003DesdeSistema(
    String entidadId,
    String vigencia,
  ) async {
    final contabilidad = ContabilidadNICSPService(
      db: db,
      auditoriaService: auditoriaService,
    );
    final cierre = CierreVigenciaService(
      db: db,
      contabilidadService: contabilidad,
      auditoriaService: auditoriaService,
    );
    final estado = await cierre.generarEstadoSituacionFinanciera(
      entidadId: entidadId,
      vigencia: vigencia,
      fechaCorte: DateTime(int.parse(vigencia), 12, 31),
    );
    final activoCorriente = estado.activos
        .where(
          (renglon) => const {
            '11',
            '12',
            '13',
            '14',
          }.contains(renglon.codigoCuenta.substring(0, 2)),
        )
        .fold<MoneyValue>(
          publicMoneyZero(),
          (total, renglon) => total + renglon.valor,
        );
    final pasivoCorriente = estado.pasivos
        .where(
          (renglon) => const {
            '21',
            '22',
            '23',
            '24',
            '25',
          }.contains(renglon.codigoCuenta.substring(0, 2)),
        )
        .fold<MoneyValue>(
          publicMoneyZero(),
          (total, renglon) => total + renglon.valor,
        );

    return DatosCGN2015_003(
      activoCorriente: activoCorriente,
      activoNoCorriente: estado.totalActivo - activoCorriente,
      totalActivo: estado.totalActivo,
      pasivoCorriente: pasivoCorriente,
      pasivoNoCorriente: estado.totalPasivo - pasivoCorriente,
      totalPasivo: estado.totalPasivo,
      patrimonio: estado.totalPatrimonio,
      totalPasivoPatrimonio: estado.totalPasivoPatrimonio,
    );
  }

  Future<DatosCGN2015_004> _datosCGN2015_004DesdeSistema(
    String entidadId,
    String vigencia,
  ) async {
    final apropiacionInicial = await _sumarSql(
      'apropiaciones',
      'valor_inicial',
      entidadId,
      vigencia,
    );
    final apropiacionDefinitiva = await _sumarSql(
      'apropiaciones',
      'valor_apropiado',
      entidadId,
      vigencia,
    );
    final compromisos = await _sumarSql('rps', 'valor_rp', entidadId, vigencia);
    final obligaciones = await _sumarSql(
      'obligaciones',
      'valor_obligacion',
      entidadId,
      vigencia,
    );
    final pagos = await _sumarSql('pagos', 'valor_pago', entidadId, vigencia);
    final modificacionNeta = apropiacionDefinitiva - apropiacionInicial;

    return DatosCGN2015_004(
      apropiacionInicial: apropiacionInicial,
      adiciones: modificacionNeta > publicMoneyZero()
          ? modificacionNeta
          : publicMoneyZero(),
      reducciones: modificacionNeta < publicMoneyZero()
          ? -modificacionNeta
          : publicMoneyZero(),
      // El esquema local conserva apropiacion inicial y definitiva, pero no
      // separa creditos y contracreditos. Se dejan en cero para no duplicar la
      // modificacion neta como detalle oficial no persistido.
      credito: publicMoneyZero(),
      contraCredito: publicMoneyZero(),
      apropiacionDefinitiva: apropiacionDefinitiva,
      compromisos: compromisos,
      obligaciones: obligaciones,
      pagos: pagos,
      saldoPorComprometer: apropiacionDefinitiva - compromisos,
    );
  }

  Future<DatosCGN2015_005> _datosCGN2015_005DesdeSistema(
    String entidadId,
    String vigencia,
  ) async {
    final deudaInterna = await _sumarSaldosPorPrefijos(
      entidadId,
      vigencia,
      const ['2313'],
      acreedora: true,
    );
    final deudaExterna = await _sumarSaldosPorPrefijos(
      entidadId,
      vigencia,
      const ['2314'],
      acreedora: true,
    );
    final cuotaAmortizacion = await _sumarSaldosPorPrefijos(
      entidadId,
      vigencia,
      const ['5320'],
      acreedora: false,
    );
    final intereses = await _sumarSaldosPorPrefijos(entidadId, vigencia, const [
      '5802',
    ], acreedora: false);

    return DatosCGN2015_005(
      deudaInterna: deudaInterna,
      deudaExterna: deudaExterna,
      deudaTotal: deudaInterna + deudaExterna,
      servicioDeuda: cuotaAmortizacion + intereses,
      cuotaAmortizacion: cuotaAmortizacion,
      intereses: intereses,
      deudaVencida: publicMoneyZero(),
    );
  }

  Future<Map<String, dynamic>> _datosCGN2016C01DesdeSistema(
    String entidadId,
    String vigencia,
  ) async {
    final anio = int.parse(vigencia);
    final anterior = (anio - 1).toString();
    final saldos = await db.rawQuery(
      '''
      SELECT
        COALESCE(a.cuenta_codigo, p.cuenta_codigo) AS cuenta_codigo,
        COALESCE(a.cuenta_nombre, p.cuenta_nombre) AS cuenta_nombre,
        COALESCE(a.saldo_neto, 0) AS saldo_actual,
        COALESCE(p.saldo_neto, 0) AS saldo_anterior
      FROM saldos_cuentas a
      LEFT JOIN saldos_cuentas p
        ON p.entidad_id = a.entidad_id
       AND p.cuenta_codigo = a.cuenta_codigo
       AND p.vigencia = ?
      WHERE a.entidad_id = ? AND a.vigencia = ?
      UNION
      SELECT
        p.cuenta_codigo,
        p.cuenta_nombre,
        0 AS saldo_actual,
        p.saldo_neto AS saldo_anterior
      FROM saldos_cuentas p
      LEFT JOIN saldos_cuentas a
        ON a.entidad_id = p.entidad_id
       AND a.cuenta_codigo = p.cuenta_codigo
       AND a.vigencia = ?
      WHERE p.entidad_id = ? AND p.vigencia = ? AND a.id IS NULL
      ORDER BY cuenta_codigo
      ''',
      [anterior, entidadId, vigencia, vigencia, entidadId, anterior],
    );
    final variaciones = <Map<String, dynamic>>[];
    for (final saldo in saldos) {
      final actual = publicMoneyFromSql(saldo['saldo_actual']);
      final previo = publicMoneyFromSql(saldo['saldo_anterior']);
      final variacion = actual - previo;
      if (variacion == publicMoneyZero()) continue;
      final porcentaje = previo == publicMoneyZero()
          ? null
          : (variacion.minorUnits * 100) / previo.minorUnits.abs();
      variaciones.add({
        'cuenta_codigo': saldo['cuenta_codigo'],
        'cuenta_nombre': saldo['cuenta_nombre'],
        'saldo_anterior': publicMoneyForDisplay(previo),
        'saldo_actual': publicMoneyForDisplay(actual),
        'variacion': publicMoneyForDisplay(variacion),
        'porcentaje_variacion': porcentaje,
        'significativa': porcentaje == null || porcentaje.abs() >= 20,
      });
    }

    return {
      'formulario': 'CGN_2016_01_VARIACIONES_TRIMESTRALES_SIGNIFICATIVAS',
      'vigencia_actual': vigencia,
      'vigencia_anterior': anterior,
      'criterio_significatividad':
          'Variacion distinta de cero; significativa si no hay base previa o si abs(variacion/base) >= 20%',
      'variaciones': variaciones,
    };
  }

  Future<MoneyValue> _sumarSql(
    String tabla,
    String columna,
    String entidadId,
    String vigencia,
  ) async {
    final resultado = await db.rawQuery(
      'SELECT COALESCE(SUM($columna), 0) AS total FROM $tabla WHERE entidad_id = ? AND vigencia = ?',
      [entidadId, vigencia],
    );
    return publicMoneyFromSql(resultado.single['total']);
  }

  Future<MoneyValue> _sumarSaldosPorPrefijos(
    String entidadId,
    String vigencia,
    List<String> prefijos, {
    required bool acreedora,
  }) async {
    final saldos = await db.query(
      'saldos_cuentas',
      where:
          'entidad_id = ? AND vigencia = ? AND (${prefijos.map((_) => 'cuenta_codigo LIKE ?').join(' OR ')})',
      whereArgs: [
        entidadId,
        vigencia,
        ...prefijos.map((prefijo) => '$prefijo%'),
      ],
    );
    return saldos.fold<MoneyValue>(publicMoneyZero(), (total, saldo) {
      final neto = publicMoneyFromSql(saldo['saldo_neto']);
      return total + (acreedora ? -neto : neto);
    });
  }

  /// Genera formulario CGN 2015_001 - Información de la Entidad
  Future<ReporteCHIP> generarCGN2015_001({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_001 datos,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.consultarAuditoria,
    );
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2015_001,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2015_001',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera formulario CGN 2015_002 - Ingresos y Gastos
  Future<ReporteCHIP> generarCGN2015_002({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_002 datos,
  }) async {
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2015_002,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2015_002',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera formulario CGN 2015_003 - Situación Financiera
  Future<ReporteCHIP> generarCGN2015_003({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_003 datos,
  }) async {
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2015_003,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2015_003',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera formulario CGN 2015_004 - Ejecución Presupuestal
  Future<ReporteCHIP> generarCGN2015_004({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_004 datos,
  }) async {
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2015_004,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2015_004',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera formulario CGN 2015_005 - Deuda Pública
  Future<ReporteCHIP> generarCGN2015_005({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_005 datos,
  }) async {
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2015_005,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datos.toJson(),
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2015_005',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera formulario CGN 2016C01 - Consolidado
  Future<ReporteCHIP> generarCGN2016C01({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required Map<String, dynamic> datosConsolidados,
  }) async {
    final id = _uuid.v4();
    final fechaGeneracion = DateTime.now();

    final reporte = ReporteCHIP(
      id: id,
      entidadId: entidadId,
      tipoFormulario: TipoFormularioCHIP.cgn2016C01,
      vigencia: vigencia,
      fechaGeneracion: fechaGeneracion,
      usuarioGenero: usuarioId,
      datos: datosConsolidados,
      estado: 'generado',
    );

    await db.insert('reportes_chip', reporte.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'auditoria',
      accion: 'generacion_chip_cgn2016c01',
      valorAnterior: {},
      valorNuevo: {'reporte_id': id, 'vigencia': vigencia},
      referenciaId: id,
    );

    return reporte;
  }

  /// Genera todos los formularios CHIP para una vigencia
  Future<Map<String, ReporteCHIP>> generarPaqueteCHIP({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required DatosCGN2015_001 datos001,
    required DatosCGN2015_002 datos002,
    required DatosCGN2015_003 datos003,
    required DatosCGN2015_004 datos004,
    required DatosCGN2015_005 datos005,
  }) async {
    final reporte001 = await generarCGN2015_001(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos001,
    );

    final reporte002 = await generarCGN2015_002(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos002,
    );

    final reporte003 = await generarCGN2015_003(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos003,
    );

    final reporte004 = await generarCGN2015_004(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos004,
    );

    final reporte005 = await generarCGN2015_005(
      entidadId: entidadId,
      usuarioId: usuarioId,
      vigencia: vigencia,
      datos: datos005,
    );

    return {
      'cgn2015_001': reporte001,
      'cgn2015_002': reporte002,
      'cgn2015_003': reporte003,
      'cgn2015_004': reporte004,
      'cgn2015_005': reporte005,
    };
  }

  /// Marca un reporte como enviado
  Future<void> marcarEnviado({
    required String reporteId,
    required String usuarioId,
  }) async {
    await db.update(
      'reportes_chip',
      {'estado': 'enviado'},
      where: 'id = ?',
      whereArgs: [reporteId],
    );

    final reporte = await obtenerReporte(reporteId);
    if (reporte != null) {
      await auditoriaService.registrarEvento(
        entidadId: reporte.entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'auditoria',
        accion: 'envio_chip',
        valorAnterior: {'estado_anterior': 'generado'},
        valorNuevo: {'estado_nuevo': 'enviado'},
        referenciaId: reporteId,
      );
    }
  }

  /// Consulta reportes CHIP por entidad y vigencia
  Future<List<ReporteCHIP>> consultarReportes({
    required String entidadId,
    String? vigencia,
    TipoFormularioCHIP? tipoFormulario,
  }) async {
    String query = 'SELECT * FROM reportes_chip WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (vigencia != null) {
      query += ' AND vigencia = ?';
      args.add(vigencia);
    }

    if (tipoFormulario != null) {
      query += ' AND tipo_formulario = ?';
      args.add(tipoFormulario.toString().split('.').last);
    }

    query += ' ORDER BY fecha_generacion DESC';

    final resultados = await db.rawQuery(query, args);

    return resultados.map((r) => ReporteCHIP.fromJson(r)).toList();
  }

  /// Obtiene un reporte por ID
  Future<ReporteCHIP?> obtenerReporte(String id) async {
    final resultado = await db.query(
      'reportes_chip',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (resultado.isEmpty) return null;
    return ReporteCHIP.fromJson(resultado.first);
  }

  /// Exporta reporte a formato plano (para envío a CGN)
  /// Transmite un reporte únicamente cuando la entidad ha configurado un
  /// canal autorizado en Centro de Integraciones. Generar/exportar un archivo
  /// local nunca se interpreta como transmisión al CHIP.
  Future<void> transmitirReporte({
    required String reporteId,
    required String entidadId,
    required String usuarioId,
  }) async {
    await _validarPermiso(
      entidadId: entidadId,
      usuarioId: usuarioId,
      permiso: Permiso.exportarDatos,
    );
    final rows = await db.query(
      'reportes_chip',
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Reporte CHIP no encontrado.');
    final reporte = ReporteCHIP.fromJson(rows.first);
    final response = await InstitutionalConnectorService.instance.postJson(
      'chip_cgn',
      payload: {
        'reporte_id': reporte.id,
        'entidad_id': reporte.entidadId,
        'formulario': reporte.tipoFormulario.name,
        'vigencia': reporte.vigencia,
        'fecha_generacion': reporte.fechaGeneracion.toUtc().toIso8601String(),
        'datos': reporte.datos,
      },
    );
    if (!response.ok) throw StateError(response.message);
    await db.update(
      'reportes_chip',
      {'estado': 'enviado', 'observaciones': response.message},
      where: 'id = ? AND entidad_id = ?',
      whereArgs: [reporteId, entidadId],
    );
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'auditoria_chip',
      accion: 'transmision_chip_configurada',
      valorAnterior: {'estado': reporte.estado},
      valorNuevo: {'estado': 'enviado', 'http_status': response.statusCode},
      referenciaId: reporteId,
    );
  }

  Future<String> exportarAPlano(String reporteId) async {
    final reporte = await obtenerReporte(reporteId);
    if (reporte == null) {
      throw Exception('Reporte no encontrado');
    }

    // Generar formato plano según especificaciones CGN
    final buffer = StringBuffer();
    buffer.writeln(
      'TIPO_FORMULARIO;${reporte.tipoFormulario.toString().split('.').last}',
    );
    buffer.writeln('ENTIDAD_ID;${reporte.entidadId}');
    buffer.writeln('VIGENCIA;${reporte.vigencia}');
    buffer.writeln(
      'FECHA_GENERACION;${reporte.fechaGeneracion.toIso8601String()}',
    );
    buffer.writeln('USUARIO_GENERO;${reporte.usuarioGenero}');
    buffer.writeln('ESTADO;${reporte.estado}');

    // Datos específicos del formulario
    reporte.datos.forEach((key, value) {
      buffer.writeln('$key;$value');
    });

    return buffer.toString();
  }

  /// Valida formato plano CHIP contra especificaciones CGN
  Future<Map<String, dynamic>> validarFormatoCHIP({
    required String formatoPlano,
    required TipoFormularioCHIP tipoFormulario,
  }) async {
    final lineas = formatoPlano.split('\n');
    final errores = <String>[];
    final advertencias = <String>[];

    // Validaciones generales
    if (lineas.isEmpty) {
      errores.add('El archivo está vacío');
    }

    // Validaciones específicas por tipo de formulario
    switch (tipoFormulario) {
      case TipoFormularioCHIP.cgn2015_001:
        errores.addAll(_validarCGN2015_001(lineas));
        break;
      case TipoFormularioCHIP.cgn2015_002:
        errores.addAll(_validarCGN2015_002(lineas));
        break;
      case TipoFormularioCHIP.cgn2015_003:
        errores.addAll(_validarCGN2015_003(lineas));
        break;
      case TipoFormularioCHIP.cgn2015_004:
        errores.addAll(_validarCGN2015_004(lineas));
        break;
      case TipoFormularioCHIP.cgn2015_005:
        errores.addAll(_validarCGN2015_005(lineas));
        break;
      case TipoFormularioCHIP.cgn2016C01:
        errores.addAll(_validarCGN2016C01(lineas));
        break;
    }

    return {
      'valido': errores.isEmpty,
      'errores': errores,
      'advertencias': advertencias,
      'total_lineas': lineas.length,
    };
  }

  /// Valida CGN 2015_001 - Información de la Entidad
  List<String> _validarCGN2015_001(List<String> lineas) {
    final errores = <String>[];

    final camposObligatorios = [
      'TIPO_FORMULARIO',
      'ENTIDAD_ID',
      'VIGENCIA',
      'FECHA_GENERACION',
    ];

    for (final campo in camposObligatorios) {
      if (!lineas.any((linea) => linea.startsWith(campo))) {
        errores.add('Campo obligatorio faltante: $campo');
      }
    }

    return errores;
  }

  /// Valida CGN 2015_002 - Ingresos y Gastos
  List<String> _validarCGN2015_002(List<String> lineas) {
    final errores = <String>[];

    for (final linea in lineas) {
      if (linea.startsWith('VALOR_')) {
        final partes = linea.split(';');
        if (partes.length < 2) continue;
        final valor = partes[1];
        if (double.tryParse(valor) == null) {
          errores.add('Valor no numérico: $valor');
        }
      }
    }

    return errores;
  }

  /// Valida CGN 2015_003 - Situación Financiera
  List<String> _validarCGN2015_003(List<String> lineas) {
    final errores = <String>[];

    double activo = 0;
    double pasivo = 0;
    double patrimonio = 0;

    for (final linea in lineas) {
      if (linea.startsWith('TOTAL_ACTIVO;')) {
        activo = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('TOTAL_PASIVO;')) {
        pasivo = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('TOTAL_PATRIMONIO;')) {
        patrimonio = double.tryParse(linea.split(';')[1]) ?? 0;
      }
    }

    if ((activo - (pasivo + patrimonio)).abs() > 0.01) {
      errores.add('El activo no cuadra con pasivo + patrimonio');
    }

    return errores;
  }

  /// Valida CGN 2015_004 - Ejecución Presupuestal
  List<String> _validarCGN2015_004(List<String> lineas) {
    final errores = <String>[];

    double apropiacionDefinitiva = 0;
    double compromisos = 0;
    double saldo = 0;

    for (final linea in lineas) {
      if (linea.startsWith('apropiacion_definitiva;')) {
        apropiacionDefinitiva = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('compromisos;')) {
        compromisos = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('saldo_por_comprometer;')) {
        saldo = double.tryParse(linea.split(';')[1]) ?? 0;
      }
    }

    if ((apropiacionDefinitiva - compromisos - saldo).abs() > 0.01) {
      errores.add(
        'La apropiacion definitiva no cuadra con compromisos + saldo',
      );
    }

    return errores;
  }

  /// Valida CGN 2015_005 - Deuda Pública
  List<String> _validarCGN2015_005(List<String> lineas) {
    final errores = <String>[];

    double deudaInterna = 0;
    double deudaExterna = 0;
    double deudaTotal = 0;

    for (final linea in lineas) {
      if (linea.startsWith('DEUDA_INTERNA;')) {
        deudaInterna = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('DEUDA_EXTERNA;')) {
        deudaExterna = double.tryParse(linea.split(';')[1]) ?? 0;
      }
      if (linea.startsWith('DEUDA_TOTAL;')) {
        deudaTotal = double.tryParse(linea.split(';')[1]) ?? 0;
      }
    }

    if ((deudaTotal - (deudaInterna + deudaExterna)).abs() > 0.01) {
      errores.add('La deuda total no cuadra con interna + externa');
    }

    return errores;
  }

  /// Valida CGN 2016C01 - Consolidado
  List<String> _validarCGN2016C01(List<String> lineas) {
    final errores = <String>[];

    final formulariosComponentes = [
      'formulario',
      'vigencia_actual',
      'vigencia_anterior',
      'variaciones',
    ];

    for (final formulario in formulariosComponentes) {
      if (!lineas.any((linea) => linea.contains(formulario))) {
        errores.add('Formulario componente faltante: $formulario');
      }
    }

    return errores;
  }

  /// Guarda o actualiza los funcionarios responsables y datos de contacto de la entidad
  Future<void> guardarFuncionariosResponsables({
    required String entidadId,
    required String representanteNombre,
    required String representanteId,
    required String ordenadorNombre,
    required String ordenadorId,
    required String contadorNombre,
    required String contadorId,
    required String contadorTarjeta,
    required String direccion,
    required String telefono,
    required String email,
  }) async {
    final batch = db.batch();

    // Representante Legal
    batch.insert('funcionarios_entidad', {
      'id': 'FL-$entidadId-representante_legal',
      'entidad_id': entidadId,
      'cargo_clave': 'representante_legal',
      'nombre_completo': representanteNombre,
      'identificacion': representanteId,
      'tarjeta_profesional': '',
      'telefono': '',
      'email': '',
      'direccion': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Ordenador
    batch.insert('funcionarios_entidad', {
      'id': 'FL-$entidadId-ordenador_gasto',
      'entidad_id': entidadId,
      'cargo_clave': 'ordenador_gasto',
      'nombre_completo': ordenadorNombre,
      'identificacion': ordenadorId,
      'tarjeta_profesional': '',
      'telefono': '',
      'email': '',
      'direccion': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Contador
    batch.insert('funcionarios_entidad', {
      'id': 'FL-$entidadId-contador',
      'entidad_id': entidadId,
      'cargo_clave': 'contador',
      'nombre_completo': contadorNombre,
      'identificacion': contadorId,
      'tarjeta_profesional': contadorTarjeta,
      'telefono': '',
      'email': '',
      'direccion': '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Contacto Entidad
    batch.insert('funcionarios_entidad', {
      'id': 'FL-$entidadId-contacto_entidad',
      'entidad_id': entidadId,
      'cargo_clave': 'contacto_entidad',
      'nombre_completo': '',
      'identificacion': '',
      'tarjeta_profesional': '',
      'telefono': telefono,
      'email': email,
      'direccion': direccion,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await batch.commit(noResult: true);
  }
}
