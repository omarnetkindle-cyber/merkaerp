import 'package:flutter/material.dart';
import '../db_helper.dart';

class OnboardingWidget extends StatefulWidget {
  const OnboardingWidget({super.key});

  @override
  State<OnboardingWidget> createState() => _OnboardingWidgetState();
}

class _OnboardingWidgetState extends State<OnboardingWidget> {
  Map<String, dynamic>? _progreso;
  bool _isLoading = true;

  final Map<String, String> _stepLabels = {
    'create_company': 'Crear Empresa',
    'add_taxes': 'Configurar Impuestos',
    'first_invoice': 'Primera Factura',
    'upload_rut': 'Subir RUT',
    'upload_signature': 'Subir Firma Digital',
  };

  final Map<String, IconData> _stepIcons = {
    'create_company': Icons.business,
    'add_taxes': Icons.receipt_long,
    'first_invoice': Icons.description,
    'upload_rut': Icons.upload_file,
    'upload_signature': Icons.draw,
  };

  final Map<String, String> _stepRoutes = {
    'create_company': 'companies',
    'add_taxes': 'settings',
    'first_invoice': 'sales',
    'upload_rut': 'companies',
    'upload_signature': 'companies',
  };

  @override
  void initState() {
    super.initState();
    _cargarProgreso();
  }

  Future<void> _cargarProgreso() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = DatabaseHelper.instance;
      final progreso = await db.obtenerProgresoOnboarding();
      setState(() {
        _progreso = progreso;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_progreso == null) {
      return const SizedBox.shrink();
    }

    final porcentaje = (_progreso!['porcentaje_completado'] as num?)?.toDouble() ?? 0;
    final pasosCompletados = (_progreso!['pasos_completados'] as int?) ?? 0;
    final totalPasos = (_progreso!['total_pasos'] as int?) ?? 1;
    final pasosDetalle = _progreso!['pasos_detalle'] as Map<String, bool>? ?? {};

    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fact_check,
                  color: porcentaje == 100 ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progreso de Configuración',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$pasosCompletados de $totalPasos pasos completados',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: porcentaje == 100 ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${porcentaje.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: porcentaje == 100 ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: porcentaje / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  porcentaje == 100 ? Colors.green : Colors.orange,
                ),
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 20),
            ..._stepLabels.entries.map((entry) {
              final stepName = entry.key;
              final label = entry.value;
              final icon = _stepIcons[stepName] ?? Icons.check_circle;
              final completado = pasosDetalle[stepName] ?? false;

              return _buildStepTile(
                label: label,
                icon: icon,
                completado: completado,
                onTap: () => _onStepTap(context, stepName, completado),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStepTile({
    required String label,
    required IconData icon,
    required bool completado,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration:BoxDecoration(
                color: completado ? Colors.green.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                completado ? Icons.check_circle : icon,
                color: completado ? Colors.green.shade700 : Colors.grey.shade600,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: completado ? Colors.grey.shade700 : Colors.grey.shade900,
                  decoration: completado ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _onStepTap(BuildContext context, String stepName, bool completado) {
    if (completado) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este paso ya está completado')),
      );
      return;
    }

    // Navegar al módulo correspondiente
    final route = _stepRoutes[stepName];
    if (route != null) {
      // Aquí deberías implementar la navegación real
      // Por ahora mostramos un mensaje
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Navegando a: $route')),
      );
    }
  }
}
