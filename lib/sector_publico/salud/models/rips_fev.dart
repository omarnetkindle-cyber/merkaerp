/// Representacion local del RIPS-JSON soporte de FEV en salud.
///
/// La estructura corresponde al Documento Tecnico 1 v003 (15-07-2026) de
/// la Resolucion 948 de 2026. La validacion MUV sigue siendo externa: esta
/// clase modela y valida las invariantes que pueden verificarse localmente.
library;

class RipsFevDocumento {
  const RipsFevDocumento({
    required this.numDocumentoIdObligado,
    required this.numFactura,
    required this.usuarios,
    this.tipoNota,
    this.numNota,
    this.cucon,
  });

  final String numDocumentoIdObligado;
  final String numFactura;
  final String? tipoNota;
  final String? numNota;
  final String? cucon;
  final List<Map<String, dynamic>> usuarios;

  Map<String, dynamic> toJson() => {
    'numDocumentoIdObligado': numDocumentoIdObligado,
    'numFactura': numFactura,
    'tipoNota': tipoNota,
    'numNota': numNota,
    'usuarios': usuarios,
  };
}
