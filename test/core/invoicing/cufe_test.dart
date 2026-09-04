import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/core/invoicing/cufe.dart';

void main() {
  test('computeDianCufe coincide con el ejemplo DIAN Anexo 1.9', () {
    final input = DianCufeInput(
      numeroFactura: '323200000129',
      fechaFactura: '2019-01-16',
      horaFactura: '10:53:10-05:00',
      valorFacturaSinImpuestos: '1500000.00',
      valorIva: '285000.00',
      valorImpuestoConsumo: '0.00',
      valorIca: '0.00',
      valorTotal: '1785000.00',
      nitFacturador: '700085371',
      numeroAdquiriente: '800199436',
      claveTecnica: '693ff6f2a553c3646a063436fd4dd9ded0311471',
      tipoAmbiente: '1',
    );

    expect(
      input.seed(),
      '3232000001292019-01-1610:53:10-05:001500000.0001285000.00040.00030.001785000.00700085371800199436693ff6f2a553c3646a063436fd4dd9ded03114711',
    );
    expect(
      computeDianCufe(input),
      '8bb918b19ba22a694f1da11c643b5e9de39adf60311cf179179e9b33381030bcd4c3c3f156c506ed5908f9276f5bd9b4',
    );
  });

  test('normaliza valores monetarios truncando a dos decimales', () {
    final input = DianCufeInput(
      numeroFactura: 'FE-1',
      fechaFactura: '2026-08-13',
      horaFactura: '10:00:00-05:00',
      valorFacturaSinImpuestos: '100.999',
      valorIva: '',
      valorImpuestoConsumo: '0',
      valorIca: '0.009',
      valorTotal: '100.99',
      nitFacturador: '900.123.456-7',
      numeroAdquiriente: '1.234.567',
      claveTecnica: 'abc',
      tipoAmbiente: '2',
    );

    expect(
      input.seed(),
      'FE-12026-08-1310:00:00-05:00100.99010.00040.00030.00100.9990012345671234567abc2',
    );
  });
}
