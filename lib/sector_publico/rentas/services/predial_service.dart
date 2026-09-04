/// Servicio de Impuesto Predial
/// Ley 44 de 1990 - Carga de catastro, liquidación masiva, acuerdos de pago
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';
import '../models/predio.dart';
import '../models/liquidacion_predial.dart';
import '../models/acuerdo_pago.dart';
import 'intereses_moratorios_service.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../../security/roles_permisos_service.dart';

class PredialService {
  final Database db;
  final InteresesMoratoriosService interesesService;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  PredialService({
    required this.db,
    required this.interesesService,
    required this.auditoriaService,
  });

  MoneyValue _moneyInput(Object? value) {
    if (value is MoneyValue) return value;
    return publicMoneyFromMajor((value ?? 0).toString());
  }

  // ignore: unused_element — pendiente de conectar a endpoints de predial que requieran autorización
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

  /// Carga masiva de catastro IGAC
  Future<void> cargarCatastroIGAC({
    required String entidadId,
    required String usuarioId,
    required List<Map<String, dynamic>> datosCatastro,
  }) async {
    final batch = db.batch();

    for (final predioData in datosCatastro) {
      final id = _uuid.v4();
      batch.insert('predios', {
        'id': id,
        'entidad_id': entidadId,
        'numero_predial': predioData['numero_predial'],
        'numero_matricula': predioData['numero_matricula'],
        'direccion': predioData['direccion'],
        'barrio': predioData['barrio'],
        'municipio': predioData['municipio'],
        'departamento': predioData['departamento'],
        'area': predioData['area'],
        'avaluo_catastral': _moneyInput(predioData['avaluo_catastral']).toSql(),
        'avaluo_anterior': _moneyInput(
          predioData['avaluo_anterior'] ?? predioData['avaluo_catastral'],
        ).toSql(),
        'uso_suelo': predioData['uso_suelo'],
        'estrato': predioData['estrato'],
        'zona': predioData['zona'],
        'propietario_id': predioData['propietario_id'],
        'propietario_nombre': predioData['propietario_nombre'],
        'propietario_identificacion': predioData['propietario_identificacion'],
        'poseedor_nombre': predioData['poseedor_nombre'],
        'poseedor_identificacion': predioData['poseedor_identificacion'],
        'fecha_registro': DateTime.now().toIso8601String(),
        'activo': 1,
        'exento': predioData['exento'] ?? 0,
        'motivo_exencion': predioData['motivo_exencion'],
        'observaciones': predioData['observaciones'],
      });
    }

    await batch.commit(noResult: true);

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'rentas',
      accion: 'carga_catastro_igac',
      valorAnterior: {},
      valorNuevo: {'cantidad_predios': datosCatastro.length},
    );
  }

  /// Liquidación masiva predial para todos los predios
  Future<List<LiquidacionPredial>> liquidacionMasiva({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required double ipcAnual,
    DateTime? fechaLiquidacion,
  }) async {
    // Obtener todos los predios activos
    final predios = await db.query(
      'predios',
      where: 'entidad_id = ? AND activo = 1',
      whereArgs: [entidadId],
    );

    final liquidaciones = <LiquidacionPredial>[];

    for (final predioData in predios) {
      try {
        final liquidacion = await liquidarPredio(
          entidadId: entidadId,
          usuarioId: usuarioId,
          vigencia: vigencia,
          predioId: predioData['id'] as String,
          ipcAnual: ipcAnual,
          fechaLiquidacion: fechaLiquidacion,
        );
        liquidaciones.add(liquidacion);
      } catch (e) {
        // Continuar con el siguiente predio si falla
        continue;
      }
    }

    return liquidaciones;
  }

  /// Liquida un predio individual
  Future<LiquidacionPredial> liquidarPredio({
    required String entidadId,
    required String usuarioId,
    required String vigencia,
    required String predioId,
    required double ipcAnual,
    DateTime? fechaLiquidacion,
  }) async {
    // Obtener el predio
    final predioResult = await db.query(
      'predios',
      where: 'id = ?',
      whereArgs: [predioId],
    );

    if (predioResult.isEmpty) {
      throw Exception('Predio no encontrado');
    }

    final predioData = predioResult.first;
    final predio = Predio.fromJson(predioData);

    // VALIDACI“N NORMATIVA: Verificar tope de incremento
    if (!predio.cumpleTopeIncremento(ipcAnual)) {
      throw Exception(
        'El predio ${predio.numeroPredial} excede el tope de incremento legal. '
        'Ley 44/1990 Art. 6 + Ley 1995/2019 Art. 19',
      );
    }

    // Obtener tarifa según uso de suelo y estrato
    final tarifaResult = await db.query(
      'tarifas_prediales',
      where:
          'entidad_id = ? AND uso_suelo = ? AND estrato = ? AND vigencia = ? AND activo = 1',
      whereArgs: [
        entidadId,
        predio.usoSuelo.toString().split('.').last,
        predio.estrato.toString().split('.').last,
        vigencia,
      ],
    );

    final tarifa = tarifaResult.isNotEmpty
        ? (tarifaResult.first['tarifa'] as num).toDouble()
        : predio.obtenerTarifaPredial({});

    // Calcular impuesto base: Avalúo × Tarifa (por mil)
    final impuestoBase = predio.avaluoCatastral
        .multiplyDecimal(tarifa.toString())
        .divideDecimal('1000');

    final fecha = fechaLiquidacion ?? DateTime.now();
    final descuentoProntoPago = fecha.month <= 3
        ? impuestoBase.multiplyDecimal('0.10')
        : publicMoneyZero();

    final total = impuestoBase - descuentoProntoPago;

    final id = _uuid.v4();
    final numeroLiquidacion = 'LP-$vigencia-${_generarNumeroSecuencial()}';
    final fechaVencimiento = fecha.add(const Duration(days: 180)); // 6 meses

    final liquidacion = LiquidacionPredial(
      id: id,
      entidadId: entidadId,
      numeroLiquidacion: numeroLiquidacion,
      vigencia: vigencia,
      predioId: predioId,
      numeroPredial: predio.numeroPredial,
      contribuyenteId: predio.propietarioId,
      contribuyenteNombre: predio.propietarioNombre,
      contribuyenteIdentificacion: predio.propietarioIdentificacion,
      avaluoCatastral: predio.avaluoCatastral,
      tarifa: tarifa,
      impuestoBase: impuestoBase,
      descuentoProntoPago: descuentoProntoPago,
      interesesMora: publicMoneyZero(),
      totalPagar: total,
      fechaLiquidacion: fecha,
      fechaVencimiento: fechaVencimiento,
      estado: EstadoLiquidacion.generada,
    );

    await db.insert('liquidaciones_prediales', liquidacion.toJson());

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.liquidacionTributo,
      modulo: 'rentas',
      accion: 'liquidacion_predial',
      valorAnterior: {'predio_id': predioId},
      valorNuevo: {
        'liquidacion_id': id,
        'numero_liquidacion': numeroLiquidacion,
        'impuesto_base': impuestoBase.toSql(),
        'total_pagar': total.toSql(),
      },
      referenciaId: id,
    );

    return liquidacion;
  }

  /// Crea un acuerdo de pago para una liquidación
  Future<AcuerdoPago> crearAcuerdoPago({
    required String entidadId,
    required String usuarioId,
    required String liquidacionId,
    required int numeroCuotas,
    required int periodicidadDias,
  }) async {
    final liquidacionResult = await db.query(
      'liquidaciones_prediales',
      where: 'id = ?',
      whereArgs: [liquidacionId],
    );

    if (liquidacionResult.isEmpty) {
      throw Exception('Liquidación no encontrada');
    }

    final liquidacionData = liquidacionResult.first;
    final liquidacion = LiquidacionPredial.fromJson(liquidacionData);

    if (liquidacion.estado != EstadoLiquidacion.vencida) {
      throw Exception(
        'Solo se pueden crear acuerdos para liquidaciones vencidas',
      );
    }

    final valorCuota = liquidacion.totalPagar / numeroCuotas;
    final id = _uuid.v4();
    final numeroAcuerdo =
        'AP-${DateTime.now().year}-${_generarNumeroSecuencial()}';
    final fechaFirma = DateTime.now();
    final fechaPrimeraCuota = fechaFirma.add(Duration(days: periodicidadDias));

    final acuerdo = AcuerdoPago(
      id: id,
      entidadId: entidadId,
      numeroAcuerdo: numeroAcuerdo,
      liquidacionId: liquidacionId,
      numeroLiquidacion: liquidacion.numeroLiquidacion,
      contribuyenteId: liquidacion.contribuyenteId,
      contribuyenteNombre: liquidacion.contribuyenteNombre,
      valorOriginal: liquidacion.totalPagar,
      valorPagado: publicMoneyZero(),
      saldoPendiente: liquidacion.totalPagar,
      numeroCuotas: numeroCuotas,
      valorCuota: valorCuota,
      fechaFirma: fechaFirma,
      fechaPrimeraCuota: fechaPrimeraCuota,
      periodicidadDias: periodicidadDias,
      estado: EstadoAcuerdo.activo,
    );

    await db.insert('acuerdos_pago', acuerdo.toJson());

    // Actualizar estado de liquidación
    await db.update(
      'liquidaciones_prediales',
      {
        'estado': EstadoLiquidacion.enAcuerdo.toString().split('.').last,
        'acuerdo_pago_id': id,
      },
      where: 'id = ?',
      whereArgs: [liquidacionId],
    );

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'rentas',
      accion: 'creacion_acuerdo_pago',
      referenciaId: liquidacionId,
      valorAnterior: {'estado_anterior': liquidacion.estado.toString()},
      valorNuevo: {
        'acuerdo_id': id,
        'numero_acuerdo': numeroAcuerdo,
        'estado_nuevo': EstadoLiquidacion.enAcuerdo.toString(),
      },
    );

    return acuerdo;
  }

  /// Consulta liquidaciones por vigencia
  Future<List<LiquidacionPredial>> consultarLiquidaciones({
    required String entidadId,
    required String vigencia,
    EstadoLiquidacion? estado,
  }) async {
    String query =
        'SELECT * FROM liquidaciones_prediales WHERE entidad_id = ? AND vigencia = ?';
    List<dynamic> args = [entidadId, vigencia];

    if (estado != null) {
      query += ' AND estado = ?';
      args.add(estado.toString().split('.').last);
    }

    query += ' ORDER BY fecha_liquidacion DESC';

    final resultados = await db.rawQuery(query, args);

    return resultados.map((r) => LiquidacionPredial.fromJson(r)).toList();
  }

  /// Consulta predios activos de una entidad
  Future<List<Predio>> consultarPredios({required String entidadId}) async {
    final prediosResult = await db.query(
      'predios',
      where: 'entidad_id = ? AND activo = 1',
      whereArgs: [entidadId],
      orderBy: 'fecha_registro DESC',
    );

    return prediosResult.map((r) => Predio.fromJson(r)).toList();
  }

  /// Exporta el recibo / declaración oficial del impuesto predial unificado en formato plano
  Future<String> exportarDeclaracionPredialAPlano(String liquidacionId) async {
    final res = await db.query(
      'liquidaciones_prediales',
      where: 'id = ?',
      whereArgs: [liquidacionId],
    );
    if (res.isEmpty) throw Exception('Liquidación predial no encontrada');
    final liq = LiquidacionPredial.fromJson(res.first);

    final buffer = StringBuffer();
    buffer.writeln(
      'PREDIAL_HEADER|${liq.numeroLiquidacion}|${liq.entidadId}|VIGENCIA|${liq.vigencia}',
    );
    buffer.writeln(
      'PREDIO|${liq.numeroPredial}|AVALUO|${liq.avaluoCatastral.toMajorUnitsString()}',
    );
    buffer.writeln(
      'CONTRIBUYENTE|${liq.contribuyenteIdentificacion}|${liq.contribuyenteNombre}',
    );
    buffer.writeln(
      'LIQUIDACION|TARIFA|${liq.tarifa}|IMPUESTO_BASE|${liq.impuestoBase.toMajorUnitsString()}|DESCUENTO|${liq.descuentoProntoPago.toMajorUnitsString()}|TOTAL|${liq.totalPagar.toMajorUnitsString()}',
    );
    buffer.writeln(
      'ESTADO|${liq.estado.name}|VENCIMIENTO|${liq.fechaVencimiento.toIso8601String()}',
    );
    buffer.writeln('PREDIAL_FOOTER|DOCUMENTO_OFICIAL_COBRO');

    return buffer.toString();
  }

  String _generarNumeroSecuencial() {
    return DateTime.now().millisecondsSinceEpoch.toString().substring(8);
  }
}
