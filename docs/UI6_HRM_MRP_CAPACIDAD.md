# UI-6: capacidad HRM conectada con MRP

La migracion v86 agrega a `hrm_job_titles`:

- `contractual_hours_per_day`: horas contractuales diarias del cargo.
- `mrp_workstation_id`: vinculo opcional con una workstation productiva.

Los empleados siguen vinculados al cargo por `empleados.job_title_id`. Por
tanto, todos los empleados activos con el mismo cargo heredan la jornada y el
vinculo productivo configurados en ese cargo. Un cargo administrativo sin
`mrp_workstation_id` continua contando unicamente en `activeHeadcount` y no se
convierte en capacidad MRP.

Cuando hay empleados vinculados a produccion y todos tienen horas configuradas,
el simulador calcula:

`capacidad_efectiva_diaria = min(horas_disponibles_workstations,
horas_contractuales_empleados_vinculados)`.

La comparacion se hace contra `projectedProductionHours`, derivadas de las
lineas de producto CRM y sus tiempos BOM/ruta. Si no hay vinculos productivos,
se conserva el comportamiento anterior y se usa la capacidad de Workstation.
Si existe un vinculo sin jornada, el resultado queda como
`capacidad_personal_no_configurada` y el simulador muestra una advertencia;
no inventa horas.

La pestana **Cargos** de HRM permite configurar nombre, descripcion, horas por
dia y Workstation productiva. La validacion vive en `HrmJobTitleService`, de
modo que no depende de la UI.
