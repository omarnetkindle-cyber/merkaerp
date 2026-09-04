/// Servicio de migración de datos históricos
/// Diagnóstico, mapeo de plan de cuentas, cargue de saldos iniciales
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../models/registro_auditoria.dart';
import '../security/auditoria_service.dart';

class DiagnosticoSistemaOrigen {
  final bool tienePlanCuentas;
  final int cantidadCuentas;
  final bool tieneSaldosIniciales;
  final int cantidadTerceros;
  final int cantidadContratos;
  final List<String> advertencias;
  final List<String> erroresCriticos;

  DiagnosticoSistemaOrigen({
    required this.tienePlanCuentas,
    required this.cantidadCuentas,
    required this.tieneSaldosIniciales,
    required this.cantidadTerceros,
    required this.cantidadContratos,
    required this.advertencias,
    required this.erroresCriticos,
  });

  bool get puedeMigrar => erroresCriticos.isEmpty;
}

class MigracionDatosService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  MigracionDatosService({required this.db, required this.auditoriaService});

  /// Resultado del diagnóstico del sistema origen

  /// Diagnostica el sistema origen antes de la migración
  Future<DiagnosticoSistemaOrigen> diagnosticarSistemaOrigen(
    Map<String, dynamic> datosOrigen,
  ) async {
    final advertencias = <String>[];
    final erroresCriticos = <String>[];

    // Verificar plan de cuentas
    final tienePlanCuentas = datosOrigen['plan_cuentas'] != null;
    final cantidadCuentas = tienePlanCuentas
        ? (datosOrigen['plan_cuentas'] as List).length
        : 0;

    if (!tienePlanCuentas) {
      erroresCriticos.add(
        'No se encontró plan de cuentas en el sistema origen',
      );
    } else if (cantidadCuentas < 50) {
      advertencias.add(
        'Plan de cuentas con muy pocas cuentas ($cantidadCuentas)',
      );
    }

    // Verificar saldos iniciales
    final tieneSaldosIniciales = datosOrigen['saldos_iniciales'] != null;
    if (!tieneSaldosIniciales) {
      advertencias.add('No se encontraron saldos iniciales');
    }

    // Verificar terceros
    final cantidadTerceros = datosOrigen['terceros'] != null
        ? (datosOrigen['terceros'] as List).length
        : 0;

    if (cantidadTerceros == 0) {
      advertencias.add('No se encontraron terceros registrados');
    }

    // Verificar contratos
    final cantidadContratos = datosOrigen['contratos'] != null
        ? (datosOrigen['contratos'] as List).length
        : 0;

    return DiagnosticoSistemaOrigen(
      tienePlanCuentas: tienePlanCuentas,
      cantidadCuentas: cantidadCuentas,
      tieneSaldosIniciales: tieneSaldosIniciales,
      cantidadTerceros: cantidadTerceros,
      cantidadContratos: cantidadContratos,
      advertencias: advertencias,
      erroresCriticos: erroresCriticos,
    );
  }

  /// Mapea cuentas del sistema origen al CGC (Catálogo General de Cuentas)
  Map<String, String> mapearPlanCuentas(
    Map<String, dynamic> planCuentasOrigen,
  ) {
    final mapeo = <String, String>{};

    // Mapeo manual de cuentas comunes
    final mapeoPredefinido = {
      '1105': '1110', // Efectivo
      '1110': '1111', // Caja
      '1120': '1121', // Bancos
      '1305': '1415', // Deudores
      '1504': '1640', // Propiedades planta y equipo
      '2205': '2401', // Cuentas por pagar
      '2335': '2410', // Obligaciones fiscales
      '2705': '2510', // Beneficios a empleados
      '4105': '4111', // Ingresos tributarios
      '5105': '5101', // Gastos de personal
      '5205': '5111', // Gastos generales
    };

    // Aplicar mapeo predefinido
    for (final entry in mapeoPredefinido.entries) {
      mapeo[entry.key] = entry.value;
    }

    // Para cuentas no mapeadas, intentar mapeo por nombre
    // (esto requeriría lógica de similitud de strings)

    return mapeo;
  }

  /// Carga saldos iniciales desde el sistema origen
  Future<void> cargarSaldosIniciales({
    required String entidadId,
    required String usuarioId,
    required Map<String, dynamic> saldosOrigen,
    required Map<String, String> mapeoCuentas,
  }) async {
    final fechaCarga = DateTime.now();

    for (final saldo in saldosOrigen.entries) {
      final cuentaOrigen = saldo.key;
      final valor = publicMoneyFromMajor((saldo.value as num).toString());

      // Obtener cuenta destino según mapeo
      final cuentaDestino = mapeoCuentas[cuentaOrigen];

      if (cuentaDestino == null) {
        // Registrar cuenta no mapeada
        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.creacionRegistro,
          modulo: 'migracion',
          accion: 'cuenta_no_mapeada',
          valorAnterior: {'cuenta_origen': cuentaOrigen},
          valorNuevo: {'valor': valor.toWireMap(), 'estado': 'no_mapeado'},
          observaciones: 'Cuenta no encontrada en mapeo CGC',
        );
        continue;
      }

      // Insertar saldo inicial
      await db.insert('saldos_iniciales', {
        'id': _uuid.v4(),
        'entidad_id': entidadId,
        'codigo_cuenta': cuentaDestino,
        'saldo_deudor': valor > publicMoneyZero() ? valor.toSql() : 0,
        'saldo_acreedor': valor < publicMoneyZero() ? (-valor).toSql() : 0,
        'fecha_carga': fechaCarga.toIso8601String(),
        'cargado_por': usuarioId,
        'cuenta_origen': cuentaOrigen,
      });

      // Registrar en auditoría
      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.creacionRegistro,
        modulo: 'migracion',
        accion: 'carga_saldo_inicial',
        valorAnterior: {
          'cuenta_origen': cuentaOrigen,
          'valor': valor.toWireMap(),
        },
        valorNuevo: {
          'cuenta_destino': cuentaDestino,
          'saldo_deudor': valor > publicMoneyZero() ? valor.toSql() : 0,
          'saldo_acreedor': valor < publicMoneyZero() ? (-valor).toSql() : 0,
        },
      );
    }
  }

  /// Migra terceros del sistema origen
  Future<void> migrarTerceros({
    required String entidadId,
    required String usuarioId,
    required List<Map<String, dynamic>> tercerosOrigen,
  }) async {
    for (final tercero in tercerosOrigen) {
      final tipoIdentificacion = tercero['tipo_identificacion'] as String;
      final numeroIdentificacion = tercero['numero_identificacion'] as String;

      // Verificar si ya existe
      final existente = await db.query(
        'terceros_sector_publico',
        where:
            'entidad_id = ? AND tipo_identificacion = ? AND numero_identificacion = ?',
        whereArgs: [entidadId, tipoIdentificacion, numeroIdentificacion],
      );

      if (existente.isNotEmpty) {
        // Actualizar tercero existente
        await db.update(
          'terceros_sector_publico',
          {
            'razon_social': tercero['razon_social'],
            'direccion': tercero['direccion'],
            'telefono': tercero['telefono'],
            'email': tercero['email'],
            'fecha_actualizacion': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [existente.first['id']],
        );

        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.modificacionRegistro,
          modulo: 'migracion',
          accion: 'actualizacion_tercero',
          valorAnterior: {'id': existente.first['id']},
          valorNuevo: tercero,
          referenciaId: existente.first['id'] as String?,
        );
      } else {
        // Crear nuevo tercero
        final id = _uuid.v4();
        await db.insert('terceros_sector_publico', {
          'id': id,
          'entidad_id': entidadId,
          'tipo_identificacion': tipoIdentificacion,
          'numero_identificacion': numeroIdentificacion,
          'digito_verificacion': tercero['digito_verificacion'],
          'razon_social': tercero['razon_social'],
          'primer_nombre': tercero['primer_nombre'],
          'segundo_nombre': tercero['segundo_nombre'],
          'primer_apellido': tercero['primer_apellido'],
          'segundo_apellido': tercero['segundo_apellido'],
          'tipo_tercero': tercero['tipo_tercero'] ?? 'general',
          'direccion': tercero['direccion'],
          'telefono': tercero['telefono'],
          'email': tercero['email'],
          'municipio': tercero['municipio'],
          'departamento': tercero['departamento'],
          'regimen_tributario': tercero['regimen_tributario'],
          'activo': 1,
          'fecha_creacion': DateTime.now().toIso8601String(),
        });

        await auditoriaService.registrarEvento(
          entidadId: entidadId,
          usuarioId: usuarioId,
          tipoEvento: TipoEventoAuditoria.creacionRegistro,
          modulo: 'migracion',
          accion: 'creacion_tercero',
          valorAnterior: {},
          valorNuevo: tercero,
          referenciaId: id,
        );
      }
    }
  }

  /// Migra contratos del sistema origen
  Future<void> migrarContratos({
    required String entidadId,
    required String usuarioId,
    required List<Map<String, dynamic>> contratosOrigen,
  }) async {
    for (final contrato in contratosOrigen) {
      final id = _uuid.v4();

      await db.insert('contratos_migracion', {
        'id': id,
        'entidad_id': entidadId,
        'numero_contrato': contrato['numero_contrato'],
        'tipo_contrato': contrato['tipo_contrato'],
        'objeto': contrato['objeto'],
        'valor_contrato': publicMoneyFromMajor(
          (contrato['valor_contrato'] as num).toString(),
        ).toSql(),
        'fecha_firma': contrato['fecha_firma'],
        'fecha_inicio': contrato['fecha_inicio'],
        'fecha_fin': contrato['fecha_fin'],
        'contratista_id': contrato['contratista_id'],
        'estado': contrato['estado'] ?? 'migrado',
        'fecha_migracion': DateTime.now().toIso8601String(),
        'migrado_por': usuarioId,
      });

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.creacionRegistro,
        modulo: 'migracion',
        accion: 'migracion_contrato',
        valorAnterior: {},
        valorNuevo: contrato,
        referenciaId: id,
      );
    }
  }

  /// Ejecuta el plan de paralelo (operación simultánea de sistemas)
  Future<void> iniciarPlanParalelo({
    required String entidadId,
    required String usuarioId,
    required int duracionDias,
  }) async {
    final fechaInicio = DateTime.now();
    final fechaFin = fechaInicio.add(Duration(days: duracionDias));

    await db.insert('plan_paralelo', {
      'id': _uuid.v4(),
      'entidad_id': entidadId,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin.toIso8601String(),
      'estado': 'en_curso',
      'creado_por': usuarioId,
    });

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'migracion',
      accion: 'inicio_plan_paralelo',
      valorAnterior: {},
      valorNuevo: {
        'fecha_inicio': fechaInicio.toIso8601String(),
        'fecha_fin': fechaFin.toIso8601String(),
        'duracion_dias': duracionDias,
      },
    );
  }

  /// Genera reporte de migración
  Future<Map<String, dynamic>> generarReporteMigracion(String entidadId) async {
    final saldosCargados = await db.rawQuery(
      'SELECT COUNT(*) as total FROM saldos_iniciales WHERE entidad_id = ?',
      [entidadId],
    );

    final tercerosMigrados = await db.rawQuery(
      'SELECT COUNT(*) as total FROM terceros_sector_publico WHERE entidad_id = ?',
      [entidadId],
    );

    final contratosMigrados = await db.rawQuery(
      'SELECT COUNT(*) as total FROM contratos_migracion WHERE entidad_id = ?',
      [entidadId],
    );

    return {
      'entidad_id': entidadId,
      'fecha_reporte': DateTime.now().toIso8601String(),
      'saldos_cargados': saldosCargados.first['total'],
      'terceros_migrados': tercerosMigrados.first['total'],
      'contratos_migrados': contratosMigrados.first['total'],
    };
  }
}
