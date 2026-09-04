/// Servicio de Provisiones NICSP 19
/// Provisiones, Pasivos Contingentes y Activos Contingentes
/// NICSP 19 - Contabilidad y Presentación de Provisiones
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';

enum TipoProvision {
  litigios,
  garantias,
  beneficiosEmpleados,
  contratosOnerosos,
  perdidasOperacionales,
  otros,
}

class ProvisionesService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  ProvisionesService({required this.db, required this.auditoriaService});

  MoneyValue _moneyCriterion(Object? value) {
    if (value == null) return publicMoneyZero();
    if (value is MoneyValue) return value;
    return publicMoneyFromMajor(value.toString());
  }

  /// Crea una provisión manual
  Future<Map<String, dynamic>> crearProvision({
    required String entidadId,
    required String usuarioId,
    required TipoProvision tipo,
    required String descripcion,
    required MoneyValue valorProvision,
    DateTime? fechaVencimiento,
    String? referenciaDocumento,
  }) async {
    final id = _uuid.v4();
    final fechaCreacion = DateTime.now();

    await db.insert('provisiones', {
      'id': id,
      'entidad_id': entidadId,
      'tipo_provision': tipo.toString().split('.').last,
      'descripcion': descripcion,
      'valor_provision': valorProvision.toSql(),
      'valor_utilizado': publicMoneyZero().toSql(),
      'saldo_disponible': valorProvision.toSql(),
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_vencimiento': fechaVencimiento?.toIso8601String(),
      'estado': 'activa',
      'referencia_documento': referenciaDocumento,
    });

    // Generar asiento contable automático
    final asientoId = await _generarAsientoProvision(
      entidadId: entidadId,
      usuarioId: usuarioId,
      provisionId: id,
      tipo: tipo,
      valor: valorProvision,
      descripcion: descripcion,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'contabilidad',
      accion: 'creacion_provision',
      valorAnterior: {},
      valorNuevo: {
        'provision_id': id,
        'tipo': tipo.toString(),
        'valor': valorProvision.toSql(),
        'asiento_id': asientoId,
      },
      referenciaId: id,
    );

    return {
      'provision_id': id,
      'tipo': tipo.toString(),
      'valor': valorProvision.toSql(),
      'saldo_disponible': valorProvision.toSql(),
      'asiento_id': asientoId,
      'estado': 'activa',
    };
  }

  /// Calcula provisiones automáticamente basadas en criterios predefinidos
  Future<Map<String, dynamic>> calcularProvisionAutomatica({
    required String entidadId,
    required String usuarioId,
    required TipoProvision tipo,
    required Map<String, dynamic> criterios,
  }) async {
    var valorCalculado = publicMoneyZero();
    String descripcion = '';
    String? referenciaDocumento;

    switch (tipo) {
      case TipoProvision.litigios:
        // Provisionar X% del valor de contratos en litigio
        final valorContratos = _moneyCriterion(
          criterios['valor_contratos_litigio'],
        );
        final porcentaje =
            criterios['porcentaje_provision'] as double? ??
            0.1; // 10% por defecto
        valorCalculado = valorContratos.multiplyDecimal(porcentaje.toString());
        descripcion =
            'Provisión para litigios - ${porcentaje * 100}% de contratos en litigio';
        referenciaDocumento = criterios['referencia_contratos'];
        break;

      case TipoProvision.garantias:
        // Provisionar valor de garantías vigentes
        valorCalculado = _moneyCriterion(criterios['valor_garantias']);
        descripcion = 'Provisión para garantías vigentes';
        referenciaDocumento = criterios['referencia_garantias'];
        break;

      case TipoProvision.beneficiosEmpleados:
        // Provisionar vacaciones y primas acumuladas
        valorCalculado =
            _moneyCriterion(criterios['vacaciones_acumuladas']) +
            _moneyCriterion(criterios['primas_acumuladas']);
        descripcion =
            'Provisión para beneficios a empleados (vacaciones + primas)';
        break;

      case TipoProvision.contratosOnerosos:
        // Provisionar pérdidas esperadas en contratos onerosos
        valorCalculado = _moneyCriterion(criterios['perdida_esperada']);
        descripcion = 'Provisión para contratos onerosos';
        referenciaDocumento = criterios['referencia_contrato'];
        break;

      case TipoProvision.perdidasOperacionales:
        // Provisionar pérdidas operacionales esperadas
        valorCalculado = _moneyCriterion(criterios['perdida_esperada']);
        descripcion = 'Provisión para pérdidas operacionales';
        break;

      case TipoProvision.otros:
        valorCalculado = _moneyCriterion(criterios['valor']);
        descripcion = criterios['descripcion'] as String? ?? 'Provisión otros';
        break;
    }

    if (valorCalculado <= publicMoneyZero()) {
      return {
        'mensaje': 'No se generó provisión - valor calculado es 0 o negativo',
        'valor_calculado': valorCalculado.toSql(),
      };
    }

    return await crearProvision(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipo: tipo,
      descripcion: descripcion,
      valorProvision: valorCalculado,
      fechaVencimiento: criterios['fecha_vencimiento'] != null
          ? DateTime.parse(criterios['fecha_vencimiento'])
          : null,
      referenciaDocumento: referenciaDocumento,
    );
  }

  /// Utiliza una provisión (cuando se materializa el riesgo)
  Future<Map<String, dynamic>> utilizarProvision({
    required String entidadId,
    required String usuarioId,
    required String provisionId,
    required MoneyValue valorUtilizar,
    required String motivo,
  }) async {
    final provisionResult = await db.query(
      'provisiones',
      where: 'id = ?',
      whereArgs: [provisionId],
    );

    if (provisionResult.isEmpty) {
      throw Exception('Provisión no encontrada');
    }

    final provision = provisionResult.first;
    final saldoDisponible = publicMoneyFromSql(provision['saldo_disponible']);

    if (valorUtilizar > saldoDisponible) {
      throw Exception(
        'El valor a utilizar excede el saldo disponible de la provisión',
      );
    }

    final nuevoSaldo = saldoDisponible - valorUtilizar;
    final valorUtilizadoActual =
        publicMoneyFromSql(provision['valor_utilizado']) + valorUtilizar;

    await db.update(
      'provisiones',
      {
        'valor_utilizado': valorUtilizadoActual.toSql(),
        'saldo_disponible': nuevoSaldo.toSql(),
        if (nuevoSaldo == publicMoneyZero()) 'estado': 'agotada',
      },
      where: 'id = ?',
      whereArgs: [provisionId],
    );

    // Generar asiento contable de reversión parcial
    final asientoId = await _generarAsientoReversionProvision(
      entidadId: entidadId,
      usuarioId: usuarioId,
      provisionId: provisionId,
      valor: valorUtilizar,
      motivo: motivo,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'contabilidad',
      accion: 'utilizacion_provision',
      valorAnterior: {
        'saldo_anterior': saldoDisponible.toSql(),
        'utilizado_anterior': provision['valor_utilizado'],
      },
      valorNuevo: {
        'saldo_nuevo': nuevoSaldo.toSql(),
        'utilizado_nuevo': valorUtilizadoActual.toSql(),
        'valor_utilizado': valorUtilizar.toSql(),
        'asiento_id': asientoId,
      },
      referenciaId: provisionId,
    );

    return {
      'provision_id': provisionId,
      'valor_utilizado': valorUtilizar.toSql(),
      'saldo_disponible': nuevoSaldo.toSql(),
      'estado': nuevoSaldo == publicMoneyZero() ? 'agotada' : 'activa',
      'asiento_id': asientoId,
    };
  }

  /// Revierte una provisión cuando ya no es necesaria
  Future<Map<String, dynamic>> revertirProvision({
    required String entidadId,
    required String usuarioId,
    required String provisionId,
    required String motivo,
  }) async {
    final provisionResult = await db.query(
      'provisiones',
      where: 'id = ?',
      whereArgs: [provisionId],
    );

    if (provisionResult.isEmpty) {
      throw Exception('Provisión no encontrada');
    }

    final provision = provisionResult.first;
    final saldoDisponible = publicMoneyFromSql(provision['saldo_disponible']);

    if (saldoDisponible <= publicMoneyZero()) {
      throw Exception('La provisión no tiene saldo disponible para revertir');
    }

    await db.update(
      'provisiones',
      {'estado': 'revertida', 'saldo_disponible': publicMoneyZero().toSql()},
      where: 'id = ?',
      whereArgs: [provisionId],
    );

    // Generar asiento contable de reversión total
    final asientoId = await _generarAsientoReversionProvision(
      entidadId: entidadId,
      usuarioId: usuarioId,
      provisionId: provisionId,
      valor: saldoDisponible,
      motivo: motivo,
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'contabilidad',
      accion: 'reversion_provision',
      valorAnterior: {
        'saldo_anterior': saldoDisponible.toSql(),
        'estado_anterior': provision['estado'],
      },
      valorNuevo: {
        'saldo_nuevo': publicMoneyZero().toSql(),
        'estado_nuevo': 'revertida',
        'asiento_id': asientoId,
      },
      referenciaId: provisionId,
    );

    return {
      'provision_id': provisionId,
      'saldo_revertido': saldoDisponible.toSql(),
      'estado': 'revertida',
      'asiento_id': asientoId,
    };
  }

  /// Genera el asiento contable de provisión
  Future<String> _generarAsientoProvision({
    required String entidadId,
    required String usuarioId,
    required String provisionId,
    required TipoProvision tipo,
    required MoneyValue valor,
    required String descripcion,
  }) async {
    final asientoId = _uuid.v4();
    final numeroAsiento = await _generarNumeroAsiento(entidadId);
    final fechaAsiento = DateTime.now();

    // Cuentas contables según NICSP 19
    // Débito: Gasto por provisión (cuenta de resultado)
    // Crédito: Provisión (cuenta de pasivo)
    final cuentaGasto = _obtenerCuentaGastoProvision(tipo);
    final cuentaProvision = _obtenerCuentaProvision(tipo);

    await db.insert('asientos_contables_sp', {
      'id': asientoId,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': 'Provisión - $descripcion',
      'tipo_asiento': 'automatico',
      'estado': 'borrador',
      'total_debito': valor.toSql(),
      'total_credito': valor.toSql(),
      'usuario_creo': usuarioId,
      'usuario_reviso': usuarioId,
      'fecha_revision': DateTime.now().toIso8601String(),
      'referencia_origen': provisionId,
      'tipo_documento_origen': 'provision',
      'observaciones':
          'Asiento generado automáticamente por provisión NICSP 19',
    });

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaGasto['codigo'],
      'cuenta_nombre': cuentaGasto['nombre'],
      'debito': valor.toSql(),
      'credito': publicMoneyZero().toSql(),
      'referencia_id': provisionId,
    });

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaProvision['codigo'],
      'cuenta_nombre': cuentaProvision['nombre'],
      'debito': publicMoneyZero().toSql(),
      'credito': valor.toSql(),
      'referencia_id': provisionId,
    });

    await db.update(
      'asientos_contables_sp',
      {'estado': 'aprobado'},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    return asientoId;
  }

  /// Genera el asiento contable de reversión de provisión
  Future<String> _generarAsientoReversionProvision({
    required String entidadId,
    required String usuarioId,
    required String provisionId,
    required MoneyValue valor,
    required String motivo,
  }) async {
    final asientoId = _uuid.v4();
    final numeroAsiento = await _generarNumeroAsiento(entidadId);
    final fechaAsiento = DateTime.now();

    // Reversión: Crédito a gasto, Débito a provisión
    final provisionResult = await db.query(
      'provisiones',
      where: 'id = ?',
      whereArgs: [provisionId],
    );

    final tipoProvision = TipoProvision.values.firstWhere(
      (e) =>
          e.toString().split('.').last ==
          provisionResult.first['tipo_provision'],
    );

    final cuentaGasto = _obtenerCuentaGastoProvision(tipoProvision);
    final cuentaProvision = _obtenerCuentaProvision(tipoProvision);

    await db.insert('asientos_contables_sp', {
      'id': asientoId,
      'entidad_id': entidadId,
      'numero_asiento': numeroAsiento,
      'fecha_asiento': fechaAsiento.toIso8601String(),
      'descripcion': 'Reversión de provisión - $motivo',
      'tipo_asiento': 'automatico',
      'estado': 'borrador',
      'total_debito': valor.toSql(),
      'total_credito': valor.toSql(),
      'usuario_creo': usuarioId,
      'usuario_reviso': usuarioId,
      'fecha_revision': DateTime.now().toIso8601String(),
      'referencia_origen': provisionId,
      'tipo_documento_origen': 'reversion_provision',
      'observaciones':
          'Asiento generado automáticamente por reversión de provisión NICSP 19',
    });

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaProvision['codigo'],
      'cuenta_nombre': cuentaProvision['nombre'],
      'debito': valor.toSql(),
      'credito': publicMoneyZero().toSql(),
      'referencia_id': provisionId,
    });

    await db.insert('detalles_asientos', {
      'id': _uuid.v4(),
      'asiento_id': asientoId,
      'cuenta_codigo': cuentaGasto['codigo'],
      'cuenta_nombre': cuentaGasto['nombre'],
      'debito': publicMoneyZero().toSql(),
      'credito': valor.toSql(),
      'referencia_id': provisionId,
    });

    await db.update(
      'asientos_contables_sp',
      {'estado': 'aprobado'},
      where: 'id = ?',
      whereArgs: [asientoId],
    );

    return asientoId;
  }

  /// Obtiene la cuenta de gasto según tipo de provisión
  Map<String, String> _obtenerCuentaGastoProvision(TipoProvision tipo) {
    switch (tipo) {
      case TipoProvision.litigios:
        return {
          'codigo': '540101',
          'nombre': 'Gastos por provisiones - Litigios',
        };
      case TipoProvision.garantias:
        return {
          'codigo': '540102',
          'nombre': 'Gastos por provisiones - Garantías',
        };
      case TipoProvision.beneficiosEmpleados:
        return {
          'codigo': '540103',
          'nombre': 'Gastos por provisiones - Beneficios a empleados',
        };
      case TipoProvision.contratosOnerosos:
        return {
          'codigo': '540104',
          'nombre': 'Gastos por provisiones - Contratos onerosos',
        };
      case TipoProvision.perdidasOperacionales:
        return {
          'codigo': '540105',
          'nombre': 'Gastos por provisiones - Pérdidas operacionales',
        };
      case TipoProvision.otros:
        return {'codigo': '540199', 'nombre': 'Gastos por provisiones - Otros'};
    }
  }

  /// Obtiene la cuenta de provisión según tipo
  Map<String, String> _obtenerCuentaProvision(TipoProvision tipo) {
    switch (tipo) {
      case TipoProvision.litigios:
        return {'codigo': '250101', 'nombre': 'Provisiones - Litigios'};
      case TipoProvision.garantias:
        return {'codigo': '250102', 'nombre': 'Provisiones - Garantías'};
      case TipoProvision.beneficiosEmpleados:
        return {
          'codigo': '250103',
          'nombre': 'Provisiones - Beneficios a empleados',
        };
      case TipoProvision.contratosOnerosos:
        return {
          'codigo': '250104',
          'nombre': 'Provisiones - Contratos onerosos',
        };
      case TipoProvision.perdidasOperacionales:
        return {
          'codigo': '250105',
          'nombre': 'Provisiones - Pérdidas operacionales',
        };
      case TipoProvision.otros:
        return {'codigo': '250199', 'nombre': 'Provisiones - Otros'};
    }
  }

  /// Genera el número de asiento siguiente
  Future<String> _generarNumeroAsiento(String entidadId) async {
    final resultado = await db.rawQuery(
      "SELECT MAX(numero_asiento) as max_numero FROM asientos_contables_sp WHERE entidad_id = ?",
      [entidadId],
    );

    final maxNumero = resultado.first['max_numero'];
    if (maxNumero == null) return 'AS-0001';

    final numeroActual = int.parse(maxNumero.toString().split('-')[1]);
    return 'AS-${(numeroActual + 1).toString().padLeft(4, '0')}';
  }

  /// Consulta provisiones por entidad
  Future<List<Map<String, dynamic>>> consultarProvisiones({
    required String entidadId,
    TipoProvision? tipo,
    String? estado,
  }) async {
    String query = 'SELECT * FROM provisiones WHERE entidad_id = ?';
    List<dynamic> args = [entidadId];

    if (tipo != null) {
      query += ' AND tipo_provision = ?';
      args.add(tipo.toString().split('.').last);
    }

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado);
    }

    query += ' ORDER BY fecha_creacion DESC';

    final resultados = await db.rawQuery(query, args);
    return resultados;
  }
}
