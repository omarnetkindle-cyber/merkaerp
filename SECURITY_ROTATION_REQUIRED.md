# MerkaERP — Rotación de secretos requerida antes de producción

El archivo original recibido contenía configuración sensible. La copia corregida elimina archivos `.env` y material privado de la entrega, pero **eliminar un secreto del repositorio no lo revoca**.

Antes de desplegar, el responsable de infraestructura debe rotar todos los secretos que hayan estado presentes en el paquete original o que se hayan reutilizado en pruebas. Como mínimo, revisar:

1. credenciales/contraseña de la base de datos y `DATABASE_URL`;
2. secretos de autenticación/JWT que hayan existido históricamente;
3. claves de cifrado o derivación utilizadas por la aplicación;
4. secretos MFA/TOTP, si fueron configurados;
5. API keys/tokens de servicios externos;
6. secretos de webhooks;
7. credenciales de correo, almacenamiento, monitoreo o terceros;
8. credenciales del Control Center y cuentas administrativas de prueba;
9. secretos HMAC de instalaciones que hayan sido expuestos fuera del almacén seguro;
10. cualquier token que haya aparecido en `.env`, scripts, logs o copias históricas.

## RSA de licencias / JWT

La aplicación cliente fija una clave pública esperada. Si la clave privada RSA correspondiente estuvo expuesta o se decide rotarla por política de seguridad, la rotación debe ser **coordinada**:

- generar un nuevo par RSA en un entorno seguro;
- configurar únicamente la privada en el backend/secret manager;
- actualizar la pública/fingerprint esperado en el cliente Flutter;
- recompilar y redistribuir el cliente;
- invalidar/renovar tokens o licencias firmadas con la autoridad anterior según la estrategia de migración.

No cambie solo la clave privada del servidor sin recompilar el cliente: el sistema corregido detecta esa incompatibilidad deliberadamente.

## Reglas de custodia

- No volver a crear `.env` dentro de un archivo de distribución.
- Usar variables del entorno o un gestor de secretos del proveedor de infraestructura.
- No enviar claves privadas por correo, chat o repositorios.
- Mantener `.env.example` únicamente con nombres y valores ficticios/no sensibles.
- Después de la rotación, probar login, activación/licencia, heartbeat, comandos firmados y servicios externos configurados.

Este documento no contiene ni reproduce ningún valor sensible del paquete original.
