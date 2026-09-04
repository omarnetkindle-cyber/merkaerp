# Despliegue de Merka Sync Server en Render

Esta guía deja listo el backend de sincronización para publicarlo en Render usando el `render.yaml` ubicado en la raíz del proyecto.

## Qué archivo usar

Usa este archivo como Blueprint principal:

```text
render.yaml
```

Ese archivo crea:

- Un servicio web Docker llamado `merka-sync-server`.
- La variable `DATABASE_URL`, que debe apuntar a una base PostgreSQL existente de Render.
- La variable secreta `MERKA_SYNC_PUBLIC_KEY_PEM`, que Render debe pedir durante el setup.
- Health check en `/health`.

## Variable obligatoria

Render debe tener configurada:

```text
DATABASE_URL
```

Valor esperado: la Internal Database URL de tu PostgreSQL existente en Render.

También debe tener configurada:

```text
MERKA_SYNC_PUBLIC_KEY_PEM
```

Contenido esperado:

```text
-----BEGIN PUBLIC KEY-----
...
-----END PUBLIC KEY-----
```

Debe ser la llave pública RS256 que valida las licencias/tokens emitidos por MerkaERP Control Center. No se debe subir una llave privada al backend ni a la app cliente.

El backend también acepta el alias `MERKA_LICENSE_PUBLIC_KEY_PEM`, pero se recomienda usar `MERKA_SYNC_PUBLIC_KEY_PEM`.

## Pasos en Render

1. Subir este proyecto a un repositorio Git.
2. Entrar a Render y crear un nuevo Blueprint.
3. Seleccionar el repositorio de MerkaERP.
4. Usar el `render.yaml` de la raíz del proyecto.
5. Cuando Render pregunte por `DATABASE_URL`, pegar la Internal Database URL de la base PostgreSQL existente.
6. Cuando Render pregunte por `MERKA_SYNC_PUBLIC_KEY_PEM`, pegar la llave pública.
7. Esperar a que Render cree el servicio Docker.
8. Si estás reintentando después de un fallo por límite de bases free, ejecuta Sync/Redeploy del Blueprint para que tome el `render.yaml` actualizado.
9. Abrir:

```text
https://merka-sync-server-sju2.onrender.com/health
```

Debe responder estado saludable.

## Configuración en MerkaERP

En la app:

1. Ir a Configuración.
2. Abrir la tarjeta "Sincronización Merka Cloud".
3. Pegar el endpoint de Render:

```text
https://merka-sync-server-sju2.onrender.com
```

4. Guardar.
5. Activar una licencia válida.
6. Probar "Sincronizar ahora".

## Resolución de tenant

La app y el backend resuelven el tenant desde la licencia/token:

- Si la licencia trae `clientId`, se usa `client:<clientId>`.
- Si no trae `clientId`, se usa `company:<companyId>`.
- El sector se deriva de la licencia: `commercial` o `public_sector`.

Esto permite que una misma instalación limpia determine automáticamente si trabaja como Comercial o Sector Público después de activar la licencia.

## Prueba local rápida del backend

Desde:

```text
backend/merka_sync_server
```

Ejecutar:

```powershell
dart pub get
dart analyze .
dart test
dart run bin/server.dart --port 8080
```

Para correr localmente también necesitas `DATABASE_URL` y `MERKA_SYNC_PUBLIC_KEY_PEM` en el entorno.
