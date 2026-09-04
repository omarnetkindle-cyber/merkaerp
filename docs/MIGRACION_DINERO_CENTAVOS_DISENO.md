# Migracion de dinero a unidades menores enteras

Fecha de diseno: 2026-08-02  
Estado: Fase 1 terminada; implementacion pendiente de aprobacion humana.

## 1. Respaldo previo

Antes de modificar el repositorio o la base se creo esta copia:

```text
Origen:   C:\Users\PC\Documents\merka_erp_test_fresco.db
Respaldo: C:\Users\PC\Documents\merka_erp_test_fresco_pre_centavos_2026-08-02.db
Tamano de ambos: 2,629,632 bytes
SHA-256 de ambos: 12F7F5BB08CD827A4A325FA1B2EF2D08B0E603099B745F1B06477799242879F7
```

El respaldo no esta dentro del repositorio y no se versionara.

## 2. Hallazgo que impide asumir COP fijo

El sistema tiene soporte multimoneda ejecutable, no solamente campos decorativos:

- `Currency` conserva `code` y `decimalPlaces` y el catalogo semilla contiene diez monedas.
- `CurrencyService` registra tasas por empresa, consulta una API, convierte montos y permite seleccionar moneda base.
- `ExchangeRate.convert()` y `convertInverse()` ejecutan multiplicacion y division reales.
- Los asientos comerciales conservan `currency`, `exchange_rate`, debito/credito en moneda de transaccion y debito/credito local.
- `companies`, `empresa_config`, cuentas bancarias y configuracion de empresa conservan moneda.

La base actual confirma una configuracion inconsistente que no debe resolverse por suposicion:

```text
companies:        empresa 1 COP; empresa 2 COP
empresa_config:   COP
app_currencies:   diez monedas; USD marcada como predeterminada
currencies:       sin filas
```

Ademas, aunque `decimal_places` es configurable, todas las semillas actuales reciben el valor por defecto 2. Por tanto, la migracion no puede aplicar `valor * 100` indiscriminadamente ni confiar en la semilla actual para monedas con otra escala.

## 3. Convencion de nombres y almacenamiento

### SQLite

Se conservara el nombre actual de cada una de las 355 columnas monetarias y se cambiara su afinidad declarada de `REAL` a `INTEGER`.

No se usara `_centavos`, `_cop_cents` ni una columna paralela porque:

- `_centavos` y `_cop_cents` codifican falsamente COP y escala 2 en un sistema multimoneda;
- dos columnas para el mismo valor permiten divergencia y dejan vivo el camino `REAL`;
- conservar el nombre reduce el riesgo de consultas que mezclen accidentalmente valores viejos y nuevos.

El significado nuevo sera siempre **unidades menores de la moneda de la fila**. En Dart, la propiedad equivalente se llamara `minorUnits`; no se expondran enteros desnudos como si fueran pesos.

Las columnas de tasa, porcentaje, cantidad, area, unidades y tipo de cambio no son dinero y no cambian a `INTEGER` por esta migracion. Sin embargo, tampoco podran multiplicar dinero mediante `double`: el calculo debera pasar por la operacion central de proporcion y redondeo descrita abajo.

## 4. Resolucion de moneda y escala

Orden obligatorio para resolver la moneda de un valor:

1. Moneda explicita de la fila, cuando exista.
2. Moneda de la empresa/entidad propietaria de la fila.
3. COP con escala 2 solamente para tablas del sector publico cuyo contrato funcional es exclusivamente colombiano.
4. Si ninguno de los anteriores es demostrable, la migracion aborta. No se inventa una moneda.

Antes de migrar montos comerciales se debe consolidar una fuente autoritativa de escala. La propuesta conservadora es `app_currencies(code, decimal_places)`; la tabla heredada `currencies`, que no tiene escala, no puede ser la autoridad. Toda moneda efectivamente usada debe tener una escala configurada y validada. La migracion falla cerrada si falta.

Esta decision preserva multimoneda. Reducir todo el producto a COP seria otro cambio de alcance y requeriria aprobacion explicita.

## 5. Punto unico de conversion

Se introducira un objeto inmutable central, provisionalmente `MoneyValue`:

```text
MoneyValue
  int minorUnits
  String currencyCode
  int scale
```

Responsabilidades exclusivas:

- parsear texto de UI a unidades menores sin pasar por `double`;
- formatear unidades menores para UI segun moneda y escala;
- sumar, restar y comparar solo valores de igual moneda y escala;
- convertir moneda mediante una proporcion decimal explicita y una politica de redondeo;
- multiplicar por cantidades/tasas mediante un factor racional o decimal escalado, nunca `double` monetario;
- comprobar overflow de entero de 64 bits antes de persistir.

No habra constructor publico `MoneyValue.fromDouble`. SQLite y repositorios leen/escriben `int`; UI recibe/entrega `String`; APIs externas se adaptan en un borde dedicado. El resto del dominio no manipula pesos ni divide entre 100.

Politica inicial de redondeo: a la unidad menor mas cercana, mitad alejandose de cero. Cualquier flujo con regla normativa distinta debera declararla explicitamente en la llamada y tener un test propio; no se aplicaran redondeos dispersos.

## 6. Diseno de la migracion SQLite

La version siguiente sera v75. La migracion se basara en un manifiesto explicito de las 355 columnas con: tabla, columna, origen de moneda y regla de escala. El manifiesto tambien servira como prueba de cobertura; no se descubriran columnas por coincidencias de nombre en produccion.

SQLite no permite cambiar de manera fiable la afinidad de una columna existente conservando todas sus restricciones. Cada tabla afectada se reconstruira con DDL canonico:

1. Preflight: confirmar existencia de tabla/columna y afinidad actual mediante `PRAGMA table_info`.
2. Si todas las columnas monetarias de la tabla ya son `INTEGER`, no hacer nada.
3. Si hay mezcla `REAL`/`INTEGER`, abortar salvo que corresponda exactamente a una reanudacion versionada y verificable.
4. Resolver moneda/escala de todas las filas y validar que no haya valores no numericos, no finitos ni fuera de rango tras escalar.
5. Crear `<tabla>__money_v75` con el DDL completo nuevo, columnas monetarias `INTEGER` y las mismas claves, `NOT NULL`, defaults y `CHECK`.
6. Copiar filas usando redondeo determinista: `ROUND(valor * 10^escala)` y `CAST(... AS INTEGER)`. Las filas `NULL` siguen `NULL`; no se fabrican ceros.
7. Verificar conteo de filas, nulos, claves y equivalencia dentro de media unidad menor.
8. Sustituir la tabla y recrear indices, triggers y claves foraneas desde definiciones explicitas.
9. Ejecutar `foreign_key_check`, `integrity_check` y el inventario de tipos antes de confirmar la transaccion.

Toda la v75 sera atomica. Un fallo en cualquier tabla revierte la migracion completa. La base actual casi vacia reduce el riesgo de datos, pero no justifica saltarse estas comprobaciones.

## 7. Instalaciones nuevas y compatibilidad

- Los `CREATE TABLE` de instalaciones nuevas se actualizaran en la misma fase que la migracion v75.
- Seeds monetarios se expresaran como enteros de unidad menor.
- Payloads de sincronizacion y API tendran version de contrato; no se enviara un entero ambiguo sin moneda/escala.
- Exportaciones y reportes convertiran solo al presentar, usando `MoneyValue`.
- No se mantendra lectura silenciosa de `REAL` despues de v75. Una base parcialmente migrada debe fallar de forma visible.

## 8. Pruebas exigidas para la implementacion

1. Inventario: las 355 columnas del manifiesto existen como `INTEGER` y ninguna columna monetaria queda `REAL`.
2. Migracion: valores positivos, negativos, cero, `NULL`, limite y mitad de unidad menor.
3. Idempotencia: reabrir una base v75 no vuelve a multiplicar valores.
4. Integridad: filas, claves foraneas, indices y triggers sobreviven a la reconstruccion.
5. Dinero: `10000.00 - 100 * 99.99` termina exactamente en `1.00`.
6. Flujos comerciales: venta, compra, caja, inventario, nomina, impuestos y contabilidad.
7. Flujos publicos: apropiacion, CDP, RP, obligacion, PAC/pago, nomina, rentas, activos y NICSP.
8. Multimoneda: misma suma por moneda, rechazo de mezcla y conversion con redondeo explicito.
9. Bordes: captura/formato UI, JSON, sincronizacion, Excel/PDF y reportes fiscales.

## 9. Tamano y fases recomendadas

La implementacion no debe ser un unico commit de 355 columnas y 108 consumidores. Orden conservador:

1. Infraestructura `MoneyValue`, escala y manifiesto, sin cambiar tablas.
2. Migracion v75 y DDL de instalaciones nuevas, con pruebas de esquema.
3. Repositorios/modelos comerciales y sus pruebas.
4. Flujos comerciales y bordes UI/reportes.
5. Repositorios/modelos publicos y sus pruebas.
6. Flujos publicos y bordes UI/reportes.
7. Auditoria final que prometa cero dinero `REAL`/`double`, analyze y builds.

No se debe activar v75 hasta que los lectores y escritores de la tabla correspondiente usen unidades menores en el mismo despliegue.

## 10. Decision requerida antes de Fase 2

Se recomienda aprobar esta regla:

> Preservar el soporte multimoneda y almacenar cada monto como `INTEGER` en la unidad menor de su moneda; sector publico usa COP/escala 2, mientras comercial resuelve moneda por fila o empresa y falla cerrado si no puede hacerlo.

La alternativa de multiplicar las 355 columnas por 100 solo es valida si se elimina formalmente el soporte multimoneda y se declara todo el producto COP. El codigo actual contradice ese supuesto, por lo que esa alternativa no se ejecutara sin una decision humana explicita.

## Cierre de la Fase 1

Estado: **Completa en diseno; implementacion no iniciada**.

Decision autonoma conservadora: conservar nombres SQL, usar unidades menores por moneda y detener una fila ambigua en vez de asumir COP. La base fue respaldada y verificada antes de crear este documento. No se modifico `lib/`, `test/` ni la base activa.
