import 'dart:convert';

import '../../core/events/domain_event.dart';
import '../../core/currency/money_value.dart';
import '../../core/security/action_permission.dart';
import '../../sync/application/sync_orchestrator.dart';
import '../../sync/domain/sync_models.dart';
import '../../telemetry/application/telemetry_service.dart';
import '../data/final_enterprise_repository.dart';
import '../domain/final_enterprise_contexts.dart';

class FinalEnterpriseCommandHandlers {
  FinalEnterpriseCommandHandlers({
    required FinalEnterpriseRepository repository,
    required DomainEventPublisher events,
    PermissionService? permissions,
    TelemetryService? telemetry,
    SyncOrchestrator? sync,
  }) : _repository = repository,
       _events = events,
       _permissions = permissions ?? PermissionService.instance,
       _telemetry = telemetry ?? TelemetryService(),
       _sync = sync;

  final FinalEnterpriseRepository _repository;
  final DomainEventPublisher _events;
  final PermissionService _permissions;
  final TelemetryService _telemetry;
  final SyncOrchestrator? _sync;
  Future<dynamic>? _currencyFuture;

  Future<MoneyValue> _money(Object? value) async {
    final currency = await (_currencyFuture ??= _repository.currency());
    return MoneyValue.fromMajorUnits(
      value?.toString() ?? '0',
      currency: currency,
    );
  }

  Future<MoneyValue> _moneySql(Object? value) async {
    final currency = await (_currencyFuture ??= _repository.currency());
    return MoneyValue.fromSql(value, currency: currency, nullableAsZero: true);
  }

  Future<Map<String, Object?>> collectReceivable(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
    String? correlationId,
  }) async {
    _assert(role, 'accounts_receivable', AppAction.collect);
    final scope = await _repository.scope();
    final customerId = _int(body['customer_id']);
    final amount = await _money(body['amount']);
    final profile = await _creditProfile(customerId);
    final updated = profile.collect(amount);
    await _upsertCreditProfile(updated);
    final entryId = await _repository.insertScoped('ar_ledger_entries', {
      'customer_id': customerId,
      'customer': body['customer']?.toString() ?? 'Cliente',
      'document_id': body['document_id']?.toString() ?? 'manual',
      'document_type': 'collection',
      'side': LedgerSide.credit.name,
      'amount': amount.toSql(),
      'open_amount': 0,
      'due_date':
          _date(body['date'])?.toIso8601String() ??
          DateTime.now().toIso8601String(),
      'occurred_at': DateTime.now().toIso8601String(),
      'description': body['description']?.toString() ?? 'Recaudo cartera',
    });
    await _repository.audit(
      action: 'ar.collect',
      entity: 'ar_ledger_entries',
      entityId: entryId,
      userId: userId,
      payload: {'amount': amount.toWireMap(), 'customer_id': customerId},
    );
    await _events.publish(
      InvoicePaidEvent(
        customerId: customerId,
        amount: amount,
        companyId: scope.companyId,
        branchId: scope.branchId,
        correlationId: correlationId,
      ),
    );
    await _syncRecord('accounts_receivable', '$entryId', {
      'amount': amount.toWireMap(),
    });
    _telemetry.log(
      name: 'ar.collection.applied',
      attributes: {'customer_id': customerId, 'amount': amount.toSql()},
    );
    return {'ledger_entry_id': entryId, 'credit_profile': updated.toMap()};
  }

  Future<Map<String, Object?>> overrideCreditLimit(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'accounts_receivable', AppAction.overrideLimit);
    final customerId = _int(body['customer_id']);
    final current = await _creditProfile(customerId);
    final updated = CreditRiskProfile(
      partyId: customerId,
      limit: await _money(body['limit']),
      balance: current.balance,
      riskScore: _double(body['risk_score'] ?? current.riskScore),
      blocked: _bool(body['blocked']),
    );
    await _upsertCreditProfile(updated);
    if (updated.shouldBlock) {
      final scope = await _repository.scope();
      await _events.publish(
        CustomerBlockedEvent(
          customerId: customerId,
          balance: updated.balance,
          companyId: scope.companyId,
          branchId: scope.branchId,
          reason: 'credit_policy',
        ),
      );
    }
    await _repository.audit(
      action: 'ar.override_limit',
      entity: 'customer_credit_profiles',
      userId: userId,
      payload: updated.toMap(),
    );
    return updated.toMap();
  }

  Future<Map<String, Object?>> promisePayment(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'accounts_receivable', AppAction.collect);
    final id = await _repository.insertScoped('ar_payment_promises', {
      'customer_id': _int(body['customer_id']),
      'customer': body['customer']?.toString() ?? 'Cliente',
      'amount': (await _money(body['amount'])).toSql(),
      'promise_date': (_date(body['promise_date']) ?? DateTime.now())
          .toIso8601String(),
      'status': 'open',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repository.audit(
      action: 'ar.promise_payment',
      entity: 'ar_payment_promises',
      entityId: id,
      userId: userId,
      payload: body,
    );
    return {'promise_id': id};
  }

  Future<Map<String, Object?>> schedulePayable(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'accounts_payable', AppAction.schedulePayment);
    final schedule = PaymentSchedule(
      id: _id('ap'),
      partyId: _int(body['supplier_id']),
      partyName: body['supplier']?.toString() ?? 'Proveedor',
      amount: await _money(body['amount']),
      dueDate: _date(body['due_date']) ?? DateTime.now(),
      sourceDocumentId: body['document_id']?.toString(),
    );
    await _repository.insertScoped('ap_payment_schedules', {
      ...schedule.toMap(),
      'payload_json': jsonEncode(body),
    });
    await _repository.audit(
      action: 'ap.schedule_payment',
      entity: 'ap_payment_schedules',
      userId: userId,
      payload: schedule.toMap(),
    );
    await _syncRecord('accounts_payable', schedule.id, schedule.toMap());
    return schedule.toMap();
  }

  Future<Map<String, Object?>> payPayable(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'accounts_payable', AppAction.approvePayment);
    final amount = await _money(body['amount']);
    final id = await _repository.insertScoped('ap_supplier_ledger', {
      'supplier_id': _int(body['supplier_id']),
      'supplier': body['supplier']?.toString() ?? 'Proveedor',
      'document_id': body['document_id']?.toString() ?? 'manual',
      'document_type': 'payment',
      'side': LedgerSide.debit.name,
      'amount': amount.toSql(),
      'open_amount': 0,
      'due_date': DateTime.now().toIso8601String(),
      'occurred_at': DateTime.now().toIso8601String(),
      'description': body['description']?.toString() ?? 'Pago proveedor',
    });
    await _repository.audit(
      action: 'ap.pay',
      entity: 'ap_supplier_ledger',
      entityId: id,
      userId: userId,
      payload: {'amount': amount.toWireMap()},
    );
    _telemetry.log(
      name: 'ap.payment.applied',
      attributes: {'amount': amount.toSql()},
    );
    return {'ledger_entry_id': id};
  }

  Future<Map<String, Object?>> createBankAccount(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'treasury', AppAction.transfer);
    final id = await _repository.insertScoped('treasury_bank_accounts', {
      'name': body['name']?.toString() ?? 'Banco',
      'bank_name': body['bank_name']?.toString() ?? 'Banco',
      'account_number': body['account_number']?.toString() ?? '',
      'currency': body['currency']?.toString() ?? 'COP',
      'balance': (await _money(body['balance'])).toSql(),
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repository.audit(
      action: 'treasury.bank_account.create',
      entity: 'treasury_bank_accounts',
      entityId: id,
      userId: userId,
      payload: body,
    );
    return {'bank_account_id': id};
  }

  Future<Map<String, Object?>> createTreasuryTransfer(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
    String? correlationId,
  }) async {
    _assert(role, 'treasury', AppAction.transfer);
    final scope = await _repository.scope();
    final transfer = TreasuryTransfer(
      id: _id('trf'),
      fromAccountId: _int(body['from_account_id']),
      toAccountId: _int(body['to_account_id']),
      amount: await _money(body['amount']),
      requestedBy: userId,
      createdAt: DateTime.now(),
      approved: _bool(body['approved']),
    );
    await _repository.insertScoped('treasury_transfers', transfer.toMap());
    await _repository.insertScoped('treasury_bank_movements', {
      'bank_account_id': transfer.fromAccountId,
      'direction': 'out',
      'amount': transfer.amount.toSql(),
      'reference': transfer.id,
      'movement_date': transfer.createdAt.toIso8601String(),
      'reconciled': 0,
    });
    await _repository.insertScoped('treasury_bank_movements', {
      'bank_account_id': transfer.toAccountId,
      'direction': 'in',
      'amount': transfer.amount.toSql(),
      'reference': transfer.id,
      'movement_date': transfer.createdAt.toIso8601String(),
      'reconciled': 0,
    });
    await _events.publish(
      TreasuryTransferCreatedEvent(
        transferId: transfer.id,
        amount: transfer.amount,
        companyId: scope.companyId,
        branchId: scope.branchId,
        correlationId: correlationId,
      ),
    );
    await _repository.audit(
      action: 'treasury.transfer',
      entity: 'treasury_transfers',
      userId: userId,
      payload: transfer.toMap(),
    );
    await _syncRecord('treasury_transfer', transfer.id, transfer.toMap());
    return transfer.toMap();
  }

  Future<Map<String, Object?>> importBankStatement(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'bank_reconciliation', AppAction.reconcile);
    final statementId = _id('stmt');
    await _repository.insertScoped('bank_statements', {
      'statement_id': statementId,
      'bank_account_id': _int(body['bank_account_id']),
      'statement_date': (_date(body['statement_date']) ?? DateTime.now())
          .toIso8601String(),
      'status': 'imported',
      'created_at': DateTime.now().toIso8601String(),
    });
    for (final item in _list(body['lines'])) {
      final line = _map(item);
      await _repository.insertScoped('bank_statement_lines', {
        'statement_id': statementId,
        'bank_account_id': _int(body['bank_account_id']),
        'reference': line['reference']?.toString() ?? '',
        'description': line['description']?.toString() ?? '',
        'amount': (await _money(line['amount'])).toSql(),
        'movement_date': (_date(line['movement_date']) ?? DateTime.now())
            .toIso8601String(),
        'matched_movement_id': null,
        'status': 'unmatched',
      });
    }
    await _repository.audit(
      action: 'bank.statement.import',
      entity: 'bank_statements',
      userId: userId,
      payload: {'statement_id': statementId},
    );
    return {'statement_id': statementId};
  }

  Future<Map<String, Object?>> reconcileBank(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'bank_reconciliation', AppAction.reconcile);
    final scope = await _repository.scope();
    final statementId = body['statement_id']?.toString() ?? '';
    final lines = await _repository.queryScoped(
      'bank_statement_lines',
      where: 'statement_id = ? AND status = ?',
      whereArgs: [statementId, 'unmatched'],
    );
    var matched = 0;
    for (final line in lines) {
      final movements = await _repository.queryScoped(
        'treasury_bank_movements',
        where:
            'bank_account_id = ? AND ABS(amount - ?) < 1 AND reference = ? AND reconciled = 0',
        whereArgs: [
          line['bank_account_id'],
          (line['amount'] as num?)?.toInt() ?? 0,
          line['reference']?.toString() ?? '',
        ],
        limit: 1,
      );
      if (movements.isNotEmpty) {
        matched++;
        await _repository.updateScoped(
          'bank_statement_lines',
          {'matched_movement_id': movements.first['id'], 'status': 'matched'},
          where: 'id = ?',
          whereArgs: [line['id']],
        );
        await _repository.updateScoped(
          'treasury_bank_movements',
          {'reconciled': 1},
          where: 'id = ?',
          whereArgs: [movements.first['id']],
        );
      }
    }
    final reconciliationId = _id('rec');
    await _repository.insertScoped('bank_reconciliations', {
      'reconciliation_id': reconciliationId,
      'statement_id': statementId,
      'matched_count': matched,
      'status': matched == lines.length
          ? ReconciliationStatus.reconciled.name
          : ReconciliationStatus.exception.name,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _events.publish(
      BankReconciledEvent(
        reconciliationId: reconciliationId,
        matched: matched,
        companyId: scope.companyId,
        branchId: scope.branchId,
      ),
    );
    await _repository.audit(
      action: 'bank.reconcile',
      entity: 'bank_reconciliations',
      userId: userId,
      payload: {'statement_id': statementId, 'matched': matched},
    );
    return {'reconciliation_id': reconciliationId, 'matched': matched};
  }

  Future<Map<String, Object?>> configureTaxRule(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'tax', AppAction.configure);
    final rule = TaxRule(
      code: body['code']?.toString() ?? _id('tax'),
      country: body['country']?.toString() ?? 'Colombia',
      documentType: body['document_type']?.toString() ?? 'invoice',
      rate: _double(body['rate']),
      retentionRate: _double(body['retention_rate']),
      exempt: _bool(body['exempt']),
      group: body['group']?.toString() ?? 'default',
    );
    await _repository.insertScoped('enterprise_tax_rules', {
      'code': rule.code,
      'country': rule.country,
      'document_type': rule.documentType,
      'rate': rule.rate,
      'retention_rate': rule.retentionRate,
      'exempt': rule.exempt ? 1 : 0,
      'group_name': rule.group,
      'active': 1,
    });
    await _repository.audit(
      action: 'tax.configure_rule',
      entity: 'enterprise_tax_rules',
      userId: userId,
      payload: rule.toMap(),
    );
    return rule.toMap();
  }

  Future<Map<String, Object?>> calculateTax(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
    String? correlationId,
  }) async {
    _assert(role, 'tax', AppAction.view);
    final scope = await _repository.scope();
    final documentType = body['document_type']?.toString() ?? 'invoice';
    final country = body['country']?.toString() ?? 'Colombia';
    final rules = await _repository.queryScoped(
      'enterprise_tax_rules',
      where: 'country = ? AND document_type = ? AND active = 1',
      whereArgs: [country, documentType],
      orderBy: 'id DESC',
      limit: 1,
    );
    final rule = rules.isEmpty
        ? const TaxRule(
            code: 'EXEMPT_CONFIGURED',
            country: 'GLOBAL',
            documentType: 'invoice',
            rate: 0,
            exempt: true,
          )
        : TaxRule(
            code: rules.first['code']?.toString() ?? 'RULE',
            country: country,
            documentType: documentType,
            rate: (rules.first['rate'] as num?)?.toDouble() ?? 0,
            retentionRate:
                (rules.first['retention_rate'] as num?)?.toDouble() ?? 0,
            exempt: ((rules.first['exempt'] as num?)?.toInt() ?? 0) == 1,
            group: rules.first['group_name']?.toString() ?? 'default',
          );
    final calculation = TaxCalculation(
      documentType: documentType,
      documentId: body['document_id']?.toString() ?? _id('doc'),
      taxableBase: await _money(body['taxable_base']),
      tax: rule.taxFor(await _money(body['taxable_base'])),
      retention: rule.retentionFor(await _money(body['taxable_base'])),
      ruleCode: rule.code,
    );
    final id = await _repository.insertScoped('enterprise_tax_calculations', {
      ...calculation.toMap(),
      'correlation_id': correlationId,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _events.publish(
      IntegrationEvent(
        name: 'TaxCalculatedEvent',
        payload: {
          ...calculation.toMap(),
          'aggregate_type': 'tax_calculation',
          'aggregate_id': '$id',
          'company_id': scope.companyId,
          'branch_id': scope.branchId,
          'correlation_id': correlationId,
        },
      ),
    );
    await _repository.audit(
      action: 'tax.calculate',
      entity: 'enterprise_tax_calculations',
      entityId: id,
      userId: userId,
      payload: calculation.toMap(),
    );
    return calculation.toMap();
  }

  Future<Map<String, Object?>> registerAsset(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'fixed_assets', AppAction.create);
    final asset = FixedAsset(
      id: body['id']?.toString() ?? _id('asset'),
      name: body['name']?.toString() ?? 'Activo',
      cost: await _money(body['cost']),
      usefulLifeMonths: _int(body['useful_life_months'], fallback: 60),
      acquiredAt: _date(body['acquired_at']) ?? DateTime.now(),
      accumulatedDepreciation: await _money(0),
      fiscalDepreciation: await _money(0),
    );
    await _repository.insertScoped('enterprise_fixed_assets', asset.toMap());
    await _repository.audit(
      action: 'assets.register',
      entity: 'enterprise_fixed_assets',
      userId: userId,
      payload: asset.toMap(),
    );
    return asset.toMap();
  }

  Future<Map<String, Object?>> depreciateAsset(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'fixed_assets', AppAction.depreciate);
    final scope = await _repository.scope();
    final assetId = body['asset_id']?.toString() ?? '';
    final rows = await _repository.queryScoped(
      'enterprise_fixed_assets',
      where: 'id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Activo fijo no encontrado.');
    final current = await _assetFromRow(rows.first);
    final depreciated = current.depreciate(
      months: _int(body['months'], fallback: 1),
      fiscalFactor: _double(body['fiscal_factor'] ?? 1),
    );
    await _repository.updateScoped(
      'enterprise_fixed_assets',
      depreciated.toMap(),
      where: 'id = ?',
      whereArgs: [assetId],
    );
    final amount =
        depreciated.accumulatedDepreciation - current.accumulatedDepreciation;
    await _repository.insertScoped('fixed_asset_events', {
      'asset_id': assetId,
      'event_type': 'depreciation',
      'amount': amount.toSql(),
      'payload_json': jsonEncode(depreciated.toMap()),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _events.publish(
      AssetDepreciatedEvent(
        assetId: assetId,
        depreciation: amount,
        companyId: scope.companyId,
        branchId: scope.branchId,
      ),
    );
    await _repository.audit(
      action: 'assets.depreciate',
      entity: 'enterprise_fixed_assets',
      userId: userId,
      payload: depreciated.toMap(),
    );
    return depreciated.toMap();
  }

  Future<Map<String, Object?>> createCrmOpportunity(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'crm', AppAction.managePipeline);
    final opportunity = CrmOpportunity(
      id: body['id']?.toString() ?? _id('opp'),
      customerId: _int(body['customer_id']),
      customerName: body['customer']?.toString() ?? 'Cliente',
      value: await _money(body['value']),
      stage: _stage(body['stage']?.toString()),
      nextFollowUpAt:
          _date(body['next_follow_up_at']) ??
          DateTime.now().add(const Duration(days: 2)),
      owner: userId,
    );
    await _repository.insertScoped('crm_opportunities', opportunity.toMap());
    await _repository.insertScoped('crm_timeline', {
      'customer_id': opportunity.customerId,
      'event_type': 'opportunity_created',
      'payload_json': jsonEncode(opportunity.toMap()),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repository.insertScoped('crm_notifications', {
      'recipient': userId,
      'title': 'Seguimiento comercial',
      'body': 'Proxima actividad para ${opportunity.customerName}',
      'scheduled_at': opportunity.nextFollowUpAt.toIso8601String(),
      'status': 'scheduled',
    });
    await _repository.audit(
      action: 'crm.manage_pipeline',
      entity: 'crm_opportunities',
      userId: userId,
      payload: opportunity.toMap(),
    );
    return opportunity.toMap();
  }

  Future<Map<String, Object?>> defineReport(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'reports', AppAction.configure);
    final definition = EnterpriseReportDefinition(
      id: body['id']?.toString() ?? _id('rpt'),
      name: body['name']?.toString() ?? 'Reporte',
      dataset: body['dataset']?.toString() ?? 'executive',
      filters: _map(body['filters'] ?? const {}),
      formats: _formats(body['formats']),
    );
    await _repository.insertScoped('report_definitions', {
      'id': definition.id,
      'name': definition.name,
      'dataset': definition.dataset,
      'filters_json': jsonEncode(definition.filters),
      'formats_json': jsonEncode(
        definition.formats.map((f) => f.name).toList(),
      ),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repository.audit(
      action: 'reports.define',
      entity: 'report_definitions',
      userId: userId,
      payload: definition.toMap(),
    );
    return definition.toMap();
  }

  Future<Map<String, Object?>> generateReport(
    Map<String, dynamic> body, {
    required String role,
    required String userId,
  }) async {
    _assert(role, 'reports', AppAction.export);
    final scope = await _repository.scope();
    final definitionId = body['definition_id']?.toString() ?? '';
    final definitions = await _repository.queryScoped(
      'report_definitions',
      where: 'id = ?',
      whereArgs: [definitionId],
      limit: 1,
    );
    if (definitions.isEmpty) {
      throw StateError('Definicion de reporte no encontrada.');
    }
    final runId = _id('run');
    final dataset = definitions.first['dataset']?.toString() ?? 'executive';
    final payload = await _reportPayload(dataset);
    final formats = _decodeFormats(definitions.first['formats_json']);
    final exports = formats
        .map(
          (format) => {
            'format': format.name,
            'file_name':
                '$definitionId-$runId.${format.name == 'excel' ? 'xlsx' : format.name}',
            'mime_type': format == ReportFormat.pdf
                ? 'application/pdf'
                : format == ReportFormat.excel
                ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                : 'application/json',
          },
        )
        .toList();
    await _repository.insertScoped('report_runs', {
      'run_id': runId,
      'definition_id': definitionId,
      'dataset': dataset,
      'payload_json': jsonEncode(payload),
      'exports_json': jsonEncode(exports),
      'status': 'generated',
      'created_at': DateTime.now().toIso8601String(),
    });
    await _repository.insertScoped('materialized_reports', {
      'report_key': '$definitionId:$runId',
      'dataset': dataset,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
    await _events.publish(
      ReportGeneratedEvent(
        reportRunId: runId,
        definitionId: definitionId,
        companyId: scope.companyId,
        branchId: scope.branchId,
      ),
    );
    await _repository.audit(
      action: 'reports.export',
      entity: 'report_runs',
      userId: userId,
      payload: {'run_id': runId, 'definition_id': definitionId},
    );
    return {
      'run_id': runId,
      'dataset': dataset,
      'payload': payload,
      'exports': exports,
    };
  }

  Future<Map<String, Object?>> _reportPayload(String dataset) async {
    if (dataset == 'treasury') {
      final accounts = await _repository.queryScoped('treasury_bank_accounts');
      final balance = accounts.fold<double>(
        0,
        (sum, row) => sum + ((row['balance'] as num?)?.toDouble() ?? 0),
      );
      return {'bank_accounts': accounts.length, 'treasury_position': balance};
    }
    if (dataset == 'crm') {
      final opportunities = await _repository.queryScoped('crm_opportunities');
      return {'opportunities': opportunities.length};
    }
    final ar = await _repository.queryScoped('ar_ledger_entries');
    final ap = await _repository.queryScoped('ap_supplier_ledger');
    return {'ar_entries': ar.length, 'ap_entries': ap.length};
  }

  Future<CreditRiskProfile> _creditProfile(int customerId) async {
    final rows = await _repository.queryScoped(
      'customer_credit_profiles',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return CreditRiskProfile(
        partyId: customerId,
        limit: await _money(0),
        balance: await _money(0),
        riskScore: 0,
      );
    }
    final row = rows.first;
    return CreditRiskProfile(
      partyId: customerId,
      limit: await _moneySql(row['credit_limit']),
      balance: await _moneySql(row['balance']),
      riskScore: (row['risk_score'] as num?)?.toDouble() ?? 0,
      blocked: ((row['blocked'] as num?)?.toInt() ?? 0) == 1,
    );
  }

  Future<void> _upsertCreditProfile(CreditRiskProfile profile) async {
    final existing = await _repository.queryScoped(
      'customer_credit_profiles',
      where: 'customer_id = ?',
      whereArgs: [profile.partyId],
      limit: 1,
    );
    final values = {
      'customer_id': profile.partyId,
      'credit_limit': profile.limit.toSql(),
      'balance': profile.balance.toSql(),
      'risk_score': profile.riskScore,
      'blocked': profile.blocked ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (existing.isEmpty) {
      await _repository.insertScoped('customer_credit_profiles', values);
    } else {
      await _repository.updateScoped(
        'customer_credit_profiles',
        values,
        where: 'customer_id = ?',
        whereArgs: [profile.partyId],
      );
    }
  }

  Future<FixedAsset> _assetFromRow(Map<String, Object?> row) async {
    return FixedAsset(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      cost: await _moneySql(row['cost']),
      usefulLifeMonths: (row['useful_life_months'] as num?)?.toInt() ?? 60,
      acquiredAt: _date(row['acquired_at']) ?? DateTime.now(),
      accumulatedDepreciation: await _moneySql(row['accumulated_depreciation']),
      fiscalDepreciation: await _moneySql(row['fiscal_depreciation']),
      status: AssetStatus.values.firstWhere(
        (item) => item.name == row['status']?.toString(),
        orElse: () => AssetStatus.active,
      ),
    );
  }

  Future<void> _syncRecord(
    String aggregateType,
    String aggregateId,
    Map<String, Object?> payload,
  ) async {
    final sync = _sync;
    if (sync == null) return;
    final scope = await _repository.scope();
    await sync.enqueue(
      SyncEnvelope(
        id: '$aggregateType-$aggregateId-${DateTime.now().microsecondsSinceEpoch}',
        companyId: scope.companyId,
        branchId: scope.branchId,
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        operation: SyncOperation.upsert,
        payload: payload,
        occurredAt: DateTime.now(),
        idempotencyKey: '$aggregateType:$aggregateId',
        vectorClock: SyncVectorClock({'branch-${scope.branchId}': 1}),
      ),
    );
  }

  void _assert(String role, String module, AppAction action) {
    if (!_permissions.can(role: role, moduleId: module, action: action)) {
      throw StateError('Permiso insuficiente para $module.${action.name}.');
    }
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  int _int(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  bool _bool(Object? value) {
    final text = value?.toString().toLowerCase().trim();
    return text == '1' || text == 'true' || text == 'yes' || text == 'si';
  }

  DateTime? _date(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  List<Object?> _list(Object? value) => value is List ? value : const [];

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  CrmStage _stage(String? value) {
    return CrmStage.values.firstWhere(
      (stage) => stage.name == value,
      orElse: () => CrmStage.lead,
    );
  }

  List<ReportFormat> _formats(Object? value) {
    final items = _list(value);
    if (items.isEmpty) return const [ReportFormat.json];
    return items
        .map(
          (item) => ReportFormat.values.firstWhere(
            (format) => format.name == item.toString(),
            orElse: () => ReportFormat.json,
          ),
        )
        .toList();
  }

  List<ReportFormat> _decodeFormats(Object? value) {
    if (value == null || value.toString().isEmpty) {
      return const [ReportFormat.json];
    }
    final decoded = jsonDecode(value.toString());
    return _formats(decoded);
  }
}
