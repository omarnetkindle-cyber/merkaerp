# Configuración de Sincronización en la Nube - MerkaERP

## Resumen

El sistema de sincronización en la nube permite que el software MerkaERP funcione en múltiples dispositivos (computador de escritorio y móvil) manteniendo los datos sincronizados automáticamente. Los datos se guardan en un servidor web y se sincronizan entre dispositivos en tiempo real.

## Arquitectura

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  MerkaERP       │  Sync   │  Servidor Web    │  Sync   │  MerkaERP       │
│  (Escritorio)   │ <------> │  (Node.js)       │ <------> │  (Móvil)        │
│                 │         │                  │         │                 │
│  SQLite Local   │         │  SQLite Central  │         │  SQLite Local   │
└─────────────────┘         └──────────────────┘         └─────────────────┘
```

## Componentes

### 1. Servidor Web (Backend Node.js)
- **Ubicación:** `C:\Users\PC\Desktop\Caja_simple\backend`
- **Puerto:** 8787 (configurable)
- **Base de datos:** SQLite (`./data/control_center.db`)
- **Función:** Recibe, procesa y distribuye eventos de sincronización

### 2. Cliente Escritorio (Flutter)
- **Ubicación:** `C:\Users\PC\Desktop\Caja_simple`
- **Servicio de sincronización:** `lib/services/sync_service.dart`
- **Función:** Envía cambios locales al servidor y recibe cambios remotos

### 3. Cliente Móvil (Flutter)
- **Ubicación:** Pendiente de implementación
- **Función:** Igual que el cliente de escritorio

## Configuración Inicial

### Paso 1: Iniciar el Servidor Web

1. Navega al directorio del backend:
```bash
cd C:\Users\PC\Desktop\Caja_simple\backend
```

2. Instala dependencias:
```bash
npm install
```

3. Configura el archivo `.env`:
```env
PORT=8787
NODE_ENV=production
CORS_ORIGIN=*
```

4. Inicia el servidor:
```bash
npm start
```

El servidor iniciará en `http://localhost:8787`

### Paso 2: Configurar el Cliente Escritorio

1. Abre el archivo `lib/services/sync_service.dart`
2. El endpoint por defecto es `http://127.0.0.1:8787`
3. Para cambiar el endpoint, ejecuta este SQL en la base de datos del cliente:
```sql
INSERT OR REPLACE INTO app_config (clave, valor) 
VALUES ('sync_server_endpoint', 'http://tu-servidor:8787');
```

### Paso 3: Verificar la Conexión

1. Inicia MerkaERP en el escritorio
2. El servicio de sincronización se iniciará automáticamente
3. Revisa los logs para ver si la sincronización está funcionando:
```
Sync completed successfully
Pushed X events to server
Pulled Y events from server
```

## API de Sincronización

### POST /api/v1/installations/sync/push
Envía cambios locales al servidor.

**Body:**
```json
{
  "installationId": "MERKA-0001-WIN",
  "events": [
    {
      "eventId": "evt_1234567890_ventas_insert",
      "table": "ventas",
      "operation": "insert",
      "data": {
        "id": 1,
        "cliente": "Juan Pérez",
        "total": 150000
      },
      "timestamp": "2026-06-30T20:00:00Z"
    }
  ]
}
```

**Respuesta:**
```json
{
  "success": true,
  "message": "Sync events received",
  "processedCount": 1,
  "timestamp": "2026-06-30T20:00:00Z"
}
```

### GET /api/v1/installations/sync/pull
Obtiene cambios del servidor para aplicar localmente.

**Query Parameters:**
- `installationId`: ID de la instalación
- `lastSyncTimestamp`: Timestamp de la última sincronización

**Respuesta:**
```json
{
  "success": true,
  "events": [
    {
      "eventId": "evt_1234567891_ventas_insert",
      "table": "ventas",
      "operation": "insert",
      "data": {
        "id": 2,
        "cliente": "María García",
        "total": 200000
      },
      "timestamp": "2026-06-30T20:05:00Z",
      "installationId": "MERKA-0002-MOBILE"
    }
  ],
  "lastSyncTimestamp": "2026-06-30T20:05:00Z"
}
```

### GET /api/v1/sync/conflicts
Obtiene conflictos de sincronización pendientes de resolución.

**Query Parameters:**
- `installationId`: ID de la instalación

**Respuesta:**
```json
{
  "success": true,
  "conflicts": [
    {
      "id": 1,
      "table": "ventas",
      "recordId": "1",
      "localData": {
        "id": 1,
        "total": 150000
      },
      "remoteData": {
        "id": 1,
        "total": 160000
      },
      "createdAt": "2026-06-30T20:10:00Z"
    }
  ]
}
```

### POST /api/v1/sync/conflicts/:id/resolve
Resuelve un conflicto de sincronización.

**Body:**
```json
{
  "resolution": "remote",
  "data": {
    "id": 1,
    "total": 160000
  }
}
```

**Respuesta:**
```json
{
  "success": true,
  "message": "Conflict resolved"
}
```

## Uso del SyncService

### Inicialización Automática

El SyncService se inicializa automáticamente en `main.dart`:

```dart
try {
  await SyncService.instance.initialize();
} catch (_) {}
```

### Sincronización Manual

Para forzar una sincronización:

```dart
await SyncService.instance.sync();
```

### Estado de Sincronización

Monitorea el estado de sincronización:

```dart
SyncService.instance.addStatusListener((status) {
  switch (status) {
    case SyncStatus.idle:
      print('Sincronización inactiva');
      break;
    case SyncStatus.syncing:
      print('Sincronizando...');
      break;
    case SyncStatus.offline:
      print('Sin conexión');
      break;
    case SyncStatus.error:
      print('Error de sincronización');
      break;
    case SyncStatus.conflict:
      print('Conflictos pendientes');
      break;
  }
});
```

### Colocar Eventos de Sincronización

Cuando hagas cambios en la base de datos local, colócalos en la cola de sincronización:

```dart
await SyncService.instance.queueEvent(
  'ventas',
  'insert',
  {'id': 1, 'cliente': 'Juan Pérez', 'total': 150000}
);
```

### Resolver Conflictos

Para resolver conflictos de sincronización:

```dart
final conflicts = await SyncService.instance.getConflicts();
for (final conflict in conflicts) {
  // Mostrar al usuario para elegir
  await SyncService.instance.resolveConflict(
    conflict.id,
    'remote', // o 'local'
    conflict.remoteData,
  );
}
```

### Configurar Endpoint del Servidor

Para cambiar el endpoint del servidor:

```dart
await SyncService.instance.setServerEndpoint('http://nuevo-servidor:8787');
```

## Tablas de Sincronización

### sync_outbox
Almacena eventos locales pendientes de enviar al servidor.

- `id`: ID local
- `event_id`: ID único del evento
- `table_name`: Nombre de la tabla afectada
- `operation`: Operación (insert, update, delete)
- `data`: Datos en JSON
- `timestamp`: Timestamp del evento
- `processed`: Si fue procesado (0/1)
- `error`: Mensaje de error si falló

### sync_inbox
Almacena eventos recibidos del servidor.

- `id`: ID local
- `event_id`: ID único del evento
- `table_name`: Nombre de la tabla afectada
- `operation`: Operación (insert, update, delete)
- `data`: Datos en JSON
- `timestamp`: Timestamp del evento
- `applied`: Si fue aplicado localmente (0/1)

### sync_conflicts
Almacena conflictos de sincronización.

- `id`: ID local
- `table_name`: Nombre de la tabla con conflicto
- `record_id`: ID del registro en conflicto
- `local_data`: Datos locales en JSON
- `remote_data`: Datos remotos en JSON
- `resolved`: Si fue resuelto (0/1)
- `resolution`: Tipo de resolución (local/remote)
- `resolved_data`: Datos finales después de resolver
- `created_at`: Timestamp de creación
- `resolved_at`: Timestamp de resolución

## Estrategia de Sincronización

### Offline-First
- La aplicación funciona completamente sin conexión
- Los cambios se guardan localmente
- Cuando hay conexión, se sincronizan automáticamente
- Si hay conflictos, se notifica al usuario

### Resolución de Conflictos
- Last-Write-Wins (LWW) por defecto
- El usuario puede elegir manualmente en caso de conflictos
- Los conflictos se guardan para revisión posterior

### Frecuencia de Sincronización
- Automática cada 5 minutos
- Manual cuando el usuario lo solicita
- Inmediata cuando hay cambios críticos

## Seguridad

### Autenticación
- Cada instalación tiene un ID único
- El servidor valida las instalaciones
- Se puede agregar autenticación adicional (JWT, API Keys)

### Encriptación
- Los datos en tránsito pueden encriptarse con HTTPS
- Los datos en reposo pueden encriptarse en el servidor

### Rate Limiting
- 100 requests por 15 minutos por IP
- Configurable en el servidor

## Monitoreo

### Logs del Servidor
```bash
# Ver logs en tiempo real
tail -f logs/server.log
```

### Logs del Cliente
Los logs del SyncService se muestran en la consola de Flutter:
```
Sync completed successfully
Pushed 5 events to server
Pulled 3 events from server
```

### Métricas
- Última sincronización: `SyncService.instance.lastSyncTimestamp`
- Estado actual: `SyncService.instance.status`
- Conexión: `SyncService.instance.isOnline`

## Solución de Problemas

### El cliente no se sincroniza
1. Verifica que el servidor esté corriendo
2. Verifica el endpoint configurado
3. Revisa los logs del cliente
4. Verifica la conexión a internet

### Conflictos frecuentes
1. Aumenta la frecuencia de sincronización
2. Implementa bloqueos optimistas en la UI
3. Notifica al usuario cuando haya conflictos

### Error de conexión
1. Verifica que el puerto 8787 esté abierto en el firewall
2. Verifica que el servidor sea accesible desde el cliente
3. Revisa la configuración de CORS

## Próximos Pasos

1. Implementar cliente móvil con el mismo SyncService
2. Agregar autenticación con JWT
3. Implementar encriptación HTTPS
4. Agregar dashboard de monitoreo
5. Implementar sincronización selectiva por tablas
6. Agregar compresión de datos para sincronización más rápida

## Soporte

Para problemas o preguntas:
- Revisa los logs del servidor y cliente
- Consulta la documentación de la API
- Contacta al equipo de desarrollo
