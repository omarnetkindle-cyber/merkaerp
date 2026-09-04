# Cierre general PARTE 2 - Bloque M - Sync allowlist

## Hallazgo

El backend `merkaerp-control-center-backend` no tenia un `ALLOWED_TABLES`
existente. La ruta `POST /api/v1/sync/push` aceptaba el campo `event.table`
sin validar contra un contrato de tablas conocidas y lo persistia directo en
`sync_events.table_name`.

## Decision conservadora

Se agrego una lista explicita de tablas sincronizables en
`backend/src/sync/allowed_tables.js` y se conecto a `backend/src/routes/heartbeat.js`.
La lista incluye:

- Tablas comerciales operativas existentes para no romper sincronizacion previa.
- Tablas nuevas de CRM, HRM y MRP.
- `impact_scenarios` del simulador.
- Tablas publicas multi-tenant, auditoria, presupuesto, planeacion, SIIF, CHIP/FUT,
  contabilidad NICSP, contratacion, nomina publica, salud/RIPS, rentas, SGP/SGR,
  transparencia y activos.

La capsula de evidencia y las senales no crean tablas propias hoy: la capsula se
exporta como JSON local y usa `auditoria_registros`; las senales son agregadas en
memoria desde fuentes existentes. Por eso no habia una tabla adicional que agregar
para esos dos casos, pero si quedaron cubiertas sus fuentes persistidas
(`auditoria_registros`, `impact_scenarios`, presupuesto/HRM/MRP/CRM).

## Archivos modificados

- `backend/src/sync/allowed_tables.js`
- `backend/src/routes/heartbeat.js`
- `backend/test_allowed_tables.js`

## Evidencia cruda

### node test_allowed_tables.js

```text
Allowed sync tables test passed (177 tables)
```

### node -c

```text
node -c src\sync\allowed_tables.js
node -c src\routes\heartbeat.js
```

Ambos comandos terminaron con codigo 0.

## Estado

Bloque M completo en codigo del backend. Como `main` del backend esta divergido
(`ahead 48, behind 22` antes de este bloque), no se fuerza push a `origin/main`.
Se publica el commit en una rama de respaldo del backend y el repo principal queda
apuntando a ese commit del submodulo.
