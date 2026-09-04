# NICSP 40: reciprocas y portal de transparencia

## Hallazgo verificable

`ConsolidacionJerarquicaService` agrega directamente `saldos_cuentas` de la entidad padre y sus hijas. La tabla y el servicio no contienen contraparte relacionada, identificador comun de operacion ni enlace entre los dos asientos de una transaccion intragrupo. Por tanto, no es posible saber de forma segura que un gasto de la gobernacion y un ingreso de una ESE representan la misma operacion.

Eliminar por codigo de cuenta, monto o fecha seria inseguro: puede borrar operaciones distintas que coinciden accidentalmente. La eliminacion automatica queda bloqueada hasta decidir y modelar una de estas alternativas:

1. Agregar a los asientos un `grupo_reciproco_id` y `entidad_contraparte_id`, obligatorios solo para operaciones intragrupo; ambos extremos deben compartir el identificador y montos compatibles.
2. Crear una tabla de conciliacion de reciprocas, alimentada por aprobacion contable, que relacione dos o mas asientos existentes sin alterar el libro original.

La opcion 2 es la mas conservadora para datos existentes: conserva los asientos y exige validacion humana antes de una eliminacion de presentacion. Requiere decision humana sobre quien puede aprobar la relacion y que tolerancia de fecha/monto se admite.

## Portal de transparencia

La UI real es `transparencia_page.dart`, que usa `TransparenciaService` para crear/publicar reportes locales. `PortalTransparenciaService` no es instanciado por esa pagina; contiene una URL de ejemplo, `<CONFIGURAR_EN_CENTRO_DE_INTEGRACIONES>`, y dos metodos internos que no persisten publicaciones ni pendientes. No debe conectarse ni invocarse hasta contar con contrato de API, credenciales de la entidad y configuracion por entorno. Esto requiere decision humana y una integracion externa, por lo que no se implementa en esta ronda.
