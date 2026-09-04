# Merka Sync Server

Backend MVP independiente para recibir eventos de sincronización MerkaERP.

## Variables de entorno

- `DATABASE_URL`: URL PostgreSQL. En Render normalmente viene del servicio PostgreSQL.
- `PORT`: puerto HTTP asignado por Render.
- `MERKA_SYNC_PUBLIC_KEY_PEM` o `MERKA_LICENSE_PUBLIC_KEY_PEM`: llave pública RS256 para validar tokens de licencia/sync.
- `MERKA_SYNC_EXPECTED_ISSUER`: opcional, por defecto `MerkaERP-ControlCenter`.

## Ejecutar local

```powershell
dart pub get
dart run bin/server.dart --port 8080
```

## Endpoint MVP

- `GET /health`
- `POST /api/sync/events`
- `GET /api/sync/events?cursor=0&limit=100&include_self=false`

El servidor no toma el `tenant_id` del body como autoridad final. Primero valida el token, resuelve el tenant/dispositivo desde sus claims y luego compara esos claims contra el evento recibido.

El tenant remoto se resuelve en este orden: `tenant_id` explícito en el JWT, `company_id` como `company:<id>`, `client_id` como `client:<id>`, o `entidad_id` como `entity:<id>`. La app MerkaERP usa `client:<client_id>` cuando la licencia lo trae, para aislar datos por cliente real del Control Center.

El pull es incremental por cursor del servidor. Por defecto no devuelve eventos originados por el mismo `source_device_id`, para evitar que una instalación reaplique lo que acaba de subir.
