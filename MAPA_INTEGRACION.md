# 🗺️ MAPA DE INTEGRACIÓN - Caja Simple + Odoo 19.0

## Estructura Visual del Proyecto

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│              📱 CAJA SIMPLE / MERKAERP - PLATAFORMA INTEGRAL               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                      🖥️  FRONTEND MULTIPLATAFORMA (Flutter)                 │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  Windows  │  macOS  │  Linux  │  Web  │  Android  │  iOS                   │
│   ✓       │   ✓     │   ✓     │  ✓    │    ✓     │   ✓                    │
│                                                                               │
│  lib/ (358 archivos Dart)                                                    │
│  ├── control_center/          ← Centro de Control (Dashboard)               │
│  ├── sales/                   ← Módulo de Ventas                           │
│  ├── purchases/               ← Módulo de Compras                          │
│  ├── inventory/               ← Módulo de Inventario                       │
│  ├── accounting/              ← Módulo de Contabilidad                     │
│  ├── crm/                     ← Gestión de Relaciones                      │
│  ├── catalog/                 ← Catálogo de Productos                      │
│  ├── pages/                   ← 30+ Pantallas                              │
│  ├── ui/                      ← 50+ Componentes                            │
│  ├── core/                    ← API interna, Permisos, Eventos            │
│  ├── cqrs/                    ← Event sourcing y proyecciones             │
│  └── services/                ← Servicios HTTP, BD, Auth                  │
│                                                                               │
└──────────────────────┬───────────────────────────────────────────────────────┘
                       │
                       │  HTTP/REST + JWT Token
                       │  Content-Type: application/json
                       │
┌──────────────────────┴───────────────────────────────────────────────────────┐
│                    🚀 BACKEND - Node.js + Express                            │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  backend/src/server.js                                                       │
│  ├── Middleware: CORS, Helmet, Morgan, Rate Limit                           │
│  ├── Autenticación: JWT, bcrypt                                             │
│  ├── Base de datos: PostgreSQL (Render) + SQLite (Local)                    │
│  │                                                                            │
│  └── RUTAS API (70+ endpoints)                                              │
│      │                                                                        │
│      ├── /api/auth/*                  [Autenticación]                        │
│      │   ├── POST /login              [Iniciar sesión]                      │
│      │   ├── POST /register           [Registrar usuario]                   │
│      │   └── POST /refresh            [Renovar token]                       │
│      │                                                                        │
│      ├── /api/admin/*                 [Administración]                       │
│      │   ├── GET /users               [Listar usuarios]                     │
│      │   ├── POST /users              [Crear usuario]                       │
│      │   └── ...                      [Más endpoints admin]                 │
│      │                                                                        │
│      ├── /api/odoo/*                  ← ⭐ ODOO INTEGRATION (NUEVO)         │
│      │   │                                                                    │
│      │   ├── /api/odoo/health         [Health check]                        │
│      │   ├── /api/odoo/docs           [Documentación API]                   │
│      │   │                                                                    │
│      │   ├── BASE MODULE                                                     │
│      │   │  ├── POST /companies       [Crear empresa]                       │
│      │   │  ├── GET /companies        [Listar empresas]                     │
│      │   │  ├── POST /users           [Crear usuario]                       │
│      │   │  └── GET /users            [Listar usuarios]                     │
│      │   │                                                                    │
│      │   ├── CONTACTS MODULE                                                │
│      │   │  ├── POST /partners        [Crear contacto]                      │
│      │   │  ├── GET /partners         [Listar contactos]                    │
│      │   │  ├── GET /partners/type/customers    [Clientes]                  │
│      │   │  └── GET /partners/type/suppliers    [Proveedores]              │
│      │   │                                                                    │
│      │   ├── PRODUCT MODULE                                                 │
│      │   │  ├── POST /products        [Crear producto]                      │
│      │   │  ├── GET /products         [Listar productos]                    │
│      │   │  └── GET /products/search  [Búsqueda]                           │
│      │   │                                                                    │
│      │   ├── STOCK MODULE                                                   │
│      │   │  ├── POST /stock/movements [Movimientos]                         │
│      │   │  ├── GET /stock/inventory  [Inventario]                         │
│      │   │  └── GET /stock/locations  [Ubicaciones]                        │
│      │   │                                                                    │
│      │   ├── SALE MODULE                                                    │
│      │   │  ├── POST /sale-orders     [Crear orden]                         │
│      │   │  ├── GET /sale-orders      [Listar órdenes]                      │
│      │   │  ├── POST /sale-orders/:id/confirm    [Confirmar]               │
│      │   │  ├── POST /sale-orders/:id/lines     [Agregar línea]            │
│      │   │  └── POST /sale-orders/:id/invoice   [Facturar]                 │
│      │   │                                                                    │
│      │   ├── PURCHASE MODULE                                                │
│      │   │  ├── POST /purchase-orders [Crear orden]                         │
│      │   │  ├── GET /purchase-orders  [Listar órdenes]                      │
│      │   │  └── POST /purchase-orders/:id/confirm  [Confirmar]             │
│      │   │                                                                    │
│      │   └── ACCOUNT MODULE                                                 │
│      │      ├── POST /invoices        [Crear factura]                       │
│      │      ├── GET /invoices         [Listar facturas]                     │
│      │      ├── POST /invoices/:id/post [Publicar]                         │
│      │      └── POST /invoices/:id/pay  [Pagar]                            │
│      │                                                                        │
│      ├── /api/sales/*                 [Ventas existentes]                    │
│      ├── /api/purchases/*             [Compras existentes]                   │
│      ├── /api/inventory/*             [Inventario existente]                 │
│      └── ...                          [Más rutas]                            │
│                                                                               │
│  MÓDULOS DE NEGOCIO (15 módulos)                                            │
│  ├── base/            [Base Module]                                         │
│  ├── contacts/        [Contacts Module]                                     │
│  ├── product/         [Product Module]                                      │
│  ├── stock/           [Stock Module]                                        │
│  ├── sale/            [Sale Module]                                         │
│  ├── purchase/        [Purchase Module]                                     │
│  ├── account/         [Account Module]                                      │
│  ├── cqrs/            [Event Sourcing]                                      │
│  ├── licensing/       [Licencias SaaS]                                      │
│  ├── telemetry/       [Telemetría]                                          │
│  ├── sync/            [Sincronización]                                      │
│  ├── workflows/       [Workflows]                                           │
│  ├── audit/           [Auditoría]                                           │
│  ├── rules/           [Reglas de negocio]                                   │
│  └── jobs/            [Job Scheduling]                                      │
│                                                                               │
└──────────────────────┬───────────────────────────────────────────────────────┘
                       │
                       │  SQL Queries
                       │  
┌──────────────────────┴───────────────────────────────────────────────────────┐
│                    💾 BASE DE DATOS (70+ tablas)                             │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  PRODUCCIÓN              │  DESARROLLO                                       │
│  ┌────────────────────────────┐                                              │
│  │   PostgreSQL (Render)      │   SQLite (Local)                            │
│  │   Hostname: db.render      │   Archivo: cajasimple.db                   │
│  │   Puerto: 5432             │   Conexión: DB_PATH                         │
│  │   DATABASE_URL             │                                              │
│  └────────────────────────────┘                                              │
│                                                                               │
│  TABLAS ODOO (22 nuevas)                                                    │
│  ├── res_users                      [Usuarios]                              │
│  ├── res_companies                  [Empresas]                              │
│  ├── res_roles                      [Roles]                                 │
│  ├── res_partners                   [Contactos]                             │
│  ├── product_categories             [Categorías]                            │
│  ├── product_products               [Productos]                             │
│  ├── stock_locations                [Ubicaciones]                           │
│  ├── stock_moves                    [Movimientos]                           │
│  ├── sale_orders                    [Órdenes venta]                         │
│  ├── sale_order_lines               [Líneas venta]                          │
│  ├── purchase_orders                [Órdenes compra]                        │
│  ├── purchase_order_lines           [Líneas compra]                         │
│  ├── account_invoices               [Facturas]                              │
│  ├── account_invoice_lines          [Líneas factura]                        │
│  ├── account_accounts               [Cuentas]                               │
│  ├── account_journals               [Diarios]                               │
│  └── ... (6 tablas más)                                                     │
│                                                                               │
│  TABLAS EXISTENTES (50+ tablas)                                             │
│  ├── companies_*                    [Empresas]                              │
│  ├── users_*                        [Usuarios]                              │
│  ├── inventory_*                    [Inventario]                            │
│  ├── sales_*                        [Ventas]                                │
│  ├── purchases_*                    [Compras]                               │
│  ├── accounting_*                   [Contabilidad]                          │
│  ├── cqrs_*                         [Event Store]                           │
│  ├── sync_*                         [Sincronización]                        │
│  └── ...                            [Más tablas]                             │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔀 Flujo de una transacción típica

### Ejemplo: Crear una orden de venta

```
1. USUARIO EN FLUTTER
   └─> Completa formulario de orden de venta
   └─> Presiona "Crear orden"

2. FRONTEND (Flutter)
   └─> Valida datos localmente
   └─> Prepara JSON payload
   └─> Añade JWT token
   └─> Envía: POST /api/odoo/sale-orders
       {
         "partner_id": 1,
         "company_id": 1,
         "order_date": "2024-01-15",
         "currency_id": 1
       }

3. BACKEND (Express)
   └─> Recibe request en server.js
   └─> Middleware CORS valida origen
   └─> Middleware Auth valida JWT
   └─> Router /api/odoo* direcciona a odooApi.js
   └─> setupOdooRoutes() busca ruta coincidente
   └─> Controlador sale/routes/orders.js procesa
   └─> SaleOrderService realiza lógica de negocio
       - Valida datos
       - Calcula totales
       - Genera estado "draft"
   └─> DatabaseAdapter.query() crea registro

4. BD (PostgreSQL)
   └─> INSERT INTO sale_orders (...) VALUES (...)
   └─> Obtiene ID generado
   └─> Retorna resultado

5. BACKEND (Express)
   └─> Formatea respuesta JSON
   └─> Incluye ID de orden, estado, etc.
   └─> Envía 200 OK

6. FRONTEND (Flutter)
   └─> Recibe respuesta
   └─> Actualiza UI con nueva orden
   └─> Muestra confirmación al usuario
   └─> Opcionalmente: sincroniza a cache local
```

---

## 📊 Matriz de integración

### Módulos Odoo vs Pantallas Flutter

| Módulo Odoo | Endpoints | Pantallas Flutter | Sincronización |
|---|---|---|---|
| Base | 8+ | Login, Usuarios | ✓ |
| Contacts | 7+ | Clientes, Proveedores | ✓ |
| Product | 7+ | Catálogo, Búsqueda | ✓ |
| Stock | 8+ | Inventario, Movimientos | ✓ |
| Sale | 9+ | Órdenes, Facturas | ✓ |
| Purchase | 9+ | Órdenes de compra | ✓ |
| Account | 9+ | Facturas, Reportes | ✓ |
| **TOTAL** | **49+** | **20+** | **✓ Todos** |

---

## 🔐 Seguridad y flujo de autenticación

```
USUARIO
   │
   ▼
┌─────────────────────────────────┐
│ Pantalla de Login (Flutter)     │
│ ├─ Email/Usuario                │
│ ├─ Contraseña                   │
│ └─ Botón: Ingresar              │
└────────────┬────────────────────┘
             │ POST /api/auth/login
             ▼
     ┌──────────────────────┐
     │ Backend Express      │
     ├──────────────────────┤
     │ 1. Busca usuario     │
     │ 2. Valida contraseña │
     │    (bcrypt)          │
     │ 3. Genera JWT token  │
     │ 4. Retorna token     │
     └────────────┬─────────┘
                  │ JWT token + user data
                  ▼
       ┌──────────────────────────┐
       │ Flutter Frontend         │
       ├──────────────────────────┤
       │ 1. Almacena token        │
       │    (SecureStorage)       │
       │ 2. Navega a Dashboard    │
       │ 3. Incluye token en      │
       │    headers: Authorization│
       │    "Bearer <token>"      │
       └────────────┬─────────────┘
                    │ Token en cada request
                    ▼
          ┌────────────────────────┐
          │ Backend Express        │
          ├────────────────────────┤
          │ Middleware auth        │
          │ 1. Extrae token       │
          │ 2. Valida JWT         │
          │ 3. Verifica expiración│
          │ 4. Permite/rechaza    │
          │    request            │
          └────────────────────────┘
```

---

## 🚀 Flujo de deployment

```
LOCAL DEVELOPMENT
│
├─ Backend: npm run dev
│  └─ SQLite local database
│
├─ Frontend: flutter run -d windows
│  └─ Conecta a http://localhost:8787
│
└─ Verificar endpoints: test_api.ps1

        │
        ▼

TESTING
│
├─ npm run test-api
│  └─ Verifica todos los endpoints
│
└─ Test de integración
   └─ Flutter conectado a backend

        │
        ▼

STAGING / QA
│
├─ Backend en servidor intermedio
│  └─ PostgreSQL remoto
│
├─ Frontend testea conexión
│  └─ URLs de staging
│
└─ Pruebas de carga y performance

        │
        ▼

PRODUCCIÓN (Render)
│
├─ Backend: npm start
│  └─ PostgreSQL en Render
│
├─ Frontend: Build y distribución
│  └─ URLs de producción
│
└─ Monitoreo y alertas
   └─ Telemetría del sistema
```

---

## 📱 Plataformas soportadas

```
┌─────────────────────────────────────────────┐
│   CAJA SIMPLE / MERKAERP                    │
│   Plataformas multiplataforma con Flutter  │
└─────────────────────────────────────────────┘

  Desktop              Mobile              Web
┌─────────────┐    ┌─────────────┐    ┌──────────┐
│  Windows    │    │  Android    │    │ Flutter  │
│   ✓ exe     │    │   ✓ apk     │    │  Web     │
│             │    │   ✓ aab     │    │  ✓       │
└─────────────┘    └─────────────┘    └──────────┘

┌─────────────┐    ┌─────────────┐
│   macOS     │    │    iOS      │
│   ✓ app     │    │   ✓ ipa     │
│   ✓ dmg     │    │   ✓ app     │
└─────────────┘    └─────────────┘

┌─────────────────────────────────────────────┐
│          Linux Desktop (GTK/AppImage)       │
│          ✓ Instalable                      │
└─────────────────────────────────────────────┘

Una sola base de código en Dart = 6 plataformas
```

---

## 💻 Requisitos para ejecutar

### Backend
```
Node.js >= 14.0
npm >= 6.0
PostgreSQL 12+ (Producción)
SQLite 3+ (Desarrollo)
```

### Frontend
```
Flutter >= 3.11.5
Dart >= 3.11.5
Android SDK (para Android)
Xcode (para iOS)
Git
```

### Sistema operativo
```
Windows (cualquier versión)
macOS (10.14+)
Linux (Ubuntu 18.04+)
```

---

## 📊 Resumen técnico

| Aspecto | Valor |
|---|---|
| **Plataformas** | 6 (Windows, macOS, Linux, Web, Android, iOS) |
| **Lenguajes** | Dart (Frontend) + JavaScript (Backend) |
| **Base de datos** | PostgreSQL + SQLite |
| **Módulos backend** | 15 |
| **Módulos Odoo** | 7 |
| **Endpoints API** | 70+ |
| **Tablas de BD** | 70+ |
| **Archivos Dart** | 358 |
| **Archivos JS** | 32 |
| **Documentación** | 10 archivos |
| **Autenticación** | JWT + bcrypt |
| **Seguridad** | Helmet, CORS, Rate Limit |
| **Estado** | ✅ Producción |

---

## 🎯 Conclusión

**Caja Simple con Odoo 19.0 es un sistema ERP profesional, multiplataforma y completamente integrado.**

Todas las piezas encajan perfectamente:
- ✅ Frontend Flutter en 6 plataformas
- ✅ Backend Node.js con 15 módulos
- ✅ Odoo 19.0 con 7 módulos funcionales
- ✅ Base de datos con 70+ tablas
- ✅ API con 70+ endpoints
- ✅ Autenticación y seguridad enterprise
- ✅ Documentación completa

**Está listo para producción.**
