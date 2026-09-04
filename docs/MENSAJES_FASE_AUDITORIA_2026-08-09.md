# Auditoria de mensajes de fase

Fecha: 2026-08-09

## Criterio

Se revisaron las coincidencias de Fase, pendiente y en desarrollo en lib/.
Solo se consideran deuda de producto los textos visibles que anuncian una
funcionalidad futura. Estados de registros (por ejemplo, una ausencia
pendiente de aprobacion), comentarios tecnicos internos y TODOs de APIs
genericas se mantienen fuera de esta tabla o se listan como brechas distintas.

## Mensajes visibles auditados

| Archivo | Texto/area | Clasificacion | Estado real y accion |
|---|---|---|---|
| lib/sector_publico/planeacion/pages/planeacion_page.dart | Banner de trazabilidad Plan-Presupuesto, antes “pendiente para Fase 4” | (b) pendiente, texto obsoleto | Corregido. Ahora declara que falta vincular automaticamente metas PDT/MGA con rubros de inversion y la cadena CDP/RP. La planeacion y el presupuesto siguen siendo operativos por separado. |
| lib/sector_publico/rentas/pages/predial_ica_page.dart | Banner de exportacion ICA, antes “en desarrollo para Fase 4” | (d) pendiente por formato externo | Corregido. Declara que falta el formato oficial PDF/XML y el servicio que lo exponga. No se invento un formato DIAN/DNP. |
| lib/sector_publico/activos/pages/activos_estado_page.dart | Banner de actas de responsabilidad, antes “pendiente para Fase 4” | (b) pendiente genuino | Corregido. Declara que falta el servicio de actas de cuentadantes y su ciclo de firma/entrega. |
| lib/sector_publico/auditoria/pages/auditoria_forense_page.dart | Encabezado “Integraciones Regulatorias Activas (Fase 4)” | (a)/(b), etiqueta obsoleta | Corregido a “Integraciones regulatorias disponibles”. Los modulos locales se muestran; la integracion remota sigue dependiendo de credenciales externas. |
| lib/sector_publico/rentas/services/ica_service.dart | Comentario “Reutilizando motor ... Fase 4” | Comentario interno | No es un mensaje de UI. El calculo usa el servicio de intereses existente; se conserva como referencia historica y no afecta al usuario. |
| lib/core/api/endpoints/sales_api.dart | Varios TODO: Implementar... | Brecha tecnica, no mensaje de fase | No se cambio en esta ronda. Son endpoints stub que requieren definir su contrato de persistencia/autorizacion antes de activarlos. |
| lib/core/api/endpoints/inventory_api.dart | Varios TODO: Implementar... | Brecha tecnica, no mensaje de fase | No se cambio en esta ronda por la misma razon; devuelve placeholders y debe entrar en un frente API separado. |

Las restantes coincidencias son estados operativos o nombres de estados,
como pendiente_pago, pendiente_revision y “solicitudes pendientes”; no se
clasifican como promesas de una fase futura.

## Verificacion

- Busqueda base: docs/evidencias/mensajes_fase_raw_2026-08-09.txt.
- Los cuatro banners visibles con referencia generica a Fase 4 fueron
  actualizados en esta ronda.
- La brecha no se marco como completa por cambiar solo el texto: queda
  trazada para una futura implementacion o decision normativa.
