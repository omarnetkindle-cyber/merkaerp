# Vigencias futuras y recibidos sin obligacion presupuestal

Fecha de investigacion: 2026-07-31.

## Alcance y fuentes

Este documento fija decisiones de diseno pendientes de implementacion. No crea
una migracion, tabla ni flujo operativo.

Fuentes primarias o institucionales consultadas:

- [Ley 819 de 2003, articulos 10 a 12](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=13712).
- [Ley 1483 de 2011, articulo 1](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=44949).
- [Decreto 2767 de 2012](https://www.funcionpublica.gov.co/eva/gestornormativo/norma.php?i=51140).
- [Decreto 111 de 1996, Estatuto Organico del Presupuesto](https://www.suin-juriscol.gov.co/viewDocument.asp?ruta=Decretos%2F1024830).
- [Guia de MinHacienda sobre entidades descentralizadas territoriales](https://www.minhacienda.gov.co/documents/d/portal/presupuesto-municipal-actualizada?download=true).
- [CGN: principio de devengo para bienes y servicios recibidos](https://www.contaduria.gov.co/documents/20127/a7afe438-1813-f783-44c1-44032e317c21).

Las fuentes institucionales de consulta no sustituyen la revision juridica del
estatuto presupuestal propio de cada entidad ni del acto que delegue funciones
del CONFIS territorial.

## Hallazgo normativo

Una vigencia futura es una autorizacion previa para asumir una obligacion cuyo
cumplimiento y pago afecta presupuestos de vigencias fiscales posteriores. El
EOP prohibe comprometer apropiaciones inexistentes o exceder el saldo sin la
autorizacion previa del CONFIS o su delegado; la Ley 819 desarrolla los
requisitos organicos.

### Ordinaria

Para entidades territoriales, el articulo 12 de la Ley 819 exige que la
ejecucion se inicie con presupuesto de la vigencia actual y que el objeto se
ejecute en cada vigencia comprometida. Requiere apropiacion minima del 15 por
ciento en la vigencia de solicitud, consistencia con el Marco Fiscal de Mediano
Plazo (MFMP), aprobacion previa del CONFIS territorial o quien haga sus veces,
e iniciativa del gobierno local. La autorizacion final la concede el concejo
municipal o la asamblea departamental, segun corresponda. El proyecto debe
estar en el Plan de Desarrollo y no puede exceder la capacidad de endeudamiento.

### Excepcional

Para entidades territoriales, el articulo 1 de la Ley 1483 permite asumir
vigencias posteriores sin apropiacion en la vigencia de autorizacion, solo para
infraestructura, energia, comunicaciones y gasto publico social en educacion,
salud, agua potable y saneamiento basico. Exige proyecto inscrito y viable en
el banco de proyectos, MFMP, aprobacion previa del CONFIS territorial o su
equivalente y, si hay inversion nacional, concepto previo favorable del DNP. La
asamblea o concejo autoriza a iniciativa del gobierno local.

Para ambos tipos territoriales, la autorizacion no puede exceder el periodo de
gobierno. Un proyecto de inversion puede excederlo solo si el Consejo de
Gobierno lo declara previamente de importancia estrategica, con estudios de
valor tecnico, obras prioritarias e ingenieria de detalle, conforme al Decreto
2767 de 2012. La Ley 1483 tambien prohibe nuevas vigencias futuras en el ultimo
ano de gobierno, salvo las excepciones legales de cofinanciacion con participacion
total o mayoritaria de la Nacion y la ultima doceava del SGP.

## Autoridad por tipo de entidad

| Tipo configurado en MerkaERP | Ruta que debe soportar el sistema | Decision de diseno |
|---|---|---|
| Municipio | Alcaldia inicia; CONFIS municipal o equivalente aprueba previamente; concejo municipal autoriza. | Ruta territorial ordinaria o excepcional, segun el tipo. |
| Departamento | Gobernacion inicia; CONFIS departamental o equivalente aprueba previamente; asamblea departamental autoriza. | Ruta territorial ordinaria o excepcional, segun el tipo. |
| Hospital/ESE | No se puede suponer que el concejo o la asamblea autoriza directamente. La ESE debe clasificarse segun su regimen presupuestal y estatuto territorial; la guia de MinHacienda distingue establecimientos publicos de EICE/asimiladas y sus autoridades. | Requerir configuracion explicita de regimen y autoridad competente, con cita del acto local, antes de habilitar una solicitud. |

Para una ESE que haga parte del presupuesto general territorial, la configuracion
debe poder registrar la corporacion administrativa aplicable. Si su regimen es
el de EICE o asimilada, la guia institucional indica CONFIS territorial. Ninguna
de estas alternativas debe inferirse solo por el valor `hospitalEse` del tipo de
entidad.

## Datos minimos auditables

Cada autorizacion debe conservar, sin sobrescribir versiones:

- entidad, tipo (ordinaria o excepcional), regimen presupuestal y causal legal;
- proyecto, codigo de banco de proyectos, Plan de Desarrollo y MFMP aplicables;
- objeto, plazo de ejecucion, monto total y distribucion exacta por vigencia;
- apropiacion actual y porcentaje de respaldo cuando aplique;
- acto de aprobacion previa de CONFIS/equivalente: numero, fecha, autoridad,
  enlace o hash del soporte y condiciones;
- acto de autorizacion de concejo/asamblea o autoridad competente: numero,
  fecha, autoridad, soporte y decision;
- concepto DNP, declaratoria de importancia estrategica y excepcion de ultimo
  ano, cuando legalmente correspondan;
- estado de solicitud/autorizacion/revocacion/modificacion, usuario, fechas,
  motivo y cadena de auditoria.

## Recibidos sin obligacion presupuestal

La CGN trata el recibido a satisfaccion como hecho de devengo: si existe una
obligacion presente medible frente a un tercero, debe reconocerse un pasivo o
cuenta por pagar; no es, por ese solo hecho, un pasivo contingente. La falta de
cupo PAC no elimina ese reconocimiento. La documentacion CGN tambien distingue
la cuenta por pagar derivada de bienes o servicios recibidos de la reserva
presupuestal y del pago posterior.

Sin embargo, recibir bienes o servicios sin una obligacion presupuestal previa
no debe convertirse en un camino ordinario del sistema. Es una excepcion de
control presupuestal: se registra para no ocultar el pasivo contable, se bloquea
el pago por el flujo normal y se exige regularizacion juridica/presupuestal y
revision de control interno. El sistema no debe fabricar retrospectivamente un
CDP, RP u obligacion.

## Diseno propuesto, sin implementar

### `autorizaciones_vigencias_futuras`

Cabecera inmutable por version de autorizacion: identificador, entidad,
`tipo`, `regimen_presupuestal`, `estado`, causal, objeto, proyecto, referencias
al Plan de Desarrollo y MFMP, fechas, plazo, monto total y campos de cada acto
o concepto requerido. Las modificaciones deben crear una nueva version ligada a
la anterior, nunca editar el acto que fue autorizado.

### `vigencias_futuras_distribucion`

Detalle obligatorio por vigencia fiscal: autorizacion, anio, monto autorizado,
monto comprometido, monto obligado, monto pagado y saldo. Un indice unico por
`(autorizacion_id, anio)` evita duplicar una anualidad. Los compromisos futuros
solo pueden consumir distribuciones autorizadas vigentes.

### `recepciones_satisfaccion`

Registro de evidencia de recibido: entidad, tercero, contrato y RP cuando
existan, acta/factura, fecha, descripcion, valor recibido, valor reconocido,
estado contable y hash/enlace de soporte. En un flujo normal, el servicio debe
exigir una obligacion presupuestal antes de aceptar la recepcion final.

### `incidentes_recibido_sin_obligacion`

Para el caso excepcional, ligar la recepcion a un incidente con motivo, persona
que reporta, usuario que revisa, concepto juridico, ruta de regularizacion,
estado y auditoria. Debe fijar `bloquea_pago = true`; solo una accion de
regularizacion documentada, no un update directo, podria asociar la obligacion
y levantar el bloqueo. Asi se reconoce el pasivo contable sin normalizar una
ejecucion presupuestal irregular.

## Decision conservadora

No se implementa todavia. Antes de migrar, una entidad piloto debe validar con
su jefe de presupuesto, juridica y control interno: el estatuto presupuestal
territorial, quien hace las veces de CONFIS, el regimen presupuestal de su ESE
si aplica y el procedimiento de regularizacion de recibidos sin obligacion.
