# Agregar Una Nueva Feature

1. Agrega la clave en `lib/features/feature_key.dart`.
2. Registra nombre, descripcion, valor por defecto y dependencias en
   `lib/features/feature_registry.dart`.
3. Asocia los modulos necesarios en `lib/main.dart` usando `featureKey`.
4. Si la feature protege escritura de datos, llama
   `DatabaseHelper.instance.validarFeatureHabilitada(...)` antes de registrar
   operaciones.
5. Agrega el valor por defecto en las plantillas JSON de `assets/templates`.
6. Actualiza pruebas si el menu visible cambia.

Ejemplo:

```dart
static const ecommerce = 'ecommerce_enabled';
```

Luego se registra en `FeatureRegistry.definitions` y se usa en un
`ModuleDefinition`.
