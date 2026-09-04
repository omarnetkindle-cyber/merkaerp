# MerkaERP 1.2.1+5 — Revisión visual integral y preparación para entornos de prueba

**Fecha:** 17 de agosto de 2026  
**Alcance:** aplicación MerkaERP únicamente. El Control Center queda expresamente fuera de esta entrega.  
**Familias:** MerkaERP Comercial y MerkaERP Público, separadas por licencia.

## 1. Objetivo

La revisión no se limitó a la pantalla principal. Se inspeccionó la composición visual y la accesibilidad operativa de las pantallas Page/Screen detectadas en la aplicación y se aplicaron mejoras transversales para que módulos, submódulos y diálogos compartan una identidad coherente, legible y entendible para usuarios nuevos.

## 2. Identidad visual preservada

Se mantuvo la identidad cromática existente de O&W/MerkaERP:

- Azul marino: navegación, encabezados, acciones estructurales y jerarquía visual.
- Dorado: acentos, selección y elementos distintivos de marca.
- Grafito y fondos claros: lectura, superficies y separación visual.
- Verde, amarillo/naranja y rojo: reservados principalmente para estados semánticos de éxito, advertencia y error.

No se sustituyó la identidad por una nueva paleta.

## 3. Mejoras globales aplicadas

- Unificación del tema Material 3 en botones, campos, tarjetas, diálogos, menús, tablas, pestañas y navegación.
- Estilos consistentes para TextButton, OutlinedButton, Filled/ElevatedButton, SegmentedButton, Checkbox, Radio y Switch.
- Unificación de NavigationBar, NavigationDrawer, Drawer, DropdownMenu, SearchBar, ExpansionTile, DatePicker, TimePicker, banners, badges e indicadores de progreso.
- Superficies, bordes y estados seleccionados sensibles al tema, evitando colores aislados heredados.
- Sustitución de colores decorativos no corporativos por la paleta azul marino/dorado/grafito cuando el color no representaba un estado funcional.
- Conservación deliberada de colores semánticos cuando comunican éxito, advertencia o error.
- Diálogos administrativos grandes ajustados mediante dimensionamiento responsivo para reducir desbordes en pantallas pequeñas.
- Pestañas extensas configuradas con desplazamiento horizontal donde corresponde.
- Tooltips explicativos en botones de icono auditados para que el usuario no dependa de reconocer el símbolo por experiencia previa.
- Eliminación de referencias visuales al antiguo teal `#006D77` en las pantallas auditadas.
- Fondo del icono adaptativo Android alineado con el azul marino corporativo.

## 4. Navegación pública corregida

Durante la revisión profunda se encontraron funciones existentes que podían estar habilitadas pero no tenían acceso directo normal desde el workspace Público. Se corrigió la composición para exponer, bajo la familia/licencia correspondiente:

- Regalías y SGP.
- Salud Pública.
- SIIF con acceso directo dentro del conjunto de control/interoperabilidad pública.

Esto evita que una capacidad implementada quede técnicamente existente pero operacionalmente inaccesible.

## 5. Separación Comercial / Público

La revisión conserva el principio definido para el producto:

- Una licencia Comercial compone únicamente la experiencia Comercial.
- Una licencia Pública compone únicamente la experiencia Pública.
- No se añadió ningún selector para intercambiar familias.
- Los colores, navegación y módulos se ajustan dentro de cada familia sin romper el núcleo visual compartido.

## 6. Auditor estático de interfaz

Se incorporó `tool/ui_static_audit.py` para detectar regresiones de consistencia en futuras versiones. En la revisión de esta entrega:

- 78 archivos Page/Screen revisados.
- 0 incidencias auditadas de paleta corporativa retirada.
- 0 IconButton auditados sin tooltip.
- 0 diálogos grandes auditados con tamaño rígido problemático.
- 0 TabBars largas auditadas sin desplazamiento donde se requiere.
- 0 colores decorativos heredados detectados por las reglas del auditor.

Resultado: **PASS**.

## 7. Manuales completos

Se produjeron dos manuales Word independientes:

1. `MANUAL_COMPLETO_MERKAERP_COMERCIAL_1.2.1_5.docx` — 51 páginas renderizadas.
2. `MANUAL_COMPLETO_MERKAERP_PUBLICO_1.2.1_5.docx` — 51 páginas renderizadas.

Los documentos fueron redactados para usuarios sin experiencia previa e incluyen conceptos básicos de uso del computador, instalación, ingreso, onboarding, operación, explicación de controles, procedimientos, motivos de cada proceso, buenas prácticas, migración, continuidad, solución de problemas, glosario y un capítulo dedicado de seguridad.

El encabezado se dejó libre para facilitar la incorporación posterior del membrete de O&W Asesorías.

## 8. Seguridad explicada con transparencia

Los manuales detallan permisos, roles, auditoría, hashes, respaldos, integraciones fail-closed, almacenamiento seguro de secretos y prácticas de protección del equipo. También informan expresamente una limitación actual: el archivo SQLite completo no se declara cifrado integralmente en reposo mientras no exista un motor SQLCipher/SQLite3MC integrado y validado. Se recomiendan cifrado del dispositivo, protección de Windows, mínimo privilegio y respaldos externos protegidos.

Esta transparencia evita prometer una propiedad de seguridad que la edición actual no implementa integralmente.

## 9. Verificaciones disponibles en este entorno

- `python tool/ui_static_audit.py`: PASS.
- `python tool/release_static_check.py`: PASS.
- Revisión visual completa de los 51 + 51 folios renderizados de los manuales Word: PASS.

## 10. Límite de esta validación

Este entorno no dispone del SDK Flutter/Dart. Por tanto, esta entrega **no declara** `flutter analyze`, `flutter test`, pruebas widget/golden/accessibility ni build release como ejecutados aquí. Esos controles deben realizarse sobre la entrega exacta en el equipo de pruebas mediante `build_release.bat` y luego el checklist Go-Live/UAT.

## 11. Recomendación para el siguiente paso

1. Extraer la entrega en una carpeta nueva.
2. Ejecutar `build_release.bat`.
3. Corregir cualquier error que reporte el toolchain real antes de continuar.
4. Instalar en un entorno de prueba, no sobre datos productivos.
5. Ejecutar UAT Comercial y Público según la licencia de prueba.
6. Probar backup, restore drill y migración con copias de datos de prueba.
7. Solo después de la aceptación funcional pasar a una liberación productiva.
