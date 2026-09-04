## **MerkaERP** 

**Módulo Sector Público Plan de Implementación Integral** _Alcaldías · Gobernaciones · Hospitales Públicos_ 

**11 24+ 50+ Colombia** Macro-Sistemas Módulos clave Normas aplicadas Normativa 

Versión 1.1  ·  Julio 2026 

## **Resumen Ejecutivo** 

## 🆕 **Registro de cambios — v1.1 (Julio 2026)** 

Se agregan cuatro macro-sistemas nuevos: Salud Pública y Facturación en Salud (RIPS, EPS, glosas), Sistema General de Regalías (SGR), Sistema General de Participaciones (SGP), y Transparencia y Control Disciplinario (Ley 1712/2014 y Ley 1952/2019). 

Se agrega la sección "Requisitos Arquitectónicos y de Habilitación": consolidación multi-entidad (NICSP 40), seguridad y habilitación (ISO 27001, MinTIC Gobierno Digital), migración de datos históricos, y roles y perfiles del sector público. 

Se agrega la sección "Validación de Mercado y Modelo Comercial": comprador real y proceso de licitación pública, y estimación de esfuerzo y costo total del proyecto. 

Estas adiciones responden a vacíos identificados tras la revisión de la v1.0: el documento original cubría el ciclo fiscal-administrativo general pero no desarrollaba la complejidad específica de hospitales, regalías, transferencias nacionales, ni los requisitos no funcionales de seguridad, migración y venta. 

Este documento define el plan técnico, normativo y funcional para transformar MerkaERP en un sistema de gestión pública de clase enterprise, capaz de operar como ERP oficial de alcaldías, gobernaciones, hospitales y demás entidades del sector público colombiano. 

La diferencia entre un ERP comercial y uno del sector público no es de escala, es de naturaleza jurídica. El Estado colombiano no compra, licita. No vende, recauda. No contrata libremente, debe ceñirse a la Ley 80 de 1993. No registra en NIIF comerciales, registra bajo NICSP según la Resolución 533 de 2015. Cada peso que entra o sale debe quedar trazado, justificado y disponible para auditoría en cualquier momento. 

|||||
|---|---|---|---|
|**Macro-Sistema**|**Función Principal**|**Norma Rectora**|**Complejidad**|
|||||
|||||
|1. Planeación y<br>Proyectos|Plan de Desarrollo + Banco<br>de Proyectos MGA|Ley 152/1994, DNP-<br>MGA|🔴Alta|
|||||
|||||
|2. Sistema Financiero<br>Integrado|Presupuesto · Tesorería ·<br>Contabilidad NICSP|Decreto 111/1996, Res.<br>533/2015|🔴Crítica|
|||||
|3. Rentas y Tributos|Predial · ICA · Cobro<br>Coactivo|Ley 44/1990, ET Arts.<br>823-843|🔴Alta|
|||||
|4. Contratación Pública|Ciclo contractual completo +<br>SECOP II|Ley 80/1993, Ley<br>1150/2007|🔴Alta|
|||||
|||||
|5. Nómina Pública|Regímenes especiales +<br>retroactivos + PILA|Decreto 1042/1978, Ley<br>4/1992|🟠Alta|
|||||
|6. Almacén y Activos<br>del Estado|Bienes institucionales vs.<br>uso público + depreciación<br>NICSP|Res. 533/2015 CGN,<br>NICSP 17|🟠Media|
|||||
|||||
|7. Trazabilidad y<br>Rendición de Cuentas|Auditoría forense + archivos<br>planos CHIP/SIA/SIIF|Ley 87/1993, Circular<br>CGN 2024|🔴Crítica|
|||||



## **Macro-Sistema 1 — Planeación y Proyectos** 

Antes de que exista un peso de presupuesto, existe un compromiso político: el Plan de Desarrollo Territorial (PDT). Todo el gasto público debe estar amarrado a una meta del PDT. Este macrosistema es el origen de toda la cadena de valor del Estado. 

## 📋 **Ley 152 de 1994 — Ley Orgánica del Plan de Desarrollo** 

Establece los procedimientos y mecanismos para elaborar, aprobar, ejecutar, hacer seguimiento, evaluar y controlar los planes de desarrollo. Obliga a todas las entidades territoriales a tener un Plan de Desarrollo cuatrienal articulado con el Plan Nacional. 

## 📋 **Metodología General Ajustada (MGA) — DNP** 

Herramienta obligatoria del Departamento Nacional de Planeación para la formulación, registro y seguimiento de proyectos de inversión pública. Todo proyecto que quiera acceder a presupuesto de inversión debe estar registrado en el Banco de Proyectos mediante la MGA. 

## **1.1 Módulo de Plan de Desarrollo Territorial (PDT)** 

Permite cargar y gestionar el PDT cuatrienal de la entidad, definiendo los programas, subprogramas y metas que guiarán la inversión durante el período de gobierno. 

||||
|---|---|---|
|**Función**|**Descripción técnica**|**Dato clave**|
||||
||||
|Carga del PDT|Importación desde Excel/XML de ejes,<br>programas, subprogramas, metas e<br>indicadores|Estructura jerárquica de 4<br>niveles|
||||
|Indicadores de<br>resultado|Metas de producto y resultado con línea base,<br>valor meta y periodicidad|Tipos: acumulado, no<br>acumulado, último dato|
||||
||||
|Seguimiento físico|Registro de avances por período<br>(trimestral/semestral) con % de cumplimiento|Alertas semáforo:<br>verde/amarillo/rojo|
||||
|Seguimiento<br>financiero|Vinculación de cada meta con sus<br>apropiaciones presupuestales reales|Cruce automático con<br>módulo de presupuesto|
||||
||||
|Reportes SISMEG|Generación de reportes en formato del<br>Sistema de Seguimiento a Metas de Gobierno|Requerido para rendición<br>de cuentas|
||||



## **1.2 Banco de Proyectos — Integración MGA** 

||||
|---|---|---|
|**Campo MGA**|**Descripción**|**Obligatorio**|
||||
||||
|Identificación del<br>proyecto|Nombre, código BPIN, sector, subsector,<br>entidad ejecutora|Sí|
||||
|Problema central|Árbol de problemas con causas y efectos|Sí|
||||



||||
|---|---|---|
|**Campo MGA**|**Descripción**|**Obligatorio**|
||||
||||
|Objetivos y alternativas|Árbol de objetivos, alternativas de solución y<br>criterios de selección|Sí|
||||
||||
|Estudio de mercado|Análisis de oferta y demanda, población<br>objetivo|Sí|
||||
|Cadena de valor|Actividades → Productos → Efectos → Impacto|Sí|
||||
||||
|Presupuesto del<br>proyecto|Costos de inversión y operación por año,<br>fuentes de financiación|Sí|
||||
|Indicadores de producto|Unidades a entregar, meta física por vigencia|Sí|
||||
|Vinculación al PDT|Programa y subprograma del Plan de<br>Desarrollo al que aporta|Sí|
||||



## **1.3 Motor de Trazabilidad Plan-Presupuesto-Resultado** 

La regla de oro del sector público es que no puede existir gasto sin plan. El sistema implementa esta regla de forma técnica: 

- Cada rubro presupuestal debe estar vinculado a un proyecto del Banco de Proyectos 

- Cada CDP, RP y obligación genera automáticamente una actualización del avance financiero del proyecto 

- El dashboard ejecutivo muestra en tiempo real: % de ejecución física vs. % de ejecución financiera 

- Alerta de desviación: si la ejecución financiera supera la física en más del 20%, el sistema alerta al jefe de planeación 

## **Macro-Sistema 2 — Sistema Financiero Inte rado g** 

Este es el corazón operativo del ERP público. Gestiona el ciclo presupuestal completo, la tesorería y la contabilidad pública bajo normas NICSP, tres subsistemas que deben operar como uno solo. 

## **2.1 Presupuesto Público — El Flujo Inquebrantable** 

## 📋 **Decreto 111 de 1996 — Estatuto Orgánico del Presupuesto (EOP)** 

Compila las Leyes 38/1989, 179/1994 y 225/1995. Es la norma suprema en materia presupuestal. Define los principios del sistema presupuestal: planificación, anualidad, universalidad, unidad de caja, programación integral, especialización, inembargabilidad, coherencia macroeconómica y sostenibilidad fiscal. Ningún gasto puede ejecutarse sin seguir este flujo. 

## ⚠ **Flujo presupuestal obligatorio — Artículo 71, Decreto 111/1996** 

APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO 

1. APROPIACIÓN: Autorización del gasto aprobada en el presupuesto anual por el Concejo/Asamblea. 

2. CDP (Certificado de Disponibilidad Presupuestal): Certifica que hay recursos disponibles. Afecta temporalmente el presupuesto. Requisito PREVIO a cualquier proceso de selección o contrato. 

3. RP (Registro Presupuestal): Compromete definitivamente los recursos. Se expide DESPUÉS de suscrito el contrato. Requisito de ejecución (Art. 41, Ley 80/1993). 

4. OBLIGACIÓN: El contratista entregó o el bien/servicio se prestó. Se reconoce la deuda. 

5. PAGO: Transferencia efectiva de recursos. Solo procede si hay cupo PAC disponible. 

El incumplimiento de este flujo genera responsabilidad disciplinaria, penal y fiscal del funcionario (Art. 71, EOP). 

|||||
|---|---|---|---|
|**Transacción**|**Norma**|**Validación del sistema**|**Asiento automático**<br>**NICSP**|
|||||
|||||
|Expedición CDP|Art. 71 EOP|Verificar disponibilidad real en<br>el rubro. Bloquear si no hay<br>saldo.|Nota presupuestal —<br>no contable|
|||||
|Expedición RP|Art. 41 Ley 80/1993|Requerir número de contrato<br>registrado. Reducir<br>disponibilidad del CDP.|Nota presupuestal —<br>no contable|
|||||
|||||
|Registro obligación|NICSP 19|Verificar acta de recibo a<br>satisfacción o factura válida.|Db: Gasto / Cr:<br>Cuentas por pagar|
|||||
|Pago|Art. 74 EOP (PAC)|Verificar cupo PAC del mes.<br>Bloquear si PAC insuficiente.|Db: Cuentas por<br>pagar / Cr: Banco|
|||||
|Cierre vigencia|Art. 89 EOP|Calcular reservas y cuentas<br>por pagar al 31-dic.|Ajustes de cierre<br>NICSP|
|||||



|||||
|---|---|---|---|
|**Transacción**|**Norma**|**Validación del sistema**|**Asiento automático**<br>**NICSP**|
|||||
|||||
|Vigencias futuras|Art. 23 EOP mod.<br>Ley 819/2003|Requerir autorización del<br>Confis/MFMP. Registrar en<br>años siguientes.|Compromiso<br>plurianual|



## **2.2 Tesorería y Programa Anual Mensualizado de Caja (PAC)** 

## 📋 **Artículo 74, Decreto 111/1996 — PAC** 

El PAC es el instrumento mediante el cual se define el monto MÁXIMO mensual de fondos disponibles para realizar pagos. Ningún pago puede hacerse si no hay cupo PAC aprobado para ese mes. El incumplimiento del PAC es causal de mala conducta. 

||||
|---|---|---|
|**Función PAC**|**Descripción**|**Detalle normativo**|
||||
||||
|Programación<br>mensual|Cada área define necesidades de<br>pago por mes. Tesorería consolida y<br>solicita aprobación.|Art. 74-75 Decreto 111/1996|
||||
|Control en tiempo<br>real|El sistema bloquea pagos que<br>superen el cupo PAC del mes en<br>curso.|Principio de Unidad de Caja, Art. 16<br>EOP|
||||
|Modificación PAC|Traslados entre meses dentro del<br>mismo año. Requiere acto<br>administrativo.|Art. 76 Decreto 111/1996|
||||
|Embargos judiciales|Las cuentas de entidades públicas<br>son inembargables. El sistema debe<br>registrar mandamientos como simple<br>información.|Art. 19 EOP — Inembargabilidad|
||||
||||
|Estampillas<br>parafiscales|Retenciones obligatorias en pagos a<br>contratistas: Estampilla Pro-<br>Universidades, Pro-Hospital, Pro-<br>Cultura según ordenanza.|Leyes habilitantes por departamento|
||||
|Retención en la<br>fuente|Aplicación de retenciones según<br>Tabla Retefuente (Art. 383-401 ET)<br>en pagos a personas<br>naturales/jurídicas.|Arts. 368-419 E.T.|



## **2.3 Contabilidad Pública — NICSP bajo Resolución 533 de 2015** 

📋 **Resolución 533 de 2015 CGN + Resoluciones 436, 437, 438 y 439 de 2024** 

La Contaduría General de la Nación incorporó mediante la Resolución 533/2015 el Marco Normativo para Entidades de Gobierno, que adopta las NICSP (Normas Internacionales de Contabilidad del 

Sector Público). Actualizada en 2024 mediante las Resoluciones 436-439. Es de obligatorio cumplimiento para alcaldías, gobernaciones y demás entidades de gobierno. 

|||||
|---|---|---|---|
|**NICSP Adoptada**|**Número**|**Tema**|**Implementación en MerkaERP**|
|||||
|||||
|Presentación EEFF|NICSP<br>1|Estado Situación<br>Financiera, Estado<br>Rendimiento<br>Financiero, ECPN,<br>EFE|Generación automática con datos<br>contables|
|||||
|Flujos de efectivo|NICSP<br>2|Estado de Flujos de<br>Efectivo — método<br>directo|Clasificación:<br>operación/inversión/financiación|
|||||
|Políticas contables|NICSP<br>3|Errores, estimaciones<br>y cambios de política|Módulo de ajustes con trazabilidad|
|||||
|||||
|Inventarios|NICSP<br>12|Medición de<br>existencias al menor<br>de costo y VNR|Kardex valorado por FIFO o<br>promedio ponderado|
|||||
|Propiedades, planta y<br>equipo|NICSP<br>17|Reconocimiento,<br>medición y<br>depreciación de<br>activos fijos|Depreciación automática por tipo<br>de activo|
|||||
|Arrendamientos|NICSP<br>13|Clasificación y<br>registro de<br>arrendamientos<br>operativos y<br>financieros|Módulo de contratos de<br>arrendamiento|
|||||
|Ingresos de transacciones<br>sin contraprestación|NICSP<br>23|Impuestos,<br>transferencias,<br>donaciones|Motor de liquidación tributaria|
|||||
|Provisiones y pasivos<br>contingentes|NICSP<br>19|Demandas, litigios,<br>garantías|Registro de contingencias con<br>probabilidad|
|||||
|Combinaciones del sector<br>público|NICSP<br>40|Fusiones y<br>adquisiciones<br>entidades públicas|Módulo de consolidación|
|||||



## **2.3.1 Catálogo General de Cuentas (CGC) — Estructura PUC Público** 

||||
|---|---|---|
|**Clase**|**Nombre**|**Ejemplos de cuentas clave para MerkaERP**|
||||
||||
|1|Activo|1110 Efectivo y equivalentes · 1415 Deudores por impuestos · 1640<br>PP&E · 1920 Activos intangibles|
||||
||||
|2|Pasivo|2401 Cuentas por pagar (contratistas) · 2410 Obligaciones fiscales ·<br>2510 Beneficios a empleados|



||||
|---|---|---|
|**Clase**|**Nombre**|**Ejemplos de cuentas clave para MerkaERP**|
||||
||||
|3|Patrimonio|3105 Capital fiscal · 3115 Resultado del ejercicio · 3120 Impacto<br>acumulado de reexpresión|
||||
||||
|4|Ingresos|4111 Impuesto predial · 4115 ICA · 4401 Transferencias SGP · 4802<br>Otros ingresos|
||||
|5|Gastos|5101 Servicios de personal · 5111 Generales · 5120 Transferencias<br>pagadas · 5310 Depreciación|
||||
||||
|6|Costo de<br>ventas/servicios|6101 Costo de producción de bienes · 6310 Costo de la<br>transformación|
||||
|8|Cuentas de orden<br>deudoras|8110 Derechos contingentes · 8390 Bienes y valores entregados en<br>custodia|
||||
||||
|9|Cuentas de orden<br>acreedoras|9110 Responsabilidades contingentes · 9390 Bienes y valores<br>recibidos en custodia|
||||



## **Macro-Sistema 3 — Sistema de Rentas Tributos y** 

Una entidad pública no vende productos: recauda impuestos. Este macro-sistema es el único en el país que le da a una alcaldía la herramienta para liquidar el predial de miles de ciudadanos, calcular intereses moratorios al día, aplicar acuerdos de pago y ejecutar cobro coactivo sin depender de sistemas externos. 

## **3.1 Impuesto Predial Unificado** 

📋 **Ley 44 de 1990 + Ley 1995 de 2019 (Catastro Multipropósito) + Decreto 1480 de 2025** 

La Ley 44/1990 creó el Impuesto Predial Unificado y define: sujeto activo (municipio), sujeto pasivo (propietario/poseedor/usufructuario), base gravable (avalúo catastral IGAC) y tarifa (entre 1 y 16 por mil, fijada por Acuerdo Municipal). El Decreto 1480 de 2025 ordenó un reajuste del 3% en avalúos catastrales para 2026 de predios no actualizados en 2025. 

||||
|---|---|---|
|**Función del módulo**|**Descripción**|**Normativa específica**|
||||
||||
|Carga del catastro<br>IGAC|Importación masiva del archivo plano<br>catastral con: número predial, área,<br>avalúo, propietario, dirección, estrato,<br>uso del suelo.|IGAC — Resolución 070/2011<br>formatos de interoperabilidad|
||||
|Liquidación masiva<br>predial|Cálculo automático del impuesto para<br>TODOS los predios del municipio:<br>Predial = Avalúo × Tarifa (por uso de<br>suelo y estrato).|Ley 44/1990 Arts. 4-7|
||||
|Topes al incremento|Validar que ningún predio aumente más<br>del 50% respecto al año anterior (tope<br>general). Estratos 1-2 hasta 135<br>SMMLV: tope = IPC. Predios rurales<br>≥100 ha: tope = 2×año anterior.|Ley 44/1990 Art. 6 + Ley<br>1995/2019 Art. 19|
||||
|Acuerdos de pago|Cuotas para deudores morosos con<br>abono a capital e intereses. Al firmar<br>acuerdo, el contribuyente pierde el<br>derecho a prescripción.|ET Art. 814 — Aplica por<br>remisión|
||||
|Descuento por pronto<br>pago|Las alcaldías pueden ofrecer hasta<br>10% de descuento si se paga en el<br>primer trimestre (según acuerdo<br>municipal).|Autonomía tributaria Art. 287<br>C.P.|
||||
||||
|Exenciones y<br>exclusiones|Predios de entidades del Estado,<br>iglesias, hospitales públicos, predios<br>con POT de protección ambiental<br>(según acuerdo municipal).|Ley 44/1990 + acuerdos locales|
||||
|Facturación masiva|Generación e impresión masiva de<br>facturas prediales con código de barras<br>para pago en bancos.|Resolución DIAN sobre factura<br>electrónica (referencial)|
||||



## **3.2 Motor de Intereses Moratorios — Cálculo Exacto** 

📋 **Artículo 635 ET + Concepto Minhacienda 032629 de 2026** 

Los intereses de mora por impuestos territoriales (predial, ICA, vehículos) se calculan con la MISMA fórmula del Estatuto Tributario Nacional. La tasa de mora es: Tasa de Usura (fijada mensualmente por la Superfinanciera) MENOS 2 puntos porcentuales. Para junio 2026: Usura = 28.79% EA → TIM = 26.79% EA. 

🔢 **Fórmula exacta de intereses moratorios (Art. 590 ET por remisión)** 

I = K × T × t 

Donde: 

K = Capital insoluto (saldo de impuesto no pagado) T = Tasa diaria = TIM_anual ÷ 365 (o 366 en año bisiesto) t = Número de días en mora 

Ejemplo: Predial 2024 de $500.000 pagado con 180 días de mora en 2026: TIM 2026 = 26.79% EA → Factor diario = 26.79% ÷ 365 = 0.07340% I = $500.000 × 0.07340% × 180 días = $66.060 de intereses Total a pagar = $500.000 + $66.060 = $566.060 

El sistema debe actualizar la TIM automáticamente cada mes desde la Superfinanciera. La prescripción de la acción de cobro ocurre a los 5 años del mandamiento de pago (Art. 817 ET). 

## **3.3 ICA — Impuesto de Industria y Comercio** 

## 📋 **Ley 14 de 1983 + Decreto 1333 de 1986 + Leyes locales** 

El ICA grava el ejercicio de actividades industriales, comerciales y de servicios en el municipio. Base gravable: ingresos brutos del contribuyente originados en el municipio. Tarifas: entre 2 y 10 por mil para actividades industriales, 2 a 10 por mil para comerciales, 2 a 10 por mil para servicios (según acuerdo municipal). 

||||
|---|---|---|
|**Función**|**Descripción**|**Dato técnico**|
||||
||||
|Censo de<br>contribuyentes ICA|Registro de todos los establecimientos<br>comerciales con actividad económica CIIU,<br>ingresos declarados y NIT.|Integración con RUT DIAN<br>para validación|
||||
|Declaración y<br>liquidación ICA|El contribuyente declara ingresos bimestrales.<br>El sistema valida y liquida automáticamente<br>ICA + complementario de avisos y tableros.|Bimestral o anual según<br>acuerdo municipal|



||||
|---|---|---|
|**Función**|**Descripción**|**Dato técnico**|
||||
||||
|Fiscalización ICA|Cruce de información: declaraciones ICA vs.<br>Ingresos reportados en renta a la DIAN<br>(información exógena).|Art. 651-657 ET —<br>información exógena|
||||
||||
|Retención de ICA<br>(ReteICA)|Cuando una entidad pública paga a un<br>proveedor, debe retener un porcentaje del ICA<br>del municipio. Tarifa: varía por actividad.|Regulada por acuerdo<br>municipal|
||||
||||
|Impuesto de avisos y<br>tableros|15% sobre el valor del ICA. Se liquida<br>automáticamente junto con el ICA.|Art. 37 Ley 14/1983|
||||



## **3.4 Fiscalización y Cobro Coactivo** 

## 📋 **Arts. 823-843 Estatuto Tributario + Arts. 99-107 Ley 1437/2011 (CPACA)** 

El cobro coactivo es el procedimiento administrativo mediante el cual la entidad pública cobra sus deudas tributarias SIN necesidad de ir a un juez. El funcionario competente (jefe de rentas) tiene poderes de embargo, secuestro y remate equiparables a los de un juez civil de ejecución. 

|||||
|---|---|---|---|
|**Etapa del cobro**<br>**coactivo**|**Acción del sistema**|**Plazo legal**|**Norma**|
|||||
|||||
|1. Mandamiento de<br>pago|Genera auto administrativo<br>de cobro con capital e<br>intereses. Notifica al deudor.|10 días para<br>comparecer|Art. 826 ET|
|||||
|2. Período de oposición|Registra excepciones del<br>deudor: pago, prescripción,<br>falta de ejecutoria.|15 días desde<br>notificación|Art. 831 ET|
|||||
|3. Medida cautelar —<br>embargo|Genera oficio de embargo a<br>entidad financiera o Registro<br>de Instrumentos Públicos.|Inmediato si hay<br>título ejecutivo<br>firme|Art. 837 ET|
|||||
|4. Secuestro de bienes|Genera acta de secuestro<br>para bienes muebles o<br>inmuebles embargados.|Después del<br>embargo|Art. 838 ET|
|||||
|5. Avalúo y remate|Registra avalúo pericial y<br>programa pública subasta<br>del bien embargado.|30 días desde<br>secuestro|Art. 840 ET|
|||||
|||||
|6. Extinción de la<br>obligación|Registra el pago, el remate<br>o la dación en pago. Cierra<br>el proceso.|Al completarse el<br>recaudo|Art. 835 ET|



## **Macro-Sistema 4 — Contratación Pública** 

El Estado no compra libremente. Cada peso que gasta debe pasar por un proceso de selección reglado, publicarse en SECOP II, contar con CDP, suscribirse con pólizas de amparo y ejecutarse con supervisión. Omitir cualquier paso genera nulidad del contrato y responsabilidad del funcionario. 

## 📋 **Ley 80 de 1993 + Ley 1150 de 2007 + Decreto 1082 de 2015** 

La Ley 80/1993 es el Estatuto General de Contratación de la Administración Pública. La Ley 1150/2007 introdujo las modalidades de selección. El Decreto 1082/2015 (DUR sector administrativo planeación) compila toda la reglamentación contractual vigente. Adicionalmente, la Ley 1474/2011 (Estatuto Anticorrupción) reforzó los controles a la contratación. 

## **4.1 Modalidades de Selección del Contratista** 

|||||
|---|---|---|---|
|**Modalidad**|**Cuándo aplica**|**Umbrales 2026**<br>**aprox.**|**Plazo mínimo**|
|||||
|||||
|Licitación Pública|Contratos que superen la<br>menor cuantía. Es la regla<br>general.|Según entidad<br>(≥1.000 SMMLV<br>aprox.)|30 días calendario<br>para recibir ofertas|
|||||
|Selección Abreviada<br>— Menor Cuantía|Contratos entre el 10% y el<br>100% de la menor cuantía.|Varía por<br>presupuesto de la<br>entidad|10 días hábiles|
|||||
|Concurso de Méritos|Exclusivo para consultoría:<br>estudios, diseños,<br>interventorías.|Sin límite de cuantía|20 días calendario|
|||||
|Mínima Cuantía|Contratos de mínima cuantía<br>(10% de la menor cuantía).|≤280 SMMLV aprox.|1 día hábil de<br>oferta|
|||||
|Contratación Directa|Excepcional: urgencia<br>manifiesta, contratos<br>interadministrativos,<br>empréstitos, artistas, etc.|Sin límite si aplica<br>causal legal|Sin término<br>mínimo|
|||||
|||||
|Acuerdos Marco CCE|Compra de bienes y servicios<br>de catálogo en la Tienda<br>Virtual del Estado.|Sin límite|Inmediato|



## **4.2 Ciclo Contractual Completo** 

**Fase 1 — Precontractual (Estudios Previos)** 

||||
|---|---|---|
|**Documento**|**Contenido obligatorio**|**Norma**|
||||
||||
|Estudios previos|Descripción de la necesidad, objeto del<br>contrato, obligaciones, modalidad de<br>selección, valor estimado, plazo, riesgo,<br>garantías exigidas.|Art. 2.2.1.1.1.6.1 Decreto<br>1082/2015|
||||
||||
|Análisis del sector|Análisis de oferta y demanda, precios del<br>mercado, experiencia habitual del sector.|Art. 2.2.1.1.1.6.1 Decreto<br>1082/2015|
||||
|Matriz de riesgos|Identificación, estimación y asignación de<br>riesgos previsibles del contrato.|Arts. 4-5 Ley 80/1993|
||||
||||
|Certificado de<br>Disponibilidad<br>Presupuestal (CDP)|Generado desde el módulo presupuestal.<br>Número de CDP debe constar en el pliego.|Art. 71 Decreto 111/1996|
||||
|Pliego de condiciones|Reglas del proceso: cronograma, requisitos<br>habilitantes, criterios de evaluación.|Art. 30 Ley 80/1993|



**Fase 2 — Contractual** 

||||
|---|---|---|
|**Documento/Evento**|**Función en el sistema**|**Norma**|
||||
||||
|Registro Presupuestal<br>(RP)|El sistema genera el RP automáticamente al<br>registrar el contrato. Compromete los<br>recursos del CDP.|Art. 41 Ley 80/1993|
||||
|Pólizas de amparo|Registro de pólizas: seriedad de la oferta,<br>cumplimiento, buen manejo del anticipo,<br>salarios y prestaciones, responsabilidad civil<br>extracontractual.|Art. 7 Ley 80/1993|
||||
|Acta de inicio|Fecha desde la cual comienza a correr el<br>plazo contractual. Hito para supervisión.|Cláusula contractual<br>estándar|
||||
|Actas de avance/pago|Registro de avance físico certificado por el<br>supervisor/interventor. Base para generar<br>obligación y orden de pago.|Arts. 83-85 Ley 80/1993|
||||
||||
|Adiciones y prórrogas|Modificaciones al contrato. Una sola adición<br>en valor, máximo el 50% del valor inicial.|Art. 40 Ley 80/1993|
||||
|Suspensiones|Suspensión del plazo contractual. Requiere<br>acta suscrita por ambas partes.|Doctrina Consejo de Estado|
||||
||||
|Multas y sanciones|Aplicación de cláusula penal o multas por<br>incumplimiento. Genera deducción en el<br>pago.|Arts. 17-18 Ley 80/1993|
||||



## **Fase 3 — Postcontractual (Liquidación)** 

||||
|---|---|---|
|**Evento**|**Descripción**|**Plazo legal**|
||||
||||
|Liquidación bilateral|Acuerdo entre las partes sobre el estado final<br>del contrato: pagos, saldos, obligaciones<br>pendientes.|4 meses después de<br>vencimiento o<br>terminación|
||||
||||
|Liquidación unilateral|El contratista no firma. La entidad liquida<br>unilateralmente mediante acto administrativo<br>motivado.|2 meses después del<br>plazo bilateral|
||||
|Balance final|El sistema verifica: ¿Se ejecutó el 100% del<br>RP? Si hay saldo sin ejecutar, libera el<br>presupuesto.|Al momento de la<br>liquidación|
||||
||||
|Archivo del expediente|Toda la documentación contractual se archiva<br>en el expediente digital del proceso en<br>SECOP II.|Inmediato — Acuerdo<br>AGN 002/2014|
||||



## **4.3 Interoperabilidad con SECOP II** 

## 📋 **X-Road — Plataforma de interoperabilidad SECOP II + Circular CCE Única 2022** 

El SECOP II permite interoperabilidad con otros sistemas a través de la plataforma X-Road. MerkaERP debe publicar en SECOP II (no duplicar información) toda la documentación precontractual, contractual y postcontractual. La Circular Única 2022 de CCE establece que los documentos electrónicos del SECOP II tienen valor probatorio pleno. 

|||||
|---|---|---|---|
|**Flujo de integración**|**Dirección**|**Datos sincronizados**|**Método**|
|||||
|||||
|Publicación proceso|MerkaERP →<br>SECOP II|Estudios previos, pliego, aviso<br>de convocatoria, adendas|API REST X-Road|
|||||
|Recepción de ofertas|SECOP II →<br>MerkaERP|Ofertas de proponentes,<br>habilitación técnica y jurídica|Webhook SECOP II|
|||||
|Publicación contrato|MerkaERP →<br>SECOP II|Contrato suscrito, RP, pólizas,<br>actas de inicio|API REST|
|||||
|Seguimiento ejecución|MerkaERP →<br>SECOP II|Actas de avance, pagos<br>realizados, adiciones|API REST|
|||||
|||||
|Publicación liquidación|MerkaERP →<br>SECOP II|Acta de liquidación, balance<br>final|API REST|



## **Macro-Sistema 5 — Nómina y Recursos Humanos Públicos** 

La nómina del sector público es la más compleja del ordenamiento jurídico colombiano. Existen al menos seis regímenes salariales diferentes que pueden coexistir en una misma entidad, y los incrementos salariales se aprueban retroactivamente, generando reliquidaciones masivas. 

## 📋 **Decreto 1042 de 1978 + Ley 4 de 1992 + Ley 909 de 2004 + Decretos anuales de salarios** 

El Decreto 1042/1978 es el Estatuto de Personal para empleados públicos de la Rama Ejecutiva del orden nacional (aplicable por remisión en territoriales). Define los factores salariales: asignación básica, gastos de representación, prima técnica, prima de servicios, prima de navidad, prima de vacaciones, subsidio de alimentación, viáticos. La Ley 4/1992 autoriza al Gobierno fijar el régimen salarial. La Ley 909/2004 regula la carrera administrativa. 

## **5.1 Regímenes Salariales que Debe Manejar el Sistema** 

||||
|---|---|---|
|**Régimen**|**Marco normativo**|**Particularidades para el sistema**|
||||
||||
|Carrera Administrativa<br>General|Ley 909/2004, Decreto<br>1083/2015|Escalafón por nivel/grado. Prima de<br>antigüedad (quinquenios) cada 5 años de<br>servicio.|
||||
|Libre Nombramiento y<br>Remoción|Art. 5 Ley 909/2004|Sin derechos de carrera. Gastos de<br>representación por grado del cargo.|
||||
|Trabajadores Oficiales|CST (Código Sustantivo<br>Trabajo)|Auxilio de cesantía retroactivo (no Ley 50).<br>Sin prima de servicios del D.1042.|
||||
|Régimen docente<br>territorial|Decreto 2277/1979, Decreto<br>1278/2002|Escalafón docente independiente.<br>Asignación básica por grado y título.<br>Primaria, básica, media.|
||||
||||
|Régimen de salud<br>(hospitales)|Decreto 1750/2003, Ley<br>647/2001|Empleados convertidos a trabajadores<br>oficiales. Convención colectiva puede<br>primar.|
||||
|Régimen especial<br>Fiscalía/Rama Judicial|Ley 270/1996, Acuerdo CSJ|Solo aplica si el módulo se vende a esas<br>entidades. Factores salariales diferentes.|



## **5.2 Factores Salariales y Prestacionales — Detalle** 

|||||
|---|---|---|---|
|**Factor**|**Base de liquidación**|**¿Factor**<br>**salarial?**|**Norma**|
|||||
|||||
|Asignación básica<br>mensual|Decreto anual de salarios|Sí|Art. 42 D.1042/1978|



|||||
|---|---|---|---|
|**Factor**|**Base de liquidación**|**¿Factor**<br>**salarial?**|**Norma**|
|||||
|||||
|Gastos de<br>representación|% de la asignación básica<br>según nivel del cargo|Sí (para<br>algunos<br>cargos)|Art. 48 D.1042/1978|
|||||
|||||
|Prima técnica|Hasta 50% asignación básica.<br>Por título posgrado +<br>experiencia|Sí|Decreto 1661/1991|
|||||
|Prima de servicios|Promedio de factores<br>salariales × 15 días. Se paga<br>en junio y diciembre.|No<br>(prestación)|Art. 58 D.1042/1978|
|||||
|||||
|Prima de navidad|1 mes de salario pagado en la<br>segunda quincena de<br>diciembre.|No<br>(prestación)|Art. 61 D.1042/1978|
|||||
|Prima de vacaciones|15 días de asignación básica<br>al iniciar vacaciones.|No<br>(prestación)|Art. 60 D.1042/1978|
|||||
|Subsidio de<br>alimentación|Valor fijo mensual. No es<br>factor salarial.|No|Art. 49 D.1042/1978|
|||||
|Cesantías|Un mes de salario por año de<br>servicio (régimen anualidad).|No<br>(prestación)|Ley 344/1996 Art. 98|
|||||
|Quinquenios (prima de<br>antigüedad)|Incremento del 5% de la<br>asignación básica por cada 5<br>años de servicio continuo.|Sí (si así lo<br>define la<br>entidad)|Según convención o<br>acuerdo|
|||||
|Viáticos|Factor salarial SOLO si se<br>perciben >180 días/año en<br>comisión.|Condicional|Art. 45 lit. i) D.1045/1978|
|||||



## **5.3 Retroactividad Salarial — El Caso Más Complejo** 

## ⚠ **Retroactividad salarial 2026 — Impacto en nómina** 

El Gobierno Nacional expidió decreto de incremento salarial del 7% para 2026, con efecto retroactivo desde enero del mismo año, 

a ser pagado en la nómina de noviembre 2026. Esto genera: 

1. RELIQUIDACIÓN de toda la nómina desde enero: asignación básica × 7% × meses transcurridos. 

2. RELIQUIDACIÓN de cesantías: el aumento afecta el factor base de liquidación. 

- → Plazo para girar diferencia a fondos de cesantías: 2 meses desde el pago del retroactivo. 

- → Incumplimiento genera intereses de mora (Decreto 312/2026 Art. 59). 

3. RELIQUIDACIÓN de prima de servicios de junio: si el incremento aplica desde enero, la prima de junio se reliquida con el nuevo salario. 

4. ASIENTO CONTABLE: Db: Gasto nómina / Cr: Nóminas por pagar. 

El retroactivo genera una obligación presupuestal adicional que requiere CDP si no estaba previsto. 

## **5.4 PILA Sector Público** 

||||||
|---|---|---|---|---|
|**Aporte**|**Base de cotización**|**Tarifa**<br>**empleador**|**Tarifa**<br>**empleado**|**Destinatario**|
||||||
||||||
|Salud|Ingresos base de<br>cotización (IBC)|8.5%|4%|EPS del servidor<br>público|
||||||
||||||
|Pensión<br>(Colpensiones)|IBC|12%|4%|Colpensiones<br>(mayoría<br>servidores)|
||||||
|Pensión (Fondo<br>Privado)|IBC|12%|4%|AFP elegida por el<br>servidor|
||||||
|ARL (Riesgos<br>Laborales)|IBC|Según clase<br>riesgo<br>(0.348% a<br>8.7%)|0%|ARL contratada|
||||||
|Caja de<br>Compensación|Nómina mensual|4%|0%|Caja<br>compensación<br>familiar|
||||||
|ICBF|Nómina mensual|3%|0%|ICBF (si salarios <<br>10 SMMLV:<br>exonerado desde<br>2013)|
||||||
|SENA|Nómina mensual|2%|0%|SENA (misma<br>exoneración)|



## **Macro-Sistema 6 — Almacén, Inventarios y Activos del Estado** 

Los bienes del Estado no son mercancía: son patrimonio público. Su gestión está regulada por la CGN bajo NICSP 17 (Propiedades, Planta y Equipo) y la distinción jurídica entre tipos de bienes es tan importante como su valoración contable. 

## 📋 **NICSP 17 — Propiedades, Planta y Equipo + Procedimiento CGN Activos No Corrientes** 

La NICSP 17 (adoptada por la Res. 533/2015 CGN) regula el reconocimiento, medición posterior y depreciación de los activos fijos del Estado. La CGN publicó procedimientos contables específicos para: bienes de uso público, bienes fiscales, bienes recibidos en dación en pago, bienes en depósito y activos intangibles. 

## **6.1 Clasificación de Bienes del Estado** 

|||||
|---|---|---|---|
|**Tipo de bien**|**Definición**|**Ejemplos**|**Cuenta CGC**|
|||||
|||||
|Bienes de uso<br>público|Destinados al uso común<br>de todos los ciudadanos.<br>No son susceptibles de<br>apropiación privada.|Calles, parques, playas, ríos<br>navegables, plazas públicas|1640 - Bienes de<br>uso público|
|||||
|Bienes fiscales|De propiedad de la<br>entidad pero NO al<br>servicio del público<br>general. Uso institucional.|Edificios de la alcaldía,<br>computadores, vehículos<br>oficiales, muebles y enseres|1635 -<br>Propiedades,<br>planta y equipo|
|||||
|Bienes de beneficio<br>y uso público|Infraestructura operada<br>por la entidad para prestar<br>servicios públicos.|Acueductos, alcantarillados,<br>alumbrado público, vías<br>concesionadas|1640 - Bienes de<br>uso público|
|||||
|Recursos naturales|Bienes naturales bajo la<br>soberanía del Estado.|Subsuelo, espectro<br>electromagnético, recursos<br>hídricos|1650 - Recursos<br>naturales y del<br>ambiente|
|||||
|||||
|Activos intangibles|Derechos sin forma física:<br>software, licencias,<br>marcas, derechos de<br>autor.|Sistemas de información,<br>licencias de software,<br>patentes|1920 - Activos<br>intangibles|
|||||



## **6.2 Depreciación NICSP 17 — Tasas por Tipo de Bien** 

📋 **Procedimiento CGN — Depreciación de Propiedades, Planta y Equipo (Entidades de Gobierno)** 

La CGN establece que la depreciación debe calcularse usando el método de línea recta, sobre la vida útil estimada de cada activo. La entidad debe revelar en notas las vidas útiles usadas. Los bienes de uso público generalmente NO se deprecian si tienen vida útil indefinida. 

||||||
|---|---|---|---|---|
|**Tipo de activo**|**Vida útil**<br>**(años)**|**Tasa depreciación**<br>**anual**|**Valor residual**|**Cuenta CGC depreciación**|
||||||
||||||
|Edificaciones|50-80|1.25% - 2%|0-10%|1635 CR: Depreciación<br>acumulada|
||||||
|Maquinaria y equipo|10-20|5% - 10%|0-5%|1635 CR: Depreciación<br>acumulada|
||||||
|Equipo de cómputo|5|20%|0%|1635 CR: Depreciación<br>acumulada|
||||||
||||||
|Vehículos|5-10|10% - 20%|0-10%|1635 CR: Depreciación<br>acumulada|
||||||
|Muebles y enseres|10|10%|0%|1635 CR: Depreciación<br>acumulada|
||||||
|Software (intangible)|3-5|20% - 33%|0%|1920 CR: Amortización<br>acumulada|
||||||
|Bienes de uso público<br>(vías)|Indefinida o<br>50-100|0% o 1%|S/A|Sujeto a deterioro NICSP|
||||||



## **6.3 Actas de Responsabilidad y Trazabilidad de Bienes** 

||||
|---|---|---|
|**Función**|**Descripción**|**Genera documento**|
||||
||||
|Asignación de bien a<br>funcionario|Al entregar un computador, vehículo o<br>equipo a un servidor público, el sistema<br>genera un Acta de Responsabilidad<br>firmada digitalmente.|Acta de entrega y<br>responsabilidad|
||||
|Traslado entre<br>dependencias|Movimiento de un bien de una unidad a<br>otra. Requiere acta firmada por el<br>funcionario saliente y entrante.|Acta de traslado|
||||
||||
|Baja por obsolescencia|Cuando un bien llega al final de su vida<br>útil o está en mal estado. Requiere<br>concepto técnico y acto administrativo.|Resolución de baja + Acta de<br>baja|
||||
|Baja por hurto o pérdida|Requiere denuncia penal y proceso de<br>responsabilidad fiscal. El bien sale de<br>inventario pero entra en la cuenta de<br>deudores.|Denuncia + Acta de pérdida +<br>Deudor CGN|
||||
|Dación en pago|Un tercero paga su deuda con bienes.<br>Requiere avalúo y acto administrativo<br>de aceptación.|Resolución de aceptación +<br>ingreso al inventario|



## **Macro-Sistema 7 — Trazabilidad, Seguridad y Rendición de Cuentas** 

Este macro-sistema es transversal a todos los anteriores. En el sector público colombiano, borrar un registro es potencialmente un delito de peculado por apropiación o falsedad ideológica en documento público. El sistema debe ser un testigo fiel e inalterable de toda la gestión. 

## 📋 **Ley 87 de 1993 — Control Interno + Ley 1474 de 2011 — Estatuto Anticorrupción + Circular CGN 001/2024** 

La Ley 87/1993 obligó a todas las entidades públicas a implementar sistemas de control interno. La Ley 1474/2011 (Estatuto Anticorrupción) reforzó los controles y penalizó conductas de corrupción. La Circular CGN 001/2024 instruyó a entidades sobre el cierre contable y la importancia de la trazabilidad de la información para los reportes a CHIP. 

## **7.1 Auditoría Forense en Base de Datos** 

## 🔒 **Principio de irreversibilidad del registro público** 

En el sector público, un registro contable NO SE BORRA. Se ANULA con un asiento de reversa. Un registro de nómina NO SE ELIMINA. Se corrige con un ajuste documentado. 

Todo intento de modificar datos históricos debe quedar registrado con: usuario, fecha, hora, IP, valor anterior y valor nuevo. 

El sistema debe implementar una tabla de auditoría SEPARADA de la base de datos principal, idealmente en solo-escritura (append-only), con hash encadenado para detectar manipulaciones. 

||||
|---|---|---|
|**Evento auditado**|**Datos que registra el log**|**Retención**<br>**mínima**|
||||
||||
|Creación de cualquier<br>registro|Tabla, ID del registro, usuario, fecha/hora,<br>IP, todos los valores insertados|10 años|
||||
|Modificación de cualquier<br>campo|Tabla, ID, campo modificado, valor<br>anterior, valor nuevo, usuario, fecha/hora,<br>IP, justificación|10 años|
||||
|Intento de eliminación|Tabla, ID, usuario, fecha/hora, IP — el<br>registro NO se borra, se marca como<br>anulado|10 años|
||||
||||
|Expedición de CDP|Usuario que expide, rubro afectado, valor,<br>número CDP, fecha/hora|10 años|
||||
|Pago de nómina|Funcionario pagado, valor, fecha, método,<br>aprobador, usuario sistema|50 años|
||||
|Login y logout|Usuario, IP, dispositivo, fecha/hora de<br>entrada y salida|5 años|
||||



||||
|---|---|---|
|**Evento auditado**|**Datos que registra el log**|**Retención**<br>**mínima**|
||||
||||
|Cambio de<br>contraseña/permisos|Usuario afectado, usuario que hace el<br>cambio, permisos anteriores y nuevos|10 años|
||||
||||
|Acceso a datos sensibles|Usuario, qué datos consultó, fecha/hora<br>(para datos de nómina y tributarios)|5 años|
||||



## **7.2 Generador Universal de Archivos Planos** 

Este es el módulo de mayor valor estratégico del ERP público. Las entidades deben reportar a múltiples organismos de control en formatos específicos, estructuras de datos exactas y plazos definidos. Generarlos manualmente es la principal fuente de errores y sanciones. 

||||||
|---|---|---|---|---|
|**Sistema de reporte**|**Organismo receptor**|**Formato**|**Periodicidad**|**Datos**<br>**fuente en**<br>**MerkaERP**|
||||||
||||||
|CHIP (Sistema CHIP)|Contaduría General<br>de la Nación|XML estructura<br>CHIP / Formularios<br>CGN|Trimestral +<br>Cierre anual<br>dic.|Todos los<br>módulos<br>contables|
||||||
|SIA Observa|Contraloría General<br>de la República|Archivos planos<br>.txt delimitados|Anual (Plan de<br>mejoramiento)|Contratación,<br>presupuesto,<br>nómina|
||||||
|SIIF Nación|Ministerio de<br>Hacienda|Estructura SIIF<br>(para entidades<br>nivel nacional)|Mensual|Presupuesto,<br>tesorería,<br>pagos|
||||||
|FUT (Formulario<br>Único Territorial)|DNP / Ministerio de<br>Hacienda|Excel + plataforma<br>Chip|Trimestral|Ingresos,<br>gastos,<br>deuda,<br>regalías|
||||||
|SECOP II|Colombia Compra<br>Eficiente|API REST X-Road<br>/ Archivos<br>PDF/XML|Por evento<br>contractual|Módulo de<br>contratación|
||||||
||||||
|PILA (Planilla<br>Integrada)|Operadores PILA<br>autorizados|Archivo plano<br>estructura PILA|Mensual|Módulo de<br>nómina|
||||||
|Declaraciones<br>tributarias territoriales|Secretaría de<br>Hacienda del<br>municipio|Formato<br>declaración<br>ICA/Predial|Según<br>calendario<br>tributario|Módulo de<br>rentas y<br>tributos|
||||||
|Informe de gestión al<br>Concejo|Concejo/Asamblea<br>Municipal|PDF con datos<br>agregados|Anual|Todos los<br>módulos|



## **7.3 Estructura del Reporte CHIP — El Más Crítico** 

## 📋 **Circular CGN 001/2024 e Instrucción CGN 001/2025 — Reporte CHIP** 

El Sistema CHIP (Consolidación de Hacienda e Información Pública) es la plataforma de la Contaduría General de la Nación para la recepción de estados financieros de todas las entidades públicas. El incumplimiento en el reporte genera sanciones directas al representante legal y al contador público suscriptor. La CGN emite instrucciones anuales de cierre (la más reciente: Instrucción 001/2025 para cierre 2024-2025). 

|||||
|---|---|---|---|
|**Formulario**<br>**CHIP**|**Nombre**|**Contenido**|**Corte**|
|||||
|||||
|CGN2015_001|Estado de Situación<br>Financiera|Activo, Pasivo, Patrimonio<br>detallado por cuenta CGC|Trimestral +<br>Anual|
|||||
|CGN2015_002|Estado de Rendimiento<br>Financiero|Ingresos y Gastos del período<br>por naturaleza|Trimestral +<br>Anual|
|||||
|CGN2015_003|Estado de Cambios en el<br>Patrimonio|Variaciones en cada<br>componente del patrimonio|Anual|
|||||
|CGN2015_004|Estado de Flujos de<br>Efectivo|Flujos de operación, inversión y<br>financiación|Anual|
|||||
|CGN2015_005|Notas a los estados<br>financieros|Políticas contables, revelaciones,<br>contingencias|Anual|
|||||
|CGN2016C01|Variaciones trimestrales<br>significativas|Explicación de cambios >X%<br>entre períodos comparados|Trimestral|
|||||
|FUT —<br>Categoría A|Ingresos corrientes<br>ejecutados|Predial, ICA, SGP, regalías,<br>otros|Trimestral|
|||||
|FUT —<br>Categoría B|Gastos ejecutados|Funcionamiento, inversión,<br>deuda|Trimestral|
|||||



## **Macro-Sistema 8 — Facturación y Gestión en Salud Pública (Hospitales / ESE)** 

Cuando el cliente es un hospital público o una Empresa Social del Estado (ESE), MerkaERP deja de competir con un ERP genérico y empieza a competir con sistemas de información en salud. Este macro-sistema reconoce que "hospitales" no es una fila más en la tabla de clientes: es un dominio regulatorio propio, con su propio lenguaje (RIPS, glosas, CUPS, CUM) y sus propios actores (EPS, ADRES, Supersalud). 

## 📋 **Resolución 3374 de 2000 + Resolución 2275 de 2023 (RIPS) + Ley 1438 de 2011** 

La Resolución 3374/2000 creó los RIPS (Registro Individual de Prestación de Servicios de Salud), obligatorios para toda factura de servicios de salud. La Resolución 2275/2023 actualizó la estructura técnica de los RIPS y su reporte a ADRES/MinSalud. La Ley 1438/2011 reforzó el Sistema General de Seguridad Social en Salud y las reglas de flujo de recursos entre EPS e IPS/ESE. 

## **8.1 RIPS — Registro Individual de Prestación de Servicios de Salud** 

||||
|---|---|---|
|**Función**|**Descripción técnica**|**Dato clave**|
||||
||||
|Generación RIPS|Construcción de los 6 archivos planos (AF,<br>AC, AP, AT, AU, AM) por cada atención<br>prestada, con estructura definida por<br>Resolución 2275/2023.|Formato oficial ADRES|
||||
|Validación previa|Motor de reglas que valida consistencia entre<br>CUPS, CUM, diagnóstico CIE-10 y tipo de<br>afiliación antes de facturar.|Evita glosas por RIPS<br>inconsistentes|
||||
|Cargue a plataforma|Transmisión de RIPS validados a la<br>plataforma de ADRES / interoperabilidad con<br>EPS.|Trazabilidad de envíos|
||||
|Vínculo con<br>facturación|Cada factura de venta de servicios de salud<br>queda amarrada 1 a 1 con su RIPS<br>correspondiente.|Requisito legal de cobro|



## **8.2 Contratación y Facturación con EPS / ADRES** 

La venta de servicios de salud no es una venta comercial libre: depende de contratos de capitación, evento, o paquete (PGP) suscritos con cada EPS, cada uno con sus propias tarifas (manual tarifario SOAT / ISS 2001 / propio) y topes. 

||||
|---|---|---|
|**Modalidad**|**Descripción**|**Implicación en el sistema**|
||||
||||
|Evento|Se cobra cada servicio individual según<br>manual tarifario pactado.|Motor de tarifación por<br>manual (SOAT/ISS/propio)<br>por contrato|
||||
|Capitación|Pago fijo per cápita mensual por población<br>asignada, independiente del uso real.|Módulo de conciliación de<br>población asignada vs.<br>atendida|



||||
|---|---|---|
|**Modalidad**|**Descripción**|**Implicación en el sistema**|
||||
||||
|PGP (Pago Global<br>Prospectivo)|Presupuesto fijo por grupo de riesgo/servicios<br>definidos.|Seguimiento de ejecución<br>presupuestal por grupo<br>PGP|
||||
||||
|Régimen subsidiado /<br>contributivo / ADRES<br>directo|Cada régimen tiene reglas propias de recobro<br>y trazabilidad.|Clasificación obligatoria del<br>paciente por régimen antes<br>de facturar|



## **8.3 Glosas y Conciliación de Cuentas Médicas** 

⚠ **Glosas — Decreto 4747 de 2007 y Resolución 3047 de 2008** Una glosa es la objeción que hace la EPS a una factura, total o parcial, por inconsistencias administrativas, tarifarias o de pertinencia médica. El proceso de radicación-glosa-respuestaconciliación tiene términos legales estrictos: la IPS/ESE tiene 5 días hábiles para responder una glosa y la EPS 15 días hábiles para resolverla, contados desde la radicación de la factura. 

|⚠**Glosas — Decreto 4747 de 2007 y Resolución 3047 de 2008**<br>Una glosa es la objeción que hace la EPS a una factura, total o parcial, por inconsistencias<br>administrativas, tarifarias o de pertinencia médica. El proceso de radicación-glosa-respuesta-<br>conciliación tiene términos legales estrictos: la IPS/ESE tiene 5 días hábiles para responder una<br>glosa y la EPS 15 días hábiles para resolverla, contados desde la radicación de la factura.|⚠**Glosas — Decreto 4747 de 2007 y Resolución 3047 de 2008**<br>Una glosa es la objeción que hace la EPS a una factura, total o parcial, por inconsistencias<br>administrativas, tarifarias o de pertinencia médica. El proceso de radicación-glosa-respuesta-<br>conciliación tiene términos legales estrictos: la IPS/ESE tiene 5 días hábiles para responder una<br>glosa y la EPS 15 días hábiles para resolverla, contados desde la radicación de la factura.|⚠**Glosas — Decreto 4747 de 2007 y Resolución 3047 de 2008**<br>Una glosa es la objeción que hace la EPS a una factura, total o parcial, por inconsistencias<br>administrativas, tarifarias o de pertinencia médica. El proceso de radicación-glosa-respuesta-<br>conciliación tiene términos legales estrictos: la IPS/ESE tiene 5 días hábiles para responder una<br>glosa y la EPS 15 días hábiles para resolverla, contados desde la radicación de la factura.|
|---|---|---|
||||
|**Función**|**Descripción técnica**|**Dato clave**|
||||
||||
|Radicación de cuentas|Registro de facturas radicadas a cada<br>EPS con fecha, monto y soportes (RIPS,<br>historia clínica, orden médica).|Contador legal de plazos de<br>respuesta|
||||
|Registro de glosas|Captura del código y descripción de la<br>glosa según tabla única de causales<br>(Resolución 3047/2008).|Clasifica por tipo:<br>administrativa, tarifaria, de<br>pertinencia|
||||
|Respuesta a glosa|Alerta automática de vencimiento del<br>término de 5 días hábiles para<br>responder.|Evita pérdida de cartera por<br>no respuesta|
||||
|Conciliación|Registro del acta de conciliación con<br>monto aceptado, monto ratificado y saldo<br>en disputa.|Insumo directo para cartera y<br>estados financieros|
||||
|Cartera en salud|Antigüedad de cartera por EPS,<br>diferenciando facturado, glosado,<br>conciliado y por cobrar.|Reporte obligatorio a junta<br>directiva ESE|



## **Macro-Sistema 9 — Sistema General de Regalías (SGR)** 

Las regalías no se ejecutan como el presupuesto ordinario del municipio. Tienen su propio ciclo de aprobación, sus propios órganos colegiados (OCAD) y su propio sistema de presupuesto y giro. Para municipios y departamentos con vocación minero-energética, el SGR puede representar una porción significativa del presupuesto de inversión, y un ERP que no lo modele deja fuera una parte material de la plata pública. 

## 📋 **Acto Legislativo 05 de 2019 + Ley 2056 de 2020 + Decreto 1821 de 2020 (SPGR)** 

El Acto Legislativo 05/2019 reformó el Sistema General de Regalías. La Ley 2056/2020 desarrolló su régimen presupuestal, de seguimiento, control y evaluación para el bienio 2021-2022 en adelante (con bienalidades sucesivas). El Decreto 1821/2020 reglamentó el Sistema de Presupuesto y Giro de Regalías (SPGR), la plataforma obligatoria del DNP para ejecutar y girar recursos de regalías. 

## **9.1 OCAD — Órganos Colegiados de Administración y Decisión** 

||||
|---|---|---|
|**Función**|**Descripción técnica**|**Dato clave**|
||||
||||
|Registro de proyectos<br>OCAD|Cargue del proyecto de inversión (formulado<br>en MGA) para viabilización y priorización por<br>el OCAD correspondiente (municipal,<br>departamental, regional).|Vinculado al Banco de<br>Proyectos (Macro-Sistema<br>1)|
||||
|Acta de aprobación|Registro del acta OCAD con el monto<br>aprobado, la fuente (asignaciones directas,<br>ambientales, paz, ciencia y tecnología) y el<br>ejecutor designado.|Documento habilitante para<br>iniciar ejecución|
||||
|Designación de<br>ejecutor|El proyecto puede ser ejecutado por una<br>entidad distinta a la que lo formuló; el sistema<br>debe permitir esa trazabilidad.|Común en proyectos<br>regionales|



## **9.2 Bienalidades y Ejecución Presupuestal del SGR** 

||||
|---|---|---|
|**Función**|**Descripción técnica**|**Dato clave**|
||||
||||
|Presupuesto bienal|El SGR se presupuesta por bienios (2 años),<br>no por vigencias anuales como el presupuesto<br>ordinario.|Ley 2056/2020|
||||
|Ejecución CDP-RP-<br>Obligación-Pago<br>SGR|El flujo presupuestal es análogo al del EOP<br>(Decreto 111/1996) pero se registra y reporta<br>exclusivamente en el SPGR.|No se mezcla con<br>SIIF/CHIP del presupuesto<br>ordinario|
||||
||||
|Rendimientos<br>financieros|Los rendimientos generados por recursos de<br>regalías no ejecutados deben reinvertirse en el<br>mismo proyecto o fin.|Control de reinversión<br>obligatoria|
||||



## **9.3 Reporte al SPGR (Sistema de Presupuesto y Giro de Regalías)** 

El sistema debe generar los archivos de interoperabilidad exigidos por el DNP para registrar programación, ejecución y giro de cada proyecto financiado con regalías, incluyendo el reporte de avance físico y financiero que alimenta el Sistema de Monitoreo, Seguimiento, Control y Evaluación (SMSCE) del SGR. 

## **Macro-Sistema 10 — Sistema General de Participaciones (SGP)** 

El SGP es la principal transferencia de la Nación a los territorios y financia, con destinación específica, los sectores de educación, salud y agua potable, además de una participación de propósito general de libre destinación parcial. Ejecutar SGP fuera de su destinación específica es una de las causales más comunes de hallazgo fiscal y disciplinario en entes territoriales. 

## 📋 **Ley 715 de 2001 + Acto Legislativo 04 de 2007** 

La Ley 715/2001 organizó la prestación de los servicios de educación y salud, y reglamentó el SGP. El Acto Legislativo 04/2007 modificó los artículos 356 y 357 de la Constitución, ajustando las participaciones y reforzando el principio de destinación específica: los recursos de SGP solo pueden usarse para el sector para el que fueron girados. 

|📋**Ley 715 de 2001 + Acto Legislativo 04 de 2007**<br>La Ley 715/2001 organizó la prestación de los servicios de educación y salud, y reglamentó el SGP.<br>El Acto Legislativo 04/2007 modificó los artículos 356 y 357 de la Constitución, ajustando las<br>participaciones y reforzando el principio de destinación específica: los recursos de SGP solo pueden<br>usarse para el sector para el que fueron girados.|📋**Ley 715 de 2001 + Acto Legislativo 04 de 2007**<br>La Ley 715/2001 organizó la prestación de los servicios de educación y salud, y reglamentó el SGP.<br>El Acto Legislativo 04/2007 modificó los artículos 356 y 357 de la Constitución, ajustando las<br>participaciones y reforzando el principio de destinación específica: los recursos de SGP solo pueden<br>usarse para el sector para el que fueron girados.|📋**Ley 715 de 2001 + Acto Legislativo 04 de 2007**<br>La Ley 715/2001 organizó la prestación de los servicios de educación y salud, y reglamentó el SGP.<br>El Acto Legislativo 04/2007 modificó los artículos 356 y 357 de la Constitución, ajustando las<br>participaciones y reforzando el principio de destinación específica: los recursos de SGP solo pueden<br>usarse para el sector para el que fueron girados.|
|---|---|---|
||||
|**Componente SGP**|**Destinación específica**|**Reglas clave para el sistema**|
||||
||||
|Educación|Nómina docente, calidad educativa,<br>infraestructura educativa según<br>certificación de la entidad.|Requiere módulo de nómina<br>docente con escalafón propio<br>(Estatuto Docente)|
||||
|Salud|Régimen subsidiado, salud pública<br>colectiva, prestación de servicios en lo no<br>cubierto con subsidios a la demanda.|Se articula con Macro-Sistema 8<br>(Salud Pública)|
||||
|Agua potable y<br>saneamiento básico|Subsidios de<br>acueducto/alcantarillado/aseo y obras de<br>infraestructura del sector.|Cruce con facturación de<br>servicios públicos domiciliarios<br>si aplica|
||||
|Propósito general|Libre inversión (con un porcentaje<br>obligatorio para deporte, cultura y libre<br>destinación según categoría del<br>municipio).|Único componente con<br>flexibilidad parcial de<br>destinación|



## **10.1 Certificación de Destinación y Reporte SICODIS** 

El sistema debe bloquear cualquier registro presupuestal que intente cruzar recursos de un componente del SGP hacia un rubro de otro sector, y debe generar los reportes trimestrales del Formulario Único Territorial (FUT) y del aplicativo SICODIS del DNP, que certifican el uso correcto de cada peso girado por concepto de SGP. 

## **Macro-Sistema 11 — Transparencia Proactiva y Control Disci linario p** 

La auditoría forense del Macro-Sistema 7 detecta anomalías, pero detectar no basta: la ley exige que esas anomalías alimenten procesos disciplinarios formales, y que buena parte de la información de la entidad esté disponible públicamente sin que el ciudadano tenga que pedirla. Este macro-sistema cierra ese ciclo. 

## **11.1 Portal de Transparencia (Ley 1712 de 2014)** 

📋 **Ley 1712 de 2014 — Ley de Transparencia y del Derecho de Acceso a la Información Pública** 

Obliga a toda entidad pública a publicar proactivamente, en su sitio web, información mínima sobre estructura, presupuesto, contratación, planta de personal y trámites, sin esperar una solicitud del ciudadano. El incumplimiento es falta disciplinaria y puede derivar en sanciones de los organismos de control. 

|📋**Ley 1712 de 2014 — Ley de Transparencia y del Derecho de Acceso a la Información**<br>**Pública**<br>Obliga a toda entidad pública a publicar proactivamente, en su sitio web, información mínima sobre<br>estructura, presupuesto, contratación, planta de personal y trámites, sin esperar una solicitud del<br>ciudadano. El incumplimiento es falta disciplinaria y puede derivar en sanciones de los organismos<br>de control.|📋**Ley 1712 de 2014 — Ley de Transparencia y del Derecho de Acceso a la Información**<br>**Pública**<br>Obliga a toda entidad pública a publicar proactivamente, en su sitio web, información mínima sobre<br>estructura, presupuesto, contratación, planta de personal y trámites, sin esperar una solicitud del<br>ciudadano. El incumplimiento es falta disciplinaria y puede derivar en sanciones de los organismos<br>de control.|📋**Ley 1712 de 2014 — Ley de Transparencia y del Derecho de Acceso a la Información**<br>**Pública**<br>Obliga a toda entidad pública a publicar proactivamente, en su sitio web, información mínima sobre<br>estructura, presupuesto, contratación, planta de personal y trámites, sin esperar una solicitud del<br>ciudadano. El incumplimiento es falta disciplinaria y puede derivar en sanciones de los organismos<br>de control.|
|---|---|---|
||||
|**Sección obligatoria**|**Contenido a publicar desde MerkaERP**|**Periodicidad**|
||||
||||
|Presupuesto|Presupuesto aprobado, modificaciones y<br>ejecución (ingresos y gastos).|Mensual|
||||
|Contratación|Contratos suscritos, cuantía, contratista y<br>estado, con enlace a SECOP II.|Continua|
||||
|Talleres de rendición de<br>cuentas|Informes de gestión y metas del PDT<br>(Macro-Sistema 1).|Anual|
||||
|Planta de personal|Estructura orgánica, nómina agregada por<br>cargo (sin datos personales sensibles).|Semestral|
||||
|Estados financieros|Estados financieros bajo NICSP publicados<br>(Macro-Sistema 2).|Trimestral|



## **11.2 Control Interno Disciplinario (Código General Disciplinario)** 

📋 **Ley 1952 de 2019 — Código General Disciplinario** 

Regula el procedimiento disciplinario aplicable a servidores públicos. El módulo de auditoría forense no puede limitarse a "detectar" anomalías: cuando detecta un hallazgo con apariencia de falta disciplinaria (p. ej. incumplir el flujo CDP→RP→Obligación→Pago, o violar el PAC), debe generar automáticamente un expediente preliminar para la oficina de Control Interno Disciplinario. 

|**Función**|**Descripción técnica**|**Dato clave**|
|---|---|---|
|Generación automática|Toda alerta crítica del módulo de auditoría|No reemplaza el análisis|
|de queja preliminar|forense (Macro-Sistema 7) que configure|jurídico humano; solo lo|
||posible falta genera un radicado|alimenta|
||preliminar dirigido a Control Interno||
||Disciplinario.||



|Expediente disciplinario|Registro de etapas: indagación preliminar,<br>investigación disciplinaria, cargos,<br>descargos, fallo.|Términos y etapas según<br>Ley 1952/2019|
|---|---|---|
||||
|Reserva del expediente|Acceso restringido por rol; la indagación<br>preliminar es reservada por ley.|Control de permisos estricto<br>(ver Roles y Perfiles)|
||||
||||
|Reporte a Procuraduría|Exportación al Sistema de Información<br>Disciplinaria (SID) de la Procuraduría<br>General de la Nación.|Obligatorio para segunda<br>instancia|
||||



## **Plan de Im lementación or Fases p p** 

Dada la complejidad normativa y técnica del sector público, se propone una implementación gradual de 8 fases que permita ir integrando los módulos sin afectar la operación del ERP comercial existente de MerkaERP. 

||||||
|---|---|---|---|---|
|**Fase**|**Macro-sistemas**|**Duración**|**Entregable clave**|**Prioridad**|
||||||
||||||
|Fase 1|M2: Presupuesto<br>público + PAC|6-8 semanas|Flujo<br>CDP→RP→Obligación→Pago<br>funcional|🔴Crítica|
||||||
|Fase 2|M2: Contabilidad<br>NICSP + CGC<br>público|6-8 semanas|Plan de cuentas CGN +<br>asientos automáticos bajo<br>NICSP|🔴Crítica|
||||||
||||||
|Fase 3|M7: Auditoría forense<br>+ CHIP básico|4-5 semanas|Log inalterable + exportación<br>formularios CHIP|🔴Crítica|
||||||
|Fase 4|M3: Predial + ICA +<br>intereses moratorios|8-10 semanas|Liquidación masiva predial con<br>importación catastro IGAC|🟠Alta|
||||||
|Fase 5|M4: Contratación<br>Pública + SECOP II|8-10 semanas|Ciclo contractual completo +<br>integración API X-Road|🟠Alta|
||||||
|Fase 6|M5: Nómina Pública<br>+ PILA + retroactivos|6-8 semanas|Liquidación con 6 regímenes +<br>archivo PILA + retroactivos|🟠Alta|
||||||
|Fase 7|M1: Planeación +<br>MGA + PDT|5-6 semanas|Banco de proyectos +<br>trazabilidad plan-presupuesto|🟡Media|
||||||
||||||
|Fase 8|M6: Activos del<br>Estado + cobro<br>coactivo + FUT<br>completo|6-8 semanas|Depreciación NICSP 17 +<br>expedientes coactivos + todos<br>los reportes|🟡Media|



## **Resumen de Módulos a Crear / Modificar** 

|||||
|---|---|---|---|
|**Módulo**|**Archivos**<br>**Flutter**|**Complejidad**|**Normativa principal**|
|||||
|||||
|presupuesto_publico_page.dart|8-12 archivos|🔴Muy Alta|Decreto 111/1996, EOP|
|||||
|pac_tesoreria_page.dart|5-7 archivos|🔴Alta|Art. 74-76 Decreto 111/1996|
|||||
|||||
|contabilidad_nicsp_page.dart|10-15<br>archivos|🔴Muy Alta|Resolución 533/2015 CGN|
|||||
|predial_ica_page.dart|12-16<br>archivos|🔴Alta|Ley 44/1990, Art. 635 ET|
|||||
|cobro_coactivo_page.dart|6-8 archivos|🟠Alta|Arts. 823-843 ET|
|||||



|||||
|---|---|---|---|
|**Módulo**|**Archivos**<br>**Flutter**|**Complejidad**|**Normativa principal**|
|||||
|||||
|contratacion_publica_page.dart|15-20<br>archivos|🔴Muy Alta|Ley 80/1993, Ley 1150/2007|
|||||
|||||
|secop_integration_service.dart|4-6 archivos|🟠Alta|Circular CCE Única 2022|
|||||
|nomina_publica_page.dart|10-14<br>archivos|🔴Muy Alta|Decreto 1042/1978, Ley<br>4/1992|
|||||
|||||
|retroactivos_service.dart|3-4 archivos|🟠Alta|Decreto 312/2026|
|||||
|activos_estado_page.dart|6-8 archivos|🟠Media|NICSP 17, Res. 533/2015|
|||||
|planeacion_pdt_page.dart|5-7 archivos|🟠Media|Ley 152/1994, MGA DNP|
|||||
|||||
|auditoria_forense_service.dart|4-5 archivos|🔴Alta|Ley 87/1993, Ley 1474/2011|
|||||
|chip_reporter_service.dart|6-8 archivos|🔴Alta|Circular CGN 001/2024|
|||||
|fut_reporter_service.dart|4-5 archivos|🟠Alta|Resolución DNP-Minhacienda|
|||||
|pila_publico_service.dart|3-4 archivos|🟠Media|PILA + regímenes especiales|
|||||
|facturacion_salud_page.dart|8-10 archivos|🔴Muy Alta|Res. 3374/2000, Res.<br>2275/2023 (RIPS)|
|||||
|glosas_conciliacion_service.dart|4-6 archivos|🟠Alta|Decreto 4747/2007, Res.<br>3047/2008|
|||||
|sgr_regalias_page.dart|6-8 archivos|🔴Alta|Ley 2056/2020, Decreto<br>1821/2020 (SPGR)|
|||||
|sgp_page.dart|5-7 archivos|🟠Alta|Ley 715/2001, Acto Legislativo<br>04/2007|
|||||
|portal_transparencia_service.dart|4-5 archivos|🟠Media|Ley 1712/2014|
|||||
|||||
|disciplinario_service.dart|4-6 archivos|🔴Alta|Ley 1952/2019 (Código<br>General Disciplinario)|
|||||
|consolidacion_nicsp40_service.dart|6-8 archivos|🔴Muy Alta|NICSP 40|
|||||
|||||
|migracion_datos_service.dart|5-7 archivos|🔴Alta|N/A — proyecto de<br>implementación|
|||||
|roles_permisos_service.dart|3-5 archivos|🟠Media|Segregación de funciones<br>sector público|
|||||



## **Re uisitos Ar uitectónicos de Habilitación q q y** 

Vender MerkaERP a una entidad territorial no es solo un problema normativo-funcional; también es un problema de arquitectura. Cuatro vacíos técnicos condicionan si el producto es viable de instalar y operar en el sector público. 

## **A.1 Multi-Entidad y Consolidación (NICSP 40)** 

📋 **NICSP 40 — Combinaciones y Traspasos de Entidades bajo Control Común** Si MerkaERP se vende a una gobernación, esta necesita ver sus propios estados financieros y, además, los estados financieros consolidados de todos los municipios, hospitales y entidades descentralizadas que le reportan. La NICSP 40 exige métodos de consolidación específicos para el sector público (distintos a la NIIF 10 comercial), reconociendo control presupuestal y no solo control accionario. 

|📋**NICSP 40 — Combinaciones y Traspasos de Entidades bajo Control Común**<br>Si MerkaERP se vende a una gobernación, esta necesita ver sus propios estados financieros y,<br>además, los estados financieros consolidados de todos los municipios, hospitales y entidades<br>descentralizadas que le reportan. La NICSP 40 exige métodos de consolidación específicos para el<br>sector público (distintos a la NIIF 10 comercial), reconociendo control presupuestal y no solo control<br>accionario.|📋**NICSP 40 — Combinaciones y Traspasos de Entidades bajo Control Común**<br>Si MerkaERP se vende a una gobernación, esta necesita ver sus propios estados financieros y,<br>además, los estados financieros consolidados de todos los municipios, hospitales y entidades<br>descentralizadas que le reportan. La NICSP 40 exige métodos de consolidación específicos para el<br>sector público (distintos a la NIIF 10 comercial), reconociendo control presupuestal y no solo control<br>accionario.|📋**NICSP 40 — Combinaciones y Traspasos de Entidades bajo Control Común**<br>Si MerkaERP se vende a una gobernación, esta necesita ver sus propios estados financieros y,<br>además, los estados financieros consolidados de todos los municipios, hospitales y entidades<br>descentralizadas que le reportan. La NICSP 40 exige métodos de consolidación específicos para el<br>sector público (distintos a la NIIF 10 comercial), reconociendo control presupuestal y no solo control<br>accionario.|
|---|---|---|
||||
|**Requisito**|**Descripción**|**Complejidad**|
||||
||||
|Modelo multi-tenant<br>jerárquico|Cada municipio/hospital opera su propia<br>instancia de datos, pero la gobernación<br>tiene una vista consolidada de solo lectura.|🔴Alta|
||||
|Eliminación de<br>operaciones recíprocas|Transferencias entre entidades del mismo<br>grupo (p. ej. gobernación → hospital) deben<br>eliminarse en la consolidación.|🔴Alta|
||||
|Plan de cuentas<br>homologado|Todas las entidades consolidadas deben<br>usar el mismo Catálogo General de Cuentas<br>(CGC) de la CGN para que la suma sea<br>válida.|🟠Media|
||||



## **A.2 Seguridad y Habilitación (ISO 27001 + MinTIC Gobierno Digital)** 

📋 **Política de Gobierno Digital (MinTIC) + ISO/IEC 27001** 

Para que una entidad pública adopte un software de gestión financiera, normalmente se exige en el pliego de condiciones evidencia de un Sistema de Gestión de Seguridad de la Información certificado bajo ISO/IEC 27001, y cumplimiento de los lineamientos de la Política de Gobierno Digital de MinTIC (arquitectura empresarial, seguridad digital, datos abiertos e interoperabilidad X-Road). 

|📋**Política de Gobierno Digital (MinTIC) + ISO/IEC 27001**<br>Para que una entidad pública adopte un software de gestión financiera, normalmente se exige en el<br>pliego de condiciones evidencia de un Sistema de Gestión de Seguridad de la Información<br>certificado bajo ISO/IEC 27001, y cumplimiento de los lineamientos de la Política de Gobierno Digital<br>de MinTIC (arquitectura empresarial, seguridad digital, datos abiertos e interoperabilidad X-Road).|📋**Política de Gobierno Digital (MinTIC) + ISO/IEC 27001**<br>Para que una entidad pública adopte un software de gestión financiera, normalmente se exige en el<br>pliego de condiciones evidencia de un Sistema de Gestión de Seguridad de la Información<br>certificado bajo ISO/IEC 27001, y cumplimiento de los lineamientos de la Política de Gobierno Digital<br>de MinTIC (arquitectura empresarial, seguridad digital, datos abiertos e interoperabilidad X-Road).|📋**Política de Gobierno Digital (MinTIC) + ISO/IEC 27001**<br>Para que una entidad pública adopte un software de gestión financiera, normalmente se exige en el<br>pliego de condiciones evidencia de un Sistema de Gestión de Seguridad de la Información<br>certificado bajo ISO/IEC 27001, y cumplimiento de los lineamientos de la Política de Gobierno Digital<br>de MinTIC (arquitectura empresarial, seguridad digital, datos abiertos e interoperabilidad X-Road).|
|---|---|---|
||||
|**Requisito**|**Descripción**|**Estado en el plan**|
||||
||||
|Certificación ISO 27001|Certificación del SGSI de MerkaERP<br>como proveedor, evaluada por ente<br>certificador acreditado.|Pendiente — no incluida<br>en v1.0|
||||
||||
|Lineamientos Gobierno<br>Digital|Cumplimiento del Marco de Referencia<br>de Arquitectura Empresarial y del Modelo<br>de Seguridad y Privacidad de la<br>Información (MSPI) de MinTIC.|Pendiente — no incluida<br>en v1.0|
||||
|Interoperabilidad X-Road|Uso del estándar de interoperabilidad del<br>Estado colombiano para conectarse con<br>SECOP II, CHIP, RUES, entre otros.|Mencionada en Fase 5<br>(Contratación); falta<br>extenderla a todo el<br>sistema|
||||



Habilitación ante Para el módulo de salud, requiere Nueva — ver MacroSupersalud / Contaduría habilitación adicional específica del Sistema 8 sector. 

## **A.3 Migración de Datos Históricos** 

Ninguna entidad empieza en cero. Casi siempre habrá que migrar información histórica desde otro ERP público (SEVEN, Softexpert, Limay, u otros) o desde hojas de Excel, con años de ejecución presupuestal y contable que deben cuadrar contra los estados financieros ya certificados a la Contaduría. 

||||
|---|---|---|
|**Etapa**|**Descripción técnica**|**Riesgo si se omite**|
||||
||||
|Diagnóstico del<br>sistema origen|Inventario de tablas, formatos y calidad de<br>datos del ERP o Excel anterior.|Subestimar el esfuerzo real<br>de migración|
||||
|Mapeo de plan de<br>cuentas|Homologar el plan de cuentas anterior al CGC<br>vigente (Res. 533/2015).|Estados financieros<br>migrados no cuadran|
||||
|Migración de saldos<br>iniciales|Cargue de saldos de apertura certificados<br>contra el último corte reportado a CHIP.|Diferencias que generan<br>hallazgo de auditoría|
||||
|Migración de terceros<br>y contratos vigentes|Proveedores, contratistas y contratos en<br>ejecución no pueden perder su trazabilidad<br>histórica.|Ruptura del historial de<br>pagos a un contratista|
||||
|Paralelo y validación|Correr el sistema antiguo y MerkaERP en<br>paralelo mínimo un cierre mensual antes del<br>corte definitivo.|Errores de corte no<br>detectados a tiempo|



## **A.4 Roles y Perfiles del Sector Público** 

Los permisos en un ERP comercial se diseñan por conveniencia operativa. En el sector público están, en buena parte, definidos por la ley: un tesorero no puede aprobar su propio pago, un contador no puede expedir un CDP. El sistema debe modelar esta segregación de funciones como una regla dura, no como una configuración opcional. 

|||||
|---|---|---|---|
|**Rol**|**Función legal**|**Permisos típicos en**<br>**MerkaERP**|**Segregación**<br>**clave**|
|||||
|||||
|Alcalde /<br>Representante<br>legal|Ordenador del gasto principal (Art.<br>82 EOP).|Aprobación final de<br>compromisos de alto<br>monto, firma de<br>contratos.|No puede<br>autoliquidarse<br>pagos|
|||||
|Secretario de<br>Hacienda|Responsable de la política fiscal y<br>presupuestal de la entidad.|Aprobación de<br>modificaciones<br>presupuestales, PAC.|No expide<br>CDP ni RP<br>directamente|
|||||
|||||
|Tesorero|Custodio de los recursos, ejecuta el<br>pago (Art. 74 EOP — PAC).|Ejecución de pagos,<br>conciliación bancaria.|No puede<br>expedir<br>CDP/RP de<br>su propio<br>pago|



|||||
|---|---|---|---|
|**Rol**|**Función legal**|**Permisos típicos en**<br>**MerkaERP**|**Segregación**<br>**clave**|
|||||
|||||
|Contador|Responsable del registro contable<br>bajo NICSP (Res. 533/2015).|Registro y ajuste de<br>asientos contables, cierre<br>de vigencia.|No aprueba<br>ni ejecuta<br>pagos|
|||||
|||||
|Jefe de Rentas /<br>Tesorería de<br>Ingresos|Responsable de la liquidación y<br>recaudo de tributos.|Liquidación predial/ICA,<br>gestión de cobro<br>coactivo.|No administra<br>el gasto, solo<br>el ingreso|
|||||
|||||
|Jefe de Control<br>Interno|Evalúa el sistema de control interno<br>(Ley 87/1993).|Acceso de solo lectura a<br>todo el sistema + módulo<br>de auditoría forense.|No puede<br>modificar<br>registros, solo<br>consultarlos|
|||||



## **Validación de Mercado Modelo Comercial y** 

Un plan técnico y normativo completo no responde todavía la pregunta comercial: ¿quién compra esto y cómo se lo vendemos? En el sector público colombiano, la respuesta no es trivial, porque el comprador no elige libremente: debe licitar. 

## **B.1 El Comprador Real y el Proceso de Adquisición** 

## ⚠ **La entidad pública no puede simplemente "comprar" MerkaERP** 

Por Ley 80/1993 y Ley 1150/2007 (ver Macro-Sistema 4), la adquisición de un software de gestión financiera por una entidad pública debe surtir un proceso de selección: normalmente licitación pública o, según cuantía y naturaleza, selección abreviada o mínima cuantía. Esto significa que MerkaERP no le vende al alcalde: le vende a un pliego de condiciones que el alcalde (o su equipo jurídico) redacta, y que puede terminar favoreciendo a un competidor si el pliego no está bien diseñado. 

|⚠**La entidad pública no puede simplemente "comprar" MerkaERP**<br>Por Ley 80/1993 y Ley 1150/2007 (ver Macro-Sistema 4), la adquisición de un software de gestión<br>financiera por una entidad pública debe surtir un proceso de selección: normalmente licitación<br>pública o, según cuantía y naturaleza, selección abreviada o mínima cuantía. Esto significa que<br>MerkaERP no le vende al alcalde: le vende a un pliego de condiciones que el alcalde (o su equipo<br>jurídico) redacta, y que puede terminar favoreciendo a un competidor si el pliego no está bien<br>diseñado.|⚠**La entidad pública no puede simplemente "comprar" MerkaERP**<br>Por Ley 80/1993 y Ley 1150/2007 (ver Macro-Sistema 4), la adquisición de un software de gestión<br>financiera por una entidad pública debe surtir un proceso de selección: normalmente licitación<br>pública o, según cuantía y naturaleza, selección abreviada o mínima cuantía. Esto significa que<br>MerkaERP no le vende al alcalde: le vende a un pliego de condiciones que el alcalde (o su equipo<br>jurídico) redacta, y que puede terminar favoreciendo a un competidor si el pliego no está bien<br>diseñado.|⚠**La entidad pública no puede simplemente "comprar" MerkaERP**<br>Por Ley 80/1993 y Ley 1150/2007 (ver Macro-Sistema 4), la adquisición de un software de gestión<br>financiera por una entidad pública debe surtir un proceso de selección: normalmente licitación<br>pública o, según cuantía y naturaleza, selección abreviada o mínima cuantía. Esto significa que<br>MerkaERP no le vende al alcalde: le vende a un pliego de condiciones que el alcalde (o su equipo<br>jurídico) redacta, y que puede terminar favoreciendo a un competidor si el pliego no está bien<br>diseñado.|
|---|---|---|
||||
|**Actor**|**Rol en la decisión de compra**|**Implicación comercial**|
||||
||||
|Secretario de Hacienda /<br>TIC|Define requisitos funcionales del pliego y<br>suele ser el sponsor técnico interno.|Interlocutor clave para pre-<br>venta y elaboración de<br>especificaciones técnicas|
||||
|Jurídico / Contratación|Redacta el pliego de condiciones y<br>verifica el cumplimiento de Ley 80/1993.|Debe validar que los<br>requisitos no configuren<br>pliegos "sastre" para un solo<br>proveedor|
||||
|Concejo / Asamblea|Aprueba el presupuesto que financia la<br>adquisición.|El proyecto debe estar<br>presupuestado antes de<br>poder contratarse (CDP<br>previo)|
||||
|Órganos de control<br>(Contraloría)|Vigila que el proceso de selección no<br>favorezca indebidamente a un oferente.|Riesgo reputacional si el<br>proceso se percibe<br>direccionado|
||||



Esto implica que la estrategia comercial de MerkaERP para el sector público no puede ser una venta directa tradicional: requiere (a) participar en procesos de licitación pública compitiendo con otros ERP del sector (SEVEN, Softexpert, entre otros), (b) trabajar la relación con el equipo técnico de la entidad antes de la publicación del pliego para influir en las especificaciones técnicas de forma lícita, y (c) considerar alianzas con integradores que ya tengan trayectoria certificada en contratación pública. 

## **B.2 Estimación de Esfuerzo y Costo Total del Proyecto** 

El plan v1.0 solo estimaba duración por fase, sin esfuerzo ni costo. La siguiente estimación agrega el orden de magnitud de esfuerzo (persona-semana) por fase, incluyendo las fases nuevas de este documento. Las cifras son un punto de partida para un ejercicio de costeo detallado, no una cotización cerrada. 

||||||
|---|---|---|---|---|
|**Fase**|**Alcance**|**Duración**|**Esfuerzo**<br>**aprox.**|**Perfil**<br>**dominante**|
||||||
||||||
|Fase 0|Migración de datos +<br>seguridad/habilitación (ISO<br>27001, MinTIC)|6-8 semanas|8-10 pers-sem|Arquitecto +<br>Data engineer|
||||||
||||||
|Fase 1|Presupuesto público + PAC|6-8 semanas|10-12 pers-sem|Backend +<br>funcional fiscal|
||||||
|Fase 2|Contabilidad NICSP + CGC<br>público|6-8 semanas|12-14 pers-sem|Backend +<br>contador<br>público|
||||||
||||||
|Fase 3|Auditoría forense + CHIP básico|4-5 semanas|6-8 pers-sem|Backend +<br>seguridad|
||||||
|Fase 4|Predial + ICA + intereses<br>moratorios|8-10 semanas|14-16 pers-sem|Full-stack +<br>tributarista|
||||||
||||||
|Fase 5|Contratación pública + SECOP II|8-10 semanas|14-18 pers-sem|Full-stack +<br>abogado<br>contratación|
||||||
|Fase 6|Nómina pública + PILA +<br>retroactivos|6-8 semanas|10-12 pers-sem|Backend +<br>nómina|
||||||
|Fase 7|Planeación + MGA + PDT|5-6 semanas|6-8 pers-sem|Full-stack +<br>planeación|
||||||
|Fase 8|Activos del Estado + cobro<br>coactivo + FUT|6-8 semanas|8-10 pers-sem|Full-stack|
||||||
|Fase 9|Salud pública: RIPS, EPS, glosas<br>(nueva)|8-10 semanas|14-16 pers-sem|Full-stack +<br>facturación<br>salud|
||||||
|Fase<br>10|SGR + SGP (nueva)|6-8 semanas|10-12 pers-sem|Backend +<br>fiscal territorial|
||||||
||||||
|Fase<br>11|Transparencia + disciplinario +<br>roles (nueva)|5-6 semanas|8-10 pers-sem|Full-stack +<br>jurídico<br>disciplinario|



## 🔢 **Orden de magnitud total** 

Sumando las 12 fases (0 a 11): aproximadamente 76-90 semanas de calendario si se ejecutan en serie, y un esfuerzo acumulado del orden de 120-150 persona-semana. 

En la práctica varias fases pueden correr en paralelo con equipos distintos, lo que podría comprimir el calendario a 12-16 meses con un equipo de 4-6 personas simultáneas. 

Esta estimación no incluye licenciamiento de terceros (p. ej. interoperabilidad X-Road, certificación ISO 27001) ni el costo del proceso de licitación en sí. 

✅ **Resultado: MerkaERP como ERP Público de Clase Enterprise** 

Con los 11 macro-sistemas implementados — incluyendo salud pública, regalías, SGP, transparencia y control disciplinario — más los requisitos de arquitectura multi-entidad, seguridad y migración, MerkaERP puede operar como ERP oficial de: 

- Alcaldías municipales de cualquier categoría (1ª a 6ª) 

- Gobernaciones departamentales 

- Hospitales públicos y ESE (Empresas Sociales del Estado) 

- Establecimientos públicos del orden territorial 

- Unidades Administrativas Especiales con y sin personería jurídica 

Todos los reportes a Contraloría (SIA Observa), Contaduría (CHIP), Ministerio de Hacienda (SIIF/FUT) y Colombia Compra Eficiente (SECOP II), además de los reportes a ADRES/Supersalud (RIPS), DNP (SPGR/SGR) y SICODIS (SGP), se generan con un clic desde el sistema. 

_MerkaERP Sector Público — Plan de Implementación v1.1  ·  Julio 2026_ 

