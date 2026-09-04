# Copilot local de MerkaERP

## Alcance

El Copilot es un orquestador hibrido y offline-first. Un modelo local puede
interpretar lenguaje natural, pero no recibe acceso a SQLite, no construye SQL
y no ejecuta reglas fiscales, contables o presupuestales. Toda consulta y accion
pasa por herramientas Dart registradas, aislamiento por empresa y RBAC.

Sin un modelo configurado, el Copilot conserva un interprete determinista para
las consultas operativas principales. Un fallo del modelo nunca bloquea el ERP.

## Flujo de seguridad

1. La UI crea una identidad con usuario, rol y modulos visibles de la sesion.
2. El orquestador expone solamente las herramientas permitidas para esa identidad.
3. El modelo local devuelve una llamada estructurada; nunca SQL libre.
4. `CopilotToolRegistry` vuelve a comprobar el permiso antes de ejecutar.
5. Una escritura se representa como propuesta. La UI exige confirmacion y el
   modulo de destino vuelve a aplicar sus reglas de negocio.
6. La conversacion queda registrada con usuario, rol, herramienta, proveedor,
   resultado y error seguro en `conversaciones_copilot`.

## Proveedor local

La integracion usa el endpoint compatible con OpenAI de `llama-server`. Solo se
aceptan endpoints HTTP en `localhost` o `127.0.0.1`; una URL remota se rechaza.
MerkaERP no incluye ni descarga un modelo automaticamente. El responsable de la
instalacion debe seleccionar un archivo GGUF cuya licencia permita su uso y
distribucion.

Ejemplo de arranque manual:

```powershell
llama-server.exe -m C:\modelos\modelo-instruct.gguf --host 127.0.0.1 --port 8080 --jinja
```

Configuracion predeterminada:

```text
Endpoint: http://127.0.0.1:8080/v1/chat/completions
Modelo: local-model
Estado: desactivado
```

Un administrador puede modificarla desde el icono de memoria del panel. No se
guardan claves ni credenciales porque el proceso es exclusivamente local.

## Herramientas iniciales

- Ventas de hoy y del mes.
- Stock critico y lotes proximos a vencer.
- Total de cartera y cuentas por pagar.
- Preparacion confirmable de venta y compra, sin escritura automatica.
- Navegacion a todos los modulos visibles de la sesion. Los comandos se generan
  dinamicamente y un modulo no autorizado no se incluye en el esquema enviado al
  modelo.

Las respuestas muestran fuente y distinguen entre interpretacion del modelo local
y resultado verificable del ERP.

## Limites deliberados

- El modelo no calcula impuestos, nomina, MoneyValue, PAC ni partida doble.
- El modelo no puede afirmar que DIAN valido un documento si el cliente activo es
  NoOp.
- No se ejecutan ventas, pagos, aprobaciones ni escrituras desde texto libre.
- El contexto conversacional enviado al modelo se limita a los ultimos ocho turnos.
- No se atribuyen al tenant activo registros legacy cuyo `company_id` sea nulo.

## Extension

Para agregar una capacidad se registra un `CopilotToolDefinition` con modulo,
esquema de parametros y handler. El handler debe reutilizar el servicio de dominio
existente. Las acciones de escritura deben devolverse como
`CopilotActionProposal` con `requiresConfirmation: true`.

Referencia del runtime local:
https://github.com/ggml-org/llama.cpp
