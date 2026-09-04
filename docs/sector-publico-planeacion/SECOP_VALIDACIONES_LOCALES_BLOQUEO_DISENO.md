# Bloqueo de diseno: orden contrato, RP y polizas

Fecha: 2026-07-31.

## Peticion a implementar

1. `crearContrato` debe comprobar que el RP existe y corresponde al proceso.
2. `expedirRP` debe requerir contrato existente y firmado.
3. `legalizarContrato` debe requerir polizas registradas y vigentes.

## Evidencia del bloqueo

El modelo y la UI actuales no tienen un estado persistible que permita cumplir
las tres reglas en un flujo feliz:

1. `contratacion_publica_page.dart` crea un contrato solo despues de seleccionar
   un RP existente, filtrado por el CDP del proceso (lineas 932-948 y 1037-1055).
2. `ContratacionService.crearContrato` persiste ese contrato con estado
   `enFirma` y con `rp_id` obligatorio (lineas 120-207).
3. `PresupuestoService.expedirRP` recibe `contratoId` y `contratoNumero`, pero
   hoy solo verifica que el numero no este vacio; no consulta la tabla de
   contratos (lineas 243-310).
4. No existe ninguna transicion que escriba `EstadoContrato.firmado`; el unico
   estado de contrato creado por el servicio es `enFirma`, y legalizar solo
   acepta el estado `firmado`.

Si se endurece `expedirRP` para consultar un contrato firmado, no habra RP
para seleccionar al crear el primer contrato. Si se endurece `crearContrato`
para que el RP apunte a un contrato existente, tampoco habra un primer contrato
legal para asociar. Insertar un contrato o RP ficticio para la prueba ocultaria
el problema y dejaria la UI inoperable.

## Decision conservadora

No se implementaron las tres validaciones ni una prueba feliz ficticia. Antes
de hacerlo se debe decidir y construir un flujo de dos etapas:

1. **Registro de contrato firmado/perfeccionado:** crea el contrato con proceso
   y CDP, sin RP, y estado `firmado`; debe conservar firma y soporte.
2. **Expedicion y asociacion de RP:** requiere ese contrato firmado, crea el RP
   y lo asocia al contrato en una transaccion. Solo despues se registran polizas
   vigentes y se permite legalizar/iniciar ejecucion.

Eso requiere hacer `rp_id`/`numero_rp` opcionales antes de la expedicion,
agregar migracion defensiva, metodo de transicion y UI acorde. La alternativa
de permitir un identificador externo de contrato antes de persistirlo debe ser
rechazada salvo que exista un registro auditable y una especificacion juridica
del sistema fuente.

## Alcance posterior recomendado

Con la decision aprobada, el siguiente cambio debe incluir una prueba de
integracion con este orden: proceso adjudicado con CDP -> contrato firmado ->
RP asociado -> poliza vigente -> legalizacion; y bloqueos para RP sin contrato
firmado, RP ajeno al proceso y legalizacion sin polizas. No se toca SECOP remoto
ni credenciales.
