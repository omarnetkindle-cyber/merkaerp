import '../../db_helper.dart';

class CompanyContext {
  const CompanyContext({required this.companyId, required this.companyName});

  final int companyId;
  final String companyName;
}

abstract class CompanyContextProvider {
  Future<CompanyContext> current({bool force = false});
}

class CompanyContextService implements CompanyContextProvider {
  CompanyContextService._();

  static final CompanyContextService instance = CompanyContextService._();

  CompanyContext? _cached;

  CompanyContext? get cached => _cached;

  @override
  Future<CompanyContext> current({bool force = false}) async {
    if (_cached != null && !force) return _cached!;
    final config = await DatabaseHelper.instance.obtenerConfiguracionActiva();
    _cached = CompanyContext(
      companyId: config.companyId,
      companyName: config.companyName,
    );
    return _cached!;
  }
}
