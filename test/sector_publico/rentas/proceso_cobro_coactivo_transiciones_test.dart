import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/rentas/models/proceso_cobro_coactivo.dart';
import 'package:merka_erp/core/currency/public_sector_money.dart';

ProcesoCobroCoactivo _proceso(EtapaCobroCoactivo etapa) => ProcesoCobroCoactivo(
  id: 'cc-1',
  entidadId: 'ent-1',
  numeroProceso: 'CC-1',
  liquidacionId: 'liq-1',
  numeroLiquidacion: 'LIQ-1',
  deudorId: 'deudor-1',
  deudorNombre: 'Deudor',
  valorDeuda: publicMoneyFromMajor('1000'),
  valorRecuperado: publicMoneyZero(),
  saldoPendiente: publicMoneyFromMajor('1000'),
  etapaActual: etapa,
  estado: EstadoProceso.enTramite,
  fechaInicio: DateTime(2026, 1, 1),
);

void main() {
  test('la ruta ordinaria de cobro coactivo no permite saltar etapas', () {
    final mandamiento = _proceso(EtapaCobroCoactivo.mandamientoPago);
    expect(
      mandamiento.puedeAvanzarA(EtapaCobroCoactivo.embargoSecuestro),
      isTrue,
    );
    expect(mandamiento.puedeAvanzarA(EtapaCobroCoactivo.remate), isFalse);
    expect(
      () => mandamiento.avanzarEtapa(EtapaCobroCoactivo.remate),
      throwsStateError,
    );
  });

  test('la prescripcion es un cierre excepcional con saldo pendiente', () {
    expect(
      _proceso(
        EtapaCobroCoactivo.embargoSecuestro,
      ).puedeAvanzarA(EtapaCobroCoactivo.prescripcion),
      isTrue,
    );
  });
}
