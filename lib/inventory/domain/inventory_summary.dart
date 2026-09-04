import '../../core/currency/currency.dart';
import '../../core/currency/money_value.dart';
import 'product.dart';

class InventorySummary {
  const InventorySummary({
    required this.costValue,
    required this.saleValue,
    required this.productCount,
    required this.lowStockCount,
  });

  final MoneyValue costValue;
  final MoneyValue saleValue;
  final int productCount;
  final int lowStockCount;

  factory InventorySummary.empty(Currency currency) => InventorySummary(
    costValue: MoneyValue(minorUnits: 0, currency: currency),
    saleValue: MoneyValue(minorUnits: 0, currency: currency),
    productCount: 0,
    lowStockCount: 0,
  );

  factory InventorySummary.fromProducts(List<Product> products) {
    if (products.isEmpty) {
      throw StateError(
        'A currency is required to summarize an empty inventory',
      );
    }
    var costValue = MoneyValue(
      minorUnits: 0,
      currency: products.first.cost.currency,
    );
    var saleValue = MoneyValue(
      minorUnits: 0,
      currency: products.first.price.currency,
    );
    for (final product in products) {
      costValue += product.stockCostValue;
      saleValue += product.stockSaleValue;
    }
    return InventorySummary(
      costValue: costValue,
      saleValue: saleValue,
      productCount: products.length,
      lowStockCount: products.where((product) => product.lowStock).length,
    );
  }
}
