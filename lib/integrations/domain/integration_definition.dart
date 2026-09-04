import '../../licensing/domain/product_family.dart';

enum IntegrationFieldKind { text, secret, number, url, toggle, choice }

class IntegrationFieldDefinition {
  const IntegrationFieldDefinition({
    required this.key,
    required this.label,
    this.kind = IntegrationFieldKind.text,
    this.required = false,
    this.hint,
    this.options = const [],
    this.defaultValue,
  });

  final String key;
  final String label;
  final IntegrationFieldKind kind;
  final bool required;
  final String? hint;
  final List<String> options;
  final String? defaultValue;

  bool get isSecret => kind == IntegrationFieldKind.secret;
}

class IntegrationDefinition {
  const IntegrationDefinition({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.fields,
    this.families = const {ProductFamily.commercial, ProductFamily.publicSector},
    this.documentationHint,
  });

  final String key;
  final String name;
  final String description;
  final String category;
  final List<IntegrationFieldDefinition> fields;
  final Set<ProductFamily> families;
  final String? documentationHint;
}

class IntegrationRegistry {
  const IntegrationRegistry._();

  static const definitions = <IntegrationDefinition>[
    IntegrationDefinition(
      key: 'dian',
      name: 'Facturación electrónica DIAN / Proveedor tecnológico',
      category: 'Fiscal y cumplimiento',
      description: 'Configura el transporte real de facturación electrónica. Sin credenciales válidas MerkaERP permanece fail-closed y no marca documentos como transmitidos.',
      fields: [
        IntegrationFieldDefinition(key: 'mode', label: 'Modo', kind: IntegrationFieldKind.choice, required: true, options: ['PTA', 'DIRECTO'], defaultValue: 'PTA'),
        IntegrationFieldDefinition(key: 'base_url', label: 'URL del proveedor/API', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'software_id', label: 'Software ID / identificador', required: true),
        IntegrationFieldDefinition(key: 'software_pin', label: 'Software PIN / secreto', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'api_token', label: 'Token API del PTA (si aplica)', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'test_set_id', label: 'Test Set ID', hint: 'Cuando aplique en habilitación.'),
        IntegrationFieldDefinition(key: 'certificate_path', label: 'Ruta/alias del certificado digital'),
        IntegrationFieldDefinition(key: 'certificate_password', label: 'Contraseña del certificado', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
        IntegrationFieldDefinition(key: 'invoice_path', label: 'Ruta de envío de factura', defaultValue: '/invoices'),
        IntegrationFieldDefinition(key: 'enablement_path', label: 'Ruta de habilitación/pruebas', defaultValue: '/enablement'),
      ],
    ),
    IntegrationDefinition(
      key: 'whatsapp_meta',
      name: 'WhatsApp Business Cloud API',
      category: 'Comunicaciones',
      description: 'Envío oficial de mensajes, documentos, cotizaciones, estados de cuenta y recordatorios mediante Meta.',
      fields: [
        IntegrationFieldDefinition(key: 'api_version', label: 'Versión Graph API', required: true, defaultValue: 'v23.0'),
        IntegrationFieldDefinition(key: 'business_account_id', label: 'WhatsApp Business Account ID', required: true),
        IntegrationFieldDefinition(key: 'phone_number_id', label: 'Phone Number ID', required: true),
        IntegrationFieldDefinition(key: 'access_token', label: 'Access token', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'verify_token', label: 'Webhook verify token', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'app_secret', label: 'Meta App Secret', kind: IntegrationFieldKind.secret),
      ],
    ),
    IntegrationDefinition(
      key: 'smtp',
      name: 'Correo institucional / SMTP',
      category: 'Comunicaciones',
      description: 'Credenciales del buzón institucional para comunicaciones salientes y futura captura de correspondencia.',
      fields: [
        IntegrationFieldDefinition(key: 'host', label: 'Servidor SMTP', required: true),
        IntegrationFieldDefinition(key: 'port', label: 'Puerto', kind: IntegrationFieldKind.number, required: true, defaultValue: '587'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario', required: true),
        IntegrationFieldDefinition(key: 'password', label: 'Contraseña / App password', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'sender_email', label: 'Correo remitente', required: true),
        IntegrationFieldDefinition(key: 'sender_name', label: 'Nombre remitente'),
        IntegrationFieldDefinition(key: 'tls', label: 'Usar TLS', kind: IntegrationFieldKind.toggle, defaultValue: 'true'),
      ],
    ),
    IntegrationDefinition(
      key: 'payroll_electronic',
      name: 'Nómina electrónica / proveedor tecnológico',
      category: 'Fiscal y cumplimiento',
      description: 'Canal contratado por la empresa para transmitir documentos de nómina electrónica. MerkaERP prepara la información desde HRM y solo marca aceptación cuando el proveedor la confirma.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base del proveedor', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre del header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta de transmisión', required: true, defaultValue: '/payroll'),
        IntegrationFieldDefinition(key: 'status_path', label: 'Ruta de consulta', required: true, defaultValue: '/payroll/{id}'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'nequi',
      name: 'Nequi / proveedor autorizado',
      category: 'Pagos',
      description: 'Credenciales y endpoint del canal Nequi o del proveedor autorizado por el comercio. Las claves quedan en almacenamiento seguro del sistema operativo.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'endpoint', label: 'URL base del proveedor', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'api_key', label: 'API key / access token', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'client_id', label: 'Client ID', required: true),
        IntegrationFieldDefinition(key: 'client_secret', label: 'Client secret', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'webhook_secret', label: 'Secreto HMAC del webhook', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'pse',
      name: 'PSE / proveedor autorizado',
      category: 'Pagos',
      description: 'Credenciales del agregador/adquirente que provee el flujo PSE al comercio. No se presupone un endpoint único.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'endpoint', label: 'URL base del proveedor', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'api_key', label: 'API key / access token', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'merchant_id', label: 'Merchant ID', required: true),
        IntegrationFieldDefinition(key: 'webhook_secret', label: 'Secreto HMAC del webhook', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'stripe',
      name: 'Stripe',
      category: 'Pagos',
      description: 'Cobros y conciliación mediante una cuenta Stripe del cliente.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'secret_key', label: 'Secret key', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'webhook_secret', label: 'Webhook signing secret', kind: IntegrationFieldKind.secret),
      ],
    ),
    IntegrationDefinition(
      key: 'paypal',
      name: 'PayPal',
      category: 'Pagos',
      description: 'Credenciales OAuth de la cuenta PayPal Business del cliente.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'environment', label: 'Ambiente', kind: IntegrationFieldKind.choice, required: true, options: ['sandbox', 'live'], defaultValue: 'sandbox'),
        IntegrationFieldDefinition(key: 'client_id', label: 'Client ID', required: true),
        IntegrationFieldDefinition(key: 'client_secret', label: 'Client secret', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'webhook_id', label: 'Webhook ID'),
      ],
    ),
    IntegrationDefinition(
      key: 'mercadopago',
      name: 'Mercado Pago',
      category: 'Pagos',
      description: 'Credenciales de Mercado Pago para cobros y webhooks.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'access_token', label: 'Access token', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'public_key', label: 'Public key'),
        IntegrationFieldDefinition(key: 'webhook_secret', label: 'Webhook secret', kind: IntegrationFieldKind.secret),
      ],
    ),
    IntegrationDefinition(
      key: 'custom_payment',
      name: 'Pasarela de pago personalizada',
      category: 'Pagos',
      description: 'Conector de checkout para un proveedor contratado por el comercio. Las credenciales permanecen en almacenamiento seguro y un HTTP 2xx solo confirma la creación de la operación, no el recaudo.',
      families: {ProductFamily.commercial},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base del proveedor', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre del header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta para crear el checkout', required: true, defaultValue: '/payments'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'cloud_backup',
      name: 'Respaldo remoto',
      category: 'Continuidad',
      description: 'Destino administrado por el cliente para almacenar respaldos cifrados fuera del equipo local.',
      fields: [
        IntegrationFieldDefinition(key: 'provider', label: 'Proveedor', kind: IntegrationFieldKind.choice, required: true, options: ['S3_COMPATIBLE', 'AZURE_BLOB_SAS', 'WEBDAV'], defaultValue: 'S3_COMPATIBLE'),
        IntegrationFieldDefinition(key: 'endpoint', label: 'Endpoint', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'bucket', label: 'Bucket / contenedor / ruta', required: true),
        IntegrationFieldDefinition(key: 'access_key', label: 'Access key / usuario', kind: IntegrationFieldKind.secret, hint: 'Requerido para S3-compatible y WebDAV.'),
        IntegrationFieldDefinition(key: 'secret_key', label: 'Secret key / contraseña', kind: IntegrationFieldKind.secret, hint: 'Requerido para S3-compatible y WebDAV.'),
        IntegrationFieldDefinition(key: 'region', label: 'Región S3', defaultValue: 'us-east-1'),
        IntegrationFieldDefinition(key: 'session_token', label: 'Session token S3 (opcional)', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'sas_token', label: 'SAS de Azure Blob (opcional)', kind: IntegrationFieldKind.secret, hint: 'Use un SAS limitado al contenedor y solo con los permisos necesarios.'),
        IntegrationFieldDefinition(key: 'encryption_passphrase', label: 'Clave de cifrado de respaldos', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'retention_count', label: 'Cantidad de respaldos locales a conservar', kind: IntegrationFieldKind.number, defaultValue: '30'),
      ],
    ),
    IntegrationDefinition(
      key: 'trm_source',
      name: 'Fuente de TRM / tasas',
      category: 'Finanzas',
      description: 'Fuente externa configurada por la organización. MerkaERP no inventa tasas si la fuente no está disponible.',
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL API', kind: IntegrationFieldKind.url, required: true, hint: 'Puede incluir los parámetros de consulta que exija la fuente.'),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, options: ['NONE', 'BEARER', 'API_KEY'], defaultValue: 'NONE'),
        IntegrationFieldDefinition(key: 'api_key', label: 'API key / token', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'api_key_header', label: 'Nombre del header API key', defaultValue: 'X-API-Key'),
        IntegrationFieldDefinition(key: 'json_path', label: 'Ruta JSON del valor', required: true, hint: 'Ej.: rates.COP'),
        IntegrationFieldDefinition(key: 'currency_code', label: 'Moneda origen', required: true, defaultValue: 'USD'),
        IntegrationFieldDefinition(key: 'base_currency', label: 'Moneda base', required: true, defaultValue: 'COP'),
      ],
    ),
    IntegrationDefinition(
      key: 'pila_operator',
      name: 'PILA / Operador de información',
      category: 'Sector Público',
      description: 'Canal del operador de información contratado por la entidad. MerkaERP genera la información localmente y solo registra transmisión cuando el servicio configurado responde satisfactoriamente.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base del operador', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre de header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta de transmisión', required: true, defaultValue: '/enviar'),
        IntegrationFieldDefinition(key: 'confirmation_path', label: 'Ruta de confirmación', required: true, defaultValue: '/confirmacion/{id}'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'bpin_service',
      name: 'BPIN / Banco de Programas y Proyectos',
      category: 'Sector Público',
      description: 'Interoperabilidad configurable con el canal BPIN/MGA que la entidad tenga autorizado. No se presupone una API pública de escritura.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base del servicio', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre de header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'project_path', label: 'Ruta de proyectos', required: true, defaultValue: '/proyectos'),
        IntegrationFieldDefinition(key: 'query_path', label: 'Ruta de consulta', required: true, defaultValue: '/proyectos/{codigo}'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'secop_ii',
      name: 'SECOP II / Colombia Compra Eficiente',
      category: 'Sector Público',
      description: 'Credenciales y endpoints institucionales para interoperabilidad contractual. La publicación permanece bloqueada hasta que la entidad configure un contrato de API válido.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base del servicio', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'service_path', label: 'Ruta de interoperabilidad', required: true, defaultValue: '/contratacion'),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre de header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'xroad_client_id', label: 'X-Road Client ID', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'socrata_app_token', label: 'App token de datos abiertos (opcional)', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'chip_cgn',
      name: 'CHIP / Contaduría General de la Nación',
      category: 'Sector Público',
      description: 'Configura el canal de intercambio institucional para reportes CHIP cuando la entidad disponga de un servicio autorizado. La generación local de reportes sigue funcionando sin transmitir.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL del servicio', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre de header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta de transmisión', defaultValue: '/reportes'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'siif_nacion',
      name: 'SIIF Nación / Interoperabilidad financiera',
      category: 'Sector Público',
      description: 'Canal configurable para exportación o interoperabilidad SIIF cuando la entidad y su nivel de gobierno cuenten con acceso autorizado.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL del servicio', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / nombre de header'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / API key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta de transmisión', defaultValue: '/reportes'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'transparency_portal',
      name: 'Portal de transparencia / publicación',
      category: 'Sector Público',
      description: 'Endpoint institucional configurado por la entidad para publicación o interoperabilidad. No se incluye una URL ficticia.',
      families: {ProductFamily.publicSector},
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL institucional', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'api_key', label: 'API key / token', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'publication_path', label: 'Ruta de publicación', required: true),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'signature_provider',
      name: 'Firma digital / sello de tiempo',
      category: 'Gestión documental',
      description: 'Proveedor de firma, certificado o sellado de tiempo de la organización para documentos electrónicos.',
      fields: [
        IntegrationFieldDefinition(key: 'provider_name', label: 'Proveedor', required: true),
        IntegrationFieldDefinition(key: 'base_url', label: 'URL API', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'client_id', label: 'Client ID / usuario', required: true),
        IntegrationFieldDefinition(key: 'client_secret', label: 'Client secret / contraseña', kind: IntegrationFieldKind.secret, required: true),
        IntegrationFieldDefinition(key: 'certificate_alias', label: 'Alias del certificado'),
        IntegrationFieldDefinition(key: 'submission_path', label: 'Ruta de solicitud de firma/sello', defaultValue: '/signatures'),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
    IntegrationDefinition(
      key: 'external_api',
      name: 'API externa personalizada',
      category: 'Interoperabilidad',
      description: 'Conector genérico para sistemas de terceros controlados por la organización.',
      fields: [
        IntegrationFieldDefinition(key: 'base_url', label: 'URL base', kind: IntegrationFieldKind.url, required: true),
        IntegrationFieldDefinition(key: 'auth_type', label: 'Autenticación', kind: IntegrationFieldKind.choice, required: true, options: ['BEARER', 'API_KEY', 'BASIC', 'NONE'], defaultValue: 'BEARER'),
        IntegrationFieldDefinition(key: 'username', label: 'Usuario / key name'),
        IntegrationFieldDefinition(key: 'credential', label: 'Token / contraseña / key', kind: IntegrationFieldKind.secret),
        IntegrationFieldDefinition(key: 'health_path', label: 'Ruta de verificación', defaultValue: '/health'),
      ],
    ),
  ];

  static List<IntegrationDefinition> forFamily(ProductFamily family) =>
      definitions.where((definition) => definition.families.contains(family)).toList(growable: false);

  static IntegrationDefinition byKey(String key) => definitions.firstWhere((definition) => definition.key == key);
}
