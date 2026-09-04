// ============================================================
// document_template.dart
// Modelo para plantillas de documentos personalizables
// ============================================================

import 'dart:convert';

class DocumentTemplate {
  final int? id;
  final int companyId;
  final String templateType; // invoice, quote, purchase_order, etc.
  final String name;
  final String description;
  final String htmlContent;
  final Map<String, dynamic>? cssStyles;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime? updatedAt;

  DocumentTemplate({
    this.id,
    required this.companyId,
    required this.templateType,
    required this.name,
    required this.description,
    required this.htmlContent,
    this.cssStyles,
    this.isDefault = false,
    required this.createdAt,
    this.updatedAt,
  });

  /// Variables disponibles para reemplazo
  static const Map<String, String> availableVariables = {
    // Empresa
    'company_name': 'Nombre de la empresa',
    'company_nit': 'NIT de la empresa',
    'company_address': 'Dirección de la empresa',
    'company_phone': 'Teléfono de la empresa',
    'company_email': 'Email de la empresa',
    
    // Documento
    'document_number': 'Número del documento',
    'document_date': 'Fecha del documento',
    'document_total': 'Total del documento',
    'document_subtotal': 'Subtotal del documento',
    'document_tax': 'Impuesto del documento',
    
    // Cliente
    'customer_name': 'Nombre del cliente',
    'customer_nit': 'NIT del cliente',
    'customer_address': 'Dirección del cliente',
    'customer_phone': 'Teléfono del cliente',
    'customer_email': 'Email del cliente',
    
    // Items
    'items_table': 'Tabla de items del documento',
  };

  DocumentTemplate copyWith({
    int? id,
    int? companyId,
    String? templateType,
    String? name,
    String? description,
    String? htmlContent,
    Map<String, dynamic>? cssStyles,
    bool? isDefault,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DocumentTemplate(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      templateType: templateType ?? this.templateType,
      name: name ?? this.name,
      description: description ?? this.description,
      htmlContent: htmlContent ?? this.htmlContent,
      cssStyles: cssStyles ?? this.cssStyles,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'template_type': templateType,
      'name': name,
      'description': description,
      'html_content': htmlContent,
      'css_styles': cssStyles != null ? jsonEncode(cssStyles) : null,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory DocumentTemplate.fromMap(Map<String, dynamic> map) {
    return DocumentTemplate(
      id: map['id'] as int?,
      companyId: map['company_id'] as int,
      templateType: map['template_type'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      htmlContent: map['html_content'] as String,
      cssStyles: map['css_styles'] != null
          ? jsonDecode(map['css_styles'] as String) as Map<String, dynamic>
          : null,
      isDefault: (map['is_default'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// Reemplaza variables en el contenido HTML
  String render(Map<String, dynamic> data) {
    String content = htmlContent;
    
    data.forEach((key, value) {
      final placeholder = '{{$key}}';
      content = content.replaceAll(placeholder, value.toString());
    });
    
    return content;
  }
}
