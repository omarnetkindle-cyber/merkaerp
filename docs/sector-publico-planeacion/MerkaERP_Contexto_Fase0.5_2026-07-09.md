# MerkaERP — Contexto para retomar (Fase 0.5, en curso)

**Fecha de este resumen:** 9 de julio de 2026
**Repositorio:** `C:\Users\PC\Desktop\Caja_simple` (rama `main`)
**Último commit confirmado:** `a39c4d9`

---

## 1. Cómo usar este documento

Para retomar esta conversación con Claude en una sesión nueva, sube junto con
este archivo los tres documentos base del proyecto:

- `MerkaERP_Plan_Maestro_v4.md` — plan técnico de 9 fases (0 a 8).
- `MerkaERP_SectorPublico_Plan_v1_1.md` — plan de producto/negocio con base normativa.
- `MerkaERP_Informe_Estado_Fase0_Completa.md` — informe original de cierre de Fase 0.

Y dile a Claude, literalmente: *"Lee estos documentos y este resumen de
contexto. Ya cerramos Fase 0 y llevamos 3 de 5 archivos resueltos en
'Fase 0.5' (limpieza de test/). Acabo de enviarle al agente el prompt de
diagnóstico de los últimos 2 archivos — toca esperar/traer su respuesta."*

**Rol de Claude en esta conversación:** asesor y filtro de calidad. No
implementa código directamente — hay un agente de IA separado que ejecuta
sobre el repo, y el usuario trae los resultados (diffs, greps, salidas de
`flutter analyze`/`flutter test`) para que Claude los audite antes de
aprobar cada paso, siguiendo el mismo rigor que ya se estableció en Fase 0
(evidencia cruda, no resúmenes; explicar en una frase simple por qué un fix
es correcto en términos de negocio, no solo de tipos).

---

## 2. Dónde estamos exactamente

### Fase 0 — ✅ Completada y comiteada (antes de esta conversación)
`lib/` compila con 0 errores (52 warnings, 121 infos, no bloquean).

### "Fase 0.5" — ⏳ En curso (no es fase formal del plan, es limpieza de `test/`
decidida como prerrequisito antes de Fase 1, siguiendo la regla de oro del
plan maestro: `flutter analyze` + `flutter test` limpios antes de avanzar)

Diagnóstico original: 100 errores en `test/`, repartidos en 5 archivos.

| Archivo | Errores | Estado |
|---|---|---|
| `roles_permisos_service_test.dart` | 18 | ✅ Resuelto y comiteado |
| `intereses_moratorios_service_test.dart` | 2 | ✅ Resuelto y comiteado |
| `nomina_service_test.dart` | 14 | ✅ Resuelto y comiteado |
| `presupuesto_service_test.dart` | 35 | ⏳ **Diagnóstico solicitado, respuesta del agente pendiente de traer** |
| `contratacion_service_test.dart` | 31 | ⏳ **Diagnóstico solicitado, respuesta del agente pendiente de traer** |

### Fase 1 (según plan maestro) — "Auditoría y adelgazamiento de `main.dart`"
Aún no iniciada. Se acordó cerrar Fase 0.5 completa antes de saltar ahí.

---

## 3. Commit `a39c4d9` — qué contiene (ya cerrado, no reabrir)

7 archivos, verificados uno por uno con diffs completos antes de aprobar:

1. **`lib/sector_publico/nomina/models/empleado.dart`** — fix de
   deserialización: `activo: json['activo'] as bool` → acepta también
   `int` (0/1), porque SQLite no tiene tipo bool nativo. Necesario para que
   el test de integración de nómina pudiera insertar datos reales.
2. **`lib/sector_publico/rentas/services/intereses_moratorios_service.dart`**
   — rename de clase `InteresionMoratoriosService` (typo) →
   `InteresesMoratoriosService`. Confirmado por grep: solo 3 call sites en
   todo `lib/`.
3. **`lib/sector_publico/rentas/services/cobro_coactivo_service.dart`** —
   actualizado al nuevo nombre de clase (call site).
4. **`lib/sector_publico/rentas/services/predial_service.dart`** —
   actualizado al nuevo nombre de clase (call site).
5. **`test/sector_publico/security/roles_permisos_service_test.dart`** —
   reescrito contra la API real (`puedeRealizarAccion`,
   `validarSegregacionFunciones`, `negacionesPorRol`). 5 tests, todos pasan.
6. **`test/sector_publico/rentas/intereses_moratorios_service_test.dart`** —
   actualizado al nuevo nombre de clase. 2 tests, todos pasan.
7. **`test/sector_publico/nomina/nomina_service_test.dart`** — reescrito
   como prueba de integración sobre `liquidarNomina()` completo (sin tocar
   `lib/nomina_service.dart`). 4 escenarios: fondo de solidaridad (0%/1%/2%
   con umbrales de 4 y 16 SMMLV) y auxilio de transporte en su límite
   exacto (2 SMMLV = 1,817,052). Todos pasan.

**No comiteado, sigue untracked (correcto, no forma parte del proyecto):**
`backend_RESPALDO_20260708/`, `diff_full.txt`.

---

## 4. Hallazgos y deuda técnica documentados en el mensaje de commit
(reales, ya registrados en el historial de git — no se resolvieron, solo se anotaron)

1. **`roles_permisos_service.dart` — `puedeRealizarAccion()`** no compara
   `usuarioId`/`referenciaId` en la rama `aprobarPago` + `tesorero`. Bloquea
   a **todo** tesorero para **todo** pago, no solo auto-aprobación. Es más
   estricto de lo necesario, no inseguro. **Pendiente para Fase 6** (roles).

2. **SMMLV hardcodeado** en `_calcularAuxilioTransporte()`
   (`nomina_service.dart`): valor `908526` con comentario `"SMMLV 2024"`, sin
   ningún mecanismo de actualización — a diferencia de `tasaMoraMensual`
   (intereses moratorios), que sí tiene `actualizarTasaUsuraDesdeSuperfinanciera()`
   y actualización manual. Han pasado 2 actualizaciones anuales de SMMLV
   desde 2024. También hay una variable `auxilioMaximo` calculada pero
   nunca usada en la condición (código muerto, no afecta el resultado
   actual). **No se tocó, queda como deuda técnica.**

3. **`presupuesto_publico_page_test.dart` — fallo runtime nuevo**, no
   detectado por `flutter analyze` (compila bien, falla al ejecutar):
   columna `identificacion` faltante en el esquema SQLite de prueba,
   `LateInitializationError` en `db`, timeout. **No estaba en el
   diagnóstico original de 100 errores** (ese solo cubría errores de
   compilación). Relacionado con el módulo de presupuesto — probablemente
   vale la pena revisarlo junto con `presupuesto_service_test.dart` cuando
   se llegue a él.

4. **Cobertura de test perdida (no recuperable con lo que existe hoy) en
   predial:** el `intereses_moratorios_service_test.dart` original tenía 5
   tests que llamaban a `validarTopeIncremento()` y
   `calcularDescuentoProntoPago()` sobre `InteresesMoratoriosService` —
   métodos que **no existen bajo ese nombre en ningún archivo actual**
   (confirmado con grep en `lib/` y `test/` completos, 0 resultados). La
   lógica equivalente hoy vive en los modelos:
   - `Predio.cumpleTopeIncremento(double ipcAnual)` en
     `lib/sector_publico/rentas/models/predio.dart`
   - `LiquidacionPredial.aplicaDescuentoProntoPago()` en
     `lib/sector_publico/rentas/models/liquidacion_predial.dart`

   **No hay cobertura de test actual para ninguna de las dos reglas.**
   `calcularDescuentoProntoPago`/`aplicaDescuentoProntoPago` ya tuvo un
   historial de 4 intentos fallidos durante Fase 0 (caso de estudio de
   `predial_service.dart` en el informe original) antes de resolverse
   correctamente — por eso esta cobertura faltante se marcó como
   **prioridad, no limpieza menor**, para la próxima ronda sobre el módulo
   predial (probablemente no es parte formal de Fase 0.5/1, sino que merece
   su propio prompt específico más adelante).

---

## 5. Patrón de verificación establecido en esta conversación
(mantenerlo igual para lo que sigue)

1. **No aceptar "patrón simple" solo porque el diagnóstico original lo
   clasificó así.** Ya pasó una vez (`intereses_moratorios`) que el test
   viejo apuntaba a métodos que migraron o desaparecieron — hay que
   verificar con grep antes de asumir que es solo rename de parámetros.
2. **Toda evidencia debe ser cruda:** greps reales, diffs completos, salida
   completa de `flutter test` (no solo "N tests passed", sino los nombres
   de cada test).
3. **Scope creep se investiga, no se asume ni se rechaza automáticamente.**
   El cambio no autorizado en `empleado.dart` (Fase de nómina) se aceptó
   porque la explicación fue verificable y necesaria. Cualquier cambio fuera
   del archivo pedido debe explicarse en una frase simple de por qué era
   necesario.
3.b. **Cobertura de test insuficiente se rechaza aunque "pase".** Pasó con
   el primer intento de `nomina_service_test.dart` (1 solo caso, sin
   ejercitar los umbrales de fondo de solidaridad ni auxilio de transporte)
   — se pidió expandir a 4 escenarios antes de aprobar.
4. **Un solo commit al final de cada archivo/tarea verificada**, con
   `git add` explícito (nunca `-A` ni `.`), mensaje de commit que documente
   cada pieza por separado y toda la deuda técnica/hallazgos descubiertos en
   el camino (aunque no se resuelvan).
5. **No implementar fixes en la misma respuesta que el diagnóstico** cuando
   se pide explícitamente "no implementes todavía" — es señal de alerta si
   el agente se adelanta.

---

## 6. Último prompt enviado al agente (9 julio 2026, respuesta aún no recibida)

```
Gracias, commit a39c4d9 confirmado. Seguimos con los dos archivos que faltan
de Fase 0.5. Trátalos con el mismo rigor que intereses_moratorios: no asumas
que es solo "actualizar nombres de parámetros" porque el diagnóstico
original lo clasificó así — ya nos topamos con un caso donde el test viejo
apuntaba a métodos que ya no existen en ningún lado.

1. presupuesto_service_test.dart (35 errores)
   Antes de tocar el test:
   - Corre flutter analyze test/sector_publico/presupuesto/presupuesto_service_test.dart
     y lista los 35 errores agrupados por tipo (nombres de parámetro vs.
     métodos inexistentes vs. otra cosa).
   - Para cada método o clase que el test llama y que dé error de "no
     definido" o "no existe", haz grep en lib/sector_publico/presupuesto/
     para confirmar si migró de nombre/ubicación o si genuinamente ya no
     existe en ningún lado (como pasó con validarTopeIncremento).
   - No reescribas nada todavía. Dame el listado clasificado:
     a) parámetros/nombres que solo cambiaron (fix simple, 1:1)
     b) métodos que migraron a otra clase/archivo (necesito saber a dónde)
     c) métodos que ya no existen en ningún lado (posible pérdida de
        cobertura, como el caso de predial)

2. contratacion_service_test.dart (31 errores)
   Mismo procedimiento: flutter analyze, clasificación de los 31 errores en
   los mismos tres grupos (a, b, c), con grep de verificación antes de
   asumir nada.

No implementes ningún fix todavía en ninguno de los dos archivos — solo el
diagnóstico clasificado, con la evidencia de grep para cada caso del grupo
(b) y (c).
```

---

## 7. Próximo paso inmediato al retomar

1. Traer la respuesta del agente al prompt de la sección 6 (clasificación
   a/b/c de ambos archivos, con evidencia de grep).
2. Revisarla con el mismo rigor que `intereses_moratorios` — prestar
   especial atención a cualquier método en el grupo (c) ("ya no existe en
   ningún lado"), porque eso puede señalar otra pérdida de cobertura de
   lógica de negocio real, no solo un rename.
3. Decidir juntos, caso por caso, si se reescribe el test contra la API
   actual, si se restaura cobertura para lógica migrada de ubicación, o si
   se documenta como deuda técnica — igual que se hizo con predial.
4. Una vez resueltos y comiteados ambos archivos, Fase 0.5 queda cerrada
   por completo (5/5), y se puede pasar a Fase 1 del plan maestro
   ("Auditoría y adelgazamiento de `main.dart`").

---

## 8. Resumen ejecutivo de una línea

**Fase 0 cerrada. Fase 0.5 (limpieza de test/) en 3/5 archivos comiteados
(commit `a39c4d9`), con 4 hallazgos documentados como deuda técnica
(segregación de funciones de tesorero, SMMLV hardcodeado, fallo runtime
nuevo en presupuesto_publico_page_test.dart, y cobertura perdida de topes/
descuento predial). Faltan 2 archivos (`presupuesto_service_test.dart`,
`contratacion_service_test.dart`) — diagnóstico ya solicitado al agente,
respuesta pendiente de traer a la conversación. Fase 1 del plan maestro
("main.dart") no ha empezado.**
