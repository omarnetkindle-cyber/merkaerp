# Diagnóstico: account_budget (presupuesto público)

## Código existente detectado en MerkaERP
- Frontend/cliente: existen componentes Flutter relacionados con presupuesto bajo `lib/sector_publico/presupuesto`:
  - `presupuesto_service.dart`, `presupuesto_publico_page.dart`, `schema_presupuesto.dart`.
  - Tests Flutter en `test/sector_publico/presupuesto`.
- No se encontró implementacion backend específica para presupuestos en `backend/src/modules`.
- No hay scripts de migración o modelos backend que den soporte a presupuestos públicos (búsqueda por `budget`, `presupuesto` en backend no arrojó resultados relevantes).

## Para qué caso de uso fue construido (frontend detectado)
- Interacción UI para gestionar partidas presupuestales, visualización de presupuesto público y operaciones básicas de consulta/registro desde la aplicación cliente.

## Qué le falta comparado con el módulo equivalente de Odoo
- Backend centralizado para almacenar presupuestos, partidas presupuestales, compromisos, apropiaciones, y ejecución presupuestal.
- Integración entre presupuesto y contabilidad: asignación de gastos a partidas, validación previa a contabilizar gastos públicos.
- Flujos de aprobación y vinculaciones con contratos/ordenes de compra para trazabilidad.
- Informes presupuestales (ejecución, saldos por partida, compromisos) implementados en el servidor.

## Qué le falta para sector público
- Control de fases presupuestales (aprobado, comprometido, devengado, pagado) y reglas de compatibilidad con partidas presupuestales del SGP/SGR.
- Validaciones legales: no permitir gastos que excedan apropiaciones, trazabilidad para auditoría (Ley 1712, Ley 80/1150) y retención de registros.
- Integración con módulos de compras/contratación para registrar apropiaciones.

## Evaluación
- ¿Ya existía algo equivalente en MerkaERP? (sí — parcial frontend, no backend)
- Decisión: crear backend nuevo y conectar frontend existente.

## Resumen breve
Hay UI y pruebas cliente para presupuesto público, pero no existe el backend. Procederé a crear el módulo backend `account_budget` con tablas de presupuesto, endpoints REST, modelos y pruebas básicas, manteniendo retrocompatibilidad y diseñando extensiones para integrarse con `account` y `purchase` ya existentes.
