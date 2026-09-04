# Consolidacion Arquitectonica

Este documento registra la capa empresarial integrada en MerkaERP para operar
con eventos persistentes, CQRS, ledger contable e inventario avanzado.

## Event-driven core

- `lib/core/events/event_store.dart`
  - `EventEnvelope`
  - `EventStore`
  - `SqliteEventStore`
- `lib/core/events/event_dispatcher.dart`
  - `EventDispatcher`
  - `PersistentEventBus`
  - `EventProjection`
  - `EventDispatchResult`

Cada evento guarda nombre, agregado, version, payload JSON, metadata,
`company_id`, `branch_id`, `idempotency_key`, `correlation_id`,
`causation_id`, `trace_id`, fecha de ocurrencia y secuencia global.

La escritura usa outbox persistente en `event_dispatch_queue`. El dispatcher
procesa eventos pendientes, reintenta con backoff y mueve errores definitivos a
`event_dead_letters` con payload JSON para diagnostico y replay controlado.

## CQRS

- `lib/cqrs/domain/read_models.dart`
- `lib/cqrs/application/dashboard_projection.dart`

`DashboardReadModelProjection` consume eventos de ventas, compras, inventario y
pagos. Mantiene offsets por proyeccion, empresa y sucursal, y actualiza
`executive_kpi_read_model` con KPIs materializados para dashboards ejecutivos.

Endpoints:

- `GET /api/v1/events`
- `POST /api/v1/events/replay`
- `GET /api/v1/cqrs/executive-dashboard`

## Ledger contable

- `lib/accounting/domain/journal_entry.dart`
- `lib/accounting/application/ledger_engine.dart`
- `lib/accounting/application/accounting_posting_service.dart`
- `lib/accounting/data/journal_entry_repository.dart`

El agregado `JournalEntry` exige partida doble, minimo dos lineas y estado
contable. `LedgerEngine` contabiliza, reversa y calcula balance de
comprobacion. `AccountingPostingService` persiste asientos posteados y publica
eventos `accounting.journal_posted` y `accounting.journal_reversed`.

Persistencia:

- `accounting_journal_entries`
- `accounting_journal_lines`

Cada linea mantiene dimensiones: empresa, sucursal, bodega, centro de costo,
tercero, moneda y tasa de cambio.

## Inventario empresarial

- `lib/inventory/domain/stock_ledger.dart`
- `lib/inventory/application/stock_ledger_service.dart`
- `lib/inventory/data/stock_ledger_repository.dart`

`StockLedger` calcula existencias disponibles, reservas, valoracion y consumos
por FIFO, LIFO o promedio. `StockLedgerService` recibe lotes, reserva,
libera reservas y consume inventario publicando eventos transaccionales.

Persistencia:

- `inventory_lots`
- `inventory_reservations`

Los lotes soportan costo unitario, lote, serial y vencimiento. Las reservas
quedan aisladas por empresa, sucursal y bodega.

## Validacion

Cobertura automatizada:

- Event bus persistente con scope, idempotencia y correlacion.
- Ledger con posteo, reverso y balance.
- Posting service con persistencia y eventos.
- Stock ledger FIFO con evento transaccional.
- API para event store, replay y read model ejecutivo.

Comandos verificados:

```bash
flutter analyze
flutter test
```
