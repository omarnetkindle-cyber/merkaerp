class XmlInvoiceGenerator {
  /// Genera un XML UBL 2.1 local para Factura Electronica DIAN.
  ///
  /// Alcance: estructura local verificable, CUFE y bloques UBL principales.
  /// No firma digital ni transmite a DIAN; eso requiere certificado/proveedor.
  static String generateInvoiceXml({
    String? cufe,
    required Map<String, dynamic> invoiceData,
    DateTime? nowForIssueDate,
  }) {
    final id = invoiceData['invoice_number']?.toString() ?? '';
    final issueDate = _dateOnly(invoiceData['issue_date'], nowForIssueDate);
    final issueTime = _timeWithOffset(
      invoiceData['issue_time'],
      invoiceData['issue_date'],
    );
    final typeCode = invoiceData['type_code']?.toString() ?? '01';
    final currency = invoiceData['currency']?.toString() ?? 'COP';
    final profileExecutionID =
        invoiceData['profile_execution_id']?.toString() ?? '2';
    final supplier = _map(invoiceData['supplier']);
    final customer = _map(invoiceData['customer']);
    final lines = (invoiceData['lines'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>();
    final taxTotals = (invoiceData['tax_totals'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>();

    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"',
      )
      ..writeln(
        '         xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"',
      )
      ..writeln(
        '         xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"',
      )
      ..writeln(
        '         xmlns:ext="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2">',
      )
      ..writeln('  <cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>')
      ..writeln(
        '  <cbc:CustomizationID>DIAN 2.1: Factura Electronica de Venta</cbc:CustomizationID>',
      )
      ..writeln('  <cbc:ProfileID>DIAN 2.1</cbc:ProfileID>')
      ..writeln(
        '  <cbc:ProfileExecutionID>$profileExecutionID</cbc:ProfileExecutionID>',
      )
      ..writeln('  <cbc:ID>${_x(id)}</cbc:ID>')
      ..writeln('  <cbc:IssueDate>$issueDate</cbc:IssueDate>')
      ..writeln('  <cbc:IssueTime>$issueTime</cbc:IssueTime>');

    if (cufe != null && cufe.trim().isNotEmpty) {
      sb.writeln(
        '  <cbc:UUID schemeID="$profileExecutionID" schemeName="CUFE-SHA384">${_x(cufe)}</cbc:UUID>',
      );
    }

    sb
      ..writeln('  <cbc:InvoiceTypeCode>$typeCode</cbc:InvoiceTypeCode>')
      ..writeln(
        '  <cbc:DocumentCurrencyCode>$currency</cbc:DocumentCurrencyCode>',
      );

    _writeParty(
      sb,
      tag: 'AccountingSupplierParty',
      data: supplier,
      currency: currency,
    );
    _writeParty(
      sb,
      tag: 'AccountingCustomerParty',
      data: customer,
      currency: currency,
    );

    for (final tax in taxTotals) {
      _writeTaxTotal(sb, tax, currency);
    }

    sb.writeln('  <cac:LegalMonetaryTotal>');
    _moneyTag(sb, 'LineExtensionAmount', invoiceData['subtotal'], currency, 4);
    _moneyTag(
      sb,
      'TaxExclusiveAmount',
      invoiceData['tax_exclusive'] ?? invoiceData['subtotal'],
      currency,
      4,
    );
    _moneyTag(sb, 'TaxInclusiveAmount', invoiceData['total'], currency, 4);
    _moneyTag(
      sb,
      'PayableAmount',
      invoiceData['payable'] ?? invoiceData['total'],
      currency,
      4,
    );
    sb.writeln('  </cac:LegalMonetaryTotal>');

    for (final line in lines) {
      _writeLine(sb, line, currency);
    }

    sb.writeln('</Invoice>');
    return sb.toString();
  }

  static Map<dynamic, dynamic> _map(Object? value) {
    return value is Map ? value : const {};
  }

  static void _writeParty(
    StringBuffer sb, {
    required String tag,
    required Map<dynamic, dynamic> data,
    required String currency,
  }) {
    final nit = data['nit']?.toString() ?? data['document']?.toString() ?? '';
    final name = data['name']?.toString() ?? '';
    final taxSchemeId = data['tax_scheme_id']?.toString() ?? '01';
    final taxSchemeName = data['tax_scheme_name']?.toString() ?? 'IVA';
    sb
      ..writeln('  <cac:$tag>')
      ..writeln('    <cac:Party>')
      ..writeln('      <cac:PartyName>')
      ..writeln('        <cbc:Name>${_x(name)}</cbc:Name>')
      ..writeln('      </cac:PartyName>')
      ..writeln('      <cac:PartyTaxScheme>')
      ..writeln(
        '        <cbc:RegistrationName>${_x(name)}</cbc:RegistrationName>',
      )
      ..writeln('        <cbc:CompanyID>${_x(nit)}</cbc:CompanyID>')
      ..writeln('        <cac:TaxScheme>')
      ..writeln('          <cbc:ID>${_x(taxSchemeId)}</cbc:ID>')
      ..writeln('          <cbc:Name>${_x(taxSchemeName)}</cbc:Name>')
      ..writeln('        </cac:TaxScheme>')
      ..writeln('      </cac:PartyTaxScheme>')
      ..writeln('      <cac:PartyLegalEntity>')
      ..writeln(
        '        <cbc:RegistrationName>${_x(name)}</cbc:RegistrationName>',
      )
      ..writeln('      </cac:PartyLegalEntity>')
      ..writeln('    </cac:Party>')
      ..writeln('  </cac:$tag>');
  }

  static void _writeTaxTotal(
    StringBuffer sb,
    Map<dynamic, dynamic> tax,
    String currency,
  ) {
    final code = tax['code']?.toString() ?? '01';
    final name = tax['name']?.toString() ?? _taxName(code);
    final percent = _amount(tax['percent'] ?? '0.00');
    sb.writeln('  <cac:TaxTotal>');
    _moneyTag(sb, 'TaxAmount', tax['amount'], currency, 4);
    sb.writeln('    <cac:TaxSubtotal>');
    _moneyTag(sb, 'TaxableAmount', tax['taxable_amount'], currency, 6);
    _moneyTag(sb, 'TaxAmount', tax['amount'], currency, 6);
    sb
      ..writeln('      <cac:TaxCategory>')
      ..writeln('        <cbc:Percent>$percent</cbc:Percent>')
      ..writeln('        <cac:TaxScheme>')
      ..writeln('          <cbc:ID>$code</cbc:ID>')
      ..writeln('          <cbc:Name>${_x(name)}</cbc:Name>')
      ..writeln('        </cac:TaxScheme>')
      ..writeln('      </cac:TaxCategory>')
      ..writeln('    </cac:TaxSubtotal>')
      ..writeln('  </cac:TaxTotal>');
  }

  static void _writeLine(
    StringBuffer sb,
    Map<dynamic, dynamic> line,
    String currency,
  ) {
    final itemType = line['tipo_item']?.toString() ?? (line['unit_code'] == 'E48' || line['unit_code'] == 'SERV' ? 'servicio' : 'producto');
    final defaultUnitCode = itemType == 'servicio' ? 'E48' : 'NIU';
    final unitCode = line['unit_code']?.toString() ?? defaultUnitCode;
    sb
      ..writeln('  <cac:InvoiceLine>')
      ..writeln('    <cbc:ID>${_x(line['id']?.toString() ?? '')}</cbc:ID>')
      ..writeln(
        '    <cbc:InvoicedQuantity unitCode="${_x(unitCode)}">${line['quantity'] ?? 0}</cbc:InvoicedQuantity>',
      );
    _moneyTag(sb, 'LineExtensionAmount', line['total'], currency, 4);
    final taxes = (line['taxes'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>();
    for (final tax in taxes) {
      _writeTaxTotal(sb, tax, currency);
    }
    sb
      ..writeln('    <cac:Item>')
      ..writeln(
        '      <cbc:Description>${_x(line['description']?.toString() ?? '')}</cbc:Description>',
      )
      ..writeln('    </cac:Item>')
      ..writeln('    <cac:Price>');
    _moneyTag(sb, 'PriceAmount', line['unit_price'], currency, 6);
    sb
      ..writeln('    </cac:Price>')
      ..writeln('  </cac:InvoiceLine>');
  }

  static void _moneyTag(
    StringBuffer sb,
    String tag,
    Object? value,
    String currency,
    int indent,
  ) {
    final spaces = ' ' * indent;
    sb.writeln(
      '$spaces<cbc:$tag currencyID="$currency">${_amount(value)}</cbc:$tag>',
    );
  }

  static String _dateOnly(Object? issueRaw, DateTime? fallback) {
    final dt = _dateTime(issueRaw, fallback);
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  static String _timeWithOffset(Object? issueTime, Object? issueDate) {
    if (issueTime != null && issueTime.toString().trim().isNotEmpty) {
      return issueTime.toString();
    }
    final dt = _dateTime(issueDate, DateTime.now());
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}-05:00';
  }

  static DateTime _dateTime(Object? raw, DateTime? fallback) {
    if (raw is DateTime) return raw;
    if (raw != null) {
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.now();
  }

  static String _amount(Object? value) {
    final text = (value ?? '0').toString().replaceAll(',', '.').trim();
    if (text.isEmpty) return '0.00';
    final parts = text.split('.');
    final whole = parts.first.replaceAll(RegExp(r'[^0-9-]'), '');
    final decimals = parts.length > 1
        ? parts[1].replaceAll(RegExp(r'[^0-9]'), '')
        : '';
    return '${whole.isEmpty ? '0' : whole}.${decimals.padRight(2, '0').substring(0, 2)}';
  }

  static String _taxName(String code) {
    return switch (code) {
      '01' => 'IVA',
      '03' => 'ICA',
      '04' => 'INC',
      _ => 'Impuesto',
    };
  }

  static String _x(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
