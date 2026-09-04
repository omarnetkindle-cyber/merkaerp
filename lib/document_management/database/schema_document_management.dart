import 'package:sqflite/sqflite.dart';

class SchemaDocumentManagement {
  const SchemaDocumentManagement._();

  static Future<void> createTables(DatabaseExecutor db) async {
    final statements = <String>[
      '''
      CREATE TABLE IF NOT EXISTS gd_settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        setting_key TEXT NOT NULL,
        setting_value TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        updated_by TEXT,
        UNIQUE(company_id, setting_key)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_dependencies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        parent_id INTEGER,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_correspondents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        document_type TEXT,
        document_number TEXT,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        address TEXT,
        city TEXT,
        kind TEXT NOT NULL DEFAULT 'external',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_trd_versions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        version_code TEXT NOT NULL,
        description TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        adoption_act TEXT,
        adoption_date TEXT,
        convalidation_act TEXT,
        convalidation_date TEXT,
        rusd_certificate TEXT,
        effective_from TEXT,
        effective_to TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, version_code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_series(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        dependency_id INTEGER,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, dependency_id, code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_subseries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        series_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, series_id, code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_document_types(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        code TEXT,
        description TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, name)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_trd_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        trd_version_id INTEGER NOT NULL,
        dependency_id INTEGER,
        series_id INTEGER NOT NULL,
        subseries_id INTEGER,
        document_type_id INTEGER,
        management_retention_years INTEGER NOT NULL DEFAULT 0,
        central_retention_years INTEGER NOT NULL DEFAULT 0,
        final_disposition TEXT NOT NULL DEFAULT 'selection',
        medium TEXT NOT NULL DEFAULT 'mixed',
        procedure TEXT,
        essential INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_tvd_versions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        version_code TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        adoption_act TEXT,
        adoption_date TEXT,
        convalidation_act TEXT,
        convalidation_date TEXT,
        rusd_certificate TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, version_code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_tvd_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        tvd_version_id INTEGER NOT NULL,
        source_office TEXT,
        series_name TEXT NOT NULL,
        subseries_name TEXT,
        start_year INTEGER,
        end_year INTEGER,
        central_retention_years INTEGER NOT NULL DEFAULT 0,
        final_disposition TEXT NOT NULL DEFAULT 'selection',
        procedure TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_instruments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        instrument_key TEXT NOT NULL,
        name TEXT NOT NULL,
        version_code TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        adoption_act TEXT,
        adoption_date TEXT,
        responsible_dependency TEXT,
        file_path TEXT,
        file_hash TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, instrument_key)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_non_working_days(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        day TEXT NOT NULL,
        description TEXT,
        recurring INTEGER NOT NULL DEFAULT 0,
        UNIQUE(company_id, day)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_sequences(
        company_id INTEGER NOT NULL,
        sequence_key TEXT NOT NULL,
        year INTEGER NOT NULL,
        current_value INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY(company_id, sequence_key, year)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_radicados(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        number TEXT NOT NULL,
        direction TEXT NOT NULL,
        document_class TEXT NOT NULL DEFAULT 'correspondence',
        subject TEXT NOT NULL,
        description TEXT,
        correspondent_id INTEGER,
        sender_name TEXT,
        recipient_name TEXT,
        channel TEXT NOT NULL DEFAULT 'digital',
        received_at TEXT NOT NULL,
        due_at TEXT,
        term_business_days INTEGER,
        priority TEXT NOT NULL DEFAULT 'normal',
        access_level TEXT NOT NULL DEFAULT 'public',
        status TEXT NOT NULL DEFAULT 'registered',
        assigned_dependency_id INTEGER,
        assigned_user_id TEXT,
        response_to_id INTEGER,
        closed_at TEXT,
        archived_at TEXT,
        physical_location_id INTEGER,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, number)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_workflow_events(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        radicado_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        from_status TEXT,
        to_status TEXT,
        from_dependency_id INTEGER,
        to_dependency_id INTEGER,
        from_user_id TEXT,
        to_user_id TEXT,
        comment TEXT,
        actor_user_id TEXT,
        created_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_expedientes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        code TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        dependency_id INTEGER,
        series_id INTEGER,
        subseries_id INTEGER,
        trd_entry_id INTEGER,
        status TEXT NOT NULL DEFAULT 'open',
        access_level TEXT NOT NULL DEFAULT 'public',
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        transfer_due_at TEXT,
        disposition_due_at TEXT,
        current_archive_stage TEXT NOT NULL DEFAULT 'management',
        physical_location_id INTEGER,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(company_id, code)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_documents(
        id TEXT PRIMARY KEY,
        company_id INTEGER NOT NULL,
        radicado_id INTEGER,
        expediente_id INTEGER,
        logical_document_id TEXT NOT NULL,
        document_type_id INTEGER,
        title TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        mime_type TEXT,
        size_bytes INTEGER NOT NULL,
        sha256 TEXT NOT NULL,
        version_number INTEGER NOT NULL DEFAULT 1,
        is_original INTEGER NOT NULL DEFAULT 1,
        is_signed INTEGER NOT NULL DEFAULT 0,
        signature_provider TEXT,
        signature_metadata_json TEXT,
        access_level TEXT NOT NULL DEFAULT 'public',
        retention_frozen INTEGER NOT NULL DEFAULT 0,
        created_by TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(company_id, logical_document_id, version_number)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_expediente_documents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        expediente_id INTEGER NOT NULL,
        document_id TEXT NOT NULL,
        order_number INTEGER NOT NULL,
        included_at TEXT NOT NULL,
        included_by TEXT,
        UNIQUE(company_id, expediente_id, document_id)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_expediente_radicados(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        expediente_id INTEGER NOT NULL,
        radicado_id INTEGER NOT NULL,
        relation_type TEXT NOT NULL DEFAULT 'related',
        included_at TEXT NOT NULL,
        included_by TEXT,
        UNIQUE(company_id, expediente_id, radicado_id)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_entity_links(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        radicado_id INTEGER,
        expediente_id INTEGER,
        document_id TEXT,
        created_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_physical_locations(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        archive_stage TEXT NOT NULL DEFAULT 'management',
        building TEXT,
        room TEXT,
        shelf TEXT,
        body TEXT,
        tray TEXT,
        box_code TEXT,
        folder_code TEXT,
        label TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        expediente_id INTEGER,
        document_id TEXT,
        borrower_user_id TEXT NOT NULL,
        borrower_name TEXT,
        purpose TEXT NOT NULL,
        loaned_at TEXT NOT NULL,
        due_at TEXT NOT NULL,
        returned_at TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        authorized_by TEXT,
        created_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_transfers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        transfer_number TEXT NOT NULL,
        transfer_type TEXT NOT NULL,
        from_stage TEXT NOT NULL,
        to_stage TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'draft',
        inventory_reference TEXT,
        act_reference TEXT,
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        completed_at TEXT,
        requested_by TEXT,
        approved_by TEXT,
        notes TEXT,
        UNIQUE(company_id, transfer_number)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_transfer_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        transfer_id INTEGER NOT NULL,
        expediente_id INTEGER NOT NULL,
        accepted INTEGER,
        observation TEXT,
        UNIQUE(company_id, transfer_id, expediente_id)
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_disposition_actions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        expediente_id INTEGER NOT NULL,
        disposition TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'proposed',
        committee_act TEXT,
        elimination_act TEXT,
        authorization_reference TEXT,
        executed_at TEXT,
        executed_by TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )''',
      '''
      CREATE TABLE IF NOT EXISTS gd_access_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_id INTEGER NOT NULL,
        resource_type TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT,
        reason TEXT,
        created_at TEXT NOT NULL
      )''',
    ];

    for (final statement in statements) {
      await db.execute(statement);
    }

    final indexes = <String>[
      'CREATE INDEX IF NOT EXISTS idx_gd_radicados_company_status ON gd_radicados(company_id, status, received_at)',
      'CREATE INDEX IF NOT EXISTS idx_gd_radicados_assigned ON gd_radicados(company_id, assigned_user_id, assigned_dependency_id, status)',
      'CREATE INDEX IF NOT EXISTS idx_gd_radicados_due ON gd_radicados(company_id, due_at, status)',
      'CREATE INDEX IF NOT EXISTS idx_gd_workflow_radicado ON gd_workflow_events(company_id, radicado_id, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_gd_expedientes_company ON gd_expedientes(company_id, status, current_archive_stage)',
      'CREATE INDEX IF NOT EXISTS idx_gd_documents_radicado ON gd_documents(company_id, radicado_id)',
      'CREATE INDEX IF NOT EXISTS idx_gd_documents_expediente ON gd_documents(company_id, expediente_id)',
      'CREATE INDEX IF NOT EXISTS idx_gd_case_radicados_case ON gd_expediente_radicados(company_id, expediente_id, radicado_id)',
      'CREATE INDEX IF NOT EXISTS idx_gd_entity_links ON gd_entity_links(company_id, entity_type, entity_id)',
      'CREATE INDEX IF NOT EXISTS idx_gd_loans_due ON gd_loans(company_id, status, due_at)',
    ];
    for (final index in indexes) {
      await db.execute(index);
    }
  }
}
