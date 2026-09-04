# MerkaERP 1.2.0+4 · Candidata a producción

## Alcance de esta fase
Esta edición concentra el trabajo realizable directamente en la aplicación MerkaERP. El Control Center se mantiene fuera de esta entrega y no se incluye su código fuente.

## Cierres principales
- Familia Comercial/Público fijada por licencia y reforzada al persistir configuración.
- Onboarding profesional por familia, con continuidad, respaldo y migración opcional desde sistema anterior.
- Migración genérica desde CSV/TSV/TXT/PSV, XLSX, JSON y SQLite de solo lectura.
- Migración de maestros, saldos comerciales, apertura contable, terceros públicos, apropiación/ejecución acumulada y apertura contable pública.
- Archivo Legado para conservar información no transformada con origen/hash/trazabilidad.
- Migración de carpetas documentales al SGDEA con copia controlada, ruta relativa, tamaño y SHA-256.
- Rollback de migración protegido contra modificaciones posteriores y reutilización documental.
- Conciliación post-migración y reporte exportable.
- SGDEA y Gestión Documental integrados a continuidad/backup.
- Centro de Soporte con diagnóstico sanitizado y restore drill no destructivo.
- Checklist Go-Live/UAT por familia y reporte JSON con checksum SHA-256.
- Manual interno sensible a la familia de licencia y manuales externos separados.
- Pasarelas remotas con estado pendiente hasta verificación de proveedor; referencia, importe y moneda deben coincidir.
- Release gate único. Los scripts antiguos de build no pueden generar una candidata saltándose analyzer/tests.
- Empaquetado Windows con Inno Setup y firma opcional verificable; el desinstalador preserva datos del usuario.

## Migración: criterio de continuidad
MerkaERP no intenta reconstruir a ciegas toda la historia de otro ERP. Los datos necesarios para continuar operando se normalizan; los saldos se cargan mediante aperturas controladas; el histórico restante se conserva como Archivo Legado/SGDEA. Esto evita duplicar inventario, caja, impuestos, contabilidad o ejecución presupuestal.

## Validaciones que debe ejecutar el propietario
En una estación con Flutter/Dart:

```bat
build_release.bat
```

El gate ejecuta `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` y `flutter build windows --release`. Solo después de analyzer/tests exitosos inyecta las evidencias correspondientes al build.

Para generar instalador:

```bat
package_windows.bat
```

La firma de código requiere el certificado real del propietario. La revisión de privacidad debe marcarse únicamente después de realizarse.

## Go-Live
Antes de operar con datos reales, complete el checklist dentro de **Salud y soporte → Go-Live/UAT** y exporte la evidencia. Si hubo migración, compare saldos/totales contra el cierre del sistema anterior y ejecute la conciliación global.

## Limitaciones deliberadas
- No se incluye empresa demo.
- No se incluye ni modifica el Control Center en esta fase.
- No se incluyen credenciales de DIAN, pagos, WhatsApp, correo, nube ni portales públicos; pertenecen a cada cliente.
- Este entorno no dispone de Flutter/Dart, por lo que no se afirma analyzer/test/build exitoso para 1.2.0+4 hasta ejecutarlo en el equipo del propietario.
- La firma del instalador no puede completarse sin certificado/PFX/huella real.
- La validación normativa final de una entidad depende también de su parametrización y actos/instrumentos institucionales; el software proporciona los mecanismos configurables.
