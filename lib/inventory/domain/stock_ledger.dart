import '../../core/currency/money_value.dart';

enum InventoryCostMethod { fifo, average }

class StockLot {
  const StockLot({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.receivedAt,
    this.batchNumber,
    this.serialNumber,
    this.expiresAt,
  });

  final String id;
  final int productId;
  final double quantity;
  final MoneyValue unitCost;
  final DateTime receivedAt;
  final String? batchNumber;
  final String? serialNumber;
  final DateTime? expiresAt;

  MoneyValue get value => unitCost.multiplyDecimal(quantity.toString());

  StockLot consume(double amount) {
    if (amount > quantity) {
      throw StateError('No hay cantidad suficiente en el lote $id.');
    }
    return StockLot(
      id: id,
      productId: productId,
      quantity: quantity - amount,
      unitCost: unitCost,
      receivedAt: receivedAt,
      batchNumber: batchNumber,
      serialNumber: serialNumber,
      expiresAt: expiresAt,
    );
  }
}

class InventoryReservation {
  const InventoryReservation({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.documentType,
    required this.documentId,
    required this.createdAt,
  });

  final String id;
  final int productId;
  final double quantity;
  final String documentType;
  final String documentId;
  final DateTime createdAt;
}

class CostConsumption {
  const CostConsumption({
    required this.quantity,
    required this.totalCost,
    required this.remainingLots,
  });

  final double quantity;
  final MoneyValue totalCost;
  final List<StockLot> remainingLots;

  MoneyValue get unitCost => quantity == 0
      ? MoneyValue(minorUnits: 0, currency: totalCost.currency)
      : totalCost.divideDecimal(quantity.toString());
}

class StockLedger {
  const StockLedger({
    required this.productId,
    required this.lots,
    this.reservations = const [],
  });

  final int productId;
  final List<StockLot> lots;
  final List<InventoryReservation> reservations;

  double get onHand => lots.fold(0, (sum, lot) => sum + lot.quantity);

  double get reserved =>
      reservations.fold(0, (sum, reservation) => sum + reservation.quantity);

  double get available => onHand - reserved;

  MoneyValue get value {
    if (lots.isEmpty) {
      throw StateError('El inventario requiere al menos un lote.');
    }
    final zero = MoneyValue(
      minorUnits: 0,
      currency: lots.first.unitCost.currency,
    );
    return lots.fold(zero, (sum, lot) => sum + lot.value);
  }

  StockLedger reserve(InventoryReservation reservation) {
    if (reservation.quantity > available) {
      throw StateError('Stock disponible insuficiente para reservar.');
    }
    return StockLedger(
      productId: productId,
      lots: lots,
      reservations: [...reservations, reservation],
    );
  }

  CostConsumption consume({
    required double quantity,
    required InventoryCostMethod method,
  }) {
    if (quantity > available) {
      throw StateError('Stock disponible insuficiente para consumir.');
    }
    if (method == InventoryCostMethod.average) {
      final average = onHand == 0
          ? MoneyValue(minorUnits: 0, currency: lots.first.unitCost.currency)
          : value.divideDecimal(onHand.toString());
      return CostConsumption(
        quantity: quantity,
        totalCost: average.multiplyDecimal(quantity.toString()),
        remainingLots: _consumeOrdered(quantity, lots),
      );
    }
    final ordered = [...lots]
      ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return _consumeWithCost(quantity, ordered);
  }

  CostConsumption _consumeWithCost(double quantity, List<StockLot> ordered) {
    var remaining = quantity;
    final zero = ordered.first.unitCost;
    var totalCost = MoneyValue(minorUnits: 0, currency: zero.currency);
    final consumedByLot = <String, double>{};

    for (final lot in ordered) {
      if (remaining <= 0) break;
      final take = remaining > lot.quantity ? lot.quantity : remaining;
      consumedByLot[lot.id] = take;
      totalCost = totalCost + lot.unitCost.multiplyDecimal(take.toString());
      remaining -= take;
    }
    if (remaining > 0.0001) {
      throw StateError('Stock insuficiente para costear salida.');
    }
    final remainingLots = [
      for (final lot in lots)
        if ((lot.quantity - (consumedByLot[lot.id] ?? 0)) > 0)
          lot.consume(consumedByLot[lot.id] ?? 0),
    ];
    return CostConsumption(
      quantity: quantity,
      totalCost: totalCost,
      remainingLots: remainingLots,
    );
  }

  List<StockLot> _consumeOrdered(double quantity, List<StockLot> originalLots) {
    var remaining = quantity;
    final result = <StockLot>[];
    for (final lot in originalLots) {
      if (remaining <= 0) {
        result.add(lot);
        continue;
      }
      final take = remaining > lot.quantity ? lot.quantity : remaining;
      final left = lot.quantity - take;
      if (left > 0) {
        result.add(lot.consume(take));
      }
      remaining -= take;
    }
    return result;
  }
}
