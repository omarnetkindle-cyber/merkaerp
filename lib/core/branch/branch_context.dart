import '../../db_helper.dart';

class BranchScope {
  const BranchScope({
    required this.companyId,
    required this.companyName,
    required this.branchId,
    required this.branchName,
    required this.warehouseId,
    required this.costCenterId,
  });

  final int companyId;
  final String companyName;
  final int branchId;
  final String branchName;
  final int warehouseId;
  final int costCenterId;

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'company_name': companyName,
    'branch_id': branchId,
    'branch_name': branchName,
    'warehouse_id': warehouseId,
    'cost_center_id': costCenterId,
  };
}

abstract class BranchScopeProvider {
  Future<BranchScope> current({bool force = false});
}

class BranchContextService implements BranchScopeProvider {
  BranchContextService._();

  static final BranchContextService instance = BranchContextService._();

  BranchScope? _cached;

  BranchScope? get cached => _cached;

  @override
  Future<BranchScope> current({bool force = false}) async {
    if (_cached != null && !force) return _cached!;
    _cached = await DatabaseHelper.instance.obtenerScopeOperativoActivo();
    return _cached!;
  }

  void clear() {
    _cached = null;
  }
}
