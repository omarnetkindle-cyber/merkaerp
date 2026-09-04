// Result enums and data types for DianTransmissionClient
//
// These types are intentionally simple and serializable-friendly so UIs
// and logging can consume them easily.

enum ConfigStatus { notConfigured, configuredPartial, configuredComplete }

enum ConnectivityStatus { notChecked, notConfigured, notConnected, connected, unauthorized, error }

enum TransmissionStatus { notConfigured, queued, submitted, acceptedByPta, rejectedByPta, simulated, error }

enum EnablementStatus { notImplemented, queued, success, failed, simulated }

class ConnectionCheckResult {
  final ConnectivityStatus status;
  final String? message;
  final DateTime timestamp;

  ConnectionCheckResult({
    required this.status,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class TransmissionResult {
  final TransmissionStatus status;
  final String message;
  final DateTime timestamp;
  final String? externalId;
  final Map<String, dynamic>? details;

  TransmissionResult({
    required this.status,
    required this.message,
    this.externalId,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class EnablementResult {
  final EnablementStatus status;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? details;

  EnablementResult({
    required this.status,
    required this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Abstract client interface for transmitting invoices to a Provider
/// Tecnológico Autorizado (PTA). Implementations may perform network I/O
/// or be local/no-op stubs used in offline/testing environments.
abstract class DianTransmissionClient {
  /// Check whether the minimal configuration is present locally.
  /// This should validate presence of dian_tech_key, dian_pin and dian_software_id
  /// (see caller responsibility note). It does NOT need to verify dian_resolution.
  Future<ConfigStatus> checkConfiguration();

  /// Check connectivity and certificate state with the PTA. Implementations
  /// may perform a lightweight remote check or return simulated values.
  Future<ConnectionCheckResult> checkConnectivity();

  /// Transmit an already-generated invoice (XML + CUFE) to the PTA.
  /// The client is responsible for returning a TransmissionResult that
  /// describes the PTA's acceptance/rejection or simulated state.
  Future<TransmissionResult> transmitInvoice({
    required int ventaId,
    required String xml,
    required String cufe,
    Map<String, dynamic>? metadata,
  });

  /// Send an enablement / test package (content is provided by caller).
  /// The parameter is the package content already read by the caller.
  Future<EnablementResult> sendEnablementPackage({
    required String packageContent,
    Map<String, dynamic>? metadata,
  });
}
