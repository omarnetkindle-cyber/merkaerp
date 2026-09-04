import '../../core/currency/money_value.dart';
import '../domain/product.dart';

enum CostingMethod { weightedAverage, fifo }

class ReplenishmentSuggestion {
  const ReplenishmentSuggestion({
    required this.product,
    required this.recommendedQuantity,
    required this.reason,
  });

  final Product product;
  final double recommendedQuantity;
  final String reason;

  Map<String, Object?> toMap() => {
    'product_id': product.id,
    'product': product.name,
    'stock': product.stock,
    'recommended_quantity': recommendedQuantity,
    'reason': reason,
  };
}

class InventoryControlReport {
  const InventoryControlReport({
    required this.products,
    required this.suggestions,
    required this.costValue,
    required this.saleValue,
  });

  final int products;
  final List<ReplenishmentSuggestion> suggestions;
  final MoneyValue costValue;
  final MoneyValue saleValue;

  MoneyValue get potentialMargin => saleValue - costValue;

  Map<String, Object?> toMap() => {
    'products': products,
    'cost_value': costValue.toWireMap(),
    'sale_value': saleValue.toWireMap(),
    'potential_margin': potentialMargin.toWireMap(),
    'replenishment': suggestions.map((item) => item.toMap()).toList(),
  };
}

class InventoryControlService {
  const InventoryControlService({
    this.reorderPoint = 5,
    this.targetStock = 15,
    this.costingMethod = CostingMethod.weightedAverage,
  });

  final double reorderPoint;
  final double targetStock;
  final CostingMethod costingMethod;

  InventoryControlReport analyze(List<Product> products) {
    if (products.isEmpty) {
      throw StateError('A currency is required to analyze an empty inventory');
    }
    var costValue = MoneyValue(
      minorUnits: 0,
      currency: products.first.cost.currency,
    );
    var saleValue = MoneyValue(
      minorUnits: 0,
      currency: products.first.price.currency,
    );
    final suggestions = <ReplenishmentSuggestion>[];
    for (final product in products) {
      costValue += product.stockCostValue;
      saleValue += product.stockSaleValue;
      if (product.stock <= reorderPoint) {
        final quantity = (targetStock - product.stock).clamp(0, targetStock);
        suggestions.add(
          ReplenishmentSuggestion(
            product: product,
            recommendedQuantity: quantity.toDouble(),
            reason: 'Stock igual o inferior al punto de reposicion.',
          ),
        );
      }
    }
    return InventoryControlReport(
      products: products.length,
      suggestions: suggestions,
      costValue: costValue,
      saleValue: saleValue,
    );
  }

  MoneyValue weightedAverageCost({
    required double currentStock,
    required MoneyValue currentCost,
    required double incomingQuantity,
    required MoneyValue incomingCost,
  }) {
    if (currentStock < 0 || incomingQuantity < 0) {
      throw ArgumentError('Las cantidades no pueden ser negativas.');
    }
    final totalQuantity = currentStock + incomingQuantity;
    if (totalQuantity == 0) {
      return MoneyValue(minorUnits: 0, currency: currentCost.currency);
    }
    final totalCost =
        currentCost.multiplyDecimal(currentStock.toString()) +
        incomingCost.multiplyDecimal(incomingQuantity.toString());
    return totalCost.divideDecimal(totalQuantity.toString());
  }
}
