# Cierre general Parte 1 - Bloque F: Deducciones laborales adicionales en nomina privada

Fecha: 2026-08-13

## Investigacion normativa y fuentes

Fuentes consultadas:

- Ministerio de Justicia, LegalApp, "Que se puede descontar del salario de un trabajador": https://www.minjusticia.gov.co/programas-co/LegalApp/Paginas/Que-se-puede-descontar-del-salario-de-un-trabajador.aspx
- Funcion Publica, Ley 1527 de 2012, marco general para libranza o descuento directo: https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=47213
- Secretaria del Senado, Ley 1527 de 2012: https://www.secretariasenado.gov.co/senado/basedoc/ley_1527_2012.html
- Secretaria del Senado, Codigo Sustantivo del Trabajo, arts. 149 y 154-156: https://www.secretariasenado.gov.co/senado/basedoc/codigo_sustantivo_trabajo_pr005.html
- Funcion Publica, concepto 251611 de 2022, aplicacion de CST art. 156 a embargos por alimentos/cooperativas: https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=198603
- Funcion Publica, concepto 308241 de 2024, retencion de cuota sindical y CST art. 400: https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=268756

Reglas aplicadas:

1. Descuentos de ley obligatorios primero: salud, pension, FSP y retefuente laboral.
2. Embargo por alimentos/cooperativas (`embargo_alimentos`, `embargo_cooperativa`): hasta 50% del neto despues de descuentos de ley.
3. Embargo judicial ordinario (`embargo_judicial`): una quinta parte del excedente sobre SMMLV.
4. Libranza (`libranza`): se aplica solo hasta conservar al menos 50% del neto despues de descuentos de ley.
5. Cuota sindical (`cuota_sindical`): se aplica como descuento legal/comunicado.
6. Prestamo de empresa y deducciones manuales (`prestamo_empresa`, `otrasDeducciones`): se aplican de forma conservadora sin llevar el neto por debajo del SMMLV.

Decision conservadora:

- Reutilizar `payroll_novelties` como entrada operativa, porque ya era la tabla real de novedades de nomina privada.
- No crear una tabla paralela de deducciones en esta ronda para evitar otra representacion redundante.
- Si el neto no alcanza, aplicar la prelacion anterior y guardar advertencia visible en `novedades_hrm`.

## Implementacion

Archivos principales:

- `lib/taxes/payroll_deduction_service.dart`
- `lib/db_helper.dart`
- `test/commercial_payroll_block5_test.dart`

Cambios:

- Nuevo `PayrollDeductionService` con resultado auditable por tipo: solicitado, aplicado, limitado y razon normativa.
- `liquidarNomina()` calcula primero deducciones obligatorias y luego deducciones laborales adicionales con prelacion.
- El asiento contable usa el total aplicado, no el total solicitado, evitando netos negativos o sobre-deducciones.
- `calculo_json` incluye `deducciones_laborales_adicionales`.
- Si algun tope limita deducciones, `novedades_hrm` muestra advertencia.

## Evidencia cruda

### Test del bloque

Comando:

```powershell
flutter test test\commercial_payroll_block5_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/commercial_payroll_block5_test.dart
00:00 +0: (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:02 +0: novedades variables entran al IBC y excluyen auxilio
00:03 +1: health_exonerated elimina salud empleador, SENA e ICBF, no caja
00:03 +2: retefuente laboral aplica la tabla progresiva del articulo 383
00:03 +3: deducciones laborales aplican embargos prestamos y cuota sindical
00:03 +4: prelacion limita embargo ordinario libranza y prestamo si no alcanza
00:03 +5: fallo al registrar asiento revierte caja y liquidacion
00:03 +6: (tearDownAll)
00:03 +6: All tests passed!
```

### Analyze dirigido

Comando:

```powershell
dart analyze lib\taxes\payroll_deduction_service.dart lib\db_helper.dart test\commercial_payroll_block5_test.dart
```

Salida:

```text
Analyzing payroll_deduction_service.dart, db_helper.dart, commercial_payroll_block5_test.dart...

   info - lib\db_helper.dart:876:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:892:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

Los dos issues son `avoid_print` preexistentes en `db_helper.dart`, fuera del cambio del Bloque F.

### Flutter analyze global

Comando:

```powershell
flutter analyze > bloque_f_analyze.txt 2>&1
```

Resultado:

```text
239 issues found. (ran in 6.7s)
Errores: 0
```

