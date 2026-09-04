/// Modelo de Acta de Responsabilidad y Custodia de Bienes del Estado (NICSP 17)
/// Asignación y traspaso de cuentadantes de activos públicos
library;

enum EstadoActaResponsabilidad { pendienteFirma, activa, devuelta, trasladada }

class ActaResponsabilidad {
  final String id;
  final String entidadId;
  final String numeroActa; // Formato: ACTA-YYYY-NNNNNN
  final String activoId;
  final String funcionarioId;
  final String funcionarioNombre;
  final String funcionarioIdentificacion;
  final String dependencia;
  final String ubicacionFisica;
  final DateTime fechaAsignacion;
  final DateTime? fechaDevolucion;
  final DateTime? fechaEntrega;
  final String? firmadoPorFuncionario;
  final DateTime? fechaFirmaFuncionario;
  final String? firmadoPorAlmacen;
  final DateTime? fechaFirmaAlmacen;
  final String? hashActa;
  final String versionFormato;
  final EstadoActaResponsabilidad estadoActa;
  final String? observaciones;

  ActaResponsabilidad({
    required this.id,
    required this.entidadId,
    required this.numeroActa,
    required this.activoId,
    required this.funcionarioId,
    required this.funcionarioNombre,
    required this.funcionarioIdentificacion,
    required this.dependencia,
    required this.ubicacionFisica,
    required this.fechaAsignacion,
    this.fechaDevolucion,
    this.fechaEntrega,
    this.firmadoPorFuncionario,
    this.fechaFirmaFuncionario,
    this.firmadoPorAlmacen,
    this.fechaFirmaAlmacen,
    this.hashActa,
    this.versionFormato = 'CGN-GAD22-FOR02-local-v1',
    required this.estadoActa,
    this.observaciones,
  });

  factory ActaResponsabilidad.fromJson(Map<String, dynamic> json) {
    return ActaResponsabilidad(
      id: json['id'] as String,
      entidadId: json['entidad_id'] as String,
      numeroActa: json['numero_acta'] as String,
      activoId: json['activo_id'] as String,
      funcionarioId: json['funcionario_id'] as String,
      funcionarioNombre: json['funcionario_nombre'] as String,
      funcionarioIdentificacion: json['funcionario_identificacion'] as String,
      dependencia: json['dependencia'] as String,
      ubicacionFisica: json['ubicacion_fisica'] as String,
      fechaAsignacion: DateTime.parse(json['fecha_asignacion'] as String),
      fechaDevolucion: json['fecha_devolucion'] != null
          ? DateTime.parse(json['fecha_devolucion'] as String)
          : null,
      fechaEntrega: json['fecha_entrega'] != null
          ? DateTime.parse(json['fecha_entrega'] as String)
          : null,
      firmadoPorFuncionario: json['firmado_por_funcionario'] as String?,
      fechaFirmaFuncionario: json['fecha_firma_funcionario'] != null
          ? DateTime.parse(json['fecha_firma_funcionario'] as String)
          : null,
      firmadoPorAlmacen: json['firmado_por_almacen'] as String?,
      fechaFirmaAlmacen: json['fecha_firma_almacen'] != null
          ? DateTime.parse(json['fecha_firma_almacen'] as String)
          : null,
      hashActa: json['hash_acta'] as String?,
      versionFormato:
          json['version_formato'] as String? ?? 'CGN-GAD22-FOR02-local-v1',
      estadoActa: EstadoActaResponsabilidad.values.firstWhere(
        (e) => e.name == json['estado_acta'],
        orElse: () => EstadoActaResponsabilidad.activa,
      ),
      observaciones: json['observaciones'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entidad_id': entidadId,
      'numero_acta': numeroActa,
      'activo_id': activoId,
      'funcionario_id': funcionarioId,
      'funcionario_nombre': funcionarioNombre,
      'funcionario_identificacion': funcionarioIdentificacion,
      'dependencia': dependencia,
      'ubicacion_fisica': ubicacionFisica,
      'fecha_asignacion': fechaAsignacion.toIso8601String(),
      'fecha_devolucion': fechaDevolucion?.toIso8601String(),
      'fecha_entrega': fechaEntrega?.toIso8601String(),
      'firmado_por_funcionario': firmadoPorFuncionario,
      'fecha_firma_funcionario': fechaFirmaFuncionario?.toIso8601String(),
      'firmado_por_almacen': firmadoPorAlmacen,
      'fecha_firma_almacen': fechaFirmaAlmacen?.toIso8601String(),
      'hash_acta': hashActa,
      'version_formato': versionFormato,
      'estado_acta': estadoActa.name,
      'observaciones': observaciones,
    };
  }

  ActaResponsabilidad copyWith({
    DateTime? fechaDevolucion,
    DateTime? fechaEntrega,
    String? firmadoPorFuncionario,
    DateTime? fechaFirmaFuncionario,
    String? firmadoPorAlmacen,
    DateTime? fechaFirmaAlmacen,
    String? hashActa,
    EstadoActaResponsabilidad? estadoActa,
    String? observaciones,
  }) {
    return ActaResponsabilidad(
      id: id,
      entidadId: entidadId,
      numeroActa: numeroActa,
      activoId: activoId,
      funcionarioId: funcionarioId,
      funcionarioNombre: funcionarioNombre,
      funcionarioIdentificacion: funcionarioIdentificacion,
      dependencia: dependencia,
      ubicacionFisica: ubicacionFisica,
      fechaAsignacion: fechaAsignacion,
      fechaDevolucion: fechaDevolucion ?? this.fechaDevolucion,
      fechaEntrega: fechaEntrega ?? this.fechaEntrega,
      firmadoPorFuncionario:
          firmadoPorFuncionario ?? this.firmadoPorFuncionario,
      fechaFirmaFuncionario:
          fechaFirmaFuncionario ?? this.fechaFirmaFuncionario,
      firmadoPorAlmacen: firmadoPorAlmacen ?? this.firmadoPorAlmacen,
      fechaFirmaAlmacen: fechaFirmaAlmacen ?? this.fechaFirmaAlmacen,
      hashActa: hashActa ?? this.hashActa,
      versionFormato: versionFormato,
      estadoActa: estadoActa ?? this.estadoActa,
      observaciones: observaciones ?? this.observaciones,
    );
  }
}
