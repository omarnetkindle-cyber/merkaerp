/// Servicio de roles y permisos con segregación de funciones dura
/// Implementa las reglas no negociables: un tesorero no puede aprobar su propio pago
library;

import 'package:sqflite/sqflite.dart';

enum RolSectorPublico {
  alcaldeRepresentanteLegal,
  secretarioHacienda,
  // Ley 909 de 2004, art. 15: la gestion de personal recae en la unidad
  // competente; su asignacion concreta se sujeta al manual de cada entidad.
  secretarioGeneral,
  tesorero,
  contador,
  jefeRentas,
  jefeControlInterno,
  jefePresupuesto,
  ordenadorGasto,
  jefePlaneacion,
  secretarioSalud, // Para hospitales
  rector, // Para establecimientos educativos
}

enum Permiso {
  // Presupuesto
  expedirCDP,
  modificarCDP,
  expedirRP,
  modificarRP,
  registrarObligacion,
  aprobarPago,
  ejecutarPago,
  modificarPAC,
  registrarAutorizacionVigenciaFutura,

  // Contabilidad
  crearAsientoContable,
  reversarAsiento,
  cerrarVigencia,
  consultarEstadosFinancieros,
  aprobarConciliacionReciproca,

  // Nómina
  liquidarNomina,
  aprobarNomina,
  pagarNomina,
  reliquidarNomina,

  // Rentas
  liquidarTributo,
  cobrarTributo,
  iniciarCobroCoactivo,
  condonarTributo,

  // Contratación
  iniciarProcesoContratacion,
  adjudicarContrato,
  firmarContrato,
  liquidarContrato,
  supervisarContrato,

  // Planeación
  crearProyecto,
  modificarProyecto,
  aprobarProyecto,
  vincularProyectoPresupuesto,

  // Seguridad
  gestionarUsuarios,
  asignarRoles,
  consultarAuditoria,

  // Gestión documental / SGDEA
  consultarGestionDocumental,
  radicarDocumentos,
  tramitarDocumentos,
  administrarArchivo,
  administrarInstrumentosArchivisticos,
  administrarGestionDocumental,

  // General
  configurarEntidad,
  consultarTodo,
  exportarDatos,
}

class RolesPermisosService {
  /// Define qué roles tienen qué permisos
  static Map<RolSectorPublico, Set<Permiso>> get permisosPorRol => {
    RolSectorPublico.alcaldeRepresentanteLegal: {
      Permiso.configurarEntidad,
      Permiso.consultarTodo,
      Permiso.aprobarPago,
      Permiso.firmarContrato,
      Permiso.liquidarContrato,
      Permiso.aprobarProyecto,
      Permiso.registrarAutorizacionVigenciaFutura,
      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.secretarioHacienda: {
      Permiso.configurarEntidad,
      Permiso.modificarCDP,
      Permiso.modificarPAC,
      Permiso.aprobarPago,
      Permiso.consultarEstadosFinancieros,
      Permiso.consultarAuditoria,
      Permiso.consultarTodo,
      Permiso.registrarAutorizacionVigenciaFutura,
      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    // Rol administrativo transversal. No recibe facultades fiscales u operativas.
    RolSectorPublico.secretarioGeneral: {
      Permiso.gestionarUsuarios,
      Permiso.asignarRoles,
      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
      Permiso.administrarArchivo,
      Permiso.administrarInstrumentosArchivisticos,
      Permiso.administrarGestionDocumental,
    },
    RolSectorPublico.tesorero: {
      Permiso.ejecutarPago,
      Permiso.modificarPAC,
      Permiso.consultarEstadosFinancieros,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.contador: {
      Permiso.crearAsientoContable,
      Permiso.reversarAsiento,
      Permiso.cerrarVigencia,
      Permiso.consultarEstadosFinancieros,
      Permiso.aprobarConciliacionReciproca,
      Permiso.liquidarNomina,
      Permiso.reliquidarNomina,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.jefeRentas: {
      Permiso.liquidarTributo,
      Permiso.cobrarTributo,
      Permiso.iniciarCobroCoactivo,
      Permiso.condonarTributo,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.jefeControlInterno: {
      Permiso.consultarAuditoria,
      Permiso.consultarTodo,
      Permiso.exportarDatos,

      Permiso.consultarGestionDocumental,
    },
    // Decreto 568 de 1996, art. 19: expide CDP o quien haga sus veces.
    RolSectorPublico.jefePresupuesto: {
      Permiso.expedirCDP,
      Permiso.expedirRP,
      Permiso.registrarAutorizacionVigenciaFutura,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.ordenadorGasto: {
      Permiso.registrarObligacion,
      Permiso.expedirRP,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.jefePlaneacion: {
      Permiso.crearProyecto,
      Permiso.modificarProyecto,
      Permiso.aprobarProyecto,
      Permiso.vincularProyectoPresupuesto,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.secretarioSalud: {
      Permiso.expedirCDP,
      Permiso.expedirRP,
      Permiso.registrarObligacion,
      Permiso.aprobarPago,
      Permiso.firmarContrato,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
    RolSectorPublico.rector: {
      Permiso.expedirCDP,
      Permiso.expedirRP,
      Permiso.registrarObligacion,
      Permiso.liquidarNomina,
      Permiso.consultarTodo,

      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
    },
  };

  /// Define las NEGACIONES EXPLÍCITAS (segregación de funciones dura)
  /// Estas reglas tienen prioridad sobre los permisos positivos
  static Map<RolSectorPublico, Set<Permiso>> get negacionesPorRol => {
    // Tesorero NO puede expedir CDP ni RP (segregación de funciones)
    RolSectorPublico.tesorero: {
      Permiso.expedirCDP,
      Permiso.modificarCDP,
      Permiso.expedirRP,
      Permiso.modificarRP,
      Permiso.registrarObligacion,
      Permiso.aprobarPago, // No puede aprobar su propio pago
    },
    // Contador NO puede expedir CDP ni RP (segregación de funciones)
    RolSectorPublico.contador: {
      Permiso.expedirCDP,
      Permiso.modificarCDP,
      Permiso.expedirRP,
      Permiso.modificarRP,
      Permiso.aprobarPago,
      Permiso.ejecutarPago,
    },
    // Ordenador de gasto NO puede ejecutar pagos
    RolSectorPublico.ordenadorGasto: {
      Permiso.ejecutarPago,
      Permiso.aprobarPago,
    },
    // Jefe de rentas NO puede modificar presupuesto
    RolSectorPublico.jefeRentas: {
      Permiso.expedirCDP,
      Permiso.modificarCDP,
      Permiso.expedirRP,
      Permiso.modificarRP,
      Permiso.registrarObligacion,
    },
  };

  /// Resuelve el RolSectorPublico de un usuario en la entidad territorial especificada.
  ///
  /// REGLAS DE SEGURIDAD OBLIGATORIAS (FAIL-CLOSED):
  /// 1. La búsqueda se realiza EXCLUSIVAMENTE por usuario_id = ? (filtrado estricto por la clave del usuario).
  /// 2. null = sin rol resuelto = acceso denegado, NUNCA asumir un rol por defecto.
  /// 3. Si no hay resultado, o si hay más de un funcionario activo vinculado al mismo usuario_id en la entidad (dato corrupto),
  ///    el método retorna null explícitamente.
  /// 4. Castea usuarioId (dynamic/int/String) a String explícitamente para evitar mismatches.
  static Future<RolSectorPublico?> obtenerRolUsuarioEnEntidad({
    required DatabaseExecutor db,
    required String entidadId,
    required dynamic usuarioId,
  }) async {
    if (usuarioId == null) return null;
    final usuarioIdStr = usuarioId.toString().trim();
    if (usuarioIdStr.isEmpty ||
        usuarioIdStr == 'null' ||
        usuarioIdStr == 'sin_sesion') {
      return null;
    }
    final res = await db.query(
      'funcionarios_entidad',
      where: 'entidad_id = ? AND usuario_id = ?',
      whereArgs: [entidadId, usuarioIdStr],
    );

    // Fail-closed: si no hay un resultado único (0 o >1), retornar null explícitamente.
    if (res.length != 1) {
      return null;
    }

    final cargoClave = res.first['cargo_clave'] as String?;
    if (cargoClave == null || cargoClave.isEmpty) {
      return null;
    }

    try {
      return RolSectorPublico.values.firstWhere((r) => r.name == cargoClave);
    } catch (_) {
      return null;
    }
  }

  /// Verifica si un rol tiene un permiso específico
  static bool tienePermiso(RolSectorPublico rol, Permiso permiso) {
    // Primero verificar negaciones explícitas (tienen prioridad)
    final negaciones = negacionesPorRol[rol];
    if (negaciones != null && negaciones.contains(permiso)) {
      return false;
    }

    // Luego verificar permisos positivos
    final permisos = permisosPorRol[rol];
    return permisos != null && permisos.contains(permiso);
  }

  /// Verifica si un usuario puede realizar una acción específica
  /// Considera múltiples roles y segregación de funciones
  static bool puedeRealizarAccion({
    required Set<RolSectorPublico> roles,
    required Permiso permiso,
    String? usuarioId,
    String? referenciaId,
  }) {
    // Si no tiene roles, denegar
    if (roles.isEmpty) return false;

    // Verificar si alguno de sus roles tiene el permiso
    bool tienePermisoPositivo = roles.any((rol) => tienePermiso(rol, permiso));
    if (!tienePermisoPositivo) return false;

    // Verificar segregación de funciones específica por acción
    // Ejemplo: un tesorero no puede aprobar un pago que él mismo inició
    if (permiso == Permiso.aprobarPago &&
        roles.contains(RolSectorPublico.tesorero)) {
      // Aquí se debería verificar si el usuario es quien inició el pago
      // Esta lógica se implementará con datos adicionales
      return false; // Por defecto, tesorero no aprueba pagos
    }

    // Ejemplo: un contador no puede reversar sus propios asientos del mismo día
    if (permiso == Permiso.reversarAsiento &&
        roles.contains(RolSectorPublico.contador)) {
      // Verificar si el asiento fue creado por el mismo usuario
      // Esta lógica se implementará con datos adicionales
    }

    return true;
  }

  /// Obtiene todos los permisos de un rol (sin negaciones)
  static Set<Permiso> obtenerPermisos(RolSectorPublico rol) {
    return permisosPorRol[rol] ?? {};
  }

  /// Obtiene todas las negaciones de un rol
  static Set<Permiso> obtenerNegaciones(RolSectorPublico rol) {
    return negacionesPorRol[rol] ?? {};
  }

  /// Obtiene los permisos efectivos (positivos - negaciones)
  static Set<Permiso> obtenerPermisosEfectivos(RolSectorPublico rol) {
    final positivos = obtenerPermisos(rol);
    final negaciones = obtenerNegaciones(rol);
    return positivos.difference(negaciones);
  }

  /// Valida una transacción según segregación de funciones
  /// Retorna true si la transacción es válida según las reglas
  static bool validarSegregacionFunciones({
    required RolSectorPublico rolQuienEjecuta,
    required RolSectorPublico rolQuienAprobo,
    required Permiso accion,
  }) {
    // Un tesorero no puede aprobar su propio pago
    if (accion == Permiso.aprobarPago &&
        rolQuienEjecuta == RolSectorPublico.tesorero &&
        rolQuienAprobo == RolSectorPublico.tesorero) {
      return false;
    }

    // Un contador no puede reversar sus propios asientos
    if (accion == Permiso.reversarAsiento &&
        rolQuienEjecuta == RolSectorPublico.contador &&
        rolQuienAprobo == RolSectorPublico.contador) {
      return false;
    }

    // Un ordenador de gasto no puede ejecutar pagos
    if (accion == Permiso.ejecutarPago &&
        rolQuienEjecuta == RolSectorPublico.ordenadorGasto) {
      return false;
    }

    return true;
  }

  /// Obtiene descripción legible del rol
  static String obtenerDescripcionRol(RolSectorPublico rol) {
    switch (rol) {
      case RolSectorPublico.alcaldeRepresentanteLegal:
        return 'Alcalde / Representante Legal';
      case RolSectorPublico.secretarioHacienda:
        return 'Secretario de Hacienda';
      case RolSectorPublico.secretarioGeneral:
        return 'Secretario General';
      case RolSectorPublico.tesorero:
        return 'Tesorero';
      case RolSectorPublico.contador:
        return 'Contador';
      case RolSectorPublico.jefeRentas:
        return 'Jefe de Rentas';
      case RolSectorPublico.jefeControlInterno:
        return 'Jefe de Control Interno';
      case RolSectorPublico.jefePresupuesto:
        return 'Jefe de Presupuesto';
      case RolSectorPublico.ordenadorGasto:
        return 'Ordenador del Gasto';
      case RolSectorPublico.jefePlaneacion:
        return 'Jefe de Planeación';
      case RolSectorPublico.secretarioSalud:
        return 'Secretario de Salud';
      case RolSectorPublico.rector:
        return 'Rector';
    }
  }

  /// Obtiene descripción legible del permiso
  static String obtenerDescripcionPermiso(Permiso permiso) {
    switch (permiso) {
      case Permiso.expedirCDP:
        return 'Expedir CDP';
      case Permiso.modificarCDP:
        return 'Modificar CDP';
      case Permiso.expedirRP:
        return 'Expedir RP';
      case Permiso.modificarRP:
        return 'Modificar RP';
      case Permiso.registrarObligacion:
        return 'Registrar Obligación';
      case Permiso.aprobarPago:
        return 'Aprobar Pago';
      case Permiso.ejecutarPago:
        return 'Ejecutar Pago';
      case Permiso.modificarPAC:
        return 'Modificar PAC';
      case Permiso.registrarAutorizacionVigenciaFutura:
        return 'Registrar Autorización de Vigencia Futura';
      case Permiso.crearAsientoContable:
        return 'Crear Asiento Contable';
      case Permiso.reversarAsiento:
        return 'Reversar Asiento';
      case Permiso.cerrarVigencia:
        return 'Cerrar Vigencia';
      case Permiso.consultarEstadosFinancieros:
        return 'Consultar Estados Financieros';
      case Permiso.aprobarConciliacionReciproca:
        return 'Aprobar Conciliación Recíproca';
      case Permiso.liquidarNomina:
        return 'Liquidar Nómina';
      case Permiso.aprobarNomina:
        return 'Aprobar Nómina';
      case Permiso.pagarNomina:
        return 'Pagar Nómina';
      case Permiso.reliquidarNomina:
        return 'Reliquidar Nómina';
      case Permiso.liquidarTributo:
        return 'Liquidar Tributo';
      case Permiso.cobrarTributo:
        return 'Cobrar Tributo';
      case Permiso.iniciarCobroCoactivo:
        return 'Iniciar Cobro Coactivo';
      case Permiso.condonarTributo:
        return 'Condonar Tributo';
      case Permiso.iniciarProcesoContratacion:
        return 'Iniciar Proceso de Contratación';
      case Permiso.adjudicarContrato:
        return 'Adjudicar Contrato';
      case Permiso.firmarContrato:
        return 'Firmar Contrato';
      case Permiso.liquidarContrato:
        return 'Liquidar Contrato';
      case Permiso.supervisarContrato:
        return 'Supervisar Contrato';
      case Permiso.crearProyecto:
        return 'Crear Proyecto';
      case Permiso.modificarProyecto:
        return 'Modificar Proyecto';
      case Permiso.aprobarProyecto:
        return 'Aprobar Proyecto';
      case Permiso.vincularProyectoPresupuesto:
        return 'Vincular Proyecto a Presupuesto';
      case Permiso.gestionarUsuarios:
        return 'Gestionar Usuarios';
      case Permiso.asignarRoles:
        return 'Asignar Roles';
      case Permiso.consultarAuditoria:
        return 'Consultar Auditoría';
      case Permiso.consultarGestionDocumental:
        return 'Consultar Gestión Documental';
      case Permiso.radicarDocumentos:
        return 'Radicar Documentos';
      case Permiso.tramitarDocumentos:
        return 'Tramitar Documentos';
      case Permiso.administrarArchivo:
        return 'Administrar Archivo';
      case Permiso.administrarInstrumentosArchivisticos:
        return 'Administrar Instrumentos Archivísticos';
      case Permiso.administrarGestionDocumental:
        return 'Administrar Gestión Documental';
      case Permiso.configurarEntidad:
        return 'Configurar Entidad';
      case Permiso.consultarTodo:
        return 'Consultar Todo';
      case Permiso.exportarDatos:
        return 'Exportar Datos';
    }
  }
}
