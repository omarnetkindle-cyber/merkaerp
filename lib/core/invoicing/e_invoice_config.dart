// ============================================================
// e_invoice_config.dart
// Configuración de facturación electrónica por país
// ============================================================

class EInvoiceConfig {
  final String countryCode;
  final String countryName;
  final String invoiceFormat; // UBL 2.1, DIAN, SAT, etc.
  final String taxIdLabel; // NIT, RFC, RUC, etc.
  final String taxIdRegex;
  final List<String> requiredFields;
  final Map<String, dynamic> defaultSettings;

  const EInvoiceConfig({
    required this.countryCode,
    required this.countryName,
    required this.invoiceFormat,
    required this.taxIdLabel,
    required this.taxIdRegex,
    required this.requiredFields,
    required this.defaultSettings,
  });

  /// Configuraciones predefinidas por país
  static const Map<String, EInvoiceConfig> countryConfigs = {
    'CO': EInvoiceConfig(
      countryCode: 'CO',
      countryName: 'Colombia',
      invoiceFormat: 'UBL 2.1 DIAN',
      taxIdLabel: 'NIT',
      taxIdRegex: r'^\d{9,15}$',
      requiredFields: [
        'invoice_number',
        'issue_date',
        'supplier_nit',
        'supplier_name',
        'customer_nit',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'COP',
        'tax_rate': 0.19,
        'resolution_prefix': 'SETT',
      },
    ),
    'MX': EInvoiceConfig(
      countryCode: 'MX',
      countryName: 'México',
      invoiceFormat: 'CFDI SAT',
      taxIdLabel: 'RFC',
      taxIdRegex: r'^[A-Z&Ñ]{3,4}[0-9]{2}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])[A-Z0-9]{3}$',
      requiredFields: [
        'uuid',
        'issue_date',
        'supplier_rfc',
        'supplier_name',
        'customer_rfc',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'MXN',
        'tax_rate': 0.16,
        'cfdi_version': '4.0',
      },
    ),
    'PE': EInvoiceConfig(
      countryCode: 'PE',
      countryName: 'Perú',
      invoiceFormat: 'UBL 2.1 SUNAT',
      taxIdLabel: 'RUC',
      taxIdRegex: r'^\d{11}$',
      requiredFields: [
        'invoice_number',
        'issue_date',
        'supplier_ruc',
        'supplier_name',
        'customer_ruc',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'PEN',
        'tax_rate': 0.18,
        'series': 'F001',
      },
    ),
    'CL': EInvoiceConfig(
      countryCode: 'CL',
      countryName: 'Chile',
      invoiceFormat: 'SII',
      taxIdLabel: 'RUT',
      taxIdRegex: r'^\d{7,8}-[\dKk]$',
      requiredFields: [
        'folio',
        'issue_date',
        'supplier_rut',
        'supplier_name',
        'customer_rut',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'CLP',
        'tax_rate': 0.19,
      },
    ),
    'AR': EInvoiceConfig(
      countryCode: 'AR',
      countryName: 'Argentina',
      invoiceFormat: 'AFIP',
      taxIdLabel: 'CUIT',
      taxIdRegex: r'^\d{11}$',
      requiredFields: [
        'cae',
        'cae_expiration',
        'issue_date',
        'supplier_cuit',
        'supplier_name',
        'customer_cuit',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'ARS',
        'tax_rate': 0.21,
        'document_type': '01',
      },
    ),
    'BR': EInvoiceConfig(
      countryCode: 'BR',
      countryName: 'Brasil',
      invoiceFormat: 'NF-e',
      taxIdLabel: 'CNPJ',
      taxIdRegex: r'^\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}$',
      requiredFields: [
        'chave_nfe',
        'issue_date',
        'supplier_cnpj',
        'supplier_name',
        'customer_cnpj',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'BRL',
        'tax_rate': 0.17,
        'environment': 'producao',
      },
    ),
    'EC': EInvoiceConfig(
      countryCode: 'EC',
      countryName: 'Ecuador',
      invoiceFormat: 'SRI',
      taxIdLabel: 'RUC',
      taxIdRegex: r'^\d{13}$',
      requiredFields: [
        'clave_acceso',
        'issue_date',
        'supplier_ruc',
        'supplier_name',
        'customer_ruc',
        'customer_name',
        'total',
        'tax_amount',
      ],
      defaultSettings: {
        'currency': 'USD',
        'tax_rate': 0.12,
      },
    ),
    'US': EInvoiceConfig(
      countryCode: 'US',
      countryName: 'Estados Unidos',
      invoiceFormat: 'Standard',
      taxIdLabel: 'EIN',
      taxIdRegex: r'^\d{2}-\d{7}$',
      requiredFields: [
        'invoice_number',
        'issue_date',
        'supplier_name',
        'customer_name',
        'total',
      ],
      defaultSettings: {
        'currency': 'USD',
        'tax_rate': 0.0,
      },
    ),
  };

  /// Obtiene configuración por código de país
  static EInvoiceConfig? getConfig(String countryCode) {
    return countryConfigs[countryCode.toUpperCase()];
  }

  /// Valida un ID fiscal según el país
  bool validateTaxId(String taxId) {
    final regex = RegExp(taxIdRegex);
    return regex.hasMatch(taxId);
  }

  /// Formatea un ID fiscal según el país
  String formatTaxId(String taxId) {
    switch (countryCode) {
      case 'BR':
        // Formato CNPJ: XX.XXX.XXX/XXXX-XX
        if (taxId.length == 14) {
          return '${taxId.substring(0, 2)}.${taxId.substring(2, 5)}.${taxId.substring(5, 8)}/${taxId.substring(8, 12)}-${taxId.substring(12)}';
        }
        break;
      case 'CL':
        // Formato RUT: XXXXXXXX-X
        if (taxId.contains('-')) return taxId;
        if (taxId.length == 9) {
          return '${taxId.substring(0, 8)}-${taxId.substring(8)}';
        }
        break;
      case 'US':
        // Formato EIN: XX-XXXXXXX
        if (taxId.contains('-')) return taxId;
        if (taxId.length == 9) {
          return '${taxId.substring(0, 2)}-${taxId.substring(2)}';
        }
        break;
    }
    return taxId;
  }

  /// Obtiene la tasa de impuesto por defecto
  double get defaultTaxRate => defaultSettings['tax_rate'] as double? ?? 0.0;

  /// Obtiene la moneda por defecto
  String get defaultCurrency => defaultSettings['currency'] as String? ?? 'USD';
}
