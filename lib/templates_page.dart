import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'db_helper.dart';
import 'core/templates/document_template.dart';
import 'core/templates/template_service.dart';
import 'core/templates/pdf_layout_settings_service.dart';

class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  final TemplateService _templateService = TemplateService.instance;
  List<DocumentTemplate> _templates = [];
  bool _isLoading = true;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
      final templates = await _templateService.getTemplatesByCompany(
        db,
        companyId,
      );

      if (!mounted) return;
      setState(() {
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar plantillas: $e')));
    }
  }

  Future<void> _setAsDefault(DocumentTemplate template) async {
    setState(() => _isUpdating = true);
    try {
      final db = await DatabaseHelper.instance.database;
      await _templateService.setAsDefault(db, template.id!);
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${template.name} establecida como predeterminada'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al establecer plantilla predeterminada: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _duplicateTemplate(DocumentTemplate template) async {
    final nameController = TextEditingController(
      text: '${template.name} (Copia)',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicar Plantilla'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nombre de la copia'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Duplicar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _templateService.duplicateTemplate(
          db,
          template.id!,
          nameController.text.trim(),
        );
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plantilla duplicada exitosamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al duplicar plantilla: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _deleteTemplate(DocumentTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Plantilla'),
        content: Text(
          '¿Está seguro de eliminar la plantilla "${template.name}"?',
        ),
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

    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        await _templateService.deleteTemplate(db, template.id!);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Plantilla eliminada')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar plantilla: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _showTemplateDialog(DocumentTemplate? template) async {
    final nameController = TextEditingController(text: template?.name ?? '');
    final descriptionController = TextEditingController(
      text: template?.description ?? '',
    );
    final htmlController = TextEditingController(
      text: template?.htmlContent ?? '',
    );
    final typeController = TextEditingController(
      text: template?.templateType ?? 'invoice',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template == null ? 'Nueva Plantilla' : 'Editar Plantilla'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeController,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  hintText: 'invoice, quote, purchase_order',
                ),
                enabled: template == null,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: htmlController,
                decoration: const InputDecoration(labelText: 'Contenido HTML'),
                maxLines: 10,
              ),
              const SizedBox(height: 8),
              const Text(
                'Variables disponibles: {{company_name}}, {{document_number}}, {{customer_name}}, etc.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
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

    if (!mounted) return;
    if (result == true) {
      setState(() => _isUpdating = true);
      try {
        final db = await DatabaseHelper.instance.database;
        final companyId = await DatabaseHelper.instance
            .obtenerEmpresaActivaId();

        final newTemplate = DocumentTemplate(
          id: template?.id,
          companyId: template?.companyId ?? companyId,
          templateType: typeController.text.trim(),
          name: nameController.text.trim(),
          description: descriptionController.text.trim(),
          htmlContent: htmlController.text.trim(),
          isDefault: template?.isDefault ?? false,
          createdAt: template?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );

        if (template == null) {
          await _templateService.createTemplate(db, newTemplate);
        } else {
          await _templateService.updateTemplate(db, newTemplate);
        }

        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                template == null ? 'Plantilla creada' : 'Plantilla actualizada',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al guardar plantilla: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isUpdating = false);
      }
    }
  }

  void _showTemplateDetails(DocumentTemplate template) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(template.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tipo: ${template.templateType}'),
              const SizedBox(height: 8),
              Text('Descripción: ${template.description}'),
              const SizedBox(height: 8),
              const Text(
                'Variables disponibles:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...DocumentTemplate.availableVariables.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Text('${entry.key}: ${entry.value}'),
                ),
              ),
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

  Future<void> _showPdfDesignDialog() async {
    final current = await PdfLayoutSettingsService.instance.load();
    if (!mounted) return;
    var paper = current.paperSize;
    var showLogo = current.showLogo;
    var showQr = current.showInternalQr;
    final footer = TextEditingController(text: current.footerText);
    final signature = TextEditingController(text: current.signatureLabel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Diseño de documentos PDF'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: paper,
                    decoration: const InputDecoration(
                      labelText: 'Tamaño de página',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'a4', child: Text('A4')),
                      DropdownMenuItem(value: 'letter', child: Text('Carta')),
                    ],
                    onChanged: (v) {
                      if (v != null) setD(() => paper = v);
                    },
                  ),
                  SwitchListTile(
                    value: showLogo,
                    onChanged: (v) => setD(() => showLogo = v),
                    title: const Text('Mostrar logo de la empresa'),
                  ),
                  SwitchListTile(
                    value: showQr,
                    onChanged: (v) => setD(() => showQr = v),
                    title: const Text('QR de trazabilidad interna'),
                    subtitle: const Text(
                      'No reemplaza CUFE/QR DIAN cuando aplique.',
                    ),
                  ),
                  TextField(
                    controller: footer,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Pie de página',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: signature,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta del bloque de firma',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await PdfLayoutSettingsService.instance.save(
      PdfLayoutSettings(
        paperSize: paper,
        showLogo: showLogo,
        showInternalQr: showQr,
        footerText: footer.text.trim(),
        signatureLabel: signature.text.trim().isEmpty
            ? 'Responsable / autorizado'
            : signature.text.trim(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Diseño PDF actualizado.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plantillas de Documentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.design_services_outlined),
            onPressed: _showPdfDesignDialog,
            tooltip: 'Diseño PDF: tamaño, logo, QR y firma',
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
          : _templates.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No hay plantillas configuradas',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crea plantillas para facturas, cotizaciones y más',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getTemplateTypeColor(
                        template.templateType,
                      ),
                      child: Icon(
                        _getTemplateTypeIcon(template.templateType),
                        color: Colors.white,
                      ),
                    ),
                    title: Text(template.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(template.description),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (template.isDefault)
                              const Chip(
                                label: Text('Predeterminada'),
                                backgroundColor: Colors.green,
                                labelStyle: TextStyle(color: Colors.white),
                                visualDensity: VisualDensity.compact,
                              ),
                            const SizedBox(width: 8),
                            Text(
                              _getTemplateTypeLabel(template.templateType),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
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
                                case 'view':
                                  _showTemplateDetails(template);
                                  break;
                                case 'edit':
                                  _showTemplateDialog(template);
                                  break;
                                case 'duplicate':
                                  _duplicateTemplate(template);
                                  break;
                                case 'default':
                                  _setAsDefault(template);
                                  break;
                                case 'delete':
                                  _deleteTemplate(template);
                                  break;
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'view',
                                child: Row(
                                  children: [
                                    Icon(Icons.visibility),
                                    SizedBox(width: 8),
                                    Text('Ver detalles'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit),
                                    SizedBox(width: 8),
                                    Text('Editar'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'duplicate',
                                child: Row(
                                  children: [
                                    Icon(Icons.copy),
                                    SizedBox(width: 8),
                                    Text('Duplicar'),
                                  ],
                                ),
                              ),
                              if (!template.isDefault)
                                const PopupMenuItem(
                                  value: 'default',
                                  child: Row(
                                    children: [
                                      Icon(Icons.star),
                                      SizedBox(width: 8),
                                      Text('Establecer como predeterminada'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'delete',
                                child: const Row(
                                  children: [
                                    Icon(Icons.delete, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text(
                                      'Eliminar',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isUpdating ? null : () => _showTemplateDialog(null),
        tooltip: 'Nueva Plantilla',
        child: const Icon(Icons.add),
      ),
    );
  }

  Color _getTemplateTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'invoice':
        return MerkaThemeTokens.navy600;
      case 'quote':
        return MerkaThemeTokens.gold500;
      case 'purchase_order':
        return MerkaThemeTokens.navy700;
      default:
        return MerkaThemeTokens.graphite600;
    }
  }

  IconData _getTemplateTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'invoice':
        return Icons.receipt_long;
      case 'quote':
        return Icons.request_quote;
      case 'purchase_order':
        return Icons.shopping_cart;
      default:
        return Icons.description;
    }
  }

  String _getTemplateTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'invoice':
        return 'Factura';
      case 'quote':
        return 'Cotización';
      case 'purchase_order':
        return 'Orden de Compra';
      default:
        return type;
    }
  }
}
