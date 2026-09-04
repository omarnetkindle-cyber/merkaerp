# Onboarding profesional

El onboarding de MerkaERP se diseña alrededor de la licencia, no de un selector local.

## Familia del producto

- una licencia Comercial crea/configura únicamente una organización Comercial;
- una licencia Pública crea/configura únicamente una entidad Pública;
- el usuario no puede alternar entre familias;
- al guardar configuración se fuerzan a `false` las capacidades de la familia contraria, de modo que la separación no depende solamente del menú.

## Comercial

El asistente recopila identidad, operación, configuración fiscal, escala y continuidad. Al finalizar puede abrir directamente la migración desde el sistema anterior. El formulario valida organización, NIT/documento, moneda, correo cuando se informa, IVA y aceptación de continuidad antes de crear la empresa.

## Público

El asistente conserva la familia Pública y permite parametrizar la naturaleza/tipo institucional requerido para visibilidad y flujos. Los instrumentos archivísticos, políticas, términos y configuraciones institucionales pertenecen a la entidad y se configuran desde los módulos correspondientes. Los switches del onboarding usan las mismas `FeatureKey` que consume el workspace público, evitando configuraciones aparentes que no afecten al módulo real.

## Continuidad obligatoria

Antes de finalizar se informa que:

- MerkaERP mantiene respaldos integrales;
- las credenciales externas pertenecen al cliente y se almacenan fuera de la base operativa cuando corresponde;
- una integración no configurada debe fallar de forma explícita;
- los datos de un sistema anterior pueden trasladarse mediante el asistente de migración.

## Después del onboarding

1. Configurar usuarios/roles.
2. Configurar integraciones necesarias.
3. Migrar datos si aplica.
4. Crear/verificar backup.
5. Ejecutar simulacro de restauración.
6. Ejecutar UAT/Go-Live.
7. Solo operar cuando los controles bloqueantes estén resueltos.
