import '../company/company_context.dart';
import 'database_gateway.dart';

enum DataHealthSeverity { info, warning, critical }

class DataHealthIssue {
  const DataHealthIssue({
    required this.id,
    required this.title,
    required this.count,
    required this.severity,
    required this.recommendation,
  });

  final String id;
  final String title;
  final int count;
  final DataHealthSeverity severity;
  final String recommendation;

  bool get active => count > 0;

  bool get blocking => active && severity == DataHealthSeverity.critical;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'count': count,
    'severity': severity.name,
    'recommendation': recommendation,
    'blocking': blocking,
  };
}

class DataHealthReport {
  const DataHealthReport({
    required this.companyId,
    required this.generatedAt,
    required this.issues,
  });

  final int companyId;
  final DateTime generatedAt;
  final List<DataHealthIssue> issues;

  List<DataHealthIssue> get activeIssues =>
      issues.where((issue) => issue.active).toList();

  List<DataHealthIssue> get blockingIssues =>
      issues.where((issue) => issue.blocking).toList();

  bool get clean => activeIssues.isEmpty;

  Map<String, Object?> toMap() => {
    'company_id': companyId,
    'generated_at': generatedAt.toIso8601String(),
    'clean': clean,
    'active_issues': activeIssues.length,
    'blocking_issues': blockingIssues.length,
    'issues': issues.map((issue) => issue.toMap()).toList(),
  };
}

class DataHealthService {
  DataHealthService({
    DatabaseGateway gateway = const SqliteDatabaseGateway(),
    CompanyContextProvider? companyContext,
  }) : _gateway = gateway,
       _companyContext = companyContext ?? CompanyContextService.instance;

  final DatabaseGateway _gateway;
  final CompanyContextProvider _companyContext;

  Future<DataHealthReport> audit() async {
    final companyId = (await _companyContext.current()).companyId;
    return DataHealthReport(
      companyId: companyId,
      generatedAt: DateTime.now(),
      issues: [
        DataHealthIssue(
          id: 'negative_stock',
          title: 'Productos con inventario negativo',
          count: await _count(
            'SELECT COUNT(*) AS total FROM productos '
            'WHERE company_id = ? AND stock < 0',
            [companyId],
          ),
          severity: DataHealthSeverity.critical,
          recommendation:
              'Ajusta kardex y documentos que dejaron stock por debajo de cero.',
        ),
        DataHealthIssue(
          id: 'orphan_sale_lines',
          title: 'Lineas de venta sin cabecera',
          count: await _count(
            '''
            SELECT COUNT(*) AS total
            FROM ventas_detalle vd
            LEFT JOIN ventas v ON v.id = vd.venta_id
            WHERE vd.company_id = ? AND v.id IS NULL
            ''',
            [companyId],
          ),
          severity: DataHealthSeverity.critical,
          recommendation:
              'Revisa integridad de ventas antes de emitir reportes o cierres.',
        ),
        DataHealthIssue(
          id: 'orphan_purchase_lines',
          title: 'Lineas de compra sin cabecera',
          count: await _count(
            '''
            SELECT COUNT(*) AS total
            FROM compras_detalle cd
            LEFT JOIN compras c ON c.id = cd.compra_id
            WHERE cd.company_id = ? AND c.id IS NULL
            ''',
            [companyId],
          ),
          severity: DataHealthSeverity.critical,
          recommendation:
              'Revisa integridad de compras antes de calcular inventario.',
        ),
        DataHealthIssue(
          id: 'unbalanced_entries',
          title: 'Asientos contables descuadrados',
          count: await _count(
            '''
            SELECT COUNT(*) AS total
            FROM (
              SELECT asiento_id
              FROM asiento_lineas
              WHERE company_id = ?
              GROUP BY asiento_id
              HAVING ABS(COALESCE(SUM(debito), 0) - COALESCE(SUM(credito), 0)) > 0.01
            )
            ''',
            [companyId],
          ),
          severity: DataHealthSeverity.critical,
          recommendation:
              'Corrige asientos descuadrados antes de cerrar periodos.',
        ),
        DataHealthIssue(
          id: 'duplicate_products',
          title: 'Productos con nombres duplicados',
          count: await _count(
            '''
            SELECT COUNT(*) AS total
            FROM (
              SELECT LOWER(TRIM(nombre)) AS nombre_normalizado
              FROM productos
              WHERE company_id = ?
              GROUP BY nombre_normalizado
              HAVING COUNT(*) > 1
            )
            ''',
            [companyId],
          ),
          severity: DataHealthSeverity.warning,
          recommendation:
              'Unifica productos duplicados para mejorar compras, ventas y costos.',
        ),
      ],
    );
  }

  Future<int> _count(String sql, List<Object?> args) async {
    final rows = await _gateway.rawQuery(sql, args);
    if (rows.isEmpty) return 0;
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
