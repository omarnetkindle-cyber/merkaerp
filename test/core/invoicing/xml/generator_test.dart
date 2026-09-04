import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/invoicing/xml/generator.dart';

void main() {
  test('incluye CUFE con schemeName CUFE-SHA384 y ambiente', () {
    final invoiceData = _invoiceData();
    final xml = XmlInvoiceGenerator.generateInvoiceXml(
      cufe: 'ABCDEF123',
      invoiceData: invoiceData,
    );

    expect(
      xml.contains(
        '<cbc:UUID schemeID="2" schemeName="CUFE-SHA384">ABCDEF123</cbc:UUID>',
      ),
      isTrue,
    );
  });

  test('omite CUFE cuando no se proporciona', () {
    final xml = XmlInvoiceGenerator.generateInvoiceXml(
      cufe: null,
      invoiceData: _invoiceData(),
    );

    expect(xml.contains('schemeName="CUFE-SHA384"'), isFalse);
  });

  test('estructura UBL DIAN principal presente', () {
    final xml = XmlInvoiceGenerator.generateInvoiceXml(
      cufe: null,
      invoiceData: _invoiceData(),
    );

    expect(
      xml.contains(
        'xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"',
      ),
      isTrue,
    );
    expect(
      xml.contains('<cbc:UBLVersionID>UBL 2.1</cbc:UBLVersionID>'),
      isTrue,
    );
    expect(
      xml.contains(
        '<cbc:CustomizationID>DIAN 2.1: Factura Electronica de Venta</cbc:CustomizationID>',
      ),
      isTrue,
    );
    expect(
      xml.contains('<cbc:ProfileExecutionID>2</cbc:ProfileExecutionID>'),
      isTrue,
    );
    expect(xml.contains('<cbc:ID>FE-000003</cbc:ID>'), isTrue);
    expect(xml.contains('<cbc:IssueDate>2026-07-11</cbc:IssueDate>'), isTrue);
    expect(
      xml.contains('<cbc:IssueTime>15:22:24-05:00</cbc:IssueTime>'),
      isTrue,
    );
    expect(
      xml.contains('<cbc:DocumentCurrencyCode>COP</cbc:DocumentCurrencyCode>'),
      isTrue,
    );
    expect(xml.contains('<cac:AccountingSupplierParty>'), isTrue);
    expect(xml.contains('<cac:AccountingCustomerParty>'), isTrue);
    expect(xml.contains('<cac:LegalMonetaryTotal>'), isTrue);
  });

  test('incluye impuestos y lineas con montos en COP', () {
    final xml = XmlInvoiceGenerator.generateInvoiceXml(
      cufe: null,
      invoiceData: _invoiceData(),
    );

    expect(xml.contains('<cbc:ID>01</cbc:ID>'), isTrue);
    expect(xml.contains('<cbc:Name>IVA</cbc:Name>'), isTrue);
    expect(
      xml.contains('<cbc:TaxAmount currencyID="COP">190.00</cbc:TaxAmount>'),
      isTrue,
    );
    expect(
      xml.contains(
        '<cbc:LineExtensionAmount currencyID="COP">1000.00</cbc:LineExtensionAmount>',
      ),
      isTrue,
    );
    expect(
      xml.contains('<cbc:Description>Producto prueba</cbc:Description>'),
      isTrue,
    );
  });
}

Map<String, dynamic> _invoiceData() {
  return {
    'invoice_number': 'FE-000003',
    'issue_date': '2026-07-11',
    'issue_time': '15:22:24-05:00',
    'profile_execution_id': '2',
    'currency': 'COP',
    'supplier': {'nit': '900123456', 'name': 'Mi Empresa SAS'},
    'customer': {'nit': '123456789', 'name': 'Cliente Prueba'},
    'subtotal': '1000.00',
    'tax_exclusive': '1000.00',
    'total': '1190.00',
    'tax_totals': [
      {
        'code': '01',
        'name': 'IVA',
        'taxable_amount': '1000.00',
        'amount': '190.00',
        'percent': '19.00',
      },
    ],
    'lines': [
      {
        'id': 1,
        'quantity': '1',
        'unit_code': 'NIU',
        'unit_price': '1000.00',
        'total': '1000.00',
        'description': 'Producto prueba',
        'taxes': [
          {
            'code': '01',
            'name': 'IVA',
            'taxable_amount': '1000.00',
            'amount': '190.00',
            'percent': '19.00',
          },
        ],
      },
    ],
  };
}
