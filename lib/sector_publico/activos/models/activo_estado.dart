/// Modelo de Activo del Estado
/// NICSP 17 - Propiedades, Planta y Equipo
library;

import '../../../core/currency/money_value.dart';
import '../../../core/currency/public_sector_money.dart';

enum TipoActivo {
  terreno,
  edificio,
  maquinaria,
  equipo,
  vehiculo,
  mobiliario,
  equipoComputo,
  intangible,
  otro,
}

enum EstadoActivo {
  nuevo,
  bueno,
  regular,
  malo,
  obsoleto,
  dadoDeBaja,
}

class ActivoEstado {
  final String id;
  final String entidadId;
  final String numeroInventario;
  final String nombreActivo;
  final TipoActivo tipoActivo;
  final String marca;
  final String modelo;
  final String serie;
  final MoneyValue valorAdquisicion;
  final MoneyValue valorLibros;
  final MoneyValue valorNeto;
  final DateTime fechaAdquisicion;
  final DateTime fechaPuestaEnMarcha;
  final int vidaUtilAnios;
  final MoneyValue valorResidual;
  final MoneyValue depreciacionAcumulada;
  final EstadoActivo estado;
  final String? ubicacion;
  final String? responsable;
  final String? observaciones;

  ActivoEstado({
    required this.id,
    required this.entidadId,
    required this.numeroInventario,
    required this.nombreActivo,
    required this.tipoActivo,
    required this.marca,
    required this.modelo,
    required this.serie,
    required this.valorAdquisicion,
    required this.valorLibros,
    required this.valorNeto,
    required this.fechaAdquisicion,
    required this.fechaPuestaEnMarcha,
    required this.vidaUtilAnios,
    required this.valorResidual,
    required this.depreciacionAcumulada,
    required this.estado,
    this.ubicacion,
    this.responsable,
    this.observaciones,
  });

  factory ActivoEstado.fromJson(Map<String, dynamic> json) {
    return ActivoEstado(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroInventario: json['numero_inventario'] as String,
      nombreActivo: json['nombre_activo'] as String,
      tipoActivo: TipoActivo.values.firstWhere(
        (e) => e.toString() == 'TipoActivo.${json['tipo_activo']}',
      ),
      marca: json['marca'] as String,
      modelo: json['modelo'] as String,
      serie: json['serie'] as String,
      valorAdquisicion: publicMoneyFromSql(json['valor_adquisicion']),
      valorLibros: publicMoneyFromSql(json['valor_libros']),
      valorNeto: publicMoneyFromSql(json['valor_neto']),
      fechaAdquisicion: DateTime.parse(json['fecha_adquisicion'] as String),
      fechaPuestaEnMarcha: DateTime.parse(json['fecha_puesta_en_marcha'] as String),
      vidaUtilAnios: json['vida_util_anios'] as int,
      valorResidual: publicMoneyFromSql(json['valor_residual']),
      depreciacionAcumulada: publicMoneyFromSql(json['depreciacion_acumulada']),
      estado: EstadoActivo.values.firstWhere(
        (e) => e.toString() == 'EstadoActivo.${json['estado']}',
      ),
      ubicacion: json['ubicacion'] as String?,
      responsable: json['responsable'] as String?,
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_inventario': numeroInventario,
      'nombre_activo': nombreActivo,
      'tipo_activo': tipoActivo.toString().split('.').last,
      'marca': marca,
      'modelo': modelo,
      'serie': serie,
      'valor_adquisicion': valorAdquisicion.toSql(),
      'valor_libros': valorLibros.toSql(),
      'valor_neto': valorNeto.toSql(),
      'fecha_adquisicion': fechaAdquisicion.toIso8601String(),
      'fecha_puesta_en_marcha': fechaPuestaEnMarcha.toIso8601String(),
      'vida_util_anios': vidaUtilAnios,
      'valor_residual': valorResidual.toSql(),
      'depreciacion_acumulada': depreciacionAcumulada.toSql(),
      'estado': estado.toString().split('.').last,
      'ubicacion': ubicacion,
      'responsable': responsable,
      'observaciones': observaciones,
    };
  }

  /// Calcula la depreciación anual según método línea recta (NICSP 17)
  MoneyValue calcularDepreciacionAnual() {
    return (valorAdquisicion - valorResidual) / vidaUtilAnios;
  }

  /// Calcula la depreciación acumulada hasta la fecha actual
  MoneyValue calcularDepreciacionAcumuladaActual() {
    final hoy = DateTime.now();
    final diasUso = hoy.difference(fechaPuestaEnMarcha).inDays;
    return calcularDepreciacionAnual().multiplyRatio(
      numerator: diasUso,
      denominator: 365,
    );
  }

  /// Calcula el valor neto actual
  MoneyValue calcularValorNetoActual() {
    final depreciacionActual = calcularDepreciacionAcumuladaActual();
    return valorAdquisicion - depreciacionActual;
  }

  /// Verifica si está totalmente depreciado
  bool estaTotalmenteDepreciado() {
    return calcularDepreciacionAcumuladaActual() >=
        (valorAdquisicion - valorResidual);
  }

  ActivoEstado copyWith({
    String? id,
    String? entidadId,
    String? numeroInventario,
    String? nombreActivo,
    TipoActivo? tipoActivo,
    String? marca,
    String? modelo,
    String? serie,
    MoneyValue? valorAdquisicion,
    MoneyValue? valorLibros,
    MoneyValue? valorNeto,
    DateTime? fechaAdquisicion,
    DateTime? fechaPuestaEnMarcha,
    int? vidaUtilAnios,
    MoneyValue? valorResidual,
    MoneyValue? depreciacionAcumulada,
    EstadoActivo? estado,
    String? ubicacion,
    String? responsable,
    String? observaciones,
  }) {
    return ActivoEstado(
      id: id ?? this.id,
      entidadId: entidadId ?? this.entidadId,
      numeroInventario: numeroInventario ?? this.numeroInventario,
      nombreActivo: nombreActivo ?? this.nombreActivo,
      tipoActivo: tipoActivo ?? this.tipoActivo,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      serie: serie ?? this.serie,
      valorAdquisicion: valorAdquisicion ?? this.valorAdquisicion,
      valorLibros: valorLibros ?? this.valorLibros,
      valorNeto: valorNeto ?? this.valorNeto,
      fechaAdquisicion: fechaAdquisicion ?? this.fechaAdquisicion,
      fechaPuestaEnMarcha: fechaPuestaEnMarcha ?? this.fechaPuestaEnMarcha,
      vidaUtilAnios: vidaUtilAnios ?? this.vidaUtilAnios,
      valorResidual: valorResidual ?? this.valorResidual,
      depreciacionAcumulada: depreciacionAcumulada ?? this.depreciacionAcumulada,
      estado: estado ?? this.estado,
      ubicacion: ubicacion ?? this.ubicacion,
      responsable: responsable ?? this.responsable,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
