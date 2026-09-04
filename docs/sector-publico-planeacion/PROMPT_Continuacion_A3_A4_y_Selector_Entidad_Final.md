# PROMPT — Continuación: A.3/A.4 + Selector de Entidad (matriz definitiva, todos los tipos)

> Continuación de los prompts anteriores. Ya cerraste A.1 (fundacional) y A.2 (integraciones externas). Este prompt cubre lo que falta de la Parte A (A.3 huecos funcionales, A.4 UI real) y la Parte B completa con la matriz ya decidida: **vas a vender desde el arranque a municipios, gobernaciones y hospitales/ESE por igual**, así que ningún tipo de entidad es "secundario" — todos necesitan sus módulos completos, no una versión reducida.

---

## Antes de avanzar: cierra el pendiente de A.1

Pídele primero al agente que resuelva esto, no lo dejes acumular:

> "¿Dónde se está almacenando la clave maestra de `encryption_service.dart`? Impleméntala con un mecanismo de gestión de secretos (variable de entorno fuera del repo, keystore del sistema operativo, o un servicio de secretos si ya existe uno en la infraestructura de MerkaERP) — nunca hardcodeada ni en la misma base de datos que cifra. Documenta también la estrategia de rotación de clave."

---

## PARTE A (continuación) — A.3 y A.4

### A.3 — Huecos funcionales pendientes (por fase, mismo orden del roadmap)

- **Fase 2 (Contabilidad NICSP):**
  - Job/proceso de depreciación automática que se ejecute periódicamente (mensual) sobre los activos configurados en la Fase 8, generando el asiento contable correspondiente sin intervención manual.
  - Lógica completa de provisiones NICSP 19 (hoy solo hay tabla, falta el cálculo y el asiento automático).
  - Lógica completa del Estado de Flujos de Efectivo (NICSP 2) — método directo o indirecto, a definir con el criterio contable que ya usa MerkaERP en su módulo comercial si existe.

- **Fase 4 (Rentas): construir ICA completo** — censo de contribuyentes, declaración bimestral/anual, ReteICA, impuesto de avisos y tableros. Esto no se hizo en la Fase 4 original (solo se hizo predial); es un módulo completo, no un ajuste menor.

- **Fase 5 (Contratación):** interventoría/supervisión (registro de informes de supervisor, alertas de incumplimiento) y liquidación de contratos (acta de liquidación, verificación de saldos a favor/en contra, cierre del expediente contractual).

- **Fase 6 (Nómina):**
  - Horas extra y recargos nocturnos/dominicales/festivos según las reglas del Código Sustantivo del Trabajo aplicables a trabajadores oficiales.
  - Auxilio de alimentación donde aplique por convención o decreto territorial.
  - **Régimen docente territorial completo** — tiene su propia escala salarial (Decreto 1278/2002 o 2277/1979 según el caso) distinta a los otros 5 regímenes ya implementados; no reutilices la lógica de los otros regímenes para docentes, tienen grado/nivel/tiempo de servicio como variables propias.

- **Fase 7 (Planeación):** formulación MGA completa (los 8 campos obligatorios: problema central, objetivo, alternativas, población, localización, cadena de valor, indicadores, fuentes de financiación) y flujo de viabilización (quién aprueba técnica y financieramente antes de que el proyecto pueda recibir CDP/RP).

- **Fase 8 (Activos):** revalorización de activos (NICSP 17 permite modelo de revaluación, no solo costo) y al menos un método de depreciación adicional a línea recta (unidades de producción es común para maquinaria pública).

- **Fase 10 (SGR/SGP):** validación de que la distribución de regalías siga las reglas legales de asignación (hoy se puede registrar cualquier distribución sin validar contra las reglas del Sistema General de Regalías por tipo de entidad y tipo de proyecto).

- **Fase 11 (Transparencia):** integración real con el portal de transparencia público (hoy el reporte se genera pero no se publica automáticamente).

### A.4 — UI real (reemplazar placeholders)

Sigue este orden de prioridad, construyendo formularios funcionales conectados a los servicios reales (no solo maquetas), con el mismo estilo visual que ya usa el módulo comercial de MerkaERP:

1. Presupuesto Público + PAC
2. Contabilidad NICSP
3. Contratación Pública + SECOP II
4. Nómina Pública + PILA
5. Rentas (Predial + ICA, una vez esté completo)
6. Salud Pública (RIPS/EPS/Glosas)
7. Activos del Estado + FUT
8. Planeación + Banco de Proyectos + PDT
9. SGR/SGP
10. Auditoría Forense + CHIP
11. Transparencia + Disciplinario + Consolidación NICSP 40

Al cerrar cada UI, confirma que los bloqueos normativos duros (los mismos que ya tienen prueba unitaria) también se reflejan en la interfaz con mensajes de error claros para el usuario final — no solo como excepción técnica.

---

## PARTE B — Selector de tipo de entidad (definitivo, todos los tipos desde el arranque)

Como vas a vender a los tres tipos de entidad pública desde el inicio, la matriz de módulos debe estar **completa para los tres**, no reducida. Esto implica un módulo nuevo que no estaba en el plan original: **Rentas Departamentales**, porque las gobernaciones no cobran predial (eso es municipal) sino impuesto de vehículos, registro, licores/cerveza y estampillas departamentales.

### B.1 — Estructura del selector (sin cambios respecto al prompt anterior)

**Paso 1 — Tipo de entidad:** `Empresa privada / comercial` (default) | `Entidad pública`

**Paso 2 — Si es pública, Tipo de entidad pública:** `Municipio / Alcaldía` | `Gobernación / Departamento` | `Hospital público / ESE` | `Otro ente descentralizado`

### B.2 — Matriz de visibilidad de módulos (definitiva)

| Módulo | Municipio | Gobernación | Hospital/ESE | Otro ente |
|---|---|---|---|---|
| Presupuesto Público + PAC | ✅ | ✅ | ✅ | ✅ |
| Contabilidad NICSP | ✅ | ✅ | ✅ | ✅ |
| Auditoría Forense + CHIP | ✅ | ✅ | ✅ | ✅ |
| Predial + ICA | ✅ | ❌ | ❌ | ✅ (opcional) |
| **Rentas Departamentales (nuevo)** | ❌ | ✅ | ❌ | ✅ (opcional) |
| Contratación + SECOP II | ✅ | ✅ | ✅ | ✅ |
| Nómina Pública + PILA | ✅ | ✅ | ✅ | ✅ |
| Planeación + Banco Proyectos + PDT | ✅ | ✅ | ❌ | ✅ (opcional) |
| Activos del Estado + FUT | ✅ | ✅ | ✅ | ✅ |
| Salud Pública: RIPS/EPS/Glosas | ❌ | ❌ | ✅ | ✅ (opcional) |
| SGR (Regalías) | toggle por entidad* | toggle por entidad* | toggle por entidad* | toggle por entidad* |
| SGP | ✅ (4 componentes) | ✅ (4 componentes) | ✅ (solo componente salud) | ✅ (opcional) |
| Transparencia + Disciplinario | ✅ | ✅ | ✅ | ✅ |
| Consolidación NICSP 40 | ❌ | ✅ | ❌ | ❌ |

*SGR no se activa solo por tipo de entidad: se activa con un toggle adicional en la ficha de la entidad ("¿Esta entidad recibe recursos de regalías?"), porque no todos los municipios/gobernaciones/hospitales son beneficiarios directos.

### B.3 — Nuevo módulo a construir: Rentas Departamentales

Como vas a vender a gobernaciones desde el arranque, este módulo ya no es opcional para después — constrúyelo con el mismo nivel de profundidad normativa que Predial/ICA:

- **Impuesto de vehículos automotores:** liquidación según avalúo comercial (tabla del Ministerio de Transporte) y tarifa según cilindraje, con el mismo motor de intereses moratorios ya construido en `intereses_moratorios_service.dart` de la Fase 4 (reutilízalo, no lo dupliques).
- **Impuesto de registro:** sobre actos/contratos sujetos a registro en Cámara de Comercio o registro de instrumentos públicos, tarifa según tipo de acto.
- **Impuesto al consumo de licores, vinos, aperitivos y cerveza:** liquidación por productor/distribuidor, con las tarifas diferenciadas de la Ley 1816/2016.
- **Estampillas departamentales:** las que aplique cada departamento por ordenanza (pro-desarrollo, pro-cultura, etc.) — modela esto como catálogo configurable por entidad, porque varía mucho entre departamentos, no lo hardcodees con una lista fija de estampillas.

### B.4 — Implementación técnica (sin cambios de fondo respecto al prompt anterior)

- Modela la matriz de B.2 como datos (`modulos_por_tipo_entidad`), no como código — así el toggle de SGR y las variaciones por entidad se resuelven con datos, no con despliegues.
- Agrega `tipo_entidad` y `subtipo_entidad_publica` al modelo `Entidad` de la Fase 0, no crees un modelo paralelo.
- El selector de módulos ya existente en la pantalla de configuración debe leer esta tabla al renderizarse.
- Permite cambiar el tipo de entidad después del onboarding inicial, desde configuración general, recalculando módulos disponibles sin perder datos de módulos que sigan siendo válidos.
- Mantén separada la lógica de "qué módulos existen para esta entidad" (Parte B) de "quién puede usarlos dentro de la entidad" (roles y permisos de la Fase 0).

### B.5 — Entregable de la Parte B

- Selector de tipo/subtipo de entidad en el onboarding.
- Tabla de visibilidad de módulos con la matriz de B.2 como semilla, incluyendo el toggle independiente de SGR.
- Módulo nuevo de Rentas Departamentales (modelos, esquema, servicio, página UI), siguiendo el mismo patrón de calidad normativa que Predial/ICA.
- Pantalla de configuración general para cambiar tipo de entidad después del onboarding.

---

## Orden de trabajo sugerido

1. Cerrar el pendiente de la clave maestra de encriptación (5 minutos de este prompt, no más).
2. A.3 completo, en el orden en que está listado arriba.
3. Parte B completa (puede ir en paralelo a A.3/A.4 si tienes más de un desarrollador, porque toca partes distintas del código: onboarding + nuevo módulo de rentas departamentales vs. lógica de negocio de los módulos existentes).
4. A.4 al final, una vez todos los módulos —incluyendo Rentas Departamentales— tengan su lógica de negocio cerrada, para no construir UI dos veces.

Al cerrar cada bloque, pide el mismo resumen de cierre de siempre: archivos creados/modificados, qué quedó implementado, qué quedó pendiente o simplificado.
