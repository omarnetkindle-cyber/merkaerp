/// Servicio de RIPS como soporte de FEV en salud.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

import '../../models/registro_auditoria.dart';
import '../../security/auditoria_service.dart';
import '../models/rips.dart';
import '../models/rips_fev.dart';

class RIPSService {
  RIPSService({required this.db, required this.auditoriaService});

  final Database db;
  final AuditoriaService auditoriaService;
  final Uuid _uuid = const Uuid();

  /// Conserva el registro clinico legado para consulta. No se exporta como
  /// RIPS-JSON porque no contiene todos los campos exigidos desde 2026.
  Future<RIPS> registrarRIPS({
    required String entidadId,
    required String usuarioId,
    required TipoRIPS tipoRIPS,
    required String codigoPrestador,
    required String nombrePrestador,
    required String numeroFactura,
    required DateTime fechaFactura,
    required DateTime fechaInicio,
    required DateTime fechaFin,
    required String codigoPaciente,
    required String nombrePaciente,
    required String tipoIdentificacion,
    required String numeroIdentificacion,
    required String codigoServicio,
    required String nombreServicio,
    required MoneyValue valorServicio,
    MoneyValue? valorCopago,
    MoneyValue? valorModera,
    String? diagnosticoPrincipal,
    String? diagnosticoRelacionado,
  }) async {
    final copago = valorCopago ?? publicMoneyZero();
    final modera = valorModera ?? publicMoneyZero();
    final rips = RIPS(
      id: _uuid.v4(),
      entidadId: entidadId,
      tipoRIPS: tipoRIPS,
      codigoPrestador: codigoPrestador,
      nombrePrestador: nombrePrestador,
      numeroFactura: numeroFactura,
      fechaFactura: fechaFactura,
      fechaInicio: fechaInicio,
      fechaFin: fechaFin,
      codigoPaciente: codigoPaciente,
      nombrePaciente: nombrePaciente,
      tipoIdentificacion: tipoIdentificacion,
      numeroIdentificacion: numeroIdentificacion,
      codigoServicio: codigoServicio,
      nombreServicio: nombreServicio,
      valorServicio: valorServicio,
      valorCopago: copago,
      valorModera: modera,
      valorNeto: valorServicio - copago - modera,
      diagnosticoPrincipal: diagnosticoPrincipal,
      diagnosticoRelacionado: diagnosticoRelacionado,
    );
    await db.insert('rips', rips.toJson());
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'salud',
      accion: 'registro_rips_legado',
      valorAnterior: const {},
      valorNuevo: {'rips_id': rips.id, 'numero_factura': numeroFactura},
      referenciaId: rips.id,
    );
    return rips;
  }

  /// Genera y conserva un RIPS-JSON para FEV, conforme a Res. 948/2026 y
  /// Documento Tecnico 1 v003. CUCON se persiste para el XML FEV (DT2), pero
  /// no se introduce artificialmente en el JSON RIPS.
  Future<String> generarRipsJson({
    required String entidadId,
    required String usuarioId,
    required RipsFevDocumento documento,
  }) async {
    final validacion = await validarRipsFev(documento);
    if (!(validacion['valido'] as bool)) {
      throw FormatException((validacion['errores'] as List<String>).join('; '));
    }
    final contenido = jsonEncode(documento.toJson());
    final id = _uuid.v4();
    await db.insert('rips_fev_documentos', {
      'id': id,
      'entidad_id': entidadId,
      'numero_factura': documento.numFactura,
      'num_documento_id_obligado': documento.numDocumentoIdObligado,
      'cucon': documento.cucon,
      'contenido_json': contenido,
      'estado_validacion_local': 'valido',
      'fecha_generacion': DateTime.now().toIso8601String(),
    });
    await auditoriaService.registrarEvento(
      entidadId: entidadId,
      usuarioId: usuarioId,
      tipoEvento: TipoEventoAuditoria.creacionRegistro,
      modulo: 'salud',
      accion: 'generacion_rips_json_948_2026',
      valorAnterior: const {},
      valorNuevo: {'rips_fev_id': id, 'numero_factura': documento.numFactura},
      referenciaId: id,
    );
    return contenido;
  }

  Future<Map<String, dynamic>> validarRipsFev(
    RipsFevDocumento documento,
  ) async {
    final errores = <String>[];
    if (documento.numDocumentoIdObligado.trim().isEmpty) {
      errores.add('numDocumentoIdObligado es obligatorio');
    }
    if (documento.numFactura.trim().isEmpty) {
      errores.add('numFactura es obligatorio');
    }
    if (documento.usuarios.isEmpty) {
      errores.add('usuarios debe contener al menos un usuario');
    }

    for (var indice = 0; indice < documento.usuarios.length; indice++) {
      final usuario = documento.usuarios[indice];
      const obligatorios = [
        'tipoDocumentoIdentificacion',
        'numDocumentoIdentificacion',
        'tipoUsuario',
        'fechaNacimiento',
        'codSexo',
        'codPaisResidencia',
        'codMunicipioResidencia',
        'codZonaTerritorialResidencia',
        'incapacidad',
        'consecutivo',
        'codPaisOrigen',
        'servicios',
      ];
      for (final campo in obligatorios) {
        if (usuario[campo] == null ||
            usuario[campo].toString().trim().isEmpty) {
          errores.add('usuarios[$indice].$campo es obligatorio');
        }
      }
      final servicios = usuario['servicios'];
      if (servicios is! Map<String, dynamic>) {
        errores.add('usuarios[$indice].servicios debe ser un objeto');
        continue;
      }
      const tiposPermitidos = {
        'consultas',
        'procedimientos',
        'urgencias',
        'hospitalizacion',
        'recienNacidos',
        'medicamentos',
        'otrosServicios',
      };
      if (servicios.keys.any((key) => !tiposPermitidos.contains(key))) {
        errores.add(
          'usuarios[$indice].servicios contiene un tipo no reconocido',
        );
      }
      if (servicios.values.whereType<List>().every((items) => items.isEmpty)) {
        errores.add(
          'usuarios[$indice].servicios no contiene atenciones facturadas',
        );
      }
      await _validarCodigosServicios(servicios, errores, indice);
    }
    return {'valido': errores.isEmpty, 'errores': errores};
  }

  Future<String> obtenerUltimoRipsJson({required String entidadId}) async {
    final documentos = await db.query(
      'rips_fev_documentos',
      where: 'entidad_id = ?',
      whereArgs: [entidadId],
      orderBy: 'fecha_generacion DESC',
      limit: 1,
    );
    if (documentos.isEmpty) {
      throw StateError(
        'No hay RIPS-JSON FEV validado. Registre el documento estructurado antes de exportarlo.',
      );
    }
    return documentos.first['contenido_json'] as String;
  }

  Future<void> _validarCodigosServicios(
    Map<String, dynamic> servicios,
    List<String> errores,
    int usuarioIndice,
  ) async {
    for (final entrada in servicios.entries) {
      final items = entrada.value;
      if (items is! List) continue;
      for (var indice = 0; indice < items.length; indice++) {
        if (items[indice] is! Map<String, dynamic>) {
          errores.add(
            'usuarios[$usuarioIndice].servicios.${entrada.key}[$indice] debe ser objeto',
          );
          continue;
        }
        final item = items[indice] as Map<String, dynamic>;
        final cups = entrada.key == 'consultas'
            ? item['codConsulta']
            : entrada.key == 'procedimientos'
            ? item['codProcedimiento']
            : null;
        if (cups != null) {
          final encontrado = await db.query(
            'catalogo_cups',
            where: 'codigo = ?',
            whereArgs: [cups],
          );
          if (encontrado.isEmpty) {
            errores.add(
              'CUPS $cups no existe en el catalogo local para ${entrada.key}',
            );
          }
        }
        for (final diagnostico in item.entries.where(
          (dato) => dato.key.startsWith('codDiagnostico'),
        )) {
          final codigo = diagnostico.value;
          if (codigo == null || codigo == '0') continue;
          final encontrado = await db.query(
            'catalogo_cie10',
            where: 'codigo = ?',
            whereArgs: [codigo],
          );
          if (encontrado.isEmpty && !await _existeCategoriaCie10(codigo)) {
            errores.add('CIE-10 $codigo no existe en el catalogo local');
          }
        }
      }
    }
  }

  Future<bool> _existeCategoriaCie10(Object codigo) async {
    final texto = codigo.toString().trim();
    if (texto.length != 3) return false;
    final encontrados = await db.query(
      'catalogo_cie10',
      where: 'codigo LIKE ?',
      whereArgs: ['$texto%'],
      limit: 1,
    );
    return encontrados.isNotEmpty;
  }

  Future<List<RIPS>> consultarRIPS({
    required String entidadId,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    TipoRIPS? tipoRIPS,
  }) async {
    var query = 'SELECT * FROM rips WHERE entidad_id = ?';
    final args = <dynamic>[entidadId];
    if (fechaDesde != null) {
      query += ' AND fecha_factura >= ?';
      args.add(fechaDesde.toIso8601String());
    }
    if (fechaHasta != null) {
      query += ' AND fecha_factura <= ?';
      args.add(fechaHasta.toIso8601String());
    }
    if (tipoRIPS != null) {
      query += ' AND tipo_rips = ?';
      args.add(tipoRIPS.name);
    }
    final resultados = await db.rawQuery(
      '$query ORDER BY fecha_factura DESC',
      args,
    );
    return resultados.map((resultado) => RIPS.fromJson(resultado)).toList();
  }
}
