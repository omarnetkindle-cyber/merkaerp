import '../../catalog/application/catalog_service.dart';
import '../domain/purchase_document.dart';

class PurchaseTaxService {
  PurchaseTaxService({CatalogService? catalog})
    : _catalog = catalog ?? CatalogService.instance;

  final CatalogService _catalog;

  Future<List<PurchaseDocumentLine>> applyDynamicTaxes({
    required List<PurchaseDocumentLine> lines,
    required String country,
    double retentionRate = 0,
  }) async {
    final taxes = await _catalog.taxOptionsForActiveCompany();
    final purchaseTaxes = taxes.where((tax) => tax.purchases).toList();
    return lines.map((line) {
      if (line.taxRate > 0 || line.taxCode != 'EXEMPT') return line;
      final matched = purchaseTaxes.firstWhere(
        (tax) => tax.rate > 0,
        orElse: () => purchaseTaxes.isEmpty ? taxes.first : purchaseTaxes.first,
      );
      return PurchaseDocumentLine(
        productId: line.productId,
        productName: line.productName,
        quantity: line.quantity,
        unitCost: line.unitCost,
        receivedQuantity: line.receivedQuantity,
        taxCode: matched.code,
        taxRate: country.toLowerCase() == 'colombia' ? matched.rate : 0,
        retentionRate: retentionRate,
        warehouseId: line.warehouseId,
      );
    }).toList();
  }
}
