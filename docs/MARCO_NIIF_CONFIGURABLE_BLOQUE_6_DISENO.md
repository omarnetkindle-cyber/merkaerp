# Bloque 6 - Marco NIIF configurable por empresa

## Decision previa a la implementacion

MerkaERP no debe fijar un unico marco contable para todas las empresas. La
clasificacion NIIF es una condicion de cada preparador de informacion
financiera y puede cambiar por los hechos juridicos y economicos de esa
empresa. Por eso se almacenara un grupo NIIF por empresa, con validacion de
los valores permitidos `grupo_1`, `grupo_2` y `grupo_3`.

Esta configuracion no pretende sustituir el analisis del contador ni
determinar automaticamente el grupo a partir de datos incompletos. La
empresa debe registrar el grupo que corresponda a su evaluacion normativa;
una futura herramienta de clasificacion automatica necesitara datos anuales,
promedios y relaciones societarias que hoy no estan modelados.

## Base normativa revisada

- El articulo 1.1.1.1 del Decreto 2420 de 2015 ubica en Grupo 1 a emisores de
  valores y entidades de interes publico. Tambien incluye entidades con mas
  de 200 trabajadores o activos superiores a 30.000 SMMLV cuando, ademas,
  sean subordinadas o sucursales de una compania extranjera que aplique NIIF
  plenas, subordinadas o matrices de una compania nacional obligada a NIIF
  plenas, matrices/asociadas/negocios conjuntos de entidades extranjeras que
  apliquen NIIF plenas, o realicen importaciones o exportaciones por encima
  del 50% de compras o ventas, segun el caso.
- El articulo 1.1.2.1 aplica Grupo 2 a quien no esta en Grupo 1 ni en Grupo 3,
  y permite que una entidad que cumpliria Grupo 3 opte voluntariamente por
  el marco de Grupo 2. El calculo de trabajadores y activos usa el promedio
  de doce meses cuando la norma lo exige.
- El articulo 1.1.3.1 remite Grupo 3 al Anexo 3 y exige la totalidad de sus
  condiciones. Entre ellas estan los limites de microempresa: menos de 10
  trabajadores, activos totales sin vivienda inferiores a 500 SMMLV e
  ingresos brutos anuales inferiores a 6.000 SMMLV, ademas de las condiciones
  sobre subordinacion, inversiones, estados financieros y planes de beneficios
  que el articulo enumera.
- Los Anexos 1/1.1, 2/2.1 y 3 incorporan marcos tecnicos distintos: NIIF
  plenas, NIIF para las PYMES y NIF para microempresas. No son solo etiquetas
  de presentacion: cambian reconocimiento, medicion, presentacion y
  revelaciones.
- El Decreto 2420 y sus modificatorios siguen cambiando; al 2026 aparece el
  Decreto 701 de 2026 con enmiendas tecnicas para los Grupos 1 y 2. El campo
  almacenado es por tanto una politica vigente declarada por la empresa y
  debe revisarse por el responsable contable cuando cambie la norma o la
  realidad economica.

Fuentes oficiales revisadas:

- Decreto 2420 compilado, SUIN Juriscol:
  https://www.suin-juriscol.gov.co/viewDocument.asp?ruta=Decretos%2F30030273
- Decreto 2420 compilado, Gestor Normativo de Funcion Publica:
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76745
- Anexo 1, Grupo 1:
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76054
- Anexo 2, Grupo 2:
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=74535
- Anexo 3, Grupo 3:
  https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=76055
- Decreto 701 de 2026, enmiendas tecnicas vigentes para Grupos 1 y 2:
  https://www.suin-juriscol.gov.co/viewDocument.asp?id=30056712

## Alcance de esta implementacion

La migracion v91 agrega `companies.niif_group` con valor defensivo
`grupo_2` para instalaciones existentes. Esto no afirma que toda empresa
sea Grupo 2; es un valor tecnico de compatibilidad para el estado anterior y
debe ser revisado en la configuracion de la empresa.

El comportamiento visible que se implementa ahora es una politica contable
consultable por empresa: nombre del marco, nivel de revelacion esperado y
politica de deterioro de inventarios. Grupo 2 expone NIIF para PYMES y
Seccion 27; Grupo 3 expone NIF para microempresas y su tratamiento
simplificado; Grupo 1 queda disponible y expone NIIF plenas/NIC 36, pero con
revelaciones completas aun pendientes. No se presentan estas etiquetas como
una implementacion completa de todas las normas.

Fuera de alcance: clasificacion automatica legal, todas las notas NIIF de
Grupo 1, conversion de saldos por cambio de marco, consolidacion o
transferencias entre empresas y cualquier integracion DIAN/PTA real.

