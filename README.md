# MerkaERP 1.3.0+8

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/omarnetkindle-cyber/merkaerp)

MerkaERP es una plataforma ERP Flutter/SQLite, offline-first y multiempresa. El producto se distribuye en dos **familias independientes** fijadas por licencia firmada:

- **MerkaERP Comercial:** ventas/POS, compras, inventario, caja, cartera, tesorería, contabilidad, CRM, HRM, MRP, activos, documentos, reportes e integraciones empresariales.
- **MerkaERP Público:** presupuesto, contratación y supervisión, tesorería, contabilidad pública/NICSP, activos/almacén, planeación, control, interoperabilidad institucional y SGDEA.

Una instalación Comercial no puede cambiar a Público desde la aplicación y viceversa. Los permisos deciden lo que un usuario puede hacer **dentro** de la familia licenciada; no conceden acceso a la otra familia.

## Capacidades transversales

- Multiempresa y aislamiento por `company_id`.
- Dinero almacenado en unidades menores enteras.
- Auditoría y permisos.
- Respaldos integrales y restauración validada.
- Salud/diagnóstico y paquete de soporte sanitizado.
- Onboarding profesional.
- Migración asistida desde sistemas anteriores.
- Centro de Integraciones con credenciales por empresa/entidad.
- Actualización segura preparada para manifiestos firmados.
- Checklist Go-Live/UAT y exportación de evidencia con SHA-256.

## Migración desde otros sistemas

**Administración → Migración de datos** admite:

- CSV, TSV, TXT y PSV.
- Excel XLSX.
- JSON.
- SQLite `.db/.sqlite/.sqlite3` en modo solo lectura.
- Carpetas de documentos/soportes hacia el gestor documental/SGDEA.

El flujo hace vista previa, mapeo de columnas, validación y backup integral antes de escribir. Puede migrar maestros y saldos de apertura y conservar el resto como **Archivo Legado** con trazabilidad. La reversión se detiene si detecta trabajo realizado después de la migración.

Consulte `docs/GUIA_MIGRACION_CLIENTES.md`.

## Gestión documental

La base común permite radicación, seguimiento, expedientes, anexos, versiones, archivo, préstamos, integridad y auditoría. MerkaERP Público añade la capa SGDEA: TRD/TVD, PGD, PINAR, CCD, SIC, transferencias, disposición, archivo físico/electrónico e instrumentos configurables por cada entidad.

## Integraciones

Las credenciales externas pertenecen al cliente y se diligencian desde el Centro de Integraciones. Los secretos no deben estar incrustados en el código ni en la base operativa. Una integración no configurada o no verificada debe permanecer *fail-closed*.

## Control Center

El Control Center se mantiene como producto/proyecto separado. Este repositorio de entrega contiene la **aplicación MerkaERP**, conservando únicamente los contratos de comunicación necesarios para integrarse con un Control Center compatible.

## Desarrollo

Requisitos: Flutter/Dart compatible con `pubspec.yaml` y el toolchain correspondiente a la plataforma.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

No utilice un `flutter build` aislado para declarar una liberación. El gate canónico ejecuta análisis y pruebas antes del build.

### Release Windows

Desde CMD:

```bat
build_release.bat
```

O PowerShell:

```powershell
.\scripts\build_release.ps1 -Target windows
```

Para build + instalador Inno Setup:

```bat
package_windows.bat
```

El empaquetador admite firma opcional mediante certificado/huella configurados por el propietario; nunca marca un artefacto como firmado si no verifica la firma real. El desinstalador no elimina automáticamente las bases, respaldos ni repositorios documentales del usuario.

Consulte `scripts/BUILD_RELEASE.md`.

## Validación de fuente

Cuando Flutter no esté disponible, puede ejecutar:

```bash
python3 tool/release_static_check.py
```

Este chequeo protege invariantes estáticas de seguridad/integridad, pero **no sustituye** `flutter analyze`, `flutter test` ni un build release real.

## Manuales

- `docs/MANUAL_USUARIO_COMERCIAL.md`
- `docs/MANUAL_USUARIO_PUBLICO.md`
- `docs/GUIA_MIGRACION_CLIENTES.md`
- Manual contextual dentro de la aplicación.

## Estado de esta entrega

La versión fuente es **1.3.0+8**. Para declararla producción en una estación real deben pasar el release gate estricto, la verificación criptográfica del instalador, un restore drill y el UAT correspondiente a la familia licenciada. Las integraciones externas requieren las credenciales/servicios reales de cada cliente.
