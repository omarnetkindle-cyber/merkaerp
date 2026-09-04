/// Modelo de Predio para Impuesto Predial
/// Ley 44 de 1990 + Ley 1995 de 2019 (Catastro Multipropósito)
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum UsoSuelo {
  residencial,
  comercial,
  industrial,
  agropecuario,
  institucional,
  otros,
}

enum Estrato { uno, dos, tres, cuatro, cinco, seis }

enum Zona { urbana, rural }

class Predio {
  final String id;
  final String entidadId;
  final String numeroPredial; // Número predial IGAC
  final String? numeroMatricula;
  final String direccion;
  final String barrio;
  final String municipio;
  final String departamento;
  final double area; // m²
  final MoneyValue avaluoCatastral; // Valor avalúo IGAC
  final MoneyValue avaluoAnterior; // Avalúo año anterior
  final UsoSuelo usoSuelo;
  final Estrato estrato;
  final Zona zona;
  final String propietarioId;
  final String propietarioNombre;
  final String propietarioIdentificacion;
  final String? poseedorNombre;
  final String? poseedorIdentificacion;
  final DateTime fechaRegistro;
  final bool activo;
  final bool exento; // Exento según Ley 44/1990
  final String? motivoExencion;
  final String? observaciones;

  Predio({
    required this.id,
    required this.entidadId,
    required this.numeroPredial,
    this.numeroMatricula,
    required this.direccion,
    required this.barrio,
    required this.municipio,
    required this.departamento,
    required this.area,
    required this.avaluoCatastral,
    required this.avaluoAnterior,
    required this.usoSuelo,
    required this.estrato,
    required this.zona,
    required this.propietarioId,
    required this.propietarioNombre,
    required this.propietarioIdentificacion,
    this.poseedorNombre,
    this.poseedorIdentificacion,
    required this.fechaRegistro,
    required this.activo,
    required this.exento,
    this.motivoExencion,
    this.observaciones,
  });

  factory Predio.fromJson(Map<String, dynamic> json) {
    return Predio(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroPredial: json['numero_predial'] as String,
      numeroMatricula: json['numero_matricula'] as String?,
      direccion: json['direccion'] as String,
      barrio: json['barrio'] as String,
      municipio: json['municipio'] as String,
      departamento: json['departamento'] as String,
      area: (json['area'] as num).toDouble(),
      avaluoCatastral: publicMoneyFromSql(json['avaluo_catastral']),
      avaluoAnterior: publicMoneyFromSql(json['avaluo_anterior']),
      usoSuelo: UsoSuelo.values.firstWhere(
        (e) => e.toString() == 'UsoSuelo.${json['uso_suelo']}',
      ),
      estrato: Estrato.values.firstWhere(
        (e) => e.toString() == 'Estrato.${json['estrato']}',
      ),
      zona: Zona.values.firstWhere(
        (e) => e.toString() == 'Zona.${json['zona']}',
      ),
      propietarioId: json['propietario_id'] as String,
      propietarioNombre: json['propietario_nombre'] as String,
      propietarioIdentificacion: json['propietario_identificacion'] as String,
      poseedorNombre: json['poseedor_nombre'] as String?,
      poseedorIdentificacion: json['poseedor_identificacion'] as String?,
      fechaRegistro: DateTime.parse(json['fecha_registro'] as String),
      activo: _asBool(json['activo']),
      exento: _asBool(json['exento']),
      motivoExencion: json['motivo_exencion'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return false;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_predial': numeroPredial,
      'numero_matricula': numeroMatricula,
      'direccion': direccion,
      'barrio': barrio,
      'municipio': municipio,
      'departamento': departamento,
      'area': area,
      'avaluo_catastral': avaluoCatastral.toSql(),
      'avaluo_anterior': avaluoAnterior.toSql(),
      'uso_suelo': usoSuelo.toString().split('.').last,
      'estrato': estrato.toString().split('.').last,
      'zona': zona.toString().split('.').last,
      'propietario_id': propietarioId,
      'propietario_nombre': propietarioNombre,
      'propietario_identificacion': propietarioIdentificacion,
      'poseedor_nombre': poseedorNombre,
      'poseedor_identificacion': poseedorIdentificacion,
      'fecha_registro': fechaRegistro.toIso8601String(),
      'activo': activo,
      'exento': exento,
      'motivo_exencion': motivoExencion,
      'observaciones': observaciones,
    };
  }

  /// Verifica si el incremento del avalúo cumple con los topes legales
  /// Ley 44/1990 Art. 6 + Ley 1995/2019 Art. 19
  bool cumpleTopeIncremento(double ipcAnual) {
    final incremento =
        ((avaluoCatastral.minorUnits - avaluoAnterior.minorUnits) /
            avaluoAnterior.minorUnits) *
        100;

    // Estratos 1-2 hasta 135 SMMLV: tope = IPC
    if ((estrato == Estrato.uno || estrato == Estrato.dos) &&
        avaluoAnterior <= publicMoneyFromMajor('${135 * 908526}')) {
      return incremento <= ipcAnual;
    }

    // Predios rurales ≥100 ha: tope = 2×año anterior
    if (zona == Zona.rural && area >= 100000) {
      return avaluoCatastral <= (avaluoAnterior * 2);
    }

    // General: tope 50%
    return incremento <= 50;
  }

  /// Obtiene la tarifa predial según uso de suelo y estrato
  double obtenerTarifaPredial(Map<String, double> tarifasMunicipales) {
    if (exento) return 0;

    final clave =
        '${usoSuelo.toString().split('.').last}_${estrato.toString().split('.').last}';
    return tarifasMunicipales[clave] ?? 5.0; // Tarifa por defecto 5‰
  }

  Predio copyWith({
    String? id,
    String? entidadId,
    String? numeroPredial,
    String? numeroMatricula,
    String? direccion,
    String? barrio,
    String? municipio,
    String? departamento,
    double? area,
    MoneyValue? avaluoCatastral,
    MoneyValue? avaluoAnterior,
    UsoSuelo? usoSuelo,
    Estrato? estrato,
    Zona? zona,
    String? propietarioId,
    String? propietarioNombre,
    String? propietarioIdentificacion,
    String? poseedorNombre,
    String? poseedorIdentificacion,
    DateTime? fechaRegistro,
    bool? activo,
    bool? exento,
    String? motivoExencion,
    String? observaciones,
  }) {
    return Predio(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroPredial: numeroPredial ?? this.numeroPredial,
      numeroMatricula: numeroMatricula ?? this.numeroMatricula,
      direccion: direccion ?? this.direccion,
      barrio: barrio ?? this.barrio,
      municipio: municipio ?? this.municipio,
      departamento: departamento ?? this.departamento,
      area: area ?? this.area,
      avaluoCatastral: avaluoCatastral ?? this.avaluoCatastral,
      avaluoAnterior: avaluoAnterior ?? this.avaluoAnterior,
      usoSuelo: usoSuelo ?? this.usoSuelo,
      estrato: estrato ?? this.estrato,
      zona: zona ?? this.zona,
      propietarioId: propietarioId ?? this.propietarioId,
      propietarioNombre: propietarioNombre ?? this.propietarioNombre,
      propietarioIdentificacion:
          propietarioIdentificacion ?? this.propietarioIdentificacion,
      poseedorNombre: poseedorNombre ?? this.poseedorNombre,
      poseedorIdentificacion:
          poseedorIdentificacion ?? this.poseedorIdentificacion,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
      activo: activo ?? this.activo,
      exento: exento ?? this.exento,
      motivoExencion: motivoExencion ?? this.motivoExencion,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
