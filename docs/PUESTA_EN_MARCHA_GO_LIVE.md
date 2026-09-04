# Puesta en marcha / Go-Live de MerkaERP

MerkaERP incluye un checklist por organización y por familia de producto. Su propósito es impedir que una instalación se considere lista únicamente porque “abre”.

## Evidencia automática

Los controles de **build release** y **analyzer + pruebas** no admiten aprobación manual. Solo pasan cuando la aplicación fue construida mediante el release gate que inyecta la evidencia después de ejecutar satisfactoriamente `flutter analyze` y `flutter test`.

El checklist puede exportarse como reporte JSON acompañado de checksum SHA-256. La evidencia incluye versión, familia licenciada, controles bloqueantes, resultados, notas, fechas y usuario que registró cada aceptación manual.

## Continuidad

Desde **Centro de salud y soporte** pueden ejecutarse:

- creación + verificación de respaldo integral;
- simulacro no destructivo de restauración;
- paquete técnico sanitizado para soporte.

El simulacro extrae el respaldo en una carpeta temporal, abre la copia SQLite en solo lectura, ejecuta `PRAGMA quick_check` y comprueba referencias del repositorio documental sin reemplazar la instalación activa.

Antes de un Go-Live definitivo sigue siendo recomendable ejecutar al menos una restauración real en una estación de prueba aislada.

## Migración

Si el cliente proviene de otro sistema, ejecutar **Migración → Historial → Conciliar todas**. El control del Go-Live queda aprobado solo cuando todas las migraciones activas conservan integridad; si no hubo migración, puede quedar `N/A`.

## Comercial

La UAT mínima cubre:

- venta de contado;
- venta a crédito y pago mixto;
- compra;
- inventario/Kardex;
- cartera;
- caja y cierre;
- contabilidad;
- reportes;
- backup/restauración;
- permisos.

## Sector Público

La UAT mínima cubre:

- apropiación → CDP → RP → obligación → pago;
- integración contable pública;
- terceros;
- SGDEA: radicación, trámite, expediente, versiones, reserva, archivo y consulta;
- instrumentos archivísticos parametrizados por la entidad;
- backup/restauración del repositorio documental;
- permisos y segregación de funciones.

## Instalador

Use `scripts/package_windows.ps1`. El script obliga a pasar el release gate antes de empaquetar, calcula SHA-256 y solo marca firma digital cuando realmente la ejecuta y verifica.

El desinstalador no elimina datos empresariales ni documentales.
