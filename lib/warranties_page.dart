import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_helper.dart';
import 'sales/application/warranty_service.dart';
import 'sales/domain/warranty.dart';

class WarrantiesPage extends StatefulWidget {
  const WarrantiesPage({super.key});

  @override
  State<WarrantiesPage> createState() => _WarrantiesPageState();
}

class _WarrantiesPageState extends State<WarrantiesPage> {
  final WarrantyService _warrantyService = WarrantyService.instance;
  List<Warranty> _warranties = [];
  List<Map<String, dynamic>> _pendingClaims = [];
  Map<String, dynamic> _statistics = {};
  bool _isLoading = true;
  bool _isUpdating = false;
  String _selectedFilter = 'active';

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
      
      // Marcar garantías vencidas
      await _warrantyService.markExpiredWarranties(db, companyId);
      
      final results = await Future.wait([
        _getFilteredWarranties(db, companyId),
        _warrantyService.getPendingClaims(db, companyId),
        _warrantyService.getWarrantyStatistics(db, companyId),
      ]);
      
      setState(() {
        _warranties = results[0] as List<Warranty>;
        _pendingClaims = results[1] as List<Map<String, dynamic>>;
        _statistics = results[2] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar garantías: $e')),
        );
      }
    }
  }

  Future<List<Warranty>> _getFilteredWarranties(Database db, int companyId) async {
    switch (_selectedFilter) {
      case 'active':
        return await _warrantyService.getActiveWarranties(db, companyId);
      case 'expiring':
        return await _warrantyService.getExpiringSoonWarranties(db, companyId);
      case 'expired':
        return await _warrantyService.getExpiredWarranties(db, companyId);
      case 'claimed':
        final maps = await db.query(
          'warranties',
          where: 'company_id = ? AND status = ?',
          whereArgs: [companyId, 'claimed'],
          orderBy: 'created_at DESC',
        );
        return maps.map((map) => Warranty.fromMap(map)).toList();
      default:
        return await _warrantyService.getActiveWarranties(db, companyId);
    }
  }

  Future<void> _createWarrantyClaim(Warranty warranty) async {
    final issueController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Reclamo de Garantía'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Producto: ${warranty.productName}'),
            const SizedBox(height: 8),
            Text('Cliente: ${warranty.customerName}'),
            const SizedBox(height: 16),
            TextField(
              controller: issueController,
              decoration: const InputDecoration(
                labelText: 'Descripción del problema',
                hintText: 'Describe el problema con el producto',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear Reclamo'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _warrantyService.createWarrantyClaim(
          db,
          warranty.id!,
          issueController.text.trim(),
        );
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reclamo creado exitosamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al crear reclamo: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _resolveClaim(int claimId, String productName) async {
    final resolutionController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Resolver Reclamo - $productName'),
        content: TextField(
          controller: resolutionController,
          decoration: const InputDecoration(
            labelText: 'Resolución',
            hintText: 'Describe cómo se resolvió el problema',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resolver'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _warrantyService.resolveWarrantyClaim(
          db,
          claimId,
          resolutionController.text.trim(),
        );
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reclamo resuelto')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al resolver reclamo: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _extendWarranty(Warranty warranty) async {
    final monthsController = TextEditingController(text: '6');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extender Garantía'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Producto: ${warranty.productName}'),
            const SizedBox(height: 8),
            Text('Fecha actual de vencimiento: ${_formatDate(warranty.endDate)}'),
            const SizedBox(height: 16),
            TextField(
              controller: monthsController,
              keyboardType: TextInputType.numberWithOptions(signed: false),
              decoration: const InputDecoration(
                labelText: 'Meses a extender',
                hintText: 'ej: 6',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Extender'),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final months = int.tryParse(monthsController.text) ?? 6;
        await _warrantyService.extendWarranty(db, warranty.id!, months);
        await _loadData();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Garantía extendida $months meses')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al extender garantía: $e')),
          );
        }
      } finally {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _searchBySaleNumber() async {
    final saleNumberController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar por Número de Venta'),
        content: TextField(
          controller: saleNumberController,
          decoration: const InputDecoration(
            labelText: 'Número de venta',
            hintText: 'ej: VENTA-001',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, saleNumberController.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final warranty = await _warrantyService.getWarrantyBySaleNumber(db, result);
        
        if (warranty != null) {
          _showWarrantyDetails(warranty);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No se encontró garantía para esa venta')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al buscar: $e')),
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
        title: const Text('Gestión de Garantías'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _isUpdating ? null : _searchBySaleNumber,
            tooltip: 'Buscar por venta',
          ),
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
                      Tab(text: 'Garantías'),
                      Tab(text: 'Reclamos'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildWarrantiesTab(),
                        _buildClaimsTab(),
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
                    '${_statistics['total_warranties'] ?? 0}',
                    MerkaThemeTokens.info,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Activas',
                    '${_statistics['active_warranties'] ?? 0}',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Vencidas',
                    '${_statistics['expired_warranties'] ?? 0}',
                    Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Por Vencer',
                    '${_statistics['expiring_soon'] ?? 0}',
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Reclamos',
                    '${_statistics['pending_claims'] ?? 0}',
                    MerkaThemeTokens.navy600,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    'Reclamadas',
                    '${_statistics['claimed_warranties'] ?? 0}',
                    Colors.amber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, Color color) {
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
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantiesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('Activas', 'active'),
                _buildFilterChip('Por Vencer', 'expiring'),
                _buildFilterChip('Vencidas', 'expired'),
                _buildFilterChip('Reclamadas', 'claimed'),
              ],
            ),
          ),
        ),
        Expanded(
          child: _warranties.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_user, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No hay garantías',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _warranties.length,
                  itemBuilder: (context, index) {
                    final warranty = _warranties[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(warranty.status),
                          child: Icon(
                            _getStatusIcon(warranty.status),
                            color: Colors.white,
                          ),
                        ),
                        title: Text(warranty.productName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cliente: ${warranty.customerName}'),
                            const SizedBox(height: 4),
                            if (warranty.saleNumber != null)
                              Text(
                                'Venta: ${warranty.saleNumber}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'Vence: ${_formatDate(warranty.endDate)} (${warranty.daysRemaining} días)',
                              style: TextStyle(
                                fontSize: 12,
                                color: warranty.daysRemaining <= 30 ? Colors.orange : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        trailing: _isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'details':
                                      _showWarrantyDetails(warranty);
                                      break;
                                    case 'claim':
                                      _createWarrantyClaim(warranty);
                                      break;
                                    case 'extend':
                                      _extendWarranty(warranty);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'details',
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility),
                                        SizedBox(width: 8),
                                        Text('Ver detalles'),
                                      ],
                                    ),
                                  ),
                                  if (warranty.isActive)
                                    const PopupMenuItem(
                                      value: 'claim',
                                      child: Row(
                                        children: [
                                          Icon(Icons.report_problem),
                                          SizedBox(width: 8),
                                          Text('Crear reclamo'),
                                        ],
                                      ),
                                    ),
                                  if (warranty.isActive)
                                    const PopupMenuItem(
                                      value: 'extend',
                                      child: Row(
                                        children: [
                                          Icon(Icons.add_circle_outline),
                                          SizedBox(width: 8),
                                          Text('Extender garantía'),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                        onTap: () => _showWarrantyDetails(warranty),
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

  Widget _buildClaimsTab() {
    return _pendingClaims.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay reclamos pendientes',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _pendingClaims.length,
            itemBuilder: (context, index) {
              final claim = _pendingClaims[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: MerkaThemeTokens.gold500,
                    child: Icon(Icons.report, color: MerkaThemeTokens.navy900),
                  ),
                  title: Text(claim['product_name'] as String),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cliente: ${claim['customer_name']}'),
                      const SizedBox(height: 4),
                      Text(
                        'Fecha: ${_formatDate(DateTime.parse(claim['claim_date'] as String))}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        claim['issue_description'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _resolveClaim(
                            claim['id'] as int,
                            claim['product_name'] as String,
                          ),
                          tooltip: 'Resolver',
                        ),
                ),
              );
            },
          );
  }

  void _showWarrantyDetails(Warranty warranty) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(warranty.productName),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Estado', _getStatusText(warranty.status)),
              _buildDetailRow('Cliente', warranty.customerName),
              if (warranty.saleNumber != null)
                _buildDetailRow('Venta #', warranty.saleNumber!),
              _buildDetailRow('Tipo de garantía', _getWarrantyTypeText(warranty.warrantyType)),
              _buildDetailRow('Duración', '${warranty.durationMonths} meses'),
              _buildDetailRow('Inicio', _formatDate(warranty.startDate)),
              _buildDetailRow('Vencimiento', _formatDate(warranty.endDate)),
              _buildDetailRow('Días restantes', '${warranty.daysRemaining}'),
              if (warranty.notes != null)
                _buildDetailRow('Notas', warranty.notes!),
              _buildDetailRow('Creada', _formatDate(warranty.createdAt)),
            ],
          ),
        ),
        actions: [
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
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'expired':
        return Colors.red;
      case 'claimed':
        return Colors.orange;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.verified;
      case 'expired':
        return Icons.event_busy;
      case 'claimed':
        return Icons.report_problem;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active':
        return 'Activa';
      case 'expired':
        return 'Vencida';
      case 'claimed':
        return 'Reclamada';
      case 'cancelled':
        return 'Cancelada';
      default:
        return status;
    }
  }

  String _getWarrantyTypeText(String type) {
    switch (type) {
      case 'manufacturer':
        return 'Fabricante';
      case 'seller':
        return 'Vendedor';
      case 'extended':
        return 'Extendida';
      default:
        return type;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
