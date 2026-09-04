import 'features/company_configuration_service.dart';
import 'core/audit/audit_identity.dart';
import 'features/module_definition.dart';
import 'core/security/action_permission.dart';
import 'db_helper.dart';
import 'sector_publico/security/roles_permisos_service.dart';

class AppSession {
  static Map<String, dynamic>? usuarioActual;

  static String? get rol {
    if (usuarioActual == null) return null;
    final r = usuarioActual!['rol']?.toString().toLowerCase().trim();
    if (r == null || r.isEmpty || r == 'sistema') return null;
    return r;
  }

  static String get nombre =>
      usuarioActual?['nombre']?.toString() ?? 'Usuario local';

  static String? get usuarioId {
    if (usuarioActual == null) return null;
    final idVal = usuarioActual!['id'] ?? usuarioActual!['usuario'];
    if (idVal == null) return null;
    final str = idVal.toString().trim();
    if (str.isEmpty) return null;
    return str;
  }

  static String? _entidadIdActiva;
  static RolSectorPublico? _rolSectorPublico;

  static String get entidadId => _entidadIdActiva ?? 'ENT-001';

  static void establecerEntidadActiva(String id) {
    _entidadIdActiva = id;
  }

  static Future<void> resolverEntidadActiva() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId(
        db,
      );
      final rows = await db.query(
        'entidades_territoriales',
        where: 'company_id = ? AND activo = 1',
        whereArgs: [companyId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        _entidadIdActiva = rows.first['id']?.toString();
      }
    } catch (_) {
      // La sesión comercial no depende de una entidad territorial.
    }
  }

  static Future<RolSectorPublico?> cargarRolSectorPublico() async {
    final db = await DatabaseHelper.instance.database;
    _rolSectorPublico = await RolesPermisosService.obtenerRolUsuarioEnEntidad(
      db: db,
      entidadId: entidadId,
      usuarioId: usuarioId,
    );
    return _rolSectorPublico;
  }

  static void iniciar(Map<String, dynamic> usuario) {
    usuarioActual = usuario;
    AuditIdentity.setFromUser(usuario);
  }

  static void cerrar() {
    usuarioActual = null;
    AuditIdentity.clear();
    _rolSectorPublico = null;
    _entidadIdActiva = null;
  }

  static bool puedeAbrir(String modulo) {
    final userRol = rol;
    if (userRol == null) return false;
    final normalizado = _normalizarModulo(modulo);
    if (userRol == 'administrador') return true;

    const permisos = {
      'contador': {
        'caja',
        'compras',
        'ventas',
        'inventario',
        'clientes',
        'proveedores',
        'contabilidad',
        'cuentas x cobrar',
        'cuentas x pagar',
        'comprobantes',
        'periodos',
        'estados fin.',
        'reportes',
        'fiscal',
        'conciliacion',
        'extractos',
        'presupuestos',
        'cierres caja',
        'recibos',
        'auditoria',
        'config.',
        'manual',
        'empresas',
        'gestion documental',
      },
      'cajero': {
        'caja',
        'ventas',
        'inventario',
        'clientes',
        'cierres caja',
        'recibos',
        'reportes',
        'manual',
        'gestion documental',
      },
      'operador': {
        'caja',
        'ventas',
        'compras',
        'inventario',
        'clientes',
        'proveedores',
        'recibos',
        'manual',
        'gestion documental',
      },
      'consulta': {
        'reportes',
        'comprobantes',
        'estados fin.',
        'auditoria',
        'recibos',
        'manual',
        'gestion documental',
      },
    };

    return permisos[rol]?.contains(normalizado) ?? false;
  }

  static bool puedeAbrirModulo(ModuleDefinition modulo) {
    if (modulo.requiresAdmin && !puedeAdministrar()) return false;
    if (_esModuloSectorPublico(modulo.id)) {
      return _puedeAbrirModuloSectorPublico(modulo.id);
    }
    if (!puedeAbrir(modulo.permissionLabel ?? modulo.title)) return false;
    if (!puedeEjecutarAccion(modulo.id, AppAction.view)) return false;
    final featureKey = modulo.featureKey;
    if (featureKey == null) return true;
    return CompanyConfigurationService.instance.featureEnabledSync(featureKey);
  }

  /// Authorization entry point for commands that only have a module id.
  ///
  /// It intentionally reuses the same commercial/public RBAC path as the
  /// workspace instead of maintaining a second permission map for commands.
  static bool puedeAbrirModuloId(String moduloId) {
    if (_esModuloSectorPublico(moduloId)) {
      return _puedeAbrirModuloSectorPublico(moduloId);
    }
    return puedeAbrir(moduloId) &&
        puedeEjecutarAccion(moduloId, AppAction.view);
  }

  static bool puedeEjecutarPermiso(Permiso permiso) {
    final userRol = rol;
    if (userRol == 'administrador' || userRol == 'sistema') return true;
    final rolPublico = _rolSectorPublico;
    return rolPublico != null &&
        RolesPermisosService.tienePermiso(rolPublico, permiso);
  }

  static bool puedeEjecutarAccion(String moduloId, AppAction accion) {
    final userRol = rol;
    if (userRol == null || userRol.isEmpty) return false;
    return PermissionService.instance.can(
      role: userRol,
      moduleId: moduloId,
      action: accion,
    );
  }

  static bool _esModuloSectorPublico(String moduloId) {
    const ids = {
      'presupuesto_publico',
      'pac',
      'contabilidad_nicsp',
      'estado_flujos_efectivo',
      'provisiones_nicsp',
      'contratacion_publica',
      'secop_ii',
      'interventoria',
      'nomina_publica',
      'pila',
      'horas_extra',
      'predial',
      'ica',
      'rentas_departamentales',
      'planeacion',
      'mga',
      'pdt',
      'activos_estado',
      'fut',
      'auditoria_forense',
      'chip',
      'transparencia',
      'regalias_sgp',
      'siif',
      'salud_publica',
      'configuracion_entidad',
      'gestion_documental',
      'integrations',
    };
    return ids.contains(moduloId);
  }

  static bool _puedeAbrirModuloSectorPublico(String moduloId) {
    final userRol = rol;
    if (userRol == 'administrador' || userRol == 'sistema') return true;
    final rolPublico = _rolSectorPublico;
    if (rolPublico == null) return false;
    if (moduloId == 'configuracion_entidad' || moduloId == 'integrations') {
      return RolesPermisosService.tienePermiso(
        rolPublico,
        Permiso.configurarEntidad,
      );
    }
    if (RolesPermisosService.tienePermiso(rolPublico, Permiso.consultarTodo)) {
      return true;
    }

    final permisos = _permisosVistaPublica[moduloId];
    if (permisos == null) return false;
    return permisos.any(
      (permiso) => RolesPermisosService.tienePermiso(rolPublico, permiso),
    );
  }

  static const Map<String, Set<Permiso>> _permisosVistaPublica = {
    'presupuesto_publico': {
      Permiso.modificarPAC,
      Permiso.ejecutarPago,
      Permiso.expedirCDP,
      Permiso.expedirRP,
      Permiso.registrarObligacion,
    },
    'pac': {Permiso.modificarPAC, Permiso.ejecutarPago, Permiso.aprobarPago},
    'contabilidad_nicsp': {
      Permiso.crearAsientoContable,
      Permiso.consultarEstadosFinancieros,
    },
    'estado_flujos_efectivo': {Permiso.consultarEstadosFinancieros},
    'provisiones_nicsp': {Permiso.consultarEstadosFinancieros},
    'contratacion_publica': {
      Permiso.iniciarProcesoContratacion,
      Permiso.adjudicarContrato,
      Permiso.firmarContrato,
      Permiso.supervisarContrato,
    },
    'secop_ii': {Permiso.iniciarProcesoContratacion},
    'interventoria': {Permiso.supervisarContrato, Permiso.liquidarContrato},
    'nomina_publica': {Permiso.liquidarNomina, Permiso.aprobarNomina},
    'pila': {Permiso.liquidarNomina, Permiso.pagarNomina},
    'horas_extra': {Permiso.liquidarNomina, Permiso.reliquidarNomina},
    'predial': {Permiso.liquidarTributo, Permiso.cobrarTributo},
    'ica': {Permiso.liquidarTributo, Permiso.cobrarTributo},
    'rentas_departamentales': {Permiso.liquidarTributo, Permiso.cobrarTributo},
    'planeacion': {Permiso.crearProyecto, Permiso.modificarProyecto},
    'mga': {Permiso.crearProyecto, Permiso.vincularProyectoPresupuesto},
    'pdt': {Permiso.crearProyecto, Permiso.aprobarProyecto},
    'activos_estado': {Permiso.consultarEstadosFinancieros},
    'fut': {Permiso.exportarDatos, Permiso.consultarAuditoria},
    'auditoria_forense': {Permiso.consultarAuditoria},
    'chip': {Permiso.exportarDatos, Permiso.consultarAuditoria},
    'transparencia': {Permiso.exportarDatos, Permiso.consultarAuditoria},
    'regalias_sgp': {Permiso.crearProyecto, Permiso.modificarProyecto},
    'siif': {Permiso.exportarDatos, Permiso.consultarEstadosFinancieros},
    'salud_publica': {
      Permiso.expedirCDP,
      Permiso.expedirRP,
      Permiso.registrarObligacion,
    },
    'configuracion_entidad': {Permiso.configurarEntidad},
    'integrations': {Permiso.configurarEntidad},
    'gestion_documental': {
      Permiso.consultarGestionDocumental,
      Permiso.radicarDocumentos,
      Permiso.tramitarDocumentos,
      Permiso.administrarArchivo,
      Permiso.administrarGestionDocumental,
    },
  };

  static String _normalizarModulo(String modulo) {
    final value = modulo.toLowerCase().trim();
    const aliases = {
      'cierres de caja': 'cierres caja',
      'estados financieros': 'estados fin.',
      'configuracion': 'config.',
      'configuración': 'config.',
      'facturación': 'facturacion',
      'facturacion electronica': 'facturacion',
      'usuarios y permisos': 'usuarios',
      'conciliacion bancaria': 'conciliacion',
      'cuentas por cobrar': 'cuentas x cobrar',
      'cuentas por pagar': 'cuentas x pagar',
      'auditoría': 'auditoria',
      'nómina': 'nomina',
      'gestión documental': 'gestion documental',
    };
    return aliases[value] ?? value;
  }

  static bool puedeModificarOperacion() {
    return rol == 'administrador' || rol == 'cajero' || rol == 'operador';
  }

  static bool puedeAdministrar() {
    return rol == 'administrador';
  }
}
