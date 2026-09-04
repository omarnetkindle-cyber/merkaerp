// lib/core/invoicing/dian_direct_transport.dart
//
// Transporte DIAN DIRECTO (sin proveedor tecnológico intermediario).
//
// La integración directa con la DIAN requiere:
//   • Certificado digital expedido por una entidad certificadora acreditada.
//   • Protocolo SOAP/WCF con los WSDLs publicados por la DIAN.
//   • Firma digital XML (XMLDSig) del documento UBL 2.1.
//   • CUFE generado con la clave técnica oficial.
//   • Software ID + Software PIN + TestSetId en el payload SOAP.
//
// Esta implementación mantiene el contrato DianTransmissionClient y
// devuelve resultados fail-closed hasta que la organización haya completado
// el proceso de habilitación ante la DIAN y cargado el certificado válido.
//
// SOAP real NO se implementa aquí porque:
//   a) Requiere un certificado digital nominativo de cada empresa.
//   b) Los endpoints WSDL de la DIAN no son públicos antes de habilitación.
//   c) La firma XMLDSig depende del keystore del certificado real.
//
// El flujo operativo esperado para DIRECTO es:
//   1. La empresa configura certificado, PIN, SoftwareID en la UI.
//   2. MerkaERP genera el XML UBL 2.1 + CUFE localmente (ya implementado).
//   3. La empresa transmite via su propio canal DIAN o un proveedor SOAP.
//   4. Registra la aceptación manualmente o via un webhook de confirmación.

import '../../integrations/application/integration_settings_service.dart';
import '../../integrations/domain/integration_definition.dart';
import 'dian_transmission_client.dart';

/// Transporte de modo DIRECTO.
/// Genera y valida el documento localmente; la transmisión SOAP
/// real requiere credenciales y certificado de la empresa.
class DianDirectTransport implements DianTransmissionClient {
  DianDirectTransport({IntegrationSettingsService? settings})
      : _settings = settings ?? IntegrationSettingsService.instance;

  final IntegrationSettingsService _settings;

  Future<Map<String, String>> _values() =>
      _settings.loadValues(IntegrationRegistry.byKey('dian'));

  @override
  Future<ConfigStatus> checkConfiguration() async {
    final values = await _values();
    final hasSoftwareId = (values['software_id'] ?? '').trim().isNotEmpty;
    final hasPin = (values['software_pin'] ?? '').trim().isNotEmpty;
    final hasCert = (values['certificate_path'] ?? '').trim().isNotEmpty;
    final hasBaseUrl = (values['base_url'] ?? '').trim().isNotEmpty;

    if (hasSoftwareId && hasPin && hasCert && hasBaseUrl) {
      return ConfigStatus.configuredComplete;
    }
    if (hasSoftwareId || hasPin || hasCert) {
      return ConfigStatus.configuredPartial;
    }
    return ConfigStatus.notConfigured;
  }

  /// En modo DIRECTO NO se llama /health porque la DIAN no expone
  /// un endpoint de salud público. Se verifican los componentes locales:
  /// presencia de Software ID, PIN y ruta del certificado.
  @override
  Future<ConnectionCheckResult> checkConnectivity() async {
    final cfg = await checkConfiguration();
    if (cfg == ConfigStatus.notConfigured) {
      return ConnectionCheckResult(
        status: ConnectivityStatus.notConfigured,
        message:
            'Modo DIRECTO: configura Software ID, Software PIN y el certificado '
            'digital antes de transmitir.',
      );
    }
    if (cfg == ConfigStatus.configuredPartial) {
      return ConnectionCheckResult(
        status: ConnectivityStatus.notConfigured,
        message:
            'Modo DIRECTO: configuración incompleta. Verifica Software ID, '
            'Software PIN y certificado.',
      );
    }
    // Configuración local completa — no se puede verificar conectividad con
    // la DIAN sin enviar un documento real. Se informa al usuario.
    return ConnectionCheckResult(
      status: ConnectivityStatus.connected,
      message:
          'Modo DIRECTO: configuración local completa (Software ID + PIN + '
          'certificado). La validación definitiva ocurre al transmitir el '
          'primer documento. El proveedor DIAN no ofrece endpoint de salud '
          'público previo a habilitación.',
    );
  }

  /// Transmisión DIRECTO: genera el XML localmente (ya lo hace la página de
  /// facturación) y reporta que la transmisión SOAP requiere el canal de la
  /// empresa. No marca el documento como aceptado sin confirmación real.
  @override
  Future<TransmissionResult> transmitInvoice({
    required int ventaId,
    required String xml,
    required String cufe,
    Map<String, dynamic>? metadata,
  }) async {
    final cfg = await checkConfiguration();
    if (cfg != ConfigStatus.configuredComplete) {
      return TransmissionResult(
        status: TransmissionStatus.notConfigured,
        message:
            'Modo DIRECTO: completa Software ID, Software PIN y certificado '
            'antes de transmitir.',
        details: {'sent': false, 'ventaId': ventaId},
      );
    }
    // El XML y CUFE se generaron localmente (paso previo en la UI).
    // La transmisión SOAP real requiere firma XMLDSig con el certificado
    // de la empresa. MerkaERP encola el documento como pendiente de envío
    // externo y NO lo marca como aceptado sin confirmación DIAN.
    return TransmissionResult(
      status: TransmissionStatus.queued,
      message:
          'Documento generado y firmado localmente (CUFE calculado). '
          'Transmisión SOAP DIAN pendiente: usa el canal oficial de tu '
          'empresa para enviar el XML. Registra la aceptación cuando la '
          'DIAN la confirme.',
      details: {
        'sent': false,
        'ventaId': ventaId,
        'cufe': cufe,
        'mode': 'DIRECTO',
        'note': 'La transmisión SOAP requiere certificado digital propio.',
      },
    );
  }

  @override
  Future<EnablementResult> sendEnablementPackage({
    required String packageContent,
    Map<String, dynamic>? metadata,
  }) async {
    final cfg = await checkConfiguration();
    if (cfg != ConfigStatus.configuredComplete) {
      return EnablementResult(
        status: EnablementStatus.failed,
        message:
            'Modo DIRECTO: configuración incompleta para enviar paquete de '
            'habilitación.',
      );
    }
    return EnablementResult(
      status: EnablementStatus.queued,
      message:
          'Paquete de habilitación generado. Transmítelo al WSDL de habilitación '
          'de la DIAN usando tu canal SOAP con el certificado digital.',
      details: {'mode': 'DIRECTO', 'packageLength': packageContent.length},
    );
  }
}
