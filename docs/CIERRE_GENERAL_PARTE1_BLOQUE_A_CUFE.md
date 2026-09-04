# Bloque A - CUFE real local y UBL 2.1

Fecha: 2026-08-13

## Fuentes consultadas

- DIAN, micrositio oficial de documentacion tecnica del sistema de facturacion electronica: publica el "Anexo Tecnico de Factura Electronica de Venta version 1.9".
- DIAN, Resolucion 000165 de 2023, Anexo Tecnico de Factura Electronica de Venta v1.9, seccion 11.2, paginas 655-659.

## Regla normativa implementada

El CUFE de factura electronica de venta se calcula con SHA-384 sobre la concatenacion:

```text
NumFac + FecFac + HorFac + ValFac + CodImp1 + ValImp1 + CodImp2 +
ValImp2 + CodImp3 + ValImp3 + ValTot + NitOFE + NumAdq + ClTec +
TipoAmbiente
```

Con codigos fijos de impuesto:

- `01`: IVA.
- `04`: Impuesto Nacional al Consumo.
- `03`: ICA.

Los montos se expresan con punto decimal, dos decimales, sin separadores de miles ni simbolo monetario. El Anexo indica que `NitOFE` y `NumAdq` se informan sin puntos ni guiones y sin digito de verificacion cuando aplique.

## Implementacion

- `lib/core/invoicing/cufe.dart`: reemplaza el CUFE interno Base64+sufijo por `computeDianCufe(DianCufeInput)` usando SHA-384.
- `lib/core/invoicing/xml/generator.dart`: genera UBL 2.1 con `ProfileExecutionID`, `IssueDate`, `IssueTime`, `UUID schemeName="CUFE-SHA384"`, partes fiscales, totales monetarios e impuestos.
- `lib/db_helper.dart`: los borradores de factura electronica usan el generador UBL compartido.
- `lib/facturacion_electronica_page.dart`: la emision local exige datos fiscales completos para calcular CUFE oficial; no inventa NIT/documento si faltan.
- `lib/ui/sales_mode_panel.dart`: el ticket POS no calcula CUFE oficial cuando no tiene identificacion fiscal completa del adquirente.

## Fuera de alcance documentado

No se implementa transmision DIAN ni firma digital. El cliente sigue siendo NoOp porque la validacion previa real requiere certificado/proveedor tecnologico/credenciales de Omar.

## Evidencia ejecutada

```text
flutter test test\core\invoicing\cufe_test.dart test\core\invoicing\xml\generator_test.dart test\core\invoicing\crear_factura_integration_test.dart --reporter expanded
Resultado: 7 tests passed.
```

```text
dart analyze lib\core\invoicing\cufe.dart lib\core\invoicing\xml\generator.dart test\core\invoicing\cufe_test.dart test\core\invoicing\xml\generator_test.dart
Resultado: No issues found.
```

```text
flutter analyze
Resultado global: 242 issues, sin errores de compilacion en archivos del Bloque A. El ruido restante corresponde a advertencias preexistentes del proyecto.
```
