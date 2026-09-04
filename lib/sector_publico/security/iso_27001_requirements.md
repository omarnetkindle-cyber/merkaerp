# Seguridad, Gobierno Digital y cumplimiento configurable — MerkaERP Público

> Documento técnico de referencia. MerkaERP implementa controles y parámetros que apoyan el cumplimiento; la entidad conserva la responsabilidad de adoptar sus políticas, instrumentos, responsables, términos, TRD/TVD y demás decisiones institucionales aplicables.

## 1. Seguridad de la información

MerkaERP Público adopta controles compatibles con buenas prácticas de ISO/IEC 27001:2022 sin afirmar que el software, por sí solo, otorgue o sustituya una certificación ISO. Si un proceso contractual exige certificación o controles adicionales, estos deben acreditarse por la organización y su infraestructura.

Controles soportados o previstos en la plataforma:

- mínimo privilegio y segregación de funciones;
- MFA para operaciones sensibles cuando el despliegue lo habilite;
- almacenamiento seguro de secretos y credenciales por entidad/empresa;
- TLS/HTTPS obligatorio para servicios remotos;
- auditoría de operaciones críticas e integridad de registros;
- respaldo integral de SQLite + repositorio documental, verificación SHA-256, restauración y rollback;
- cifrado autenticado de respaldos remotos;
- clasificación y reserva documental con control de acceso en capa de servicio;
- bloqueo de operaciones externas cuando no exista una integración real configurada (*fail-closed*);
- separación estricta entre familias MerkaERP Comercial y MerkaERP Público mediante licencia firmada.

## 2. Política de Gobierno Digital

La configuración institucional debe poder ajustarse a la Política de Gobierno Digital vigente, al Manual de Gobierno Digital y a los lineamientos que resulten aplicables a cada entidad. MerkaERP no fija valores institucionales que legalmente deban ser definidos o aprobados por la entidad.

La plataforma facilita:

- interoperabilidad mediante conectores configurables y HTTPS;
- trazabilidad y auditoría;
- gestión de datos y documentos;
- continuidad operativa;
- gestión de usuarios, roles y permisos;
- publicación/transmisión a servicios externos únicamente cuando la entidad configure el canal autorizado;
- exportaciones estructuradas para procesos que no dispongan de API institucional.

## 3. Gestión documental / SGDEA

El motor documental se diseña con referencia al marco archivístico colombiano vigente y al Modelo de Requisitos para SGDEA del Archivo General de la Nación.

La entidad configura dentro de MerkaERP, según corresponda:

- Programa de Gestión Documental (PGD);
- Plan Institucional de Archivos (PINAR);
- Cuadro de Clasificación Documental (CCD);
- Tablas de Retención Documental (TRD);
- Tablas de Valoración Documental (TVD);
- inventarios/FUID;
- banco terminológico;
- esquema de publicación;
- registro de activos de información;
- índice de información clasificada y reservada;
- calendarios, días no hábiles y términos de trámite;
- dependencias, series, subseries, tipos documentales y responsables;
- actos de adopción, convalidación, registro y evidencias que apliquen.

El software controla radicación, actuaciones, expedientes, versiones, integridad, firma/evidencia, transferencias, préstamos, ubicación física, disposición final y trazabilidad, pero no presume que un instrumento ha sido adoptado, convalidado o registrado: ese estado debe ser configurado y respaldado por la entidad.

## 4. Protección de datos, transparencia y reserva

La plataforma permite parametrizar niveles de acceso —público, restringido, clasificado, reservado y datos personales— y aplicar la restricción tanto en interfaz como en servicios. La entidad define la clasificación jurídica concreta, responsables, finalidades, políticas de tratamiento, tiempos de conservación y reglas de publicación.

## 5. Integraciones institucionales

DIAN/PTA, SECOP II, CHIP/CGN, SIIF, PILA, BPIN/MGA, transparencia, firma/sello de tiempo, correo, respaldos y APIs externas se administran desde el Centro de Integraciones. Las credenciales pertenecen a cada cliente y los secretos no se guardan en texto claro dentro de SQLite.

Un archivo generado localmente no se marca como “transmitido”, “publicado”, “firmado” o “pagado” solo por haber sido creado. El cambio de estado exige una respuesta/evidencia verificable del proveedor o una actuación explícita debidamente auditada.

## 6. Verificación antes de producción

Antes de distribuir una versión, el responsable técnico debe ejecutar como mínimo:

```text
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build windows
```

Para una liberación formal deben documentarse además firma de producción, versión, respaldo/restauración real, revisión de privacidad, salud de datos y configuración de infraestructura. El panel de Release Readiness no declara estos controles aprobados por defecto.
