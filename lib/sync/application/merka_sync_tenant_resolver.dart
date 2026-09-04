import '../../licensing/domain/product_family.dart';
import '../../services/licencia_service.dart';

String resolveMerkaSyncTenantKind(LicenciaInfo? license) {
  if (license?.productFamily == ProductFamily.publicSector) {
    return 'public_sector';
  }
  return 'commercial';
}

String resolveMerkaSyncTenantId(LicenciaInfo? license, int companyId) {
  final clientId = license?.clientId?.trim();
  if (clientId != null && clientId.isNotEmpty) return 'client:$clientId';
  return 'company:$companyId';
}
