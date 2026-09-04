# Matriz de implementación — MerkaERP 1.3.0+8

Base de trabajo: MerkaERP 1.2.1+7 confirmada como compilable por el propietario.

Principio aplicado: mejorar y consolidar los dominios ya existentes. No se crean módulos paralelos cuando una capacidad pertenece naturalmente a un módulo actual.

## MerkaERP Comercial

| # | Compromiso | Ubicación natural | Estado 1.3.0+8 | Qué se integró / mejoró |
|---|---|---|---|---|
| 1 | Backup y recuperación profesional | Administración > Respaldos | INTEGRADO | Backup manual/automático, respaldo integral de BD + documentos, retención 7/30/90 configurable, verificación SHA-256, restore drill, restauración validada, rollback previo y respaldo remoto cifrado cuando el cliente configura proveedor. |
| 2 | Centro de salud | Administración > Salud y soporte | INTEGRADO | Esquema, espacio, backup, sincronización, licencia, salud de datos, errores, restauración de prueba, optimización REINDEX/ANALYZE/PRAGMA optimize, verificación de inventario y diagnóstico contable. |
| 3 | Cierre de caja avanzado | Caja > Cierres | INTEGRADO | Turno por usuario, fondo inicial declarado, cierre asociado al responsable, arqueo/diferencia, historial, bloqueo y reapertura solo administrativa con motivo auditado. |
| 4 | Auditoría empresarial completa | Administración > Auditoría | INTEGRADO | Usuario, fecha, empresa, huella SHA-256 del equipo, antes/después cuando el flujo lo provee, detalle y análisis de operaciones de riesgo/sospechosas sin etiquetar automáticamente como fraude. |
| 5 | Motor de alertas | Núcleo de señales + Dashboard | INTEGRADO | Stock crítico/negativo, vencimientos, cartera, proveedores, caja, margen, FE pendiente, backup atrasado y licencia; navegación hacia el módulo responsable. |
| 6 | Dashboard ejecutivo | Inicio Comercial | INTEGRADO | Ventas día/semana/mes/año, utilidad/margen, cartera/proveedores, caja/bancos, inventario valorizado, rankings, evolución y puntuación “¿Cómo va mi empresa?”. |
| 7 | Reportes configurables | Reportes > Diseñador | INTEGRADO | Origen, campos, filtros, agrupación, orden, totales seleccionables, guardar definición, vista previa, Excel y PDF/impresión. |
| 8 | PDF profesionales | Plantillas + documentos | INTEGRADO | A4/Carta, logo, QR interno de trazabilidad, firma/responsable, pie configurable, paleta corporativa y uso en documentos comerciales principales. El QR interno no se presenta como QR DIAN. |
| 9 | POS rápido | Ventas/POS | INTEGRADO | Atajos F2/F4/F8/F10, lector teclado, favoritos, venta suspendida/recuperada, bloqueo de doble envío, autoimpresión y modo táctil configurable. Mantiene operación offline local. |
| 10 | Periféricos | Ventas/POS > Periféricos | INTEGRADO CON ALCANCE DECLARADO | ESC/POS TCP RAW, cajón, etiquetas ZPL/TSPL, báscula TCP y lector USB tipo teclado. Hardware propietario que requiera SDK del fabricante necesita conector específico. |
| 11 | Inventario avanzado | Inventario > Centro de control | INTEGRADO/CONSOLIDADO | Reutiliza lotes, vencimientos, Kardex, bodegas y reservas; añade política min/max/lead time, reposición, traslados, conteos, variantes y series como operaciones visibles. |
| 12 | Compras inteligentes | Compras > ¿Qué debo comprar? | INTEGRADO | Sugerencias según consumo histórico, existencia, min/max y tiempo de reposición; el usuario revisa cantidades antes de llevarlas al flujo normal de compra. |
| 13 | CRM inteligente | CRM > Inteligencia de clientes | INTEGRADO | VIP, inactivos, riesgo, frecuencia, ticket promedio, última compra, recompra estimada, cartera y creación de campañas para segmentos seleccionados. |
| 14 | WhatsApp | Clientes / Cartera / Documentos | INTEGRADO, REQUIERE CREDENCIALES | Meta WhatsApp Business mediante perfil de integración; envío de texto, recordatorios y documentos disponibles. No simula entrega/lectura. |
| 15 | Contabilidad colombiana automática | Contabilidad | INTEGRADO/MEJORADO | Mantiene PUC/parametrización/asientos/terceros/impuestos/reportes existentes y añade diagnóstico de descuadres, cuentas huérfanas, terceros faltantes, ventas/compras sin contabilizar e inventario negativo. |
| 16 | Facturación electrónica DIAN | Facturación electrónica + Integraciones | ARQUITECTURA OPERATIVA, REQUIERE PROVEEDOR/CREDENCIALES | Generación y flujo existentes + transporte configurable PTA/DIAN, verificación fail-closed. No se afirma habilitación DIAN sin credenciales/certificados/ambiente del cliente. |
| 17 | Nómina electrónica | HRM > Nómina > Nómina electrónica | INTEGRADO, REQUIERE PROVEEDOR/CREDENCIALES | Nómina comercial consolidada dentro de HRM; quinta etapa de nómina electrónica sobre liquidaciones reales, con envío/verificación mediante integración configurada. |
| 18 | Actualizador profesional | Administración / UpdateService | INTEGRADO EN APP | Manifiesto RS256, instalación ligada, HTTPS, SHA-256, backup preactualización y fail-closed. Distribución/servidor de releases se conecta posteriormente al Control Center externo. |
| 19 | Control Center SaaS | Fuera de este repositorio | EXCLUIDO POR DECISIÓN DEL PROPIETARIO | MerkaERP conserva solo contratos/clientes de comunicación. El Control Center se desarrolla por separado. |
| 20 | Asistente IA / Copilot | Copilot | INTEGRADO COMO SOLO LECTURA/RECOMENDACIÓN | Consultas de salud empresarial, compras sugeridas y clientes VIP/inactivos/riesgo; no modifica contabilidad ni ejecuta actos sensibles sin flujo humano. |

## MerkaERP Público — mejoras consolidadas

| Área | Estado 1.3.0+8 | Mejora |
|---|---|---|
| Dashboard institucional | INTEGRADO | Corrige columnas/escalas monetarias y añade contratos/pólizas por vencer, alertas de supervisión, obligaciones y estado SGDEA. |
| Cadena presupuestal | CONSOLIDADA | Salud institucional verifica apropiación → CDP → RP → obligación → pago y referencias huérfanas. |
| Contratación / Supervisión | INTEGRADO DENTRO DE CONTRATACIÓN | Quinta área “Supervisión”: bandeja, avance físico/financiero, informes, alertas, pólizas y trazabilidad proceso → CDP → RP → obligación → pago → SGDEA. |
| Contabilidad pública/NICSP | MEJORADA | Centro de salud verifica partida doble y pagos presupuestales sin asiento correspondiente. |
| PAC / Tesorería | MEJORADA | Controles de coherencia dentro de Salud institucional. |
| SGDEA / Gestión documental | CONSOLIDADO | Radicación, expedientes, versiones, firma/evidencia, archivo físico, préstamos, transferencias, TRD/TVD, instrumentos y disposición configurables por la entidad. |
| Regalías / SGP | MEJORADO | Bienios SGR quedan visibles y operables dentro del módulo existente. |
| Salud Pública | CONSERVADO/INTEGRADO | Se mantiene dentro del workspace Público y sujeto a licencia/configuración. |
| Interoperabilidad | FAIL-CLOSED | SECOP, CHIP, SIIF, PILA, BPIN y transparencia dependen de configuración/credenciales de la entidad; exportar no equivale a transmitir. |
| Salud institucional | INTEGRADO EN SALUD Y SOPORTE | Presupuesto, contabilidad, PAC, contratos, pólizas, supervisión, soportes y SGDEA en un mismo diagnóstico preventivo. |

## Seguridad y límites que no deben ocultarse

- Las familias Comercial y Público se enrutan por licencia; no son un selector libre del usuario.
- Secretos de integraciones se mantienen fuera de la base operativa cuando corresponde y las integraciones son fail-closed.
- Los comandos/actualizaciones remotas usan verificaciones criptográficas en el cliente.
- La auditoría conserva una huella SHA-256 del equipo; no guarda seriales de hardware en claro para este propósito.
- Los respaldos integrales incluyen repositorio documental y verifican integridad.
- La base SQLite completa todavía no se anuncia como cifrada integralmente en reposo; para equipos Windows debe complementarse con BitLocker/cifrado del dispositivo y control de cuentas.
- Compatibilidad con periféricos propietarios depende de que el fabricante ofrezca un protocolo/SDK integrable.
- DIAN, WhatsApp, pagos, nómina electrónica e interoperabilidades públicas requieren habilitación y credenciales reales del cliente/proveedor.

## Criterio de liberación

Esta matriz demuestra integración funcional/estática en el código. No sustituye el gate real de Flutter. Antes de declarar producción deben pasar en la máquina de build: `flutter analyze`, `flutter test`, `flutter build windows --release` y las pruebas funcionales/UAT correspondientes.
