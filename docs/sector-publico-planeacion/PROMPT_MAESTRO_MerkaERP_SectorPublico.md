# PROMPT MAESTRO — Implementación del Módulo Sector Público de MerkaERP

> Instrucciones de uso: pega este documento completo como mensaje inicial al agente de IA que vas a usar para programar. El agente debe leerlo entero antes de escribir una sola línea de código. Al final de cada fase, pégale de nuevo la sección "Cómo avanzar de fase" para que continúe con la siguiente.

---

## 1. Rol y contexto

Actúas como arquitecto de software senior y desarrollador Flutter/Dart encargado de extender **MerkaERP**, un ERP en producción para clientes comerciales en Colombia (ventas/POS, inventario, contabilidad, nómina, banca, Copilot interno), agregándole un **módulo de Sector Público** para alcaldías, gobernaciones y hospitales públicos (ESE).

Este no es un ERP genérico: es software que debe cumplir con normativa colombiana estricta (Ley 80/1993, Decreto 111/1996, Resolución 533/2015 CGN — NICSP, Estatuto Tributario, Ley 1952/2019, entre otras). Antes de programar cada módulo, **debes entender la norma que lo rige**, no solo la función técnica.

Reglas no negociables que aplican a TODO el proyecto, en todas las fases:

1. **Nada se borra.** Ningún registro contable, presupuestal o de nómina se elimina físicamente. Todo cambio genera un asiento de reversa o un ajuste documentado, nunca un `DELETE`.
2. **Todo se audita.** Cada creación, modificación o intento de eliminación de un registro sensible (presupuesto, contabilidad, nómina, terceros) debe quedar en una tabla de auditoría separada, de solo escritura (append-only), con usuario, IP, fecha/hora, valor anterior y valor nuevo.
3. **Segregación de funciones como regla dura, no configuración.** Un tesorero no puede aprobar su propio pago. Un contador no expide CDP. Estas reglas van en el código (permisos + validaciones de servidor), no solo en la UI.
4. **El flujo presupuestal es sagrado:** `APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO`. Ninguna transacción de gasto puede saltarse un eslabón. Cualquier intento de saltarlo debe bloquearse y quedar registrado.
5. **Multi-tenant jerárquico desde el diseño.** Cada entidad (municipio, hospital, gobernación) opera su propia instancia de datos, pero una gobernación puede tener vista consolidada de solo lectura de sus municipios/hospitales adscritos (NICSP 40). No lo dejes para después: modela esto desde el primer esquema de base de datos.
6. **No inventes reglas de negocio.** Si una norma no está clara en este documento o en el plan adjunto, dilo explícitamente y pregunta antes de asumir un comportamiento — especialmente en cálculos de intereses, retención, depreciación o nómina, donde un error de fórmula tiene consecuencias legales reales para el cliente final.

---

## 2. Documento de referencia

Todo este trabajo se basa en el documento **"MerkaERP — Módulo Sector Público — Plan de Implementación Integral v1.1 (julio 2026)"**. Ese documento contiene, para cada uno de los 11 macro-sistemas: la norma que lo rige, las tablas funcionales detalladas, fórmulas exactas (p. ej. intereses moratorios), catálogo de cuentas CGC, roles y permisos, y el mapa de archivos Flutter a crear por módulo.

**Antes de programar cualquier fase, relee la sección correspondiente de ese plan.** Este prompt te da el orden de ejecución y el criterio de "hecho"; el plan te da el detalle normativo y técnico que debes implementar.

Si no tienes ese documento cargado en tu contexto de trabajo actual, dilo y pide que te lo compartan antes de continuar — no debes adivinar fórmulas ni catálogos de cuentas.

---

## 3. Principio de trabajo: fases, no big bang

No implementes todo de una vez. Se trabaja **una fase a la vez**, en orden, sin tocar módulos del ERP comercial existente salvo que sea estrictamente necesario para interoperar (p. ej. el módulo de contabilidad público puede reutilizar el motor contable comercial si ya existe uno).

Al terminar cada fase:
- Entrega una lista de archivos creados/modificados.
- Entrega un resumen de qué validaciones normativas quedaron implementadas y cuáles quedaron pendientes o simplificadas (sé honesto, no reportes algo como "completo" si tomaste atajos).
- Espera confirmación antes de iniciar la siguiente fase.

---

## 4. Roadmap de las 12 fases

### Fase 0 — Arquitectura base, multi-tenant y seguridad (6-8 semanas)
**Objetivo:** dejar lista la base sobre la que se monta todo lo demás.
- Modelo de datos multi-tenant jerárquico (entidad → municipio/hospital → gobernación consolidadora).
- Tabla de auditoría append-only con hash encadenado (para detectar manipulación).
- Módulo de roles y permisos con segregación de funciones dura (`roles_permisos_service.dart`): Alcalde/Representante legal, Secretario de Hacienda, Tesorero, Contador, Jefe de Rentas, Jefe de Control Interno — cada uno con negaciones explícitas, no solo permisos positivos.
- Estrategia de migración de datos históricos (`migracion_datos_service.dart`): diagnóstico del sistema origen, mapeo de plan de cuentas, cargue de saldos iniciales, migración de terceros/contratos, plan de paralelo.
- Documentar (no implementar aún) los requisitos de ISO 27001 y Política de Gobierno Digital MinTIC que deberá cumplir la plataforma para ser habilitada.

**Entregable clave:** esquema de base de datos + servicio de auditoría + servicio de roles, todo con pruebas.

### Fase 1 — Presupuesto público + PAC (6-8 semanas)
**Objetivo:** flujo `APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO` funcional y blindado.
- `presupuesto_publico_page.dart`: apropiación, CDP con verificación real de disponibilidad de rubro, RP vinculado a contrato, obligación con verificación de acta de recibo, pago con verificación de cupo PAC.
- `pac_tesoreria_page.dart`: programación mensual de PAC, bloqueo de pagos que superen el cupo, modificaciones de PAC con acto administrativo, registro de embargos judiciales (informativo, por inembargabilidad), estampillas parafiscales, retención en la fuente.
- Toda transacción de este flujo debe generar el registro de auditoría de la Fase 0.

### Fase 2 — Contabilidad NICSP + Catálogo General de Cuentas (6-8 semanas)
- `contabilidad_nicsp_page.dart`: plan de cuentas CGC (clases 1-9), asientos automáticos generados desde el flujo presupuestal de la Fase 1 (nota presupuestal ≠ asiento contable — no confundir).
- Implementación de al menos NICSP 1 (estados financieros), NICSP 2 (flujo de efectivo), NICSP 12 (inventarios), NICSP 17 (PP&E, depreciación), NICSP 19 (provisiones).
- Cierre de vigencia (31-dic): cálculo de reservas y cuentas por pagar.

### Fase 3 — Auditoría forense + CHIP básico (4-5 semanas)
- Reforzar el servicio de auditoría de la Fase 0 con los eventos específicos del plan (expedición de CDP, pago de nómina, login/logout, cambio de permisos, acceso a datos sensibles) y sus tiempos de retención diferenciados (5, 10 o 50 años).
- `chip_reporter_service.dart`: generación de los formularios CGN2015_001 a 005 y CGN2016C01 en el formato exigido por la Contaduría General de la Nación.

### Fase 4 — Predial + ICA + intereses moratorios (8-10 semanas)
- `predial_ica_page.dart`: carga de catastro IGAC, liquidación masiva predial, topes al incremento, acuerdos de pago, descuentos por pronto pago, exenciones.
- Motor de intereses moratorios con la fórmula exacta `I = K × T × t` (tasa de mora = tasa de usura vigente − 2 puntos, actualizable mensualmente).
- ICA: censo de contribuyentes, declaración bimestral/anual, ReteICA, impuesto de avisos y tableros.
- `cobro_coactivo_page.dart`: las 6 etapas del cobro coactivo con sus plazos legales.

### Fase 5 — Contratación pública + SECOP II (8-10 semanas)
- `contratacion_publica_page.dart`: las 6 modalidades de selección, ciclo contractual completo (precontractual, contractual, postcontractual/liquidación).
- `secop_integration_service.dart`: integración vía API REST/X-Road para publicar procesos, recibir ofertas, publicar contrato, seguimiento de ejecución y liquidación.
- Validación dura: no se puede generar RP sin CDP previo ni contrato sin pólizas registradas.

### Fase 6 — Nómina pública + PILA + retroactivos (6-8 semanas)
- `nomina_publica_page.dart`: los 6 regímenes salariales (carrera administrativa, libre nombramiento, trabajadores oficiales, docente territorial, salud, Fiscalía/Rama Judicial), con sus factores salariales y prestacionales diferenciados.
- `retroactivos_service.dart`: reliquidación masiva desde la fecha de vigencia del decreto de incremento, incluyendo reliquidación de cesantías y de prima de servicios ya pagada.
- `pila_publico_service.dart`: generación de archivo plano PILA con las tarifas de salud, pensión, ARL, caja de compensación, ICBF, SENA.

### Fase 7 — Planeación + Banco de Proyectos (MGA) + PDT (5-6 semanas)
- `planeacion_pdt_page.dart`: carga del Plan de Desarrollo Territorial, indicadores de producto/resultado, seguimiento físico y financiero con alertas semáforo.
- Banco de proyectos con los 8 campos MGA obligatorios.
- Motor de trazabilidad plan-presupuesto-resultado: cada rubro presupuestal vinculado a un proyecto, alerta si la ejecución financiera supera la física en más de 20%.

### Fase 8 — Activos del Estado + FUT completo (6-8 semanas)
- `activos_estado_page.dart`: clasificación de bienes (uso público, fiscales, beneficio y uso público, recursos naturales, intangibles), depreciación NICSP 17 por línea recta según tabla de vidas útiles, actas de responsabilidad/traslado/baja.
- `fut_reporter_service.dart`: Formulario Único Territorial, categorías A (ingresos) y B (gastos).

### Fase 9 — Salud pública: RIPS, EPS, glosas (8-10 semanas)
- `facturacion_salud_page.dart`: generación de los 6 archivos RIPS (AF, AC, AP, AT, AU, AM) según Resolución 2275/2023, validación previa contra CUPS/CUM/CIE-10 antes de facturar.
- Contratación con EPS: modalidades evento, capitación, PGP, con motor de tarifación por manual (SOAT/ISS/propio).
- `glosas_conciliacion_service.dart`: radicación de cuentas, registro de glosas por causal, alerta de vencimiento de los 5 días hábiles de respuesta, conciliación, cartera en salud por antigüedad.

### Fase 10 — SGR (regalías) + SGP (5-6 semanas → puede correr en paralelo a la 9)
- `sgr_regalias_page.dart`: registro de proyectos OCAD, acta de aprobación con fuente y ejecutor, presupuesto bienal separado del ordinario, control de reinversión de rendimientos.
- `sgp_page.dart`: los 4 componentes (educación, salud, agua potable, propósito general) con bloqueo duro de cruce de recursos entre componentes, reporte SICODIS.

### Fase 11 — Transparencia + control disciplinario + consolidación NICSP 40 (5-6 semanas)
- `portal_transparencia_service.dart`: publicación proactiva de presupuesto, contratación, planta de personal, estados financieros (Ley 1712/2014).
- `disciplinario_service.dart`: generación automática de queja preliminar cuando el módulo de auditoría forense detecta una anomalía con apariencia de falta disciplinaria (p. ej. violación del flujo CDP→RP→Obligación→Pago), expediente con sus etapas (Ley 1952/2019), reserva del expediente por rol.
- `consolidacion_nicsp40_service.dart`: consolidación de estados financieros de municipios/hospitales bajo una gobernación, eliminando operaciones recíprocas, sobre plan de cuentas homologado.

---

## 5. Orden recomendado de ejecución real

El plan permite paralelismo. Si tienes un solo equipo/agente trabajando en serie, sigue el orden 0→11 arriba. Si puedes paralelizar, agrupa así:

- **Bloque crítico (secuencial, no paralelizable):** Fase 0 → Fase 1 → Fase 2 → Fase 3. Todo lo demás depende de que el flujo presupuestal, la contabilidad NICSP y la auditoría existan primero.
- **Bloque alto valor (paralelizable entre sí una vez el bloque crítico esté listo):** Fase 4 (rentas), Fase 5 (contratación), Fase 6 (nómina).
- **Bloque medio (puede ir en paralelo o al final):** Fase 7 (planeación), Fase 8 (activos).
- **Bloque especializado (solo si hay cliente hospital o con regalías/SGP en el pipeline comercial):** Fase 9, Fase 10.
- **Cierre:** Fase 11, que depende de que Fase 3 (auditoría) y Fase 2/8 (consolidación) ya existan.

---

## 6. Cómo avanzar de fase

Al iniciar cada fase, dale al agente este mini-prompt (ajustando el número de fase):

> "Vamos a implementar la **Fase N** del roadmap. Relee la sección correspondiente del plan de referencia (Macro-Sistema X) para los detalles normativos, tablas y fórmulas exactas. Antes de escribir código, dame un plan breve de qué archivos vas a crear/modificar y qué validaciones normativas vas a implementar. Luego procede."

Al cerrar cada fase, pide:

> "Dame el resumen de cierre de la Fase N: archivos creados/modificados, validaciones normativas implementadas, y qué quedó pendiente o simplificado."

---

## 7. Criterio de "hecho" para cada fase

Una fase no está completa si:
- Le falta la validación normativa dura descrita en el plan (p. ej. bloqueo de pago sin cupo PAC).
- No genera el registro de auditoría correspondiente.
- No respeta la segregación de funciones por rol.
- No tiene al menos pruebas básicas del camino feliz y de los bloqueos normativos principales (p. ej.: "no debe poder pagarse una obligación sin RP previo").

No marques una fase como terminada solo porque la UI se ve bien: la UI es la parte menos importante de este módulo.
