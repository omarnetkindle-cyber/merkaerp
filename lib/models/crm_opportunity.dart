enum EtapaOportunidad {
  prospecto,
  calificado,
  cotizacionEnviada,
  negociacion,
  ganado,
  perdido,
}

enum PrioridadOportunidad { baja, media, alta }

class CrmOpportunity {
  const CrmOpportunity({
    required this.id,
    required this.clientId,
    required this.clienteNombre,
    required this.titulo,
    required this.etapa,
    required this.valorEstimado,
    required this.probabilidad,
    required this.fechaCierreEstimada,
    required this.creadoEn,
    this.vendedorId,
    this.vendedorNombre,
    this.descripcion,
    this.prioridad = PrioridadOportunidad.media,
    this.motivoPerdida,
    this.ultimaActividad,
    this.actualizadoEn,
  });

  final int id;
  final int clientId;
  final String clienteNombre;
  final String titulo;
  final EtapaOportunidad etapa;
  final double valorEstimado;
  final int probabilidad; // 0-100
  final DateTime fechaCierreEstimada;
  final DateTime creadoEn;
  final int? vendedorId;
  final String? vendedorNombre;
  final String? descripcion;
  final PrioridadOportunidad prioridad;
  final String? motivoPerdida;
  final DateTime? ultimaActividad;
  final DateTime? actualizadoEn;

  bool get estaGanada => etapa == EtapaOportunidad.ganado;
  bool get estaPerdida => etapa == EtapaOportunidad.perdido;
  bool get estaActiva => !estaGanada && !estaPerdida;
  bool get estaVencida => DateTime.now().isAfter(fechaCierreEstimada) && estaActiva;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clientId,
      'cliente_nombre': clienteNombre,
      'titulo': titulo,
      'etapa': etapa.name,
      'valor_estimado': valorEstimado,
      'probabilidad': probabilidad,
      'fecha_cierre_estimada': fechaCierreEstimada.toIso8601String(),
      'creado_en': creadoEn.toIso8601String(),
      'vendedor_id': vendedorId,
      'vendedor_nombre': vendedorNombre,
      'descripcion': descripcion,
      'prioridad': prioridad.name,
      'motivo_perdida': motivoPerdida,
      'ultima_actividad': ultimaActividad?.toIso8601String(),
      'actualizado_en': actualizadoEn?.toIso8601String(),
    };
  }

  static CrmOpportunity fromMap(Map<String, dynamic> map) {
    return CrmOpportunity(
      id: map['id'] as int,
      clientId: map['cliente_id'] as int,
      clienteNombre: map['cliente_nombre'] as String,
      titulo: map['titulo'] as String,
      etapa: EtapaOportunidad.values.firstWhere(
        (e) => e.name == map['etapa'],
        orElse: () => EtapaOportunidad.prospecto,
      ),
      valorEstimado: (map['valor_estimado'] as num).toDouble(),
      probabilidad: map['probabilidad'] as int? ?? 50,
      fechaCierreEstimada: DateTime.parse(map['fecha_cierre_estimada'] as String),
      creadoEn: DateTime.parse(map['creado_en'] as String),
      vendedorId: map['vendedor_id'] as int?,
      vendedorNombre: map['vendedor_nombre'] as String?,
      descripcion: map['descripcion'] as String?,
      prioridad: PrioridadOportunidad.values.firstWhere(
        (e) => e.name == map['prioridad'],
        orElse: () => PrioridadOportunidad.media,
      ),
      motivoPerdida: map['motivo_perdida'] as String?,
      ultimaActividad: map['ultima_actividad'] != null
          ? DateTime.parse(map['ultima_actividad'] as String)
          : null,
      actualizadoEn: map['actualizado_en'] != null
          ? DateTime.parse(map['actualizado_en'] as String)
          : null,
    );
  }

  CrmOpportunity copyWith({
    EtapaOportunidad? etapa,
    int? probabilidad,
    DateTime? fechaCierreEstimada,
    String? motivoPerdida,
    DateTime? ultimaActividad,
    DateTime? actualizadoEn,
  }) {
    return CrmOpportunity(
      id: id,
      clientId: clientId,
      clienteNombre: clienteNombre,
      titulo: titulo,
      etapa: etapa ?? this.etapa,
      valorEstimado: valorEstimado,
      probabilidad: probabilidad ?? this.probabilidad,
      fechaCierreEstimada: fechaCierreEstimada ?? this.fechaCierreEstimada,
      creadoEn: creadoEn,
      vendedorId: vendedorId,
      vendedorNombre: vendedorNombre,
      descripcion: descripcion,
      prioridad: prioridad,
      motivoPerdida: motivoPerdida ?? this.motivoPerdida,
      ultimaActividad: ultimaActividad ?? this.ultimaActividad,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
    );
  }

  static int calcularProbabilidadPorEtapa(EtapaOportunidad etapa) {
    switch (etapa) {
      case EtapaOportunidad.prospecto:
        return 10;
      case EtapaOportunidad.calificado:
        return 30;
      case EtapaOportunidad.cotizacionEnviada:
        return 50;
      case EtapaOportunidad.negociacion:
        return 70;
      case EtapaOportunidad.ganado:
        return 100;
      case EtapaOportunidad.perdido:
        return 0;
    }
  }
}

class CrmActividad {
  const CrmActividad({
    required this.id,
    required this.oportunidadId,
    required this.tipo,
    required this.descripcion,
    required this.fecha,
    this.usuarioId,
    this.usuarioNombre,
    this.resultado,
  });

  final int id;
  final int oportunidadId;
  final String tipo; // llamada, correo, reunion, nota
  final String descripcion;
  final DateTime fecha;
  final int? usuarioId;
  final String? usuarioNombre;
  final String? resultado;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'oportunidad_id': oportunidadId,
      'tipo': tipo,
      'descripcion': descripcion,
      'fecha': fecha.toIso8601String(),
      'usuario_id': usuarioId,
      'usuario_nombre': usuarioNombre,
      'resultado': resultado,
    };
  }

  static CrmActividad fromMap(Map<String, dynamic> map) {
    return CrmActividad(
      id: map['id'] as int,
      oportunidadId: map['oportunidad_id'] as int,
      tipo: map['tipo'] as String,
      descripcion: map['descripcion'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      usuarioId: map['usuario_id'] as int?,
      usuarioNombre: map['usuario_nombre'] as String?,
      resultado: map['resultado'] as String?,
    );
  }
}
