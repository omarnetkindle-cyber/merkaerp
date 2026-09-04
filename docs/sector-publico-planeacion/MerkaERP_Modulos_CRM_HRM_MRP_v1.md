# MerkaERP — Especificación de Módulos CRM, HRM y MRP
### Documento listo para agente de IA (Copilot/Cline/Claude Code)

**Origen:** Modelos de datos y lógica de negocio extraídos directamente del código fuente real de:
- **CRM →** SuiteCRM (`salesagility/SuiteCRM`, AGPLv3)
- **HRM →** OrangeHRM (`orangehrm/orangehrm`, GPLv3)
- **MRP →** ERPNext (`frappe/erpnext`, GPLv3)

**Método:** clean-room. No se copió ni una línea de código fuente de los tres proyectos. Se extrajeron únicamente nombres de entidades, campos, tipos de dato y relaciones desde sus esquemas SQL/JSON públicos, y se documentó su lógica de negocio a partir de esa estructura. Todo el código que produzca el agente debe escribirse desde cero en Dart, siguiendo las convenciones ya usadas en MerkaERP.

**Convenciones obligatorias para el agente:**
1. Seguir el mismo patrón de módulos ya usado en MerkaERP (`account`, `stock`, `sale`, `purchase`, `contacts`, `base`): un archivo de modelo Dart + tabla SQLite + servicio + repositorio por entidad.
2. Usar **entity-type config flags** (no bifurcar código) para diferenciar comportamiento comercial vs. sector público, igual que en los módulos existentes.
3. Seguir el flujo diagnose → specify → implement con actualización de `PROGRESO.md` tras cada entidad completada.
4. Nombres de tablas en snake_case con prefijo de módulo: `crm_*`, `hrm_*`, `mrp_*`.
5. Toda referencia monetaria en pesos colombianos (COP), sin decimales de centavos salvo que el campo lo requiera.

---

## MÓDULO 1 — CRM (referencia: SuiteCRM)

### Entidades principales y su lógica de negocio
- **Lead** → prospecto no calificado. Se convierte (`converted`) en `Contact` + `Account` + `Opportunity` cuando califica. Tiene `lead_source`, `status`, `opportunity_amount` estimado.
- **Account** (Cuenta/Empresa) → entidad organizacional. Puede tener cuenta padre (`parent_id`) para jerarquías corporativas. Relacionada con Contacts, Opportunities, Leads, Casos.
- **Contact** (Contacto/Persona) → individuo asociado a una Account. Tiene `reports_to_id` (jerarquía interna del cliente), `lead_source`, rol en oportunidades (`opportunity_role`).
- **Opportunity** (Oportunidad) → negocio en curso. Campos clave: `sales_stage` (etapa del pipeline), `probability`, `amount`, `next_step`, `date_closed`, `opportunity_type`, `lead_source`, `campaign_id`.

### Flujo de negocio (pipeline de ventas)
```
Lead (nuevo) → calificación → Lead (convertido)
                                   ↓
                    crea: Account + Contact + Opportunity
                                   ↓
Opportunity.sales_stage recorre: Prospecting → Qualification → Needs Analysis →
  Value Proposition → Negotiation/Review → Closed Won / Closed Lost
                                   ↓
                    probability se ajusta automáticamente por stage
                                   ↓
             Closed Won → puede generar Quote/Sale en el módulo `sale` existente
```

### Esquema SQLite propuesto
```sql
CREATE TABLE crm_account (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  parent_id INTEGER REFERENCES crm_account(id),
  email TEXT,
  phone TEXT,
  entity_type TEXT DEFAULT 'comercial', -- flag comercial/publico
  assigned_user_id INTEGER,
  created_at TEXT, modified_at TEXT
);

CREATE TABLE crm_contact (
  id INTEGER PRIMARY KEY,
  account_id INTEGER REFERENCES crm_account(id),
  first_name TEXT, last_name TEXT,
  birthdate TEXT,
  email TEXT, phone_work TEXT, phone_mobile TEXT,
  reports_to_id INTEGER REFERENCES crm_contact(id),
  lead_source TEXT,
  assigned_user_id INTEGER
);

CREATE TABLE crm_lead (
  id INTEGER PRIMARY KEY,
  account_name TEXT, contact_id INTEGER,
  lead_source TEXT, status TEXT DEFAULT 'nuevo',
  opportunity_amount REAL,
  converted INTEGER DEFAULT 0,
  converted_account_id INTEGER REFERENCES crm_account(id),
  converted_opportunity_id INTEGER,
  assigned_user_id INTEGER
);

CREATE TABLE crm_opportunity (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  account_id INTEGER REFERENCES crm_account(id),
  amount REAL, currency TEXT DEFAULT 'COP',
  sales_stage TEXT DEFAULT 'Prospecting',
  probability INTEGER DEFAULT 10,
  lead_source TEXT, opportunity_type TEXT,
  next_step TEXT, date_closed TEXT,
  assigned_user_id INTEGER,
  linked_sale_id INTEGER -- puente hacia módulo `sale` existente
);
```

### Tareas para el agente (CRM)
- [ ] Crear modelos Dart: `CrmAccount`, `CrmContact`, `CrmLead`, `CrmOpportunity`
- [ ] Implementar máquina de estados de `sales_stage` con probabilidades automáticas
- [ ] Implementar conversión Lead → Account+Contact+Opportunity (transacción atómica)
- [ ] Puente `Opportunity (Closed Won)` → registro en módulo `sale` existente
- [ ] Pantallas: Kanban de pipeline por `sales_stage`, ficha de Account con historial

---

## MÓDULO 2 — HRM (referencia: OrangeHRM)

### Entidades principales (extraídas de dumps SQL reales `hs_hr_*` / `ohrm_*`)
- **Employee** (`hs_hr_employee`) → ficha completa: identificación, contacto, `job_title_code`, `emp_status`, `joined_date`, `sal_grd_code` (grado salarial), `termination_id`.
- **JobTitle** (`ohrm_job_title`) → catálogo de cargos.
- **LeaveType** (`ohrm_leave_type`) → tipos de ausencia (vacaciones, incapacidad, permiso, etc.), con bandera `exclude_in_reports_if_no_entitlement`.
- **LeaveEntitlement** (`ohrm_leave_entitlement`) → días asignados por empleado/tipo/periodo (`no_of_days`, `days_used`, `from_date`, `to_date`).
- **LeaveRequest** (`ohrm_leave_request`) → solicitud (fecha, tipo, comentarios).
- **Leave** (`ohrm_leave`) → detalle de días/horas concretas dentro de una solicitud, con `status` (pendiente/aprobado/rechazado) y `duration_type` (día completo/medio día/por horas).
- **AttendanceRecord** (`ohrm_attendance_record`) → registro de entrada/salida (`punch_in_utc_time`, `punch_out_utc_time`, `state`).

### Flujo de negocio (ausencias — el más crítico del módulo)
```
Employee tiene LeaveEntitlement (saldo) por LeaveType y periodo
        ↓
Employee crea LeaveRequest → genera uno o más registros Leave (por día/rango)
        ↓
Leave.status: PENDIENTE → (aprobador revisa) → APROBADO / RECHAZADO
        ↓
Si APROBADO: se descuenta de LeaveEntitlement.days_used
        ↓
Reporte de nómina consulta días aprobados del periodo para el cálculo de pago
```

### Esquema SQLite propuesto
```sql
CREATE TABLE hrm_employee (
  id INTEGER PRIMARY KEY,
  employee_code TEXT UNIQUE,
  first_name TEXT, last_name TEXT,
  birthdate TEXT, gender TEXT, marital_status TEXT,
  document_id TEXT, -- equivalente a emp_ssn_num/cedula en Colombia
  job_title_id INTEGER REFERENCES hrm_job_title(id),
  status TEXT DEFAULT 'activo', -- activo/retirado
  joined_date TEXT, termination_date TEXT,
  email_work TEXT, phone_mobile TEXT,
  address TEXT, city TEXT,
  salary_grade TEXT,
  entity_type TEXT DEFAULT 'comercial'
);

CREATE TABLE hrm_job_title (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  is_deleted INTEGER DEFAULT 0
);

CREATE TABLE hrm_leave_type (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL, -- vacaciones, incapacidad, permiso, luto, maternidad/paternidad
  requires_entitlement INTEGER DEFAULT 1
);

CREATE TABLE hrm_leave_entitlement (
  id INTEGER PRIMARY KEY,
  employee_id INTEGER REFERENCES hrm_employee(id),
  leave_type_id INTEGER REFERENCES hrm_leave_type(id),
  days_total REAL, days_used REAL DEFAULT 0,
  period_from TEXT, period_to TEXT
);

CREATE TABLE hrm_leave_request (
  id INTEGER PRIMARY KEY,
  employee_id INTEGER REFERENCES hrm_employee(id),
  leave_type_id INTEGER REFERENCES hrm_leave_type(id),
  date_applied TEXT, comments TEXT
);

CREATE TABLE hrm_leave (
  id INTEGER PRIMARY KEY,
  leave_request_id INTEGER REFERENCES hrm_leave_request(id),
  employee_id INTEGER REFERENCES hrm_employee(id),
  leave_type_id INTEGER REFERENCES hrm_leave_type(id),
  date TEXT, length_days REAL, duration_type TEXT DEFAULT 'dia_completo',
  status TEXT DEFAULT 'pendiente', -- pendiente/aprobado/rechazado
  approved_by INTEGER, comments TEXT
);

CREATE TABLE hrm_attendance_record (
  id INTEGER PRIMARY KEY,
  employee_id INTEGER REFERENCES hrm_employee(id),
  punch_in TEXT, punch_out TEXT,
  state TEXT -- IN_PROGRESS / COMPLETED
);
```

### Tareas para el agente (HRM)
- [ ] Crear modelos Dart: `HrmEmployee`, `HrmJobTitle`, `HrmLeaveType`, `HrmLeaveEntitlement`, `HrmLeaveRequest`, `HrmLeave`, `HrmAttendanceRecord`
- [ ] Implementar validación: no permitir `Leave` aprobado si `days_used + length_days > days_total` del `LeaveEntitlement`
- [ ] Ajustar catálogo `LeaveType` a normativa laboral colombiana (vacaciones, incapacidad EPS/ARL, licencia de maternidad/paternidad, luto)
- [ ] Puente hacia nómina/DIAN: el reporte de nómina electrónica debe poder consultar `hrm_leave` aprobado del periodo
- [ ] Pantallas: ficha de empleado, calendario de ausencias del equipo, aprobación de solicitudes

---

## MÓDULO 3 — MRP (referencia: ERPNext, doctypes de Manufacturing)

### Entidades principales (extraídas de los doctypes JSON reales)
- **BOM** (Lista de Materiales) → `item` (producto terminado), `quantity`, `is_active`, `is_default`, `routing` (secuencia de operaciones), `operating_cost`, `raw_material_cost`, `total_cost`. Contiene tabla hija `items` (BOM Item).
- **BOM Item** → línea de insumo: `item_code`, `qty`, `uom`, `rate`, `amount`, `source_warehouse`, `is_sub_assembly_item` (permite BOMs anidados/multinivel).
- **Routing / Operation** → secuencia de operaciones de manufactura, reutilizable entre BOMs.
- **Workstation** (Centro de trabajo) → `hour_rate` (costo/hora), `production_capacity`, `status` (Producción/Detenido/Mantenimiento), `warehouse` asociado.
- **Work Order** (Orden de Producción) → `production_item`, `bom_no`, `qty` planificada, `produced_qty` real, `status` (Draft→Not Started→In Process→Completed), `wip_warehouse` / `fg_warehouse` (bodega en proceso / bodega producto terminado), `planned_start_date`/`actual_start_date`. Contiene tabla hija `required_items` (Work Order Item).
- **Work Order Item** → `item_code`, `required_qty`, `transferred_qty`, `consumed_qty` — permite rastrear consumo real vs. planificado.

### Flujo de negocio (producción)
```
Item (producto terminado) tiene una BOM activa/default
        ↓
Se crea Work Order: referencia la BOM, define qty a producir
        ↓
Work Order genera required_items (explosión de la BOM × qty)
        ↓
Transferencia de materiales: bodega origen → wip_warehouse (bodega "en proceso")
        ↓ (aquí se conecta con el módulo `stock` existente de MerkaERP)
Se ejecutan operaciones (Routing) en Workstations, acumulando operating_cost
        ↓
Al completar: consumo real se descuenta de wip_warehouse,
              producto terminado entra a fg_warehouse
        ↓
Costeo: raw_material_cost + operating_cost = total_cost del producto fabricado
```

### Esquema SQLite propuesto
```sql
CREATE TABLE mrp_bom (
  id INTEGER PRIMARY KEY,
  item_id INTEGER NOT NULL, -- FK a tabla `item`/`product` ya existente en MerkaERP
  quantity REAL DEFAULT 1,
  uom TEXT,
  is_active INTEGER DEFAULT 1,
  is_default INTEGER DEFAULT 0,
  routing_id INTEGER REFERENCES mrp_routing(id),
  raw_material_cost REAL DEFAULT 0,
  operating_cost REAL DEFAULT 0,
  total_cost REAL DEFAULT 0,
  entity_type TEXT DEFAULT 'comercial'
);

CREATE TABLE mrp_bom_item (
  id INTEGER PRIMARY KEY,
  bom_id INTEGER REFERENCES mrp_bom(id),
  item_id INTEGER NOT NULL, -- insumo
  qty REAL, uom TEXT,
  rate REAL, amount REAL,
  source_warehouse_id INTEGER,
  is_sub_assembly_item INTEGER DEFAULT 0 -- permite anidar otra BOM como insumo
);

CREATE TABLE mrp_routing (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE mrp_operation (
  id INTEGER PRIMARY KEY,
  routing_id INTEGER REFERENCES mrp_routing(id),
  workstation_id INTEGER REFERENCES mrp_workstation(id),
  operation_name TEXT,
  sequence_order INTEGER,
  time_minutes REAL
);

CREATE TABLE mrp_workstation (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  hour_rate REAL DEFAULT 0,
  production_capacity INTEGER DEFAULT 1,
  status TEXT DEFAULT 'produccion',
  warehouse_id INTEGER
);

CREATE TABLE mrp_work_order (
  id INTEGER PRIMARY KEY,
  production_item_id INTEGER NOT NULL,
  bom_id INTEGER REFERENCES mrp_bom(id),
  qty_planned REAL,
  qty_produced REAL DEFAULT 0,
  status TEXT DEFAULT 'borrador', -- borrador/no_iniciada/en_proceso/completada/cancelada
  wip_warehouse_id INTEGER,
  fg_warehouse_id INTEGER,
  planned_start_date TEXT, actual_start_date TEXT,
  planned_end_date TEXT, actual_end_date TEXT,
  planned_operating_cost REAL DEFAULT 0,
  actual_operating_cost REAL DEFAULT 0
);

CREATE TABLE mrp_work_order_item (
  id INTEGER PRIMARY KEY,
  work_order_id INTEGER REFERENCES mrp_work_order(id),
  item_id INTEGER NOT NULL,
  required_qty REAL,
  transferred_qty REAL DEFAULT 0,
  consumed_qty REAL DEFAULT 0,
  source_warehouse_id INTEGER
);
```

### Tareas para el agente (MRP)
- [ ] Crear modelos Dart: `MrpBom`, `MrpBomItem`, `MrpRouting`, `MrpOperation`, `MrpWorkstation`, `MrpWorkOrder`, `MrpWorkOrderItem`
- [ ] Implementar "explosión de BOM": al crear Work Order, generar automáticamente `required_items` multiplicando `mrp_bom_item.qty × qty_planned` (soportar BOM multinivel vía `is_sub_assembly_item`)
- [ ] Integrar con módulo `stock` existente: transferencia origen→WIP y WIP→bodega de producto terminado deben mover inventario real
- [ ] Implementar máquina de estados de `Work Order.status`
- [ ] Calcular `total_cost` = `raw_material_cost` (suma de BOM Items) + `operating_cost` (suma de tiempo×`hour_rate` por Workstation)
- [ ] Pantallas: editor de BOM, tablero de órdenes de producción por estado, ficha de Workstation

---

## Plan de integración (orden sugerido)

1. **CRM primero** — no depende de inventario, es el más aislado; conecta al final con `sale`.
2. **HRM segundo** — independiente, aunque conviene definir ya el catálogo de `LeaveType` colombiano antes de programarlo.
3. **MRP tercero** — depende directamente del módulo `stock` existente (bodegas, movimientos), por lo que se hace al final para reutilizar esa infraestructura sin duplicar lógica de inventario.

Cada módulo sigue el mismo ciclo ya usado en MerkaERP: **diagnose → specify → implement**, actualizando `PROGRESO.md` por entidad terminada, y usando entity-type flags en vez de bifurcar código para comercial vs. sector público.

## Nota legal
Ninguna tabla, campo o fragmento de código de SuiteCRM, OrangeHRM o ERPNext debe copiarse literalmente. Esta especificación documenta *nombres de conceptos y estructura de datos* (no protegidos por copyright) para que el agente los reimplemente desde cero en Dart/SQLite bajo la licencia propia de MerkaERP.

---

## PROMPTS PARA EL AGENTE DE IA (copiar y pegar tal cual)

Cada módulo se ejecuta con el mismo flujo de tres pasos ya usado en MerkaERP: **diagnose → specify → implement**, con actualización de `PROGRESO.md` al cerrar cada entidad. Pega los prompts en orden: primero el de arranque, luego el del módulo correspondiente (CRM → HRM → MRP), uno a la vez, esperando a que el agente termine y actualice `PROGRESO.md` antes de pasar al siguiente.

### Prompt 0 — Arranque (ejecutar una sola vez, antes del primer módulo)

```
Vas a implementar tres módulos nuevos en MerkaERP (Flutter/Dart + SQLite): CRM, HRM y MRP.
La especificación completa está en el archivo MerkaERP_Modulos_CRM_HRM_MRP_v1.md — léelo
completo antes de escribir código.

Reglas obligatorias:
1. No copies código de SuiteCRM, OrangeHRM ni ERPNext bajo ninguna circunstancia. Solo usa
   los nombres de entidades/campos y la lógica de negocio descritos en el documento.
2. Sigue el patrón de módulos ya existente en el repo (account, stock, sale, purchase,
   contacts, base): un modelo Dart + tabla SQLite + servicio + repositorio por entidad.
3. Usa entity-type config flags para diferenciar comportamiento comercial vs. sector
   público — nunca bifurques código con if/else de tipo de entidad repartidos por el codebase.
4. Antes de crear cualquier tabla, verifica si PROGRESO.md ya registra ese módulo/entidad
   como completado. Si existe, no la reimplementes: continúa desde ahí.
5. Al terminar cada entidad (modelo + tabla + servicio + repositorio + tests básicos),
   agrega una línea a PROGRESO.md con: módulo, entidad, fecha, archivos creados/modificados.
6. Si encuentras una tabla o convención ya existente en el repo que choque con el esquema
   propuesto en el documento (por ejemplo, una tabla `item`/`product` ya existente para
   referenciar desde mrp_bom), usa la existente y ajusta las foreign keys — no dupliques.

Confirma que leíste el documento y el estado actual de PROGRESO.md antes de continuar.
```

### Prompt 1 — Módulo CRM (diagnose → specify → implement)

```
MÓDULO: CRM (referencia funcional: SuiteCRM — ver sección "MÓDULO 1" del documento)

PASO 1 — DIAGNOSE:
Revisa el repo actual y reporta: (a) si ya existe alguna tabla o modelo relacionado con
clientes/cuentas/oportunidades, (b) cómo se relaciona el módulo `contacts` existente con
lo que se propone aquí (¿se reusa o se extiende?), (c) qué convención de nombres de
archivo/carpeta usar para el nuevo módulo `crm`.

PASO 2 — SPECIFY:
Con base en el diagnóstico, produce un plan concreto de archivos a crear/modificar
(modelo, tabla, servicio, repositorio, pantalla) para las 4 entidades: CrmAccount,
CrmContact, CrmLead, CrmOpportunity. Indica explícitamente cómo CrmAccount se relaciona
o se fusiona con el módulo `contacts` existente. Espera mi confirmación antes de
implementar si hay ambigüedad con `contacts`.

PASO 3 — IMPLEMENT:
Implementa en este orden: CrmAccount → CrmContact → CrmLead → CrmOpportunity.
Para cada una: modelo Dart, migración SQLite, servicio, repositorio, tests básicos.
Luego implementa:
  - Máquina de estados de sales_stage con probabilidad automática asociada
  - Conversión Lead → Account + Contact + Opportunity como transacción atómica
  - Puente Opportunity (Closed Won) → registro en el módulo `sale` existente
  - Pantalla Kanban de pipeline agrupada por sales_stage
Actualiza PROGRESO.md al cerrar cada entidad.
```

### Prompt 2 — Módulo HRM (diagnose → specify → implement)

```
MÓDULO: HRM (referencia funcional: OrangeHRM — ver sección "MÓDULO 2" del documento)

PASO 1 — DIAGNOSE:
Revisa el repo y reporta: (a) si ya existe algún modelo de "usuario" o "empleado" que
deba diferenciarse de HrmEmployee (por ejemplo, usuarios del sistema con login vs.
empleados como registro de RRHH), (b) si ya hay tablas de nómina o DIAN que HrmLeave
deba alimentar, (c) confirma con qué catálogo de LeaveType colombiano arrancar
(vacaciones, incapacidad EPS, incapacidad ARL, licencia de maternidad, licencia de
paternidad, luto, permiso remunerado, permiso no remunerado).

PASO 2 — SPECIFY:
Produce el plan de archivos para las 7 entidades: HrmEmployee, HrmJobTitle,
HrmLeaveType, HrmLeaveEntitlement, HrmLeaveRequest, HrmLeave, HrmAttendanceRecord.
Define explícitamente la validación de saldo (days_used + length_days <= days_total)
y en qué capa vive (servicio, no UI).

PASO 3 — IMPLEMENT:
Implementa en este orden: HrmJobTitle → HrmEmployee → HrmLeaveType →
HrmLeaveEntitlement → HrmLeaveRequest → HrmLeave → HrmAttendanceRecord.
Para cada una: modelo Dart, migración SQLite, servicio, repositorio, tests básicos.
Luego implementa:
  - Validación de saldo de LeaveEntitlement antes de aprobar un HrmLeave
  - Carga inicial (seed) del catálogo LeaveType colombiano acordado en el diagnóstico
  - Consulta expuesta para que el módulo de nómina/DIAN pueda leer HrmLeave aprobado
    de un periodo dado
  - Pantalla de ficha de empleado y calendario de ausencias del equipo
Actualiza PROGRESO.md al cerrar cada entidad.
```

### Prompt 3 — Módulo MRP (diagnose → specify → implement)

```
MÓDULO: MRP (referencia funcional: ERPNext Manufacturing — ver sección "MÓDULO 3" del documento)

PASO 1 — DIAGNOSE:
Revisa el módulo `stock` existente y reporta: (a) nombre exacto de la tabla de
productos/items a referenciar desde mrp_bom y mrp_bom_item, (b) nombre exacto de la
tabla de bodegas/warehouses a referenciar desde wip_warehouse_id/fg_warehouse_id,
(c) cómo se registran hoy los movimientos de inventario (para poder enganchar ahí la
transferencia origen→WIP→bodega de producto terminado sin duplicar lógica).

PASO 2 — SPECIFY:
Produce el plan de archivos para las 7 entidades: MrpBom, MrpBomItem, MrpRouting,
MrpOperation, MrpWorkstation, MrpWorkOrder, MrpWorkOrderItem. Especifica con exactitud
qué función del módulo `stock` existente se va a llamar para mover inventario en cada
transición de estado de MrpWorkOrder. No implementes movimientos de inventario propios
del módulo MRP: siempre delegar a `stock`.

PASO 3 — IMPLEMENT:
Implementa en este orden: MrpWorkstation → MrpRouting → MrpOperation → MrpBom →
MrpBomItem → MrpWorkOrder → MrpWorkOrderItem.
Para cada una: modelo Dart, migración SQLite, servicio, repositorio, tests básicos.
Luego implementa:
  - Explosión de BOM al crear un Work Order (soportar multinivel vía is_sub_assembly_item)
  - Máquina de estados de MrpWorkOrder.status (borrador→no_iniciada→en_proceso→completada/cancelada)
  - Integración real con `stock` para las transferencias origen→WIP y WIP→bodega de
    producto terminado
  - Cálculo de total_cost = raw_material_cost + operating_cost (tiempo × hour_rate por Workstation)
  - Pantalla de editor de BOM y tablero de órdenes de producción por estado
Actualiza PROGRESO.md al cerrar cada entidad.
```

### Prompt 4 — Cierre (ejecutar después de los tres módulos)

```
Los tres módulos (CRM, HRM, MRP) están implementados según PROGRESO.md. Genera un
resumen de: (a) qué quedó pendiente o marcado como TODO en cada módulo, (b) qué
puntos de integración cruzan entre módulos (ej. Opportunity→sale, Leave→nómina,
WorkOrder→stock) y si quedaron realmente conectados o solo con la estructura lista,
(c) una lista de pruebas manuales recomendadas antes de dar el trabajo por cerrado.
```
