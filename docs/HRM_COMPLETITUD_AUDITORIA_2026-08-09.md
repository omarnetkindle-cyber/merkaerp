# Auditoria de completitud HRM - 2026-08-09

## Comparacion campo a campo

| Entidad | Campo/relacion de la especificacion | Estado | Evidencia |
|---|---|---|---|
| HrmEmployee | identificacion y nombre completo | Parcial | Se conserva en `empleados`; el nombre actual es un campo unico y no separa nombres/apellidos. |
| HrmEmployee | document_id, job_title_code/id, emp_status | Implementado | `documento`, `job_title_id`, `activo` y `HrmJobTitle`. |
| HrmEmployee | joined_date y termination_date | Implementado | `fecha_contratacion` y `fecha_terminacion`. |
| HrmEmployee | sal_grd_code / grado salarial | Implementado | `salary_grade` agregado en v85. |
| HrmEmployee | datos personales: birthdate, gender, marital_status | Implementado | Columnas y propiedades agregadas en v85. |
| HrmEmployee | estructura de reporte / manager | Implementado | `manager_id` nullable, validado para evitar auto-referencia y cruces de empresa. |
| HrmJobTitle | titulo, descripcion, borrado logico | Implementado | `hrm_job_titles` y servicio CRUD. |
| HrmLeaveType | nombre, catalogo laboral, requires_entitlement | Implementado | Ocho tipos sembrados, incluido permiso no remunerado sin saldo. |
| HrmLeaveType | exclude_in_reports_if_no_entitlement | Implementado | Columna/propriedad agregada en v85; queda disponible para reportes. |
| HrmLeaveEntitlement | empleado, tipo, dias totales/usados y periodo | Implementado | `hrm_leave_entitlements` con unicidad por periodo. |
| HrmLeaveRequest | empleado, tipo, fecha y comentarios | Implementado | `hrm_leave_requests`, con estado de solicitud. |
| HrmLeave | detalle por fecha/dias/horas, estado y aprobador | Implementado | `hrm_leaves`, aprobacion atomica, `reviewed_by/reviewed_at` y rechazo auditable. |
| HrmAttendanceRecord | entrada, salida y estado | Implementado | `hrm_attendance_records`; soporta turno abierto. |
| HRM -> nomina | dias aprobados del periodo | Implementado con alcance explicito | Comercial y publica llaman `HrmPayrollAbsenceService`; vacaciones/permisos se procesan y incapacidades/licencias generan advertencia manual. |

## Brechas evaluadas

- **Costo laboral por hora/capacidad UI-6:** no se implementa en esta ronda.
  `salario_base` es mensual y el documento HRM no define jornada, turnos ni
  horas contractuales; dividir silenciosamente entre 240 seria una suposicion
  de producto. Recomendacion: una configuracion explicita de horas por periodo
  y costo laboral horario, vinculada a workstation solo cuando la empresa la
  configure.
- **Evaluacion de desempeno y reclutamiento:** no aparecen como entidades ni
  flujo en la seccion HRM original; quedan fuera, recomendados como modulos
  separados si el producto los prioriza.
- **Nomina completa dentro de HRM:** el documento exige el puente de ausencias,
  no duplicar los motores comercial/publico. La integracion existente cumple
  ese alcance; reglas normativas pendientes para incapacidades EPS/ARL y
  maternidad/paternidad siguen generando advertencia manual.
