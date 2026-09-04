import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'sales/application/commission_service.dart';
import 'sales/domain/commission.dart';

class CommissionsPage extends StatefulWidget {
  const CommissionsPage({super.key});

  @override
  State<CommissionsPage> createState() => _CommissionsPageState();
}

class _CommissionsPageState extends State<CommissionsPage> {
  final CommissionService _commissionService = CommissionService.instance;
  List<Commission> _commissions = [];
  List<Map<String, dynamic>> _rules = [];
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;
  bool _isUpdating = false;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      
      final results = await Future.wait([
        _getFilteredCommissions(db, companyId),
        _commissionService.getCommissionRules(db, companyId),
        _commissionService.getCommissionStatistics(db, companyId),
      ]);
      
      setState(() {
        _commissions = results[0] as List<Commission>;
        _rules = results[1] as List<Map<String, dynamic>>;
        _statistics = results[2] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar comisiones: $e')),
        );
      }
    }
  }

  Future<List<Commission>> _getFilteredCommissions(Database db, int companyId) async {
    switch (_selectedFilter) {
      case 'pending':
        return await _commissionService.getPendingCommissions(db, companyId);
      case 'paid':
        return await _commissionService.getCommissionsByStatus(db, companyId, 'paid');
      case 'cancelled':
        return await _commissionService.getCommissionsByStatus(db, companyId, 'cancelled');
      default:
        return await _commissionService.getCommissionsByStatus(db, companyId, 'pending');
    }
  }

  Future<void> _markAsPaid(Commission commission) async {
    setState(() => _isUpdating = true);
    try {
      final db = await DatabaseHelper.instance.database;
      await _commissionService.markAsPaid(db, commission.id!);
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Comisión de ${commission.salespersonName} marcada como pagada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al marcar comisión como pagada: $e')),
        );
      }
    } finally {
      setState(() => _isUpdating = false);
    }
  }

  Future<void> _cancelCommission(Commission commission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar Comisión'),
        content: Text('¿Está seguro de cancelar la comisión de ${commission.salespersonName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _commissionService.cancelCommission(db, commission.id!);
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comisión cancelada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cancelar comisión: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _showAddRuleDialog() async {
    final rateController = TextEditingController(text: '5.0');
    final minAmountController = TextEditingController(text: '0');
    final maxAmountController = TextEditingController();
    final categoryController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Regla de Comisión'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tasa de comisión (%)',
                  hintText: 'ej: 5.0 para 5%',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: minAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto mínimo (opcional)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto máximo (opcional)',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(
                  labelText: 'Categoría de producto (opcional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
        
        await _commissionService.registerCommissionRule(
          db,
          companyId,
          double.tryParse(rateController.text) ?? 5.0,
          minAmount: double.tryParse(minAmountController.text),
          maxAmount: maxAmountController.text.isEmpty ? null : double.tryParse(maxAmountController.text),
          productCategory: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
        );
        
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Regla de comisión agregada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al agregar regla: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteRule(int ruleId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Regla'),
        content: const Text('¿Está seguro de eliminar esta regla de comisión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _commissionService.deactivateCommissionRule(db, ruleId);
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Regla eliminada')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar regla: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Comisiones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadData,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  _buildStatisticsCard(),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Comisiones'),
                      Tab(text: 'Reglas'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildCommissionsTab(),
                        _buildRulesTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estadísticas',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Total',
                    '${_statistics['total_commissions'] ?? 0}',
                    '\$${(_statistics['total_amount'] ?? 0).toStringAsFixed(2)}',
                    MerkaThemeTokens.info,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Pendientes',
                    '${_statistics['pending_commissions'] ?? 0}',
                    '\$${(_statistics['pending_amount'] ?? 0).toStringAsFixed(2)}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Pagadas',
                    '${_statistics['paid_commissions'] ?? 0}',
                    '\$${(_statistics['paid_amount'] ?? 0).toStringAsFixed(2)}',
                    Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String count, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Todas', 'all'),
                _buildFilterChip('Pendientes', 'pending'),
                _buildFilterChip('Pagadas', 'paid'),
                _buildFilterChip('Canceladas', 'cancelled'),
              ],
            ),
          ),
        ),
        Expanded(
          child: _commissions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.money_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay comisiones',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _commissions.length,
                  itemBuilder: (context, index) {
                    final commission = _commissions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(commission.status),
                          child: Icon(
                            _getStatusIcon(commission.status),
                            color: Colors.white,
                          ),
                        ),
                        title: Text(commission.salespersonName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Venta #${commission.saleNumber ?? 'N/A'}'),
                            const SizedBox(height: 4),
                            Text(
                              'Monto venta: \$${commission.saleAmount.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${commission.commissionAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${commission.commissionRate.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        onTap: () => _showCommissionDetails(commission),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: _selectedFilter == value,
        onSelected: (selected) {
          setState(() => _selectedFilter = value);
          _loadData();
        },
      ),
    );
  }

  Widget _buildRulesTab() {
    return Column(
      children: [
        Expanded(
          child: _rules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rule, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay reglas configuradas',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Agrega reglas para calcular comisiones',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rules.length,
                  itemBuilder: (context, index) {
                    final rule = _rules[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: MerkaThemeTokens.navy600,
                          child: Icon(Icons.percent, color: Colors.white),
                        ),
                        title: Text('${rule['commission_rate']}% de comisión'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rule['salesperson_id'] != null)
                              Text('Vendedor ID: ${rule['salesperson_id']}')
                            else
                              const Text('Regla general'),
                            const SizedBox(height: 4),
                            Text(
                              'Rango: \$${rule['min_amount'] ?? 0} - \$${rule['max_amount'] ?? '∞'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                            if (rule['product_category'] != null)
                              Text(
                                'Categoría: ${rule['product_category']}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                        trailing: _isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                tooltip: 'Eliminar regla de comisión',
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteRule(rule['id'] as int),
                              ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isUpdating ? null : _showAddRuleDialog,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Regla'),
            ),
          ),
        ),
      ],
    );
  }

  void _showCommissionDetails(Commission commission) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Comisión - ${commission.salespersonName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Venta #', commission.saleNumber ?? 'N/A'),
              _buildDetailRow('Monto venta', '\$${commission.saleAmount.toStringAsFixed(2)}'),
              _buildDetailRow('Tasa', '${commission.commissionRate.toStringAsFixed(1)}%'),
              _buildDetailRow('Comisión', '\$${commission.commissionAmount.toStringAsFixed(2)}'),
              _buildDetailRow('Estado', _getStatusText(commission.status)),
              if (commission.paidDate != null)
                _buildDetailRow('Fecha pago', _formatDate(commission.paidDate!)),
              _buildDetailRow('Creada', _formatDate(commission.createdAt)),
            ],
          ),
        ),
        actions: [
          if (commission.isPending)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _markAsPaid(commission);
              },
              child: const Text('Marcar como pagada'),
            ),
          if (commission.isPending)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _cancelCommission(commission);
              },
              child: const Text('Cancelar', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.pending;
      case 'paid':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pendiente';
      case 'paid':
        return 'Pagada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
