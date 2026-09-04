// Legacy compatibility shim.
//
// MerkaERP no permite cambiar entre Comercial y Público desde la instalación.
// La familia de producto se obtiene exclusivamente de la licencia firmada.
import '../../licensing/domain/product_family.dart';
import '../../services/licencia_service.dart';

enum ModoOperacion { privada, publica }

class SelectorModoService {
  static Future<ModoOperacion?> obtenerModoActual() async {
    final licencia = await LicenciaService.instance.obtenerLicencia();
    if (licencia == null) return null;
    return licencia.productFamily == ProductFamily.publicSector
        ? ModoOperacion.publica
        : ModoOperacion.privada;
  }

  static Future<bool> tieneAutoridadReconfiguracion({
    required dynamic db,
    required String entidadId,
    required dynamic usuarioId,
  }) async => false;

  static Future<void> guardarModo({
    dynamic database,
    required String entidadId,
    required dynamic usuarioId,
    required ModoOperacion modo,
  }) async {
    throw StateError(
      'La familia MerkaERP Comercial/Público está fijada por la licencia firmada y no puede cambiarse desde la aplicación.',
    );
  }
}
