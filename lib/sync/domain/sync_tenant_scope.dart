import '../../app_session.dart';

/// Resolvedor unificado de contexto de tenencia (Multi-Tenant Scope).
/// Diferencia entre el modelo Comercial (company_id/branch_id: int)
/// y el modelo de Sector Público (entidad_id: String, ej. 'ENT-001').
class SyncTenantScope {
  const SyncTenantScope({
    required this.tenantType,
    this.companyId,
    this.branchId,
    this.entidadId,
    this.usuarioId,
  });

  /// Tipo de tenencia: 'commercial' | 'public_sector'
  final String tenantType;

  /// Identificador de empresa comercial (int)
  final int? companyId;

  /// Identificador de sucursal comercial (int)
  final int? branchId;

  /// Identificador de entidad del sector público (String, ej. 'ENT-001')
  final String? entidadId;

  /// Identificador del usuario autenticado en la sesión activa
  final String? usuarioId;

  /// Constructor para contexto Comercial (requiere companyId y branchId explícitos).
  factory SyncTenantScope.commercial({
    required int companyId,
    required int branchId,
    String? usuarioId,
  }) {
    return SyncTenantScope(
      tenantType: 'commercial',
      companyId: companyId,
      branchId: branchId,
      entidadId: null,
      usuarioId: usuarioId ?? AppSession.usuarioId,
    );
  }

  /// Constructor para contexto de Sector Público.
  factory SyncTenantScope.publicSector({
    String? entidadId,
    String? usuarioId,
  }) {
    return SyncTenantScope(
      tenantType: 'public_sector',
      companyId: null,
      branchId: null,
      entidadId: entidadId ?? AppSession.entidadId,
      usuarioId: usuarioId ?? AppSession.usuarioId,
    );
  }

  /// Resuelve dinámicamente el scope actual.
  factory SyncTenantScope.current({
    bool isPublicSectorMode = false,
    int? companyId,
    int? branchId,
  }) {
    if (isPublicSectorMode) {
      return SyncTenantScope.publicSector();
    }
    if (companyId == null || branchId == null) {
      throw StateError(
        'El contexto comercial requiere companyId y branchId explícitos (Fail-Closed).',
      );
    }
    return SyncTenantScope.commercial(companyId: companyId, branchId: branchId);
  }

  Map<String, dynamic> toMap() {
    return {
      'tenant_type': tenantType,
      'company_id': companyId,
      'branch_id': branchId,
      'entidad_id': entidadId,
      'usuario_id': usuarioId,
    };
  }
}
