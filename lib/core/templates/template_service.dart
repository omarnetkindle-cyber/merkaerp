// ============================================================
// template_service.dart
// Servicio de gestión de plantillas de documentos
// ============================================================

import 'package:sqflite/sqflite.dart';
import 'document_template.dart';

class TemplateService {
  static final TemplateService instance = TemplateService._internal();
  
  TemplateService._internal();
  
  /// Crea las tablas necesarias para plantillas
  Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        template_type TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        html_content TEXT NOT NULL,
        css_styles TEXT,
        is_default INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    
    // Índices
    await db.execute('CREATE INDEX IF NOT EXISTS idx_templates_company ON document_templates(company_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_templates_type ON document_templates(template_type)');
    
    // Insertar plantillas por defecto
    await _insertDefaultTemplates(db);
  }
  
  /// Inserta plantillas por defecto
  Future<void> _insertDefaultTemplates(Database db) async {
    final defaultInvoiceTemplate = DocumentTemplate(
      companyId: 0, // 0 indica plantilla global
      templateType: 'invoice',
      name: 'Factura Estándar',
      description: 'Plantilla de factura por defecto',
      htmlContent: _getDefaultInvoiceTemplate(),
      isDefault: true,
      createdAt: DateTime.now(),
    );
    
    await db.insert(
      'document_templates',
      defaultInvoiceTemplate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    
    final defaultQuoteTemplate = DocumentTemplate(
      companyId: 0,
      templateType: 'quote',
      name: 'Cotización Estándar',
      description: 'Plantilla de cotización por defecto',
      htmlContent: _getDefaultQuoteTemplate(),
      isDefault: true,
      createdAt: DateTime.now(),
    );
    
    await db.insert(
      'document_templates',
      defaultQuoteTemplate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  
  /// Plantilla de factura por defecto
  String _getDefaultInvoiceTemplate() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Factura {{document_number}}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
    .header { display: flex; justify-content: space-between; margin-bottom: 30px; }
    .company-info { flex: 1; }
    .invoice-info { text-align: right; }
    .invoice-number { font-size: 24px; font-weight: bold; color: #0A2540; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background-color: #f5f5f5; }
    .total { text-align: right; font-size: 18px; font-weight: bold; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="header">
    <div class="company-info">
      <h1>{{company_name}}</h1>
      <p>NIT: {{company_nit}}</p>
      <p>{{company_address}}</p>
      <p>Tel: {{company_phone}}</p>
    </div>
    <div class="invoice-info">
      <div class="invoice-number">Factura #{{document_number}}</div>
      <p>Fecha: {{document_date}}</p>
    </div>
  </div>
  
  <h2>Cliente</h2>
  <p>{{customer_name}}</p>
  <p>NIT: {{customer_nit}}</p>
  <p>{{customer_address}}</p>
  
  <h2>Detalle</h2>
  {{items_table}}
  
  <div class="total">
    <p>Subtotal: {{document_subtotal}}</p>
    <p>Impuesto: {{document_tax}}</p>
    <p>Total: {{document_total}}</p>
  </div>
</body>
</html>
''';
  }
  
  /// Plantilla de cotización por defecto
  String _getDefaultQuoteTemplate() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Cotización {{document_number}}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
    .header { display: flex; justify-content: space-between; margin-bottom: 30px; }
    .company-info { flex: 1; }
    .quote-info { text-align: right; }
    .quote-number { font-size: 24px; font-weight: bold; color: #0A2540; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
    th { background-color: #f5f5f5; }
    .total { text-align: right; font-size: 18px; font-weight: bold; margin-top: 20px; }
    .validity { background-color: #fff3cd; padding: 10px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="header">
    <div class="company-info">
      <h1>{{company_name}}</h1>
      <p>NIT: {{company_nit}}</p>
      <p>{{company_address}}</p>
    </div>
    <div class="quote-info">
      <div class="quote-number">Cotización #{{document_number}}</div>
      <p>Fecha: {{document_date}}</p>
    </div>
  </div>
  
  <h2>Cliente</h2>
  <p>{{customer_name}}</p>
  <p>NIT: {{customer_nit}}</p>
  
  <h2>Detalle</h2>
  {{items_table}}
  
  <div class="total">
    <p>Subtotal: {{document_subtotal}}</p>
    <p>Impuesto: {{document_tax}}</p>
    <p>Total: {{document_total}}</p>
  </div>
  
  <div class="validity">
    <p><strong>Válida hasta:</strong> {{valid_until}}</p>
  </div>
</body>
</html>
''';
  }
  
  /// Crea una nueva plantilla
  Future<int> createTemplate(Database db, DocumentTemplate template) async {
    final id = await db.insert('document_templates', template.toMap());
    return id;
  }
  
  /// Obtiene una plantilla por ID
  Future<DocumentTemplate?> getTemplateById(Database db, int templateId) async {
    final maps = await db.query(
      'document_templates',
      where: 'id = ?',
      whereArgs: [templateId],
    );
    
    if (maps.isEmpty) return null;
    return DocumentTemplate.fromMap(maps.first);
  }
  
  /// Obtiene plantillas por empresa
  Future<List<DocumentTemplate>> getTemplatesByCompany(Database db, int companyId) async {
    final maps = await db.query(
      'document_templates',
      where: 'company_id = ? OR company_id = 0',
      whereArgs: [companyId],
      orderBy: 'is_default DESC, name ASC',
    );
    
    return maps.map((map) => DocumentTemplate.fromMap(map)).toList();
  }
  
  /// Obtiene plantillas por tipo
  Future<List<DocumentTemplate>> getTemplatesByType(Database db, String templateType) async {
    final maps = await db.query(
      'document_templates',
      where: 'template_type = ?',
      whereArgs: [templateType],
      orderBy: 'is_default DESC, name ASC',
    );
    
    return maps.map((map) => DocumentTemplate.fromMap(map)).toList();
  }
  
  /// Obtiene la plantilla por defecto para un tipo
  Future<DocumentTemplate?> getDefaultTemplate(Database db, String templateType) async {
    final maps = await db.query(
      'document_templates',
      where: 'template_type = ? AND is_default = 1',
      whereArgs: [templateType],
      limit: 1,
    );
    
    if (maps.isEmpty) return null;
    return DocumentTemplate.fromMap(maps.first);
  }
  
  /// Actualiza una plantilla
  Future<void> updateTemplate(Database db, DocumentTemplate template) async {
    await db.update(
      'document_templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }
  
  /// Establece una plantilla como por defecto
  Future<void> setAsDefault(Database db, int templateId) async {
    final template = await getTemplateById(db, templateId);
    if (template == null) return;
    
    // Remover default de otras plantillas del mismo tipo
    await db.update(
      'document_templates',
      {'is_default': 0},
      where: 'template_type = ?',
      whereArgs: [template.templateType],
    );
    
    // Establecer nueva default
    await db.update(
      'document_templates',
      {'is_default': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [templateId],
    );
  }
  
  /// Elimina una plantilla
  Future<void> deleteTemplate(Database db, int templateId) async {
    await db.delete('document_templates', where: 'id = ?', whereArgs: [templateId]);
  }
  
  /// Duplica una plantilla
  Future<int> duplicateTemplate(Database db, int templateId, String newName) async {
    final original = await getTemplateById(db, templateId);
    if (original == null) return 0;
    
    final duplicate = original.copyWith(
      id: null,
      name: newName,
      isDefault: false,
      createdAt: DateTime.now(),
    );
    
    return await createTemplate(db, duplicate);
  }
  
  /// Renderiza un documento usando una plantilla
  String renderDocument(
    DocumentTemplate template,
    Map<String, dynamic> data,
  ) {
    return template.render(data);
  }
  
  /// Genera tabla de items HTML
  String generateItemsTable(List<Map<String, dynamic>> items) {
    final buffer = StringBuffer();
    buffer.writeln('<table>');
    buffer.writeln('<thead>');
    buffer.writeln('<tr>');
    buffer.writeln('<th>Descripción</th>');
    buffer.writeln('<th>Cantidad</th>');
    buffer.writeln('<th>Precio Unitario</th>');
    buffer.writeln('<th>Total</th>');
    buffer.writeln('</tr>');
    buffer.writeln('</thead>');
    buffer.writeln('<tbody>');
    
    for (final item in items) {
      buffer.writeln('<tr>');
      buffer.writeln('<td>${item['description'] ?? ''}</td>');
      buffer.writeln('<td>${item['quantity'] ?? 0}</td>');
      buffer.writeln('<td>${item['unit_price'] ?? 0}</td>');
      buffer.writeln('<td>${item['total'] ?? 0}</td>');
      buffer.writeln('</tr>');
    }
    
    buffer.writeln('</tbody>');
    buffer.writeln('</table>');
    
    return buffer.toString();
  }
}
