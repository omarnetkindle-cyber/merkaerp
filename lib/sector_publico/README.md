# MerkaERP - Módulo Sector Público

Módulo de Sector Público para MerkaERP, diseñado para alcaldías, gobernaciones y hospitales públicos (ESE) en Colombia.

## Familia de producto

MerkaERP Público es una familia de producto independiente de MerkaERP Comercial. La familia se obtiene de la licencia firmada (`PUBLIC`) y no existe un selector de usuario para cambiar a Comercial. Ambos productos comparten infraestructura técnica cuando es conveniente, pero sus rutas, módulos, permisos e integraciones visibles se componen según la licencia adquirida.

## Gestión Documental / SGDEA

MerkaERP Público incorpora Gestión Documental como dominio principal: radicación recibida/enviada/interna, seguimiento, términos, expedientes electrónicos, versiones, integridad SHA-256, clasificación/reserva, firma y evidencia, TRD/TVD, instrumentos archivísticos, FUID, transferencias, ubicación física, préstamos, disposición final y auditoría de acceso. PGD, PINAR, CCD, TRD/TVD y demás instrumentos o actos institucionales son parametrizados y respaldados por cada entidad; el sistema no presume su adopción jurídica.

## Arquitectura

### Multi-Tenant Jerárquico
- Cada entidad territorial opera su propia instancia de datos
- Gobernaciones pueden consolidar información de municipios/hospitales adscritos (NICSP 40)
- Aislamiento completo de datos entre entidades

### Seguridad

#### Reglas No Negociables
1. **Nada se borra**: Ningún registro contable, presupuestal o de nómina se elimina físicamente
2. **Todo se audita**: Cada operación sensible queda en tabla de auditoría append-only
3. **Segregación de funciones dura**: Implementada en código, no solo configuración
4. **Flujo presupuestal sagrado**: APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO

#### Auditoría
- Registro append-only con hash encadenado SHA-256
- Política de retención de auditoría parametrizable por cada entidad según sus instrumentos archivísticos y actos vigentes
- Detección de manipulación de registros
- Trigger SQLite de inmutabilidad: bloquea DELETE y solo permite archivar de 0 a 1
- configuracion_entidad versionada por parámetro vigente, con historial y matriz de módulos persistida

#### Roles y Permisos
- Alcalde/Representante Legal
- Secretario de Hacienda
- Tesorero
- Contador
- Jefe de Rentas
- Jefe de Control Interno
- Ordenador del Gasto
- Jefe de Planeación
- Secretario de Salud (hospitales)
- Rector (establecimientos educativos)

## Estructura de Directorios

```
lib/sector_publico/
├── models/                    # Modelos de datos
│   ├── entidad.dart          # Entidad territorial
│   └── registro_auditoria.dart # Registro de auditoría
├── security/                  # Seguridad y auditoría
│   ├── auditoria_service.dart # Servicio de auditoría
│   ├── roles_permisos_service.dart # Roles y permisos
│   └── iso_27001_requirements.md # Requisitos ISO 27001
├── database/                  # Esquema de base de datos
│   └── schema_multi_tenant.dart # Esquema multi-tenant
├── services/                  # Servicios de negocio
│   └── migracion_datos_service.dart # Migración de datos
├── presupuesto/               # Módulo de presupuesto (Fase 1)
├── contabilidad/              # Módulo de contabilidad NICSP (Fase 2)
├── rentas/                    # Módulo de rentas (Fase 4)
├── contratacion/              # Módulo de contratación (Fase 5)
├── nomina/                    # Módulo de nómina pública (Fase 6)
├── planeacion/                # Módulo de planeación (Fase 7)
├── activos/                   # Módulo de activos del Estado (Fase 8)
├── salud/                     # Módulo de salud pública (Fase 9)
├── regalias/                  # Módulo SGR (Fase 10)
└── transparencia/             # Módulo de transparencia (Fase 11)
```

## Normativa Aplicable

### Presupuesto
- Decreto 111 de 1996 - Estatuto Orgánico del Presupuesto (EOP)
- Ley 80 de 1993 - Estatuto General de Contratación

### Contabilidad
- Resolución 533 de 2015 CGN - NICSP
- Resoluciones 436, 437, 438, 439 de 2024 CGN

### Tributario
- Ley 44 de 1990 - Impuesto Predial Unificado
- Estatuto Tributario - Arts. 823-843 (Rentas)

### Nómina
- Decreto 1042 de 1978 - Escalas salariales
- Ley 4 de 1992 - Régimen salarial

### Salud
- Resolución 2275 de 2023 - RIPS

### Seguridad y Transparencia
- Ley 1581 de 2012 - Habeas Data
- Ley 1712 de 2014 - Transparencia
- Ley 1952 de 2019 - Control disciplinario

## Fases de Implementación

### Fase 0: Arquitectura Base ✅
- [x] Modelo de datos multi-tenant jerárquico
- [x] Tabla de auditoría append-only con hash encadenado
- [x] Módulo de roles y permisos con segregación de funciones dura
- [x] Estrategia de migración de datos históricos
- [x] Documentación de requisitos ISO 27001 y MinTIC

### Fase 1: Presupuesto Público + PAC (Parcial)
- Flujo APROPIACIÓN → CDP → RP → OBLIGACIÓN → PAGO
- Programación Anual Mensualizada de Caja (PAC)
- Faltan certificación integral del flujo y cobertura completa de validaciones normativas.

### Fase 2: Contabilidad NICSP (Parcial)
- Catálogo General de Cuentas (CGC)
- NICSP 1, 2, 12, 17, 19
- Faltan certificación de cierre de vigencia y cobertura normativa integral.

### Fase 3: Auditoría Forense + CHIP (Parcial)
- Eventos específicos de auditoría
- Formularios CGN 2015_001 a 005
- Formulario CGN 2016C01
- Faltan validaciones de extremo a extremo de los reportes regulatorios.

### Fase 4: Predial + ICA (Parcial)
- Carga de catastro IGAC
- Liquidación masiva
- Motor de intereses moratorios
- Cobro coactivo
- Faltan certificación de integración con catastro y del ciclo de cobro.

### Fase 5: Contratación Pública (Parcial)
- 6 modalidades de selección
- Interoperabilidad SECOP II configurable (fail-closed hasta configurar un canal autorizado)
- Ciclo contractual completo
- Faltan integración SECOP II certificada y cobertura funcional completa.

### Fase 6: Nómina Pública (Parcial)
- 6 regímenes salariales
- Retroactivos
- Interoperabilidad PILA configurable por operador de información
- Faltan cobertura de los seis regímenes y validación operativa de PILA.

### Fase 7: Planeación + Banco de Proyectos (Parcial)
- Plan de Desarrollo Territorial (PDT)
- Metodología MGA
- Trazabilidad plan-presupuesto-resultado
- Falta certificar la trazabilidad completa entre planeación, presupuesto y resultados.

### Fase 8: Activos del Estado (Parcial)
- Clasificación de bienes
- Depreciación NICSP 17
- Formulario Único Territorial (FUT)
- Faltan ejecución programada de depreciación y validación de reporte FUT.

### Fase 9: Salud Pública (Parcial)
- RIPS (6 archivos)
- Contratación EPS
- Glosas y conciliación
- Faltan integración y validación regulatoria completa de RIPS/EPS.

### Fase 10: SGR + SGP (Parcial)
- Sistema General de Regalías
- Sistema General de Participaciones
- Faltan flujos integrados y certificación normativa de regalías y participaciones.

### Fase 11: Transparencia + Control Disciplinario (Parcial)
- Portal de transparencia
- Control disciplinario (Ley 1952/2019)
- Consolidación NICSP 40
- Faltan publicación verificable, flujo disciplinario completo y consolidación certificada.

## Integración con MerkaERP Comercial

El módulo de Sector Público se integra con el ERP comercial existente:

- **Contabilidad**: Reutiliza motor contable comercial con adaptaciones NICSP
- **Nómina**: Extiende nómina comercial con regímenes especiales públicos
- **Inventario**: Comparte módulo de inventario con clasificación especial
- **Bancos**: Reutiliza módulo de bancos con controles PAC adicionales

## Pruebas

Cada fase debe incluir:

- Pruebas del camino feliz
- Pruebas de bloqueos normativos
- Pruebas de segregación de funciones
- Pruebas de auditoría
- Pruebas de multi-tenant

## Criterio de "Hecho"

Una fase no está completa si:

- Le falta validación normativa dura
- No genera registro de auditoría
- No respeta segregación de funciones
- No tiene pruebas básicas

## Licencia

Propiedad de MerkaERP. Uso exclusivo para entidades del sector público colombiano.
