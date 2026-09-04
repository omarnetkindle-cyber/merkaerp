import '../../core/branch/branch_context.dart';
import '../../core/currency/money_value.dart';
import '../../core/events/domain_event.dart';
import '../data/stock_ledger_repository.dart';
import '../domain/stock_ledger.dart';

class StockConsumptionResult {
  const StockConsumptionResult({
    required this.productId,
    required this.quantity,
    required this.totalCost,
    required this.unitCost,
    required this.remainingOnHand,
  });

  final int productId;
  final double quantity;
  final MoneyValue totalCost;
  final MoneyValue unitCost;
  final double remainingOnHand;

  Map<String, Object?> toMap() => {
    'product_id': productId,
    'quantity': quantity,
    'total_cost': totalCost.toWireMap(),
    'unit_cost': unitCost.toWireMap(),
    'remaining_on_hand': remainingOnHand,
  };
}

class StockLedgerService {
  StockLedgerService({
    StockLedgerRepository? repository,
    BranchScopeProvider? scopeProvider,
    DomainEventPublisher events = const NoopDomainEventPublisher(),
  }) : _repository = repository ?? SqliteStockLedgerRepository(),
       _scopeProvider = scopeProvider ?? BranchContextService.instance,
       _events = events;

  final StockLedgerRepository _repository;
  final BranchScopeProvider _scopeProvider;
  final DomainEventPublisher _events;

  Future<StockLedger> current(int productId) async {
    final scope = await _scopeProvider.current();
    return _repository.load(productId: productId, scope: scope);
  }

  Future<void> receiveLot(StockLot lot) async {
    final scope = await _scopeProvider.current();
    await _repository.saveLot(lot, scope: scope);
    await _events.publish(
      IntegrationEvent(
        name: 'inventory.lot_received',
        payload: {
          'aggregate_type': 'inventory_lot',
          'aggregate_id': lot.id,
          'product_id': lot.productId,
          'quantity': lot.quantity,
          'unit_cost': lot.unitCost.toWireMap(),
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'warehouse_id': scope.warehouseId,
        },
      ),
    );
  }

  Future<StockLedger> reserve(InventoryReservation reservation) async {
    final scope = await _scopeProvider.current();
    final ledger = await _repository.load(
      productId: reservation.productId,
      scope: scope,
    );
    final reserved = ledger.reserve(reservation);
    await _repository.saveReservation(reservation, scope: scope);
    await _events.publish(
      IntegrationEvent(
        name: 'inventory.reserved',
        payload: {
          'aggregate_type': 'inventory_reservation',
          'aggregate_id': reservation.id,
          'product_id': reservation.productId,
          'quantity': reservation.quantity,
          'document_type': reservation.documentType,
          'document_id': reservation.documentId,
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'warehouse_id': scope.warehouseId,
        },
      ),
    );
    return reserved;
  }

  Future<void> releaseReservation(String reservationId) async {
    final scope = await _scopeProvider.current();
    await _repository.releaseReservation(reservationId, scope: scope);
    await _events.publish(
      IntegrationEvent(
        name: 'inventory.reservation_released',
        payload: {
          'aggregate_type': 'inventory_reservation',
          'aggregate_id': reservationId,
          'reservation_id': reservationId,
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'warehouse_id': scope.warehouseId,
        },
      ),
    );
  }

  Future<StockConsumptionResult> consume({
    required int productId,
    required double quantity,
    required InventoryCostMethod method,
    required String documentType,
    required String documentId,
  }) async {
    final scope = await _scopeProvider.current();
    final ledger = await _repository.load(productId: productId, scope: scope);
    final consumption = ledger.consume(quantity: quantity, method: method);
    await _repository.replaceLots(
      consumption.remainingLots,
      productId: productId,
      scope: scope,
    );
    await _events.publish(
      IntegrationEvent(
        name: 'inventory.consumed',
        payload: {
          'aggregate_type': 'inventory',
          'aggregate_id': productId.toString(),
          'product_id': productId,
          'quantity': quantity,
          'cost_method': method.name,
          'total_cost': consumption.totalCost.toWireMap(),
          'unit_cost': consumption.unitCost.toWireMap(),
          'document_type': documentType,
          'document_id': documentId,
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'warehouse_id': scope.warehouseId,
        },
      ),
    );
    return StockConsumptionResult(
      productId: productId,
      quantity: quantity,
      totalCost: consumption.totalCost,
      unitCost: consumption.unitCost,
      remainingOnHand: consumption.remainingLots.fold(
        0,
        (sum, lot) => sum + lot.quantity,
      ),
    );
  }
}
