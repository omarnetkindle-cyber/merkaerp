# Cierre general PARTE 1 - Bloque C

## Alcance

Se reemplazo la alerta manual para incapacidades EPS/ARL y licencias de
maternidad/paternidad por una regla local reutilizable para nomina comercial y
nomina publica. La integracion sigue usando `approvedForPeriod` de HRM y no
requiere servicios externos.

## Fuentes normativas consultadas

- Decreto 2943 de 2013, Función Pública, modifica el paragrafo 1 del articulo
  40 del Decreto 1406 de 1999: los dos primeros dias de incapacidad general
  quedan a cargo del empleador.
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=55977
- Concepto Función Pública 024961 de 2024, regla operativa citada para
  enfermedad no profesional: desde el dia 3 y hasta el dia 90 se reconoce
  2/3 del salario.
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=236230
- Ley 776 de 2002, Función Pública: prestaciones economicas por riesgos
  laborales, incapacidad temporal a cargo de la ARL.
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=16752
- Ley 1822 de 2017, Función Pública: licencia de maternidad de 18 semanas.
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=78833
- Ley 2114 de 2021, Función Pública: licencia de paternidad de dos semanas.
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=167967

## Decisión implementada

- `vacaciones` y `permiso_remunerado`: se pagan como dias ordinarios.
- `permiso_no_remunerado`: descuenta dias pagados y auxilio de transporte.
- `incapacidad_eps`: dias 1-2 a cargo del empleador; desde el dia 3 se
  reconoce por EPS a 2/3 del salario en esta ronda.
- `incapacidad_arl`: se reconoce desde el dia 1 a cargo de ARL.
- `licencia_maternidad` y `licencia_paternidad`: se reconocen a cargo de EPS.
- `luto`: queda como revision manual porque no se investigo en este bloque.

La regla vive en `HrmPayrollAbsenceSummary.payrollImpact()` y se consume desde:

- `DatabaseHelper.liquidarNomina()` para nomina comercial.
- `NominaService.liquidarNomina()` para nomina publica.

## Evidencia cruda

### Tests dirigidos

Comando:

```powershell
flutter test test\hrm\hrm_payroll_absence_rules_test.dart test\hrm\hrm_payroll_integration_test.dart --reporter expanded
```

Salida:

```text
00:00 +0: loading C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart
00:00 +0: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart: HrmPayrollAbsenceSummary payrollImpact incapacidad EPS paga dos dias empleador y desde dia 3 a 2/3 EPS
00:00 +1: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart: HrmPayrollAbsenceSummary payrollImpact incapacidad ARL reconoce desde el dia 1 a cargo de ARL
00:00 +2: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart: HrmPayrollAbsenceSummary payrollImpact licencia de maternidad queda a cargo de EPS por el periodo
00:00 +3: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart: HrmPayrollAbsenceSummary payrollImpact licencia de paternidad queda a cargo de EPS por dos semanas
00:00 +4: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_absence_rules_test.dart: HrmPayrollAbsenceSummary payrollImpact tipos no automatizados siguen generando revision manual
00:00 +5: loading C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart
00:00 +5: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina publica usa ausencias HRM vacaciones y permisos aplican el mapeo aprobado
00:01 +6: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina publica usa ausencias HRM incapacidad EPS liquida pagador desde el dia 3
00:01 +7: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina publica usa ausencias HRM sin ausencias conserva el calculo anterior
00:01 +8: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina publica usa ausencias HRM hrm_employee_id nulo liquida con cero ausencias
00:01 +9: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina comercial usa ausencias HRM (setUpAll)
Inicializando tablas del Sector Público para nueva instalación...
00:03 +9: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina comercial usa ausencias HRM permiso no remunerado reduce solo el periodo vinculado
00:03 +10: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina comercial usa ausencias HRM licencia de maternidad queda registrada como pagador EPS
00:03 +11: C:/Users/PC/Desktop/Caja_simple/test/hrm/hrm_payroll_integration_test.dart: nomina comercial usa ausencias HRM (tearDownAll)
00:03 +11: All tests passed!
```

### Analisis dirigido

Comando:

```powershell
dart analyze lib\hrm\application\hrm_payroll_absence_service.dart lib\db_helper.dart lib\sector_publico\nomina\services\nomina_service.dart test\hrm\hrm_payroll_absence_rules_test.dart test\hrm\hrm_payroll_integration_test.dart
```

Salida:

```text
Analyzing hrm_payroll_absence_service.dart, db_helper.dart, nomina_service.dart, hrm_payroll_absence_rules_test.dart, hrm_payroll_integration_test.dart...

   info - lib\db_helper.dart:875:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print
   info - lib\db_helper.dart:891:7 - Don't invoke 'print' in production code. Try using a logging framework. - avoid_print

2 issues found.
```

Los dos issues son preexistentes en `db_helper.dart` y no pertenecen al codigo
tocado por este bloque.

### flutter analyze completo

Comando:

```powershell
flutter analyze > bloque_c_analyze.txt 2>&1
```

Resultado:

```text
239 issues found. (ran in 8.2s)
```

`Select-String` sobre `bloque_c_analyze.txt` encontro `0` lineas `error -`.
No hubo issues en `hrm_payroll_absence_service.dart`, `nomina_service.dart` ni
en los tests nuevos de HRM.
