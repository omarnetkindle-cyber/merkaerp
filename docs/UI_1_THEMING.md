# UI-1: Theming unificado de MerkaERP

Fecha: 2026-08-09

## Decisión

`EnterpriseThemeEngine` es la única fuente activa de `ThemeData`. Sus tokens
visuales viven en `lib/ui/merka_theme_tokens.dart` para que puedan ser usados
por el motor, el logo y las fachadas legacy sin imports circulares.

`AppBrand` queda deprecado como API de compatibilidad. `AppTheme` queda
deprecado como fachada del tema anterior. `ThemeService` ya no activa
`AppTheme`: delega en `EnterpriseThemeEngine` para los modos claro, oscuro y
del sistema.

## Tokens aplicados

- Navy: `#071522`, `#0A2540`, `#123057`, `#1B3F70`.
- Grafito: `#444B58`, `#7A8393`.
- Papel: `#F4F6F9`, `#E9ECF2`.
- Oro: `#C6A15B`, `#D8B87A`, `#E9D6AA`.
- Display: Montserrat como familia declarativa.
- Body: Inter como familia principal.
- Comercial y sector público comparten el mismo `ColorScheme`.

El oro se usa como acento y foco. Los estados de éxito, advertencia, error e
información conservan tokens semánticos separados para no confundir identidad
de marca con estado operativo.

## Migración de esta ronda

Conteo sobre archivos Dart versionados bajo `lib/`:

| Métrica | Antes | Después | Cambio |
|---|---:|---:|---:|
| Referencias `Color(...)`/`Colors.*` | 1.108 | 968 | -140 |
| Construcciones hex `Color(0x...)` | 287 | 197 | -90 |

Se migraron 58 de los 230 hexadecimales que estaban fuera de las tres fuentes
centrales originales. También se migraron los colores directos del motor de
tema, marca, shell, Copilot, panel operativo y estados priorizados de ventas,
caja y contratación pública.

## Pendientes explícitos

Quedan 172 construcciones hex fuera de los archivos centrales, distribuidas así:

| Archivo | Referencias |
|---|---:|
| `lib/core/workspace/workspace_config.dart` | 35 |
| `lib/erp_readiness_page.dart` | 35 |
| `lib/ui/sales_mode_panel.dart` | 29 |
| `lib/licensing_page.dart` | 29 |
| `lib/facturacion_electronica_page.dart` | 21 |
| `lib/ui/finance_mode_panel.dart` | 17 |
| `lib/sector_publico/siif/pages/siif_page.dart` | 5 |
| `lib/sector_publico/salud/pages/salud_publica_page.dart` | 1 |

También quedan usos de `Colors.*` que no son necesariamente errores de marca
(blanco, transparente, negro y colores funcionales). Deben migrarse por
contexto, no mediante sustitución ciega, en una ronda posterior.

## Accesibilidad

Se añadieron pruebas de tema en
`test/ui/enterprise_theme_test.dart`. Verifican la paleta aplicada en ambos
modos y contraste WCAG AA para texto de controles primarios y secundarios.

## Verificación de esta fase

- `flutter test test/ui/enterprise_theme_test.dart`: 2 tests passed.
- `flutter analyze`: 241 issues, 0 errors. Los issues son warnings/info de la
  línea base; no quedaron errores en los archivos modificados.
- `flutter test --reporter compact`: 261 passed, 3 skipped, 0 failures.
- `flutter build windows`: compilación exitosa; se generó
  `build/windows/x64/runner/Release/MerkaERP.exe`. El wrapper de Flutter
  emitió un aviso de `Nuget.exe` en stderr, pero el proceso terminó con éxito
  y el artefacto existe.
