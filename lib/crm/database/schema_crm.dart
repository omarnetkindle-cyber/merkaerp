import 'package:sqflite/sqflite.dart';

/// Esquema persistente del CRM.
///
/// Las tablas comerciales existentes (`clientes` y `crm_opportunities`) son
/// la fuente canónica. Esta rutina solo agrega columnas faltantes y crea las
/// entidades nuevas de CRM de forma idempotente.
class SchemaCrm {
  const SchemaCrm._();

  static Future<void> crearTablas(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clientes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER,
        nombre TEXT NOT NULL,
        documento TEXT,
        telefono TEXT,
        direccion TEXT,
        email TEXT,
        estado TEXT DEFAULT 'activo',
        fecha TEXT,
        gran_contribuyente INTEGER DEFAULT 0,
        autorretenedor INTEGER DEFAULT 0,
        regimen_tributario TEXT DEFAULT 'ordinario',
        declarante INTEGER DEFAULT 1
      )
    ''');
    await _agregarColumnaSiNoExiste(db, 'clientes', 'parent_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(
      db,
      'clientes',
      'assigned_user_id',
      'INTEGER',
    );
    await _agregarColumnaSiNoExiste(db, 'clientes', 'territory_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(
      db,
      'clientes',
      'entity_type',
      "TEXT NOT NULL DEFAULT 'comercial'",
    );
    await _agregarColumnaSiNoExiste(db, 'clientes', 'created_at', 'TEXT');
    await _agregarColumnaSiNoExiste(db, 'clientes', 'modified_at', 'TEXT');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        account_id INTEGER NOT NULL,
        first_name TEXT NOT NULL,
        last_name TEXT NOT NULL DEFAULT '',
        birthdate TEXT,
        email TEXT,
        phone_work TEXT,
        phone_mobile TEXT,
        reports_to_id INTEGER,
        lead_source TEXT,
        opportunity_role TEXT,
        assigned_user_id INTEGER,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT NOT NULL,
        modified_at TEXT,
        FOREIGN KEY (account_id) REFERENCES clientes(id),
        FOREIGN KEY (reports_to_id) REFERENCES crm_contacts(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_leads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        account_name TEXT,
        contact_id INTEGER,
        lead_source TEXT,
        status TEXT NOT NULL DEFAULT 'nuevo',
        opportunity_amount INTEGER NOT NULL DEFAULT 0,
        converted INTEGER NOT NULL DEFAULT 0,
        converted_account_id INTEGER,
        converted_opportunity_id TEXT,
        campaign_id INTEGER,
        territory_id INTEGER,
        assigned_user_id INTEGER,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT NOT NULL,
        modified_at TEXT,
        FOREIGN KEY (contact_id) REFERENCES crm_contacts(id),
        FOREIGN KEY (converted_account_id) REFERENCES clientes(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_opportunities (
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 1,
        warehouse_id INTEGER NOT NULL DEFAULT 1,
        cost_center_id INTEGER NOT NULL DEFAULT 1,
        customer_id INTEGER NOT NULL,
        customer TEXT NOT NULL,
        value INTEGER NOT NULL DEFAULT 0,
        stage TEXT NOT NULL DEFAULT 'prospecting',
        next_follow_up_at TEXT NOT NULL,
        owner TEXT NOT NULL DEFAULT 'local',
        name TEXT,
        account_id INTEGER,
        amount INTEGER,
        sales_stage TEXT,
        probability INTEGER,
        lead_source TEXT,
        opportunity_type TEXT,
        next_step TEXT,
        date_closed TEXT,
        campaign_id INTEGER,
        territory_id INTEGER,
        assigned_user_id INTEGER,
        linked_sale_id INTEGER,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT,
        modified_at TEXT,
        FOREIGN KEY (account_id) REFERENCES clientes(id)
      )
    ''');

    for (final column in const [
      ('name', 'TEXT'),
      ('account_id', 'INTEGER'),
      ('amount', 'INTEGER'),
      ('sales_stage', 'TEXT'),
      ('probability', 'INTEGER'),
      ('lead_source', 'TEXT'),
      ('opportunity_type', 'TEXT'),
      ('next_step', 'TEXT'),
      ('date_closed', 'TEXT'),
      ('campaign_id', 'INTEGER'),
      ('territory_id', 'INTEGER'),
      ('assigned_user_id', 'INTEGER'),
      ('linked_sale_id', 'INTEGER'),
      ('entity_type', "TEXT NOT NULL DEFAULT 'comercial'"),
      ('created_at', 'TEXT'),
      ('modified_at', 'TEXT'),
    ]) {
      await _agregarColumnaSiNoExiste(
        db,
        'crm_opportunities',
        column.$1,
        column.$2,
      );
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_interactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        interaction_type TEXT NOT NULL,
        subject TEXT NOT NULL,
        description TEXT,
        interaction_date TEXT NOT NULL,
        outcome TEXT,
        next_action TEXT,
        follow_up_date TEXT,
        created_by TEXT,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES clientes(id)
      )
    ''');

    await crearBacklogComercial(db);

    await crearOpportunityItems(db);

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_contacts_account ON crm_contacts(company_id, account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_leads_status ON crm_leads(company_id, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_opportunities_account ON crm_opportunities(company_id, account_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_interactions_customer ON crm_interactions(company_id, customer_id, interaction_date)',
    );
  }

  static Future<void> crearBacklogComercial(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_campaigns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        campaign_type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'planned',
        start_date TEXT NOT NULL,
        end_date TEXT,
        budget INTEGER NOT NULL DEFAULT 0,
        expected_revenue INTEGER NOT NULL DEFAULT 0,
        assigned_user_id INTEGER,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_territories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        country TEXT,
        department TEXT,
        city TEXT,
        sector TEXT,
        assigned_user_id INTEGER,
        active INTEGER NOT NULL DEFAULT 1,
        entity_type TEXT NOT NULL DEFAULT 'comercial',
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_campaigns_company_status ON crm_campaigns(company_id, status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_territories_company_user ON crm_territories(company_id, assigned_user_id)',
    );
    await _agregarColumnaSiNoExiste(db, 'crm_leads', 'campaign_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(db, 'crm_leads', 'territory_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(db, 'clientes', 'territory_id', 'INTEGER');
    await _agregarColumnaSiNoExiste(
      db,
      'crm_opportunities',
      'campaign_id',
      'INTEGER',
    );
    await _agregarColumnaSiNoExiste(
      db,
      'crm_opportunities',
      'territory_id',
      'INTEGER',
    );
  }

  /// Product lines are an extension of the canonical opportunity table. They
  /// reference the existing inventory catalog instead of duplicating products.
  static Future<void> crearOpportunityItems(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS crm_opportunity_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        opportunity_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        uom TEXT NOT NULL DEFAULT 'UND',
        unit_price INTEGER NOT NULL DEFAULT 0,
        amount INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        modified_at TEXT,
        FOREIGN KEY (opportunity_id) REFERENCES crm_opportunities(id),
        FOREIGN KEY (product_id) REFERENCES productos(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_crm_opportunity_items_opportunity '
      'ON crm_opportunity_items(company_id, opportunity_id)',
    );
  }

  static Future<void> _agregarColumnaSiNoExiste(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final exists = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    if (exists.isEmpty) return;
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
