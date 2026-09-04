class CompanyProfile {
  const CompanyProfile({
    this.id,
    required this.companyId,
    this.employeeCount = '',
    this.branchCount = '',
    this.operationVolume = '',
    this.taxRegime = '',
    this.vatEnabled = false,
    this.withholdingEnabled = false,
  });

  final int? id;
  final int companyId;
  final String employeeCount;
  final String branchCount;
  final String operationVolume;
  final String taxRegime;
  final bool vatEnabled;
  final bool withholdingEnabled;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'company_id': companyId,
    'employee_count': employeeCount,
    'branch_count': branchCount,
    'operation_volume': operationVolume,
    'tax_regime': taxRegime,
    'vat_enabled': vatEnabled ? 1 : 0,
    'withholding_enabled': withholdingEnabled ? 1 : 0,
  };
}
