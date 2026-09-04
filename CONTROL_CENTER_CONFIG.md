# Configuración del Centro de Control

## Endpoint por Defecto

El cliente Flutter está configurado por defecto para comunicarse con el Centro de Control en:
- **Local:** `http://127.0.0.1:8787`
- **Puerto:** 8787

## Cambiar el Endpoint del Centro de Control

### Opción 1: A través de la Base de Datos (SQL)

Ejecuta este comando SQL en la base de datos SQLite del cliente:

```sql
INSERT OR REPLACE INTO app_config (clave, valor) 
VALUES ('control_center_endpoint', 'http://tu-servidor:8787');
```

### Opción 2: A través de la Interfaz de Usuario (si está disponible)

1. Ve a Configuración
2. Busca "Centro de Control"
3. Ingresa la URL del servidor
4. Guarda los cambios

### Opción 3: Modificar el Código (para desarrollo)

Edita el archivo `lib/control_center_agent.dart`:

```dart
static const defaultEndpoint = 'http://tu-servidor:8787';
```

## Iniciar el Centro de Control

### En Windows

1. Navega al directorio del Centro de Control:
```bash
cd C:\Users\PC\Desktop\Merka_Control_Center
```

2. Ejecuta la aplicación:
```bash
flutter run -d windows
```

### En Producción

1. Compila la aplicación:
```bash
flutter build windows
```

2. Ejecuta el ejecutable generado en `build\windows\runner\Release\`

## Verificar Conexión

El Centro de Control iniciará automáticamente el servidor HTTP en el puerto 8787. Puedes verificar que está funcionando:

```bash
curl http://localhost:8787/health
```

Respuesta esperada:
```json
{
  "status": "healthy",
  "service": "merka-control-center-api",
  "timestamp": "2026-06-30T20:00:00.000Z"
}
```

## Configuración de Firewall

Asegúrate de que el puerto 8787 esté abierto en el firewall para permitir conexiones remotas:

### Windows (PowerShell como Administrador)
```powershell
New-NetFirewallRule -DisplayName "Merka Control Center" -Direction Inbound -LocalPort 8787 -Protocol TCP -Action Allow
```

## Endpoints Disponibles

### Heartbeat
- `POST /api/v1/installations/heartbeat` - Enviar heartbeat del cliente

### Telemetría
- `POST /api/v1/telemetry/events` - Enviar eventos de telemetría

### Comandos
- `GET /api/v1/installations/{uuid}/commands` - Obtener comandos pendientes
- `POST /api/v1/commands/{id}/ack` - Acknowledge comando
- `POST /api/v1/commands` - Crear nuevo comando
- `GET /api/v1/commands` - Listar comandos
- `DELETE /api/v1/commands/{id}` - Eliminar comando

### Instalaciones
- `GET /api/v1/installations` - Listar todas las instalaciones
- `GET /api/v1/installations/{id}` - Obtener detalles de instalación
- `POST /api/v1/installations/{id}/block` - Bloquear instalación
- `POST /api/v1/installations/{id}/unblock` - Desbloquear instalación
- `POST /api/v1/installations/{id}/license` - Actualizar licencia
- `GET /api/v1/installations/{id}/license` - Obtener licencia
- `POST /api/v1/installations/{id}/rollback` - Solicitar rollback

### Actualizaciones
- `GET /api/v1/updates/check` - Verificar actualizaciones disponibles
- `POST /api/v1/updates` - Crear actualización
- `GET /api/v1/updates` - Listar actualizaciones
- `DELETE /api/v1/updates/{id}` - Eliminar actualización

## Autenticación

El Centro de Control requiere autenticación para la mayoría de endpoints:

- **Login:** `POST /api/v1/auth/login`
- **Header:** `Authorization: Bearer {token}`

No existen credenciales administrativas por defecto. En una instalación nueva, el bootstrap exige definir explícitamente `BOOTSTRAP_ADMIN_PASSWORD` con una contraseña robusta de al menos 12 caracteres. El primer usuario administrativo queda con rol `superadmin`; no se incluyen contraseñas conocidas dentro del repositorio.

## Seguridad en Producción

⚠️ **IMPORTANTE:** Antes de desplegar en producción:

1. Definir una contraseña de bootstrap robusta y retirarla del entorno una vez creado el administrador.
2. Configurar HTTPS (SSL/TLS); el cliente rechaza HTTP remoto.
3. Configurar `CORS_ORIGINS` con orígenes explícitos.
4. Restringir el acceso administrativo mediante firewall/red privada cuando aplique.
5. Mantener habilitados los límites de peticiones y monitorear intentos de autenticación.
6. Custodiar la clave privada RS256 y coordinar cualquier rotación con una nueva compilación del cliente que incluya la clave pública correspondiente.
