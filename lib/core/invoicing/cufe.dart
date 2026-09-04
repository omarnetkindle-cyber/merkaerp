import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Datos canonicos exigidos por el Anexo Tecnico DIAN Factura Electronica
/// de Venta v1.9, seccion 11.2.
///
/// Fuente normativa:
/// DIAN, Resolucion 000165 de 2023, Anexo Tecnico FE v1.9, paginas 655-659:
/// CUFE = SHA-384(NumFac + FecFac + HorFac + ValFac + CodImp1 + ValImp1
/// + CodImp2 + ValImp2 + CodImp3 + ValImp3 + ValTot + NitOFE + NumAdq
/// + ClTec + TipoAmbiente).
class DianCufeInput {
  const DianCufeInput({
    required this.numeroFactura,
    required this.fechaFactura,
    required this.horaFactura,
    required this.valorFacturaSinImpuestos,
    required this.valorIva,
    required this.valorImpuestoConsumo,
    required this.valorIca,
    required this.valorTotal,
    required this.nitFacturador,
    required this.numeroAdquiriente,
    required this.claveTecnica,
    required this.tipoAmbiente,
  });

  final String numeroFactura;
  final String fechaFactura;
  final String horaFactura;
  final String valorFacturaSinImpuestos;
  final String valorIva;
  final String valorImpuestoConsumo;
  final String valorIca;
  final String valorTotal;
  final String nitFacturador;
  final String numeroAdquiriente;
  final String claveTecnica;
  final String tipoAmbiente;

  String seed() {
    return '${numeroFactura.trim()}'
        '${fechaFactura.trim()}'
        '${horaFactura.trim()}'
        '${_money(valorFacturaSinImpuestos)}'
        '01'
        '${_money(valorIva)}'
        '04'
        '${_money(valorImpuestoConsumo)}'
        '03'
        '${_money(valorIca)}'
        '${_money(valorTotal)}'
        '${_digits(nitFacturador)}'
        '${_digits(numeroAdquiriente)}'
        '${claveTecnica.trim()}'
        '${tipoAmbiente.trim()}';
  }
}

String computeDianCufe(DianCufeInput input) {
  return sha384.convert(utf8.encode(input.seed())).toString();
}

String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

String _money(String value) {
  final trimmed = value.trim().replaceAll(',', '.');
  if (trimmed.isEmpty) return '0.00';
  final parts = trimmed.split('.');
  final whole = parts.first.replaceAll(RegExp(r'[^0-9-]'), '');
  final decimals = parts.length > 1
      ? parts[1].replaceAll(RegExp(r'[^0-9]'), '')
      : '';
  return '${whole.isEmpty ? '0' : whole}.${decimals.padRight(2, '0').substring(0, 2)}';
}
