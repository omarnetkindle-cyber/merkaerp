/// Servicio PILA (Planilla Integrada de Liquidación de Aportes)
/// Integración real con operador de información PILA
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';
import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../../../integrations/application/institutional_connector_service.dart';
import '../../../integrations/application/integration_settings_service.dart';
import '../../../integrations/domain/integration_definition.dart';

class PILAService {
  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();
  final InstitutionalConnectorService _connector =
      InstitutionalConnectorService.instance;
  final IntegrationSettingsService _integrationSettings =
      IntegrationSettingsService.instance;

  PILAService({
    required this.db,
    required this.auditoriaService,
  });

  /// Genera reporte PILA para un periodo
  Future<Map<String, dynamic>> generarReportePILA({
    required String entidadId,
    required String usuarioId,
    required String periodo,
  }) async {
    final liquidaciones = await db.query(
      'liquidaciones_nomina',
      where: 'entidad_id = ? AND periodo = ?',
      whereArgs: [entidadId, periodo],
    );

    if (liquidaciones.isEmpty) {
      throw Exception('No hay liquidaciones para el periodo');
    }

    final reporteId = _uuid.v4();
    var totalSalud = publicMoneyZero();
    var totalPension = publicMoneyZero();
    var totalFondoSolidaridad = publicMoneyZero();
    var totalRiesgos = publicMoneyZero();
    var totalCaja = publicMoneyZero();
    var totalSena = publicMoneyZero();
    var totalICBF = publicMoneyZero();
    for (final liquidacion in liquidaciones) {
      totalSalud += publicMoneyFromSql(liquidacion['salud']);
      totalPension += publicMoneyFromSql(liquidacion['pension']);
      totalFondoSolidaridad += publicMoneyFromSql(
        liquidacion['fondo_solidaridad'],
      );
      totalRiesgos += publicMoneyFromSql(liquidacion['riesgos_laborales']);
      totalCaja += publicMoneyFromSql(liquidacion['caja_compensacion']);
      totalSena += publicMoneyFromSql(liquidacion['sena']);
      totalICBF += publicMoneyFromSql(liquidacion['icbf']);
    }

    final reporte = {
      'reporte_id': reporteId,
      'entidad_id': entidadId,
      'periodo': periodo,
      'fecha_generacion': DateTime.now().toIso8601String(),
      'total_empleados': liquidaciones.length,
      'total_salud': publicMoneyForDisplay(totalSalud),
      'total_pension': publicMoneyForDisplay(totalPension),
      'total_fondo_solidaridad': publicMoneyForDisplay(totalFondoSolidaridad),
      'total_riesgos_laborales': publicMoneyForDisplay(totalRiesgos),
      'total_caja_compensacion': publicMoneyForDisplay(totalCaja),
      'total_sena': publicMoneyForDisplay(totalSena),
      'total_icbf': publicMoneyForDisplay(totalICBF),
      'gran_total': publicMoneyForDisplay(
        totalSalud +
            totalPension +
            totalFondoSolidaridad +
            totalRiesgos +
            totalCaja +
            totalSena +
            totalICBF,
      ),
    };

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'nomina',
      accion: 'generacion_reporte_pila',
      valorAnterior: {},
      valorNuevo: reporte,
      referenciaId: reporteId,
    );

    return reporte;
  }

  /// Envía reporte PILA al operador de información
  Future<String> enviarReportePILA({
    required String entidadId,
    required String usuarioId,
    required String periodo,
    required String nitEntidad,
  }) async {
    final liquidaciones = await db.query(
      'liquidaciones_nomina',
      where: 'entidad_id = ? AND periodo = ?',
      whereArgs: [entidadId, periodo],
    );

    if (liquidaciones.isEmpty) {
      throw Exception('No hay liquidaciones para el periodo');
    }

    try {
      // Preparar payload para PILA
      final payload = {
        'tipo_registro': '1',
        'nit_entidad': nitEntidad,
        'periodo': periodo,
        'fecha_generacion': DateTime.now().toIso8601String(),
        'total_registros': liquidaciones.length,
        'detalles': liquidaciones
            .map(
              (liq) => {
                'identificacion': liq['empleado_identificacion'],
                'nombre': liq['empleado_nombre'],
                'salud': publicMoneyForDisplay(
                  publicMoneyFromSql(liq['salud']),
                ),
                'pension': publicMoneyForDisplay(
                  publicMoneyFromSql(liq['pension']),
                ),
                'fondo_solidaridad': publicMoneyForDisplay(
                  publicMoneyFromSql(liq['fondo_solidaridad']),
                ),
                'riesgos_laborales': publicMoneyForDisplay(
                  publicMoneyFromSql(liq['riesgos_laborales']),
                ),
                'caja_compensacion': publicMoneyForDisplay(
                  publicMoneyFromSql(liq['caja_compensacion']),
                ),
                'sena': publicMoneyForDisplay(publicMoneyFromSql(liq['sena'])),
                'icbf': publicMoneyForDisplay(publicMoneyFromSql(liq['icbf'])),
              },
            )
            .toList(),
      };

      final response = await _connector.postJson(
        'pila_operator',
        payload: payload,
        pathField: 'submission_path',
      );
      if (!response.ok) {
        throw Exception(response.message);
      }
      final data = response.data;
      final responseMap = data is Map
          ? data.map((key, value) => MapEntry(key.toString(), value))
          : <String, Object?>{};
      final pilaId = (responseMap['pila_id'] ??
              responseMap['id'] ??
              responseMap['reference'] ??
              responseMap['referencia'])
          ?.toString()
          .trim();
      if (pilaId == null || pilaId.isEmpty) {
        throw Exception(
          'El operador aceptó la transmisión pero no devolvió un identificador verificable. '
          'Revisa el contrato técnico configurado en Integraciones.',
        );
      }

      await auditoriaService.registrarEvento(
        entidadId: entidadId,
        usuarioId: usuarioId,
        tipoEvento: TipoEventoAuditoria.modificacionRegistro,
        modulo: 'nomina',
        accion: 'envio_reporte_pila',
        valorAnterior: {'periodo': periodo},
        valorNuevo: {'pila_id': pilaId, 'respuesta_api': response.data},
      );

      return pilaId;
    } catch (e) {
      throw Exception('No fue posible transmitir PILA: $e');
    }
  }

  /// Recibe confirmación de PILA
  Future<Map<String, dynamic>> recibirConfirmacionPILA({
    required String pilaId,
  }) async {
    try {
      final definition = IntegrationRegistry.byKey('pila_operator');
      if (!await _integrationSettings.isConfigured(definition.key)) {
        throw Exception('PILA / operador de información no está configurado.');
      }
      final values = await _integrationSettings.loadValues(definition);
      final template = (values['confirmation_path'] ?? '').trim();
      if (!template.contains('{id}')) {
        throw Exception('La ruta de confirmación debe incluir {id}.');
      }
      final path = template.replaceAll('{id}', Uri.encodeComponent(pilaId));
      final response = await _connector.getPath(definition.key, path: path);
      if (!response.ok) throw Exception(response.message);
      if (response.data is Map) {
        return (response.data as Map)
            .map((key, value) => MapEntry(key.toString(), value));
      }
      return {'raw_response': response.data};
    } catch (e) {
      throw Exception('No fue posible consultar la confirmación PILA: $e');
    }
  }

  /// Asocia PILA a liquidaciones
  Future<void> asociarPILA({
    required String entidadId,
    required String usuarioId,
    required List<String> liquidacionIds,
    required String pilaId,
  }) async {
    for (final liquidacionId in liquidacionIds) {
      await db.update(
        'liquidaciones_nomina',
        {'pila_id': pilaId},
        where: 'id = ?',
        whereArgs: [liquidacionId],
      );
    }

    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.modificacionRegistro,
      modulo: 'nomina',
      accion: 'asociacion_pila',
      valorAnterior: {},
      valorNuevo: {'pila_id': pilaId, 'cantidad': liquidacionIds.length},
    );
  }

  /// Exporta formato plano para PILA
  Future<String> exportarFormatoPlano({
    required String entidadId,
    required String periodo,
  }) async {
    final liquidaciones = await db.query(
      'liquidaciones_nomina',
      where: 'entidad_id = ? AND periodo = ?',
      whereArgs: [entidadId, periodo],
    );

    final buffer = StringBuffer();
    buffer.writeln('TIPO_REGISTRO;1');
    buffer.writeln('ENTIDAD;$entidadId');
    buffer.writeln('PERIODO;$periodo');
    buffer.writeln('FECHA_GENERACION;${DateTime.now().toIso8601String()}');
    buffer.writeln('TOTAL_REGISTROS;${liquidaciones.length}');

    for (final liq in liquidaciones) {
      buffer.writeln('DETALLE');
      buffer.writeln('IDENTIFICACION;${liq['empleado_identificacion']}');
      buffer.writeln('NOMBRE;${liq['empleado_nombre']}');
      buffer.writeln(
        'SALUD;${publicMoneyForDisplay(publicMoneyFromSql(liq['salud']))}',
      );
      buffer.writeln(
        'PENSION;${publicMoneyForDisplay(publicMoneyFromSql(liq['pension']))}',
      );
      buffer.writeln(
        'FONDO_SOLIDARIDAD;${publicMoneyForDisplay(publicMoneyFromSql(liq['fondo_solidaridad']))}',
      );
      buffer.writeln(
        'RIESGOS_LABORALES;${publicMoneyForDisplay(publicMoneyFromSql(liq['riesgos_laborales']))}',
      );
      buffer.writeln(
        'CAJA_COMPENSACION;${publicMoneyForDisplay(publicMoneyFromSql(liq['caja_compensacion']))}',
      );
      buffer.writeln(
        'SENA;${publicMoneyForDisplay(publicMoneyFromSql(liq['sena']))}',
      );
      buffer.writeln(
        'ICBF;${publicMoneyForDisplay(publicMoneyFromSql(liq['icbf']))}',
      );
    }

    return buffer.toString();
  }
}
