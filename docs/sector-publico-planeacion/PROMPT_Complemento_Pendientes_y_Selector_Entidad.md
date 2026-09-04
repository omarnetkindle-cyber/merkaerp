# PROMPT — Cierre de Pendientes + Selector de Tipo de Entidad (Sector Público MerkaERP)

> Este prompt es continuación directa del Prompt Maestro anterior. Pégalo completo al agente. Ya tienes 12 fases con la arquitectura funcional pero con brechas marcadas en cada resumen de cierre (⚠️). Este prompt tiene dos partes: **Parte A** cierra esas brechas, **Parte B** agrega el selector de tipo de entidad en la configuración inicial. Haz primero la Parte A (bloque de seguridad/datos), y en paralelo o después la Parte B, que es independiente.

---

## PARTE A — Cerrar brechas pendientes de las 12 fases

No repitas trabajo ya hecho. Ve fase por fase, pero agrupa el trabajo por tipo para no perder tiempo saltando de contexto en contexto.

### A.1 — Fundacional (bloqueante, hazlo primero)

- **Integración real con base de datos.** Todos los servicios de las 12 fases están escritos pero, según los propios resúmenes de cierre, no probados contra una base de datos real. Conecta `schema_multi_tenant.dart`, `schema_presupuesto.dart`, `schema_contabilidad.dart`, `schema_auditoria.dart`, `schema_rentas.dart`, `schema_contratacion.dart`, `schema_nomina.dart`, `schema_planeacion.dart`, `schema_activos.dart`, `schema_salud.dart`, `schema_regalias.dart` y `schema_transparencia.dart` al motor de base de datos que ya usa el ERP comercial de MerkaERP (revisa qué usa hoy el módulo comercial — probablemente SQLite local + sincronización, o Postgres — y sigue ese mismo patrón, no introduzcas un motor nuevo).
- **MFA (autenticación multifactor)** — implementa lo que quedó solo documentado en `iso_27001_requirements.md` de la Fase 0. Mínimo: TOTP (Google Authenticator/Authy) obligatorio para roles con permisos de aprobación (Tesorero, Secretario de Hacienda, Alcalde/Representante legal, Contador).
- **Encriptación AES-256** de datos sensibles en reposo (terceros, nómina, cuentas bancarias) — también quedó solo documentada, impleméntala.
- **Pruebas unitarias del camino normativo duro** en las 12 fases. No necesitas cobertura exhaustiva de UI; el mínimo no negociable es: para cada validación marcada como "✅ Implementada (Dura)" en los resúmenes de cierre, debe existir al menos una prueba que confirme que el sistema **bloquea** la operación cuando se viola la regla (ej.: "no debe poder pagarse una obligación sin RP previo", "un tesorero no puede aprobar su propio pago", "no se puede exceder el cupo PAC").

### A.2 — Integraciones externas reales (hoy son placeholders)

- `secop_service.dart` (Fase 5): reemplazar el placeholder por integración real con la API de SECOP II vía X-Road, incluyendo autenticación, publicación de proceso, recepción de ofertas, publicación de adjudicación.
- `pila_service.dart` (Fase 6): integración real con el operador de información PILA (formato plano ya existe; falta el envío/recepción real).
- `chip_reporter_service.dart` (Fase 3): validar el formato plano generado contra las especificaciones exactas publicadas por la CGN (hoy no está validado).
- `rips_service.dart` (Fase 9): validar los 6 archivos RIPS contra la Resolución 2275/2023 antes de permitir el envío a EPS (hoy no hay validación de formato).
- `predial_service.dart` (Fase 4): automatizar la actualización periódica de la tasa de usura desde la Superintendencia Financiera (hoy es manual).
- Banco de Proyectos (Fase 7): evaluar integración real con el BPIN del DNP en vez de un BPIN generado localmente.

### A.3 — Funcionalidad simplificada que quedó a medias (por fase)

- **Fase 2 (Contabilidad NICSP):** depreciación automática (hoy solo hay configuración, falta el job/proceso que la ejecute), lógica completa de provisiones NICSP 19, lógica completa del Estado de Flujos de Efectivo (NICSP 2) — hoy está simplificada.
- **Fase 4 (Rentas):** el módulo de **ICA (Industria y Comercio) no se implementó**, solo predial. Esto quedó marcado explícitamente como pendiente — impleméntalo completo: censo de contribuyentes, declaración bimestral/anual, ReteICA, impuesto de avisos y tableros.
- **Fase 5 (Contratación):** interventoría/supervisión y liquidación de contratos no se implementaron — solo el flujo hasta contrato firmado.
- **Fase 6 (Nómina):** horas extra, recargos nocturnos, auxilio de alimentación y el cálculo especial del régimen docente territorial (que tiene su propia escala salarial, distinta a los otros 5 regímenes) no se implementaron.
- **Fase 7 (Planeación):** la formulación MGA completa (los 8 campos obligatorios del proyecto) y la viabilización quedaron simplificadas — hoy solo hay registro básico de proyecto.
- **Fase 8 (Activos):** revalorización de activos y métodos de depreciación distintos a línea recta no se implementaron.
- **Fase 10 (SGR/SGP):** falta la validación de que la distribución de regalías siga las reglas legales de asignación por tipo de entidad (hoy se puede registrar cualquier distribución).
- **Fase 11 (Transparencia):** integración con el portal de transparencia público (hoy solo genera el reporte internamente, no lo publica).

### A.4 — UI real (hoy son placeholders en casi todas las fases)

Todas las páginas (`*_page.dart`) de las 12 fases están marcadas como UI básica/placeholder. Constrúyelas como formularios funcionales conectados a los servicios reales, siguiendo el estilo visual que ya usa el ERP comercial de MerkaERP (no un estilo nuevo). Prioriza en este orden: Presupuesto/PAC → Contabilidad → Contratación → Nómina → Rentas → el resto.

### Orden sugerido para la Parte A

1. A.1 completo (base de datos real + MFA + encriptación + pruebas del camino duro) — sin esto, nada de lo demás es confiable.
2. A.3 (huecos funcionales) fase por fase, en el mismo orden del roadmap original (0→11).
3. A.2 (integraciones externas) — estas dependen de credenciales/convenios reales con cada entidad externa (SECOP, PILA, EPS, DNP), así que probablemente necesites datos de conexión de un cliente piloto antes de poder probarlas de verdad. Si no los tienes, deja la integración lista con mocks claramente marcados como tales.
4. A.4 (UI real) al final, o en paralelo si tienes más de un desarrollador.

---

## PARTE B — Selector de tipo de entidad en la configuración inicial

### B.1 — Qué existe hoy

MerkaERP tiene una pantalla de configuración inicial donde, la primera vez que el cliente entra, llena los datos de la empresa y elige qué módulos comerciales quiere activar (ventas/POS, inventario, contabilidad, nómina, etc.).

### B.2 — Qué hay que agregar

Un **selector de tipo de entidad** en esa misma pantalla, ANTES o junto al selector de módulos, con esta estructura:

**Paso 1 — Tipo de entidad** (campo nuevo, obligatorio):
- `Empresa privada / comercial` (default, es el comportamiento actual de MerkaERP sin cambios)
- `Entidad pública`

**Paso 2 — Si elige "Entidad pública", aparece un segundo campo: Tipo de entidad pública:**
- `Municipio / Alcaldía`
- `Gobernación / Departamento`
- `Hospital público / ESE`
- `Otro ente descentralizado` (opción de respaldo genérica que muestra todos los módulos públicos disponibles, para no bloquear a un tipo de entidad que no encaje en las tres anteriores — p. ej. una asamblea departamental o un concejo municipal)

Este segundo campo determina **qué módulos del Sector Público se ofrecen** en el selector de módulos que ya existe hoy. No reemplaces el selector de módulos actual: alimenta su lista de opciones disponibles según el tipo de entidad elegido.

### B.3 — Matriz de visibilidad de módulos por tipo de entidad (punto de partida — ver nota de diseño abajo)

| Módulo (Fase) | Municipio/Alcaldía | Gobernación | Hospital/ESE | Otro ente |
|---|---|---|---|---|
| Presupuesto Público + PAC (Fase 1) | ✅ | ✅ | ✅ | ✅ |
| Contabilidad NICSP (Fase 2) | ✅ | ✅ | ✅ | ✅ |
| Auditoría Forense + CHIP (Fase 3) | ✅ | ✅ | ✅ | ✅ |
| Predial + ICA (Fase 4) | ✅ | ⚠️ ver nota | ❌ | ✅ (opcional) |
| Contratación + SECOP II (Fase 5) | ✅ | ✅ | ✅ | ✅ |
| Nómina Pública + PILA (Fase 6) | ✅ | ✅ | ✅ | ✅ |
| Planeación + Banco Proyectos + PDT (Fase 7) | ✅ | ✅ | ❌ | ✅ (opcional) |
| Activos del Estado + FUT (Fase 8) | ✅ | ✅ | ✅ | ✅ |
| Salud Pública: RIPS/EPS/Glosas (Fase 9) | ❌ | ❌ | ✅ | ✅ (opcional) |
| SGR (Regalías) (Fase 10) | ✅ (opcional, según si recibe regalías) | ✅ | ❌ | ✅ (opcional) |
| SGP (Fase 10) | ✅ | ✅ | ✅ (solo componente salud) | ✅ (opcional) |
| Transparencia + Disciplinario (Fase 11) | ✅ | ✅ | ✅ | ✅ |
| Consolidación NICSP 40 (Fase 11) | ❌ | ✅ (es la única que consolida) | ❌ | ❌ |

**Nota de diseño — importante:** esta matriz es un punto de partida razonable basado en la normativa general, **no una verdad absoluta**. Antes de fijarla en código, valida especialmente estos dos casos con Omar (el dueño del producto), porque dependen de cómo se vaya a vender el producto:

1. **Gobernación y Predial/ICA:** los departamentos no cobran predial (es renta municipal), pero sí cobran otras rentas propias (impuesto de vehículos, registro, licores, cerveza, estampillas departamentales) que **el plan original no construyó como módulo separado**. Márcalo como módulo pendiente de construir si se va a vender a gobernaciones, no lo fuerces dentro de "Predial/ICA".
2. **SGR en municipios/hospitales:** solo aplica si la entidad específica es beneficiaria directa de regalías (depende del municipio, no es universal). Considera que este módulo se active con un toggle adicional dentro de la ficha de la entidad ("¿Esta entidad recibe recursos de regalías?"), no solo por tipo de entidad.

### B.4 — Cómo implementarlo técnicamente

- **No hardcodees la matriz en el código de la UI.** Modélala como datos: una tabla/config `modulos_por_tipo_entidad` (tipo_entidad, subtipo_entidad, modulo_id, visible_por_defecto, requiere_toggle_adicional). Así, cuando aparezca un caso especial (como los de la nota de diseño), se ajusta con datos y no con un despliegue de código.
- Reutiliza el modelo `Entidad` y el esquema multi-tenant de la Fase 0 (`entidad.dart`, `schema_multi_tenant.dart`) — probablemente ya tiene o necesita un campo `tipo_entidad` y `subtipo_entidad_publica`. Si no existe, agrégalo ahí, no crees un modelo paralelo.
- El selector de módulos ya existente debe leer esta tabla al momento de renderizarse, filtrando por el tipo/subtipo de la entidad configurada, en vez de mostrar una lista fija.
- **Permitir cambiar el tipo de entidad después del onboarding inicial**, desde configuración general, no solo en el primer ingreso — un cliente puede empezar como "otro ente" y luego el equipo de soporte de MerkaERP aclara que es un hospital. Este cambio debe recalcular qué módulos están disponibles sin perder datos ya cargados en módulos que sigan siendo válidos.
- La segregación de roles y permisos de la Fase 0 (`roles_permisos_service.dart`) es independiente de esta matriz de módulos — no mezcles ambas lógicas. La matriz de esta parte B decide **qué módulos existen para la entidad**; los roles deciden **quién puede usarlos dentro de esa entidad**.

### B.5 — Entregable de la Parte B

- Cambios en la pantalla de configuración inicial (nuevo paso de tipo/subtipo de entidad).
- Tabla/config de visibilidad de módulos, con la matriz de B.3 como semilla inicial (dejar comentado en el código o en un README que esa matriz debe validarse con el negocio antes de ir a producción).
- Lógica de filtrado del selector de módulos existente basada en esa tabla.
- Pantalla de configuración general donde se pueda cambiar el tipo de entidad después del onboarding.

---

## Cómo usar este prompt

Dale este documento completo al agente. Pídele que empiece por **A.1** (es lo único verdaderamente bloqueante para todo lo demás), y que al terminar cada bloque (A.1, A.2, A.3, A.4, B) te dé el mismo tipo de resumen de cierre que ya usaste en las 12 fases anteriores: archivos creados/modificados, qué quedó implementado, qué quedó pendiente o simplificado.
