import '../../licensing/domain/product_family.dart';
import 'migration_models.dart';

class MigrationCatalog {
  static const _commercial = {ProductFamily.commercial};
  static const _public = {ProductFamily.publicSector};
  static const _both = {ProductFamily.commercial, ProductFamily.publicSector};

  static const entities = <MigrationEntityDefinition>[
    MigrationEntityDefinition(
      key: 'legacy_archive',
      label: 'Archivo histórico · conservar sin transformar',
      productFamilies: _both,
      description: 'Conserva íntegramente una tabla/exportación del sistema anterior, con hash y trazabilidad, sin afectar módulos operativos.',
      fields: [],
    ),
    MigrationEntityDefinition(
      key: 'customers',
      label: 'Clientes',
      productFamilies: _commercial,
      description: 'Clientes, terceros comerciales y datos de contacto.',
      fields: [
        MigrationFieldDefinition(key: 'name', label: 'Nombre / razón social', required: true, aliases: ['nombre', 'razon social', 'cliente', 'name', 'customer']),
        MigrationFieldDefinition(key: 'document', label: 'NIT / documento', aliases: ['nit', 'documento', 'identificacion', 'cedula', 'document', 'tax id']),
        MigrationFieldDefinition(key: 'phone', label: 'Teléfono', aliases: ['telefono', 'celular', 'movil', 'phone']),
        MigrationFieldDefinition(key: 'email', label: 'Correo', type: MigrationFieldType.email, aliases: ['email', 'correo', 'e-mail']),
        MigrationFieldDefinition(key: 'address', label: 'Dirección', aliases: ['direccion', 'address']),
        MigrationFieldDefinition(key: 'city', label: 'Ciudad', aliases: ['ciudad', 'municipio', 'city']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'suppliers',
      label: 'Proveedores',
      productFamilies: _commercial,
      description: 'Proveedores y datos de contacto.',
      fields: [
        MigrationFieldDefinition(key: 'name', label: 'Nombre / razón social', required: true, aliases: ['nombre', 'razon social', 'proveedor', 'supplier', 'name']),
        MigrationFieldDefinition(key: 'document', label: 'NIT / documento', aliases: ['nit', 'documento', 'identificacion', 'document', 'tax id']),
        MigrationFieldDefinition(key: 'phone', label: 'Teléfono', aliases: ['telefono', 'celular', 'phone']),
        MigrationFieldDefinition(key: 'email', label: 'Correo', type: MigrationFieldType.email, aliases: ['email', 'correo']),
        MigrationFieldDefinition(key: 'address', label: 'Dirección', aliases: ['direccion', 'address']),
        MigrationFieldDefinition(key: 'contact', label: 'Contacto', aliases: ['contacto', 'contact']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'products',
      label: 'Productos e inventario inicial',
      productFamilies: _commercial,
      description: 'Catálogo, precios, costos y existencias de apertura.',
      fields: [
        MigrationFieldDefinition(key: 'name', label: 'Producto', required: true, aliases: ['producto', 'nombre', 'descripcion', 'item', 'product', 'name']),
        MigrationFieldDefinition(key: 'code', label: 'Código', aliases: ['codigo', 'sku', 'code', 'referencia']),
        MigrationFieldDefinition(key: 'barcode', label: 'Código de barras', aliases: ['codigo de barras', 'codigo_barras', 'barcode', 'ean', 'upc']),
        MigrationFieldDefinition(key: 'unit', label: 'Unidad', aliases: ['unidad', 'unidad base', 'unit', 'uom']),
        MigrationFieldDefinition(key: 'stock', label: 'Existencia', type: MigrationFieldType.decimal, aliases: ['stock', 'existencia', 'cantidad', 'saldo inventario', 'qty']),
        MigrationFieldDefinition(key: 'cost', label: 'Costo unitario', type: MigrationFieldType.money, aliases: ['costo', 'costo unitario', 'cost']),
        MigrationFieldDefinition(key: 'price', label: 'Precio de venta', type: MigrationFieldType.money, aliases: ['precio', 'precio venta', 'precio de venta', 'price']),
        MigrationFieldDefinition(key: 'tax', label: 'IVA %', type: MigrationFieldType.decimal, aliases: ['iva', 'impuesto', 'tax', 'tax rate']),
        MigrationFieldDefinition(key: 'description', label: 'Descripción', aliases: ['descripcion larga', 'detalle', 'description']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'ar_opening',
      label: 'Cartera inicial · cuentas por cobrar',
      productFamilies: _commercial,
      description: 'Saldos pendientes a favor de la empresa al momento de migrar.',
      fields: [
        MigrationFieldDefinition(key: 'customer_document', label: 'Documento cliente', aliases: ['nit cliente', 'documento cliente', 'identificacion cliente', 'customer document']),
        MigrationFieldDefinition(key: 'customer_name', label: 'Cliente', required: true, aliases: ['cliente', 'nombre cliente', 'customer']),
        MigrationFieldDefinition(key: 'document_number', label: 'Factura / documento', aliases: ['factura', 'documento', 'numero factura', 'invoice']),
        MigrationFieldDefinition(key: 'balance', label: 'Saldo pendiente', required: true, type: MigrationFieldType.money, aliases: ['saldo', 'saldo pendiente', 'balance', 'valor pendiente']),
        MigrationFieldDefinition(key: 'date', label: 'Fecha origen', type: MigrationFieldType.date, aliases: ['fecha', 'fecha factura', 'date']),
        MigrationFieldDefinition(key: 'due_date', label: 'Vencimiento', type: MigrationFieldType.date, aliases: ['vencimiento', 'fecha vencimiento', 'due date']),
        MigrationFieldDefinition(key: 'description', label: 'Descripción', aliases: ['descripcion', 'concepto', 'observacion']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'ap_opening',
      label: 'Cuentas por pagar iniciales',
      productFamilies: _commercial,
      description: 'Obligaciones pendientes con proveedores al momento de migrar.',
      fields: [
        MigrationFieldDefinition(key: 'supplier_document', label: 'NIT proveedor', aliases: ['nit proveedor', 'documento proveedor', 'supplier document']),
        MigrationFieldDefinition(key: 'supplier_name', label: 'Proveedor', required: true, aliases: ['proveedor', 'nombre proveedor', 'supplier']),
        MigrationFieldDefinition(key: 'document_number', label: 'Factura / documento', aliases: ['factura', 'documento', 'numero factura', 'invoice']),
        MigrationFieldDefinition(key: 'balance', label: 'Saldo pendiente', required: true, type: MigrationFieldType.money, aliases: ['saldo', 'saldo pendiente', 'balance', 'valor pendiente']),
        MigrationFieldDefinition(key: 'date', label: 'Fecha origen', type: MigrationFieldType.date, aliases: ['fecha', 'fecha factura', 'date']),
        MigrationFieldDefinition(key: 'description', label: 'Descripción', aliases: ['descripcion', 'concepto', 'observacion']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'accounting_opening',
      label: 'Saldos contables iniciales',
      productFamilies: _commercial,
      description: 'Asiento de apertura balanceado por cuenta. No se importa si débitos y créditos no cuadran.',
      fields: [
        MigrationFieldDefinition(key: 'account_code', label: 'Código cuenta', required: true, aliases: ['cuenta', 'codigo cuenta', 'codigo', 'account code']),
        MigrationFieldDefinition(key: 'account_name', label: 'Nombre cuenta', aliases: ['nombre cuenta', 'cuenta nombre', 'account name']),
        MigrationFieldDefinition(key: 'nature', label: 'Naturaleza', aliases: ['naturaleza', 'nature']),
        MigrationFieldDefinition(key: 'debit', label: 'Débito', type: MigrationFieldType.money, aliases: ['debito', 'debe', 'debit']),
        MigrationFieldDefinition(key: 'credit', label: 'Crédito', type: MigrationFieldType.money, aliases: ['credito', 'haber', 'credit']),
        MigrationFieldDefinition(key: 'third_party', label: 'Tercero', aliases: ['tercero', 'beneficiario', 'third party']),
        MigrationFieldDefinition(key: 'description', label: 'Descripción', aliases: ['descripcion', 'concepto', 'detalle']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'public_third_parties',
      label: 'Terceros del Sector Público',
      productFamilies: _public,
      description: 'Contratistas, proveedores, beneficiarios y demás terceros.',
      fields: [
        MigrationFieldDefinition(key: 'id_type', label: 'Tipo identificación', aliases: ['tipo identificacion', 'tipo documento', 'id type']),
        MigrationFieldDefinition(key: 'document', label: 'Número identificación', required: true, aliases: ['nit', 'documento', 'numero identificacion', 'identificacion']),
        MigrationFieldDefinition(key: 'check_digit', label: 'DV', aliases: ['dv', 'digito verificacion']),
        MigrationFieldDefinition(key: 'name', label: 'Razón social / nombre', required: true, aliases: ['razon social', 'nombre', 'tercero']),
        MigrationFieldDefinition(key: 'third_party_type', label: 'Tipo tercero', aliases: ['tipo tercero', 'clase tercero']),
        MigrationFieldDefinition(key: 'address', label: 'Dirección', aliases: ['direccion']),
        MigrationFieldDefinition(key: 'phone', label: 'Teléfono', aliases: ['telefono', 'celular']),
        MigrationFieldDefinition(key: 'email', label: 'Correo', type: MigrationFieldType.email, aliases: ['email', 'correo']),
        MigrationFieldDefinition(key: 'city', label: 'Municipio', aliases: ['municipio', 'ciudad']),
        MigrationFieldDefinition(key: 'department', label: 'Departamento', aliases: ['departamento']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'public_chart_accounts',
      label: 'Plan de cuentas público',
      productFamilies: _public,
      description: 'Catálogo contable de la entidad, preservando los códigos existentes.',
      fields: [
        MigrationFieldDefinition(key: 'code', label: 'Código cuenta', required: true, aliases: ['codigo', 'cuenta', 'codigo cuenta']),
        MigrationFieldDefinition(key: 'name', label: 'Nombre cuenta', required: true, aliases: ['nombre', 'nombre cuenta', 'cuenta nombre']),
        MigrationFieldDefinition(key: 'class', label: 'Clase', aliases: ['clase']),
        MigrationFieldDefinition(key: 'group', label: 'Grupo', aliases: ['grupo']),
        MigrationFieldDefinition(key: 'subgroup', label: 'Subgrupo', aliases: ['subgrupo']),
        MigrationFieldDefinition(key: 'nature', label: 'Naturaleza', required: true, aliases: ['naturaleza']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'public_budget_opening',
      label: 'Presupuesto y ejecución acumulada de apertura',
      productFamilies: _public,
      description: 'Carga la apropiación y, opcionalmente, la ejecución acumulada vigente por rubro sin inventar CDP/RP/obligaciones históricas. Los documentos históricos se conservan en el Archivo Legado.',
      fields: [
        MigrationFieldDefinition(key: 'year', label: 'Vigencia', required: true, type: MigrationFieldType.integer, aliases: ['vigencia', 'ano', 'año', 'year']),
        MigrationFieldDefinition(key: 'code', label: 'Código rubro', required: true, aliases: ['codigo rubro', 'rubro', 'codigo']),
        MigrationFieldDefinition(key: 'name', label: 'Nombre rubro', required: true, aliases: ['nombre rubro', 'descripcion rubro', 'nombre']),
        MigrationFieldDefinition(key: 'initial_value', label: 'Apropiación inicial', required: true, type: MigrationFieldType.money, aliases: ['apropiacion inicial', 'valor inicial', 'presupuesto inicial']),
        MigrationFieldDefinition(key: 'current_appropriation', label: 'Apropiación vigente', type: MigrationFieldType.money, aliases: ['apropiacion vigente', 'valor apropiado', 'presupuesto vigente', 'apropiacion definitiva']),
        MigrationFieldDefinition(key: 'cdp_accumulated', label: 'CDP acumulado', type: MigrationFieldType.money, aliases: ['cdp acumulado', 'valor cdp', 'certificados acumulados']),
        MigrationFieldDefinition(key: 'rp_accumulated', label: 'RP acumulado', type: MigrationFieldType.money, aliases: ['rp acumulado', 'valor rp', 'compromisos acumulados']),
        MigrationFieldDefinition(key: 'obligated_accumulated', label: 'Obligado acumulado', type: MigrationFieldType.money, aliases: ['obligado acumulado', 'valor obligado', 'obligaciones acumuladas']),
        MigrationFieldDefinition(key: 'paid_accumulated', label: 'Pagado acumulado', type: MigrationFieldType.money, aliases: ['pagado acumulado', 'valor pagado', 'pagos acumulados']),
        MigrationFieldDefinition(key: 'funding_source', label: 'Fuente financiación', required: true, aliases: ['fuente', 'fuente financiacion', 'fuente de financiacion']),
        MigrationFieldDefinition(key: 'sector', label: 'Sector', aliases: ['sector']),
        MigrationFieldDefinition(key: 'program', label: 'Programa', aliases: ['programa']),
        MigrationFieldDefinition(key: 'subprogram', label: 'Subprograma', aliases: ['subprograma']),
        MigrationFieldDefinition(key: 'project', label: 'Proyecto', aliases: ['proyecto']),
        MigrationFieldDefinition(key: 'activity', label: 'Actividad', aliases: ['actividad']),
        MigrationFieldDefinition(key: 'expense_object', label: 'Objeto del gasto', aliases: ['objeto gasto', 'objeto del gasto']),
        MigrationFieldDefinition(key: 'administrative_act', label: 'Acto administrativo', aliases: ['acto administrativo', 'acuerdo', 'decreto']),
        MigrationFieldDefinition(key: 'approval_date', label: 'Fecha aprobación', type: MigrationFieldType.date, aliases: ['fecha aprobacion', 'fecha acuerdo']),
      ],
    ),
    MigrationEntityDefinition(
      key: 'public_accounting_opening',
      label: 'Saldos contables públicos de apertura',
      productFamilies: _public,
      description: 'Crea un asiento de apertura NICSP balanceado y actualiza saldos por cuenta. No se importa si débitos y créditos no cuadran.',
      fields: [
        MigrationFieldDefinition(key: 'year', label: 'Vigencia', required: true, type: MigrationFieldType.integer, aliases: ['vigencia', 'ano', 'año', 'year']),
        MigrationFieldDefinition(key: 'account_code', label: 'Código cuenta', required: true, aliases: ['cuenta', 'codigo cuenta', 'codigo', 'account code']),
        MigrationFieldDefinition(key: 'account_name', label: 'Nombre cuenta', aliases: ['nombre cuenta', 'cuenta nombre', 'account name']),
        MigrationFieldDefinition(key: 'nature', label: 'Naturaleza', aliases: ['naturaleza', 'nature']),
        MigrationFieldDefinition(key: 'debit', label: 'Débito', type: MigrationFieldType.money, aliases: ['debito', 'debe', 'debit']),
        MigrationFieldDefinition(key: 'credit', label: 'Crédito', type: MigrationFieldType.money, aliases: ['credito', 'haber', 'credit']),
        MigrationFieldDefinition(key: 'description', label: 'Descripción', aliases: ['descripcion', 'concepto', 'detalle']),
      ],
    ),
  ];

  static List<MigrationEntityDefinition> forFamily(ProductFamily family) =>
      entities.where((entity) => entity.productFamilies.contains(family)).toList();

  static MigrationEntityDefinition byKey(String key) =>
      entities.firstWhere((entity) => entity.key == key);
}
