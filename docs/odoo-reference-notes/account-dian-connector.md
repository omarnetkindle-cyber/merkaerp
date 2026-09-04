# Conector DIAN (estado y requisitos)

## Estado actual
- Se creó un scaffold funcional con las siguientes piezas dentro de `backend/src/modules/account/services/dian/`:
  - `Connector.js`: clase principal que orquesta generación, firmado y envío.
  - `xmlGenerator.js`: generador XML placeholder (no cumple XSD DIAN aún).
  - `signer.js`: stub que lanza error (firma no implementada; requiere certificado y clave privada).
  - `httpClient.js`: cliente HTTP básico usando `axios` (placeholder; DIAN puede requerir SOAP/envelope específco).
- Archivo de ejemplo de configuración: `backend/config/dian.config.example.json`.
- Test stub agregado: `backend/test/dian_connector_test.js`.

## Requisitos externos para completar la integración
1. Certificado digital de la entidad (P12/PFX) y su contraseña, o clave privada y certificado en PEM según el método elegido.
2. Esquemas (XSD) y especificaciones oficiales de la DIAN para facturación electrónica (l10n_co_edi).
3. Credenciales de prueba (homologación) y endpoints SOAP/REST provistos por la DIAN o por un proveedor autorizado de facturación electrónica.
4. Decisión de formato de intercambio: XML directo vs. SOAP vs. servicios de intermediarios.
5. Mecanismo de firma XML (XML-DSig) y manejo de PKCS#12 en Node.js (paquetes como `xml-crypto`, `node-forge`, o uso de herramientas externas para firmar).
6. Ejemplos de XML válidos y respuestas de la DIAN para implementar parsing y manejo de errores.

## Pasos concretos para completar (sugeridos)
1. Obtener XSDs y muestras de XML de la DIAN y mapear los campos del modelo `Invoice` a los nodos del XSD.
2. Implementar `xmlGenerator.generateInvoiceXml()` para generar XML que cumpla con los XSD.
3. Implementar `signer.signXml()` usando `pkcs12` o `xml-crypto` y soportar P12/PFX (configurable).
4. Adaptar `httpClient.postToDian()` para el protocolo requerido (SOAP/REST) y agregar reintentos y manejo de códigos de error específicos.
5. Implementar tests de integración contra el ambiente de homologación de la DIAN.
6. Añadir flags/feature toggles en la configuración de compañía para activar facturación electrónica por entidad.

## Riesgos y notas de seguridad
- Las claves privadas y certificados deben guardarse en un lugar seguro (Vault, HSM o almacenamiento encriptado), nunca en repositorio.
- Manejar expiración de certificados y rotación.
- Registrar y auditar envíos y respuestas DIAN para soporte legal y contable.

## Resultado esperado
- Un conector que permita generar, firmar y enviar facturas electrónicas hacia la DIAN en modo homologación y producción, con logging, reintentos y trazabilidad. Actualmente se dispone del scaffold; faltan certificados, XSDs y credenciales para completar la implementación.
