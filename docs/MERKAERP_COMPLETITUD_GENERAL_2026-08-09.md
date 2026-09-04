# MerkaERP: mapa general de completitud

Fecha de corte: 2026-08-09

Este documento es un mapa de trabajo, no una declaracion de certificacion
productiva. Completo significa que existe flujo implementado y prueba
ejecutada para el alcance descrito; Parcial significa que hay codigo real
pero quedan integraciones, reglas, catalogos oficiales, formatos o cobertura.

## Evidencia transversal

- Smoke de modulos: docs/evidencias/module_smoke_total_2026-08-09_v8.txt,
  1 prueba pasada. Abre los modulos registrados sobre una base fresca y no
  encontro excepciones visibles.
- Auditoria de consultas: docs/evidencias/auditoria_schema_queries_2026-08-09_final.txt,
  tables=271 references=978 discrepancies=0.
- Auditoria de mojibake: docs/evidencias/auditoria_mojibake_2026-08-09_post.txt,
  files=0 lines=0 changed=0.
- Arranque: test/core/startup_flow_test.dart cubre licencia antes de
  onboarding, onboarding incompleto y ruta al login; la ruta ahora no depende
  de la ultima pantalla visitada.

## Sector publico

| Frente | Estado | Evidencia y limite actual |
|---|---|---|
| Arranque, contexto y selector de entidad | Parcial | lib/core/startup/startup_flow.dart, lib/sector_publico/database/schema_multi_tenant.dart, tests de startup/selector/contexto. Se resuelven licencia, onboarding y entidad; falta certificar todo el flujo con datos reales de cada tipo de entidad. |
| Presupuesto EOP: apropiacion -> CDP -> RP -> obligacion -> pago/PAC | Parcial | PresupuestoService y presupuesto_pago_integracion_test.dart cubren la cadena y bloqueos principales. Cierre de vigencia, vigencias futuras avanzadas y certificacion normativa integral siguen fuera. |
| Contabilidad publica/NICSP y estados financieros | Parcial | ContabilidadNICSPService, generadores NICSP y tests de signos/ecuacion. Faltan certificacion completa de todos los estados, revelaciones y cierre productivo por entidad. |
| Contratacion publica local | Parcial | ContratacionService, contrato firmado -> RP -> polizas -> legalizacion y tests de integracion. SECOP II/X-Road real, interoperabilidad y credenciales no estan conectados. |
| Nomina publica | Parcial | Regimenes y servicios publicos existen; vinculacion HRM y alertas para ausencias no procesadas estan implementadas. Reglas especificas no certificadas para todos los regimenes y casos normativos siguen pendientes. |
| Planeacion PDT/MGA | Parcial | Paginas y servicios de planeacion existen. Sigue pendiente la vinculacion automatica metas/programas -> rubros de inversion -> CDP/RP. |
| Rentas: predial, ICA, intereses y cobro coactivo | Parcial | Calculo, cartera tributaria e intereses estan en SQLite y tienen pruebas dirigidas. Exportacion oficial ICA y catalogos/formatos externos no estan expuestos. |
| Activos del Estado | Parcial | Registro, depreciacion, revalorizacion y asiento de depreciacion tienen servicio y pruebas. Faltan actas de responsabilidad de cuentadantes y su ciclo de firma/entrega. |
| Regalias SGR/SGP | Parcial | Proyectos OCAD, fuentes y bloqueos de destinacion tienen implementacion y pruebas. Falta certificacion completa del presupuesto bienal e integracion operativa con todos los componentes oficiales. |
| Salud/RIPS | Parcial | Generadores RIPS y conexion parcial a datos internos para formularios iniciales. 004/005/2016C01 requieren fuentes mas completas; CUPS/CIE-10/CUM oficiales no estan sembrados ni validados integralmente. |
| CHIP | Parcial | CGN2015_001-003 tienen prueba con datos del sistema. 004/005/CGN2016C01 y taxonomias faltantes siguen documentados como brecha. |
| SIIF Nacion, SIA Observa y FUT | Parcial | Hay generadores/payloads locales y pantallas. Las capturas de Omar confirman que hoy pueden fallar por referencias de entidad si el contexto no esta inicializado; el smoke fresco ya cubre apertura, pero no certifica envio oficial ni credenciales. |
| Auditoria forense e inmutabilidad | Parcial | auditoria_registros tiene hash encadenado y proteccion SQL; conciliacion NICSP 40 manual con aprobacion RBAC. Automatizacion disciplinaria y todas las excepciones de integracion siguen pendientes. |
| Transparencia/NICSP 40 | Parcial | Portal y consolidacion local existen; conciliaciones explicitas se conservan sin alterar asientos. Publicacion remota y eliminacion automatica/sugerida de reciprocas requieren datos/credenciales adicionales. |

## Comercial

| Frente | Estado | Evidencia y limite actual |
|---|---|---|
| Ventas/POS | Parcial | Flujo real, MoneyValue y ReteICA por regla de empresa. Quedan certificaciones operativas amplias, fiscalidad completa y todos los conectores de negocio. |
| Compras | Parcial | Compras, recepciones y cartera de proveedores usan el dominio monetario central. La cobertura funcional completa y escenarios de devolucion/conciliacion siguen pendientes. |
| Inventario | Parcial | Stock, lotes, movimientos y MRP comparten servicios; se agregaron compatibilidades legacy. Aun hay representaciones historicas (inventory_lots, lotes y stock) que requieren canonizacion. |
| Caja y conciliacion bancaria | Parcial | Movimientos, pagos y conciliacion local existen. Integraciones bancarias reales y cobertura exhaustiva de excepciones requieren otro frente. |
| CxC/CxP | Parcial | Saldos, abonos, estados y reportes existen con MoneyValue. Faltan certificaciones de todos los documentos comerciales y escenarios de integracion externa. |
| Contabilidad comercial | Parcial | Plan de cuentas, asientos, periodos, cierre y marco por empresa existen. La auditoria de esquema ya no encuentra discrepancias obvias; la certificacion productiva completa de NIIF permanece pendiente. |
| Nomina privada | Parcial | Liquidacion transaccional, novedades y conexion HRM existen. Retenciones, IBC, exoneraciones y todos los escenarios laborales requieren validacion normativa completa. |
| Facturacion electronica DIAN | Parcial | Factura y estado pendiente de transmision estan implementados. La transmision efectiva depende de proveedor, PIN/credenciales y pruebas externas. |
| Multiempresa/offline/sincronizacion | Parcial | Contexto de empresa y colas de sincronizacion existen. La compatibilidad schema v94 evita fallos obvios; falta una migracion canonica de las variantes legacy y certificacion multiempresa prolongada. |

## Modulos CRM/HRM/MRP

| Modulo | Estado | Evidencia y limite actual |
|---|---|---|
| CRM | Parcial | Account/Contact/Lead/Opportunity, interacciones, pipeline y lineas de producto tienen implementacion y tests. Faltan funciones avanzadas del documento original y certificacion comercial amplia. |
| HRM | Parcial | Las siete entidades, aprobacion de ausencias, saldos, calendario, asistencia y puente a nomina existen. Evaluacion de desempeno, reclutamiento y nomina completa propia de HRM no estan implementados como modulo independiente. |
| MRP | Parcial | BOM multinivel, rutas, operaciones, Work Order, stock y capacidad de workstation existen y tienen pruebas. Subcontratacion, rutas alternativas y todos los casos manufactureros avanzados requieren decisiones/implementacion adicional. |

## Brechas criticas priorizadas

1. Interoperabilidad externa: SECOP II/X-Road, DIAN, SIIF/SIA/FUT y portal de
   transparencia requieren credenciales, contratos de integracion y pruebas en
   ambientes oficiales.
2. Catalogos oficiales: CUPS, CIE-10, CUM y taxonomias CHIP/RIPS deben provenir
   de fuentes oficiales versionadas; no se debe inventar un catalogo parcial.
3. Modelo de datos legacy: warranties, lotes y sincronizacion tienen aliases
   defensivos; falta una migracion canonica y una estrategia de retiro de
   columnas antiguas.
4. Certificacion normativa completa: regimenes de nomina publica, reportes
   fiscales, NICSP/NIIF, cierre y formatos de rendicion necesitan casos de
   prueba por tipo de entidad y periodo.
5. Planeacion y trazabilidad: falta el enlace automatico PDT/MGA con rubros y
   cadena presupuestal.
6. Operacion de activos: faltan actas de responsabilidad y su trazabilidad de
   entrega, firma y devolucion.
7. APIs internas stub: core/api/endpoints/sales_api.dart e
   inventory_api.dart todavia devuelven placeholders; requieren contrato,
   autenticacion y persistencia antes de declararse operativas.

## Regla de mantenimiento

Cada nuevo cierre debe agregar la prueba ejecutada, archivos reales y el
alcance exacto en la fila correspondiente. No subir un frente a Completo solo
porque una pantalla abre o una funcion existe.
