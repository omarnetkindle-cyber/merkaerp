import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:merka_erp/core/currency/currency.dart';
import 'package:merka_erp/core/currency/money_value.dart';
import 'package:merka_erp/crm/application/crm_account_service.dart';
import 'package:merka_erp/crm/application/crm_contact_service.dart';
import 'package:merka_erp/crm/application/crm_interaction_service.dart';
import 'package:merka_erp/crm/application/crm_lead_service.dart';
import 'package:merka_erp/crm/application/crm_opportunity_service.dart';
import 'package:merka_erp/crm/application/crm_opportunity_item_service.dart';
import 'package:merka_erp/crm/domain/crm_account.dart';
import 'package:merka_erp/crm/domain/crm_contact.dart';
import 'package:merka_erp/crm/domain/crm_lead.dart';
import 'package:merka_erp/crm/domain/crm_opportunity.dart';
import 'package:merka_erp/crm/domain/crm_opportunity_item.dart';
import 'package:merka_erp/crm/domain/customer_interaction.dart';
import 'package:merka_erp/db_helper.dart';
import 'package:merka_erp/features/company_configuration_service.dart';

void main() {
  late Directory dbDir;
  late Database db;
  late int companyId;
  late Currency cop;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseHelper.resetForTests();
    CompanyConfigurationService.instance.resetForTests();
    dbDir = await Directory.systemTemp.createTemp('merkaerp_crm_module_');
    await databaseFactory.setDatabasesPath(dbDir.path);
    db = await DatabaseHelper.instance.database;
    companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
    await DatabaseHelper.instance.guardarCompanySettings(companyId, {
      'onboarding_completed': '1',
      'country': 'Colombia',
      'currency': 'COP',
      'timezone': 'America/Bogota',
    });
    cop = Currency(
      code: 'COP',
      name: 'Colombian Peso',
      symbol: r'$',
      decimalPlaces: 2,
    );
  });

  tearDownAll(() async {
    await DatabaseHelper.resetForTests();
    await dbDir.delete(recursive: true);
  });

  test('CrmAccount usa clientes y conserva la bandera de entidad', () async {
    final accountId = await CrmAccountService().create(
      CrmAccount(
        companyId: companyId,
        name: 'Cuenta CRM de prueba',
        entityType: 'comercial',
      ),
    );
    final account = await CrmAccountService().findById(accountId);

    expect(account?.name, 'Cuenta CRM de prueba');
    expect(account?.entityType, 'comercial');
    expect(
      (await db.query(
        'clientes',
        where: 'id = ?',
        whereArgs: [accountId],
      )).single['entity_type'],
      'comercial',
    );
  });

  test('CrmContact queda relacionado con una cuenta existente', () async {
    final accountId = await CrmAccountService().create(
      CrmAccount(companyId: companyId, name: 'Cuenta contacto'),
    );
    final contactId = await CrmContactService().create(
      CrmContact(
        companyId: companyId,
        accountId: accountId,
        firstName: 'Ana',
        lastName: 'Contacto',
        email: 'ana@example.test',
      ),
    );
    final contacts = await CrmContactService().listForAccount(accountId);

    expect(contactId, greaterThan(0));
    expect(contacts.single.firstName, 'Ana');
    expect(contacts.single.accountId, accountId);
  });

  test('CRM valida cuentas padre, nombres y montos cero', () async {
    final parentId = await CrmAccountService().create(
      CrmAccount(companyId: companyId, name: 'Cuenta padre'),
    );
    final childId = await CrmAccountService().create(
      CrmAccount(companyId: companyId, name: 'Cuenta hija', parentId: parentId),
    );
    expect(childId, greaterThan(parentId));
    await expectLater(
      () => CrmAccountService().create(
        CrmAccount(companyId: companyId, name: ''),
      ),
      throwsArgumentError,
    );
    await expectLater(
      () => CrmAccountService().create(
        CrmAccount(
          companyId: companyId,
          name: 'Cuenta huerfana',
          parentId: 999999,
        ),
      ),
      throwsStateError,
    );

    final opportunityId = await CrmOpportunityService().create(
      CrmOpportunity(
        id: 'crm-zero-${DateTime.now().microsecondsSinceEpoch}',
        companyId: companyId,
        accountId: childId,
        accountName: 'Cuenta hija',
        name: 'Oportunidad sin monto',
        amount: MoneyValue(minorUnits: 0, currency: cop),
        salesStage: CrmSalesStage.prospecting,
        nextFollowUpAt: DateTime(2026, 8, 25),
      ),
    );
    expect(opportunityId, isNotEmpty);
  });

  test(
    'las lineas de oportunidad usan el catalogo y calculan total exacto',
    () async {
      final accountId = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cuenta con productos'),
      );
      final opportunityId = await CrmOpportunityService().create(
        CrmOpportunity(
          id: 'crm-line-${DateTime.now().microsecondsSinceEpoch}',
          companyId: companyId,
          accountId: accountId,
          accountName: 'Cuenta con productos',
          name: 'Venta de productos',
          amount: MoneyValue(minorUnits: 25000, currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 25),
        ),
      );
      final productId = await db.insert('productos', {
        'company_id': companyId,
        'nombre': 'Producto CRM linea',
        'unidad_base': 'UND',
        'stock': 10,
        'costo': 5000,
        'precio': 10000,
      });
      await CrmOpportunityItemService().save(
        CrmOpportunityItem(
          companyId: companyId,
          opportunityId: opportunityId,
          productId: productId,
          quantity: 2.5,
          unitPrice: MoneyValue.fromMajorUnits('100.00', currency: cop),
        ),
      );
      final lines = await CrmOpportunityItemService().listForOpportunity(
        opportunityId,
      );
      expect(lines, hasLength(1));
      expect(lines.single.amount.minorUnits, 25000);
    },
  );

  test(
    'CRM rechaza supervisor de otra cuenta y conserva contacto sin supervisor',
    () async {
      final firstAccount = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cuenta uno'),
      );
      final secondAccount = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cuenta dos'),
      );
      final managerId = await CrmContactService().create(
        CrmContact(
          companyId: companyId,
          accountId: firstAccount,
          firstName: 'Supervisora',
        ),
      );
      final contactId = await CrmContactService().create(
        CrmContact(
          companyId: companyId,
          accountId: secondAccount,
          firstName: 'Contacto independiente',
        ),
      );
      expect(contactId, greaterThan(0));
      await expectLater(
        () => CrmContactService().create(
          CrmContact(
            companyId: companyId,
            accountId: secondAccount,
            firstName: 'Contacto invalido',
            reportsToId: managerId,
          ),
        ),
        throwsStateError,
      );
    },
  );

  test('Lead se convierte atomica y unicamente una vez', () async {
    final leadId = await CrmLeadService().create(
      CrmLead(
        companyId: companyId,
        accountName: 'Cuenta desde lead',
        leadSource: 'web',
        opportunityAmount: MoneyValue.fromMajorUnits('1250', currency: cop),
      ),
    );
    final result = await CrmLeadService().convert(
      leadId: leadId,
      account: CrmAccount(companyId: companyId, name: 'Cuenta desde lead'),
      contact: CrmContact(
        companyId: companyId,
        accountId: 0,
        firstName: 'Luis',
        lastName: 'Prospecto',
      ),
      opportunity: CrmOpportunity(
        id: '',
        companyId: companyId,
        accountId: 0,
        accountName: 'Cuenta desde lead',
        name: 'Oportunidad convertida',
        amount: MoneyValue.fromMajorUnits('1250', currency: cop),
        salesStage: CrmSalesStage.prospecting,
        nextFollowUpAt: DateTime(2026, 8, 20),
      ),
    );

    final lead = await CrmLeadService().findById(leadId);
    final accounts = await db.query(
      'clientes',
      where: 'id = ?',
      whereArgs: [result.accountId],
    );
    final contacts = await db.query(
      'crm_contacts',
      where: 'id = ?',
      whereArgs: [result.contactId],
    );
    final opportunities = await db.query(
      'crm_opportunities',
      where: 'id = ?',
      whereArgs: [result.opportunityId],
    );

    expect(lead?.converted, isTrue);
    expect(lead?.convertedAccountId, result.accountId);
    expect(accounts, hasLength(1));
    expect(contacts.single['account_id'], result.accountId);
    expect(opportunities.single['account_id'], result.accountId);
    await expectLater(
      () => CrmLeadService().convert(
        leadId: leadId,
        account: CrmAccount(companyId: companyId, name: 'Duplicada'),
        contact: CrmContact(
          companyId: companyId,
          accountId: 0,
          firstName: 'Duplicado',
        ),
        opportunity: CrmOpportunity(
          id: '',
          companyId: companyId,
          accountId: 0,
          accountName: 'Duplicada',
          name: 'Duplicada',
          amount: MoneyValue(minorUnits: 0, currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 20),
        ),
      ),
      throwsStateError,
    );
  });

  test('La conversion de lead hace rollback si falla la oportunidad', () async {
    final conflictId = 'crm-conflict-${DateTime.now().microsecondsSinceEpoch}';
    final accountId = await CrmAccountService().create(
      CrmAccount(companyId: companyId, name: 'Cuenta conflicto existente'),
    );
    await CrmOpportunityService().create(
      CrmOpportunity(
        id: conflictId,
        companyId: companyId,
        accountId: accountId,
        accountName: 'Cuenta conflicto existente',
        name: 'Oportunidad que ocupa el id',
        amount: MoneyValue(minorUnits: 0, currency: cop),
        salesStage: CrmSalesStage.prospecting,
        nextFollowUpAt: DateTime(2026, 8, 20),
      ),
    );
    final leadId = await CrmLeadService().create(
      CrmLead(
        companyId: companyId,
        accountName: 'Cuenta rollback',
        opportunityAmount: MoneyValue(minorUnits: 0, currency: cop),
      ),
    );

    await expectLater(
      () => CrmLeadService().convert(
        leadId: leadId,
        account: CrmAccount(companyId: companyId, name: 'Cuenta rollback'),
        contact: CrmContact(
          companyId: companyId,
          accountId: 0,
          firstName: 'Contacto rollback',
        ),
        opportunity: CrmOpportunity(
          id: conflictId,
          companyId: companyId,
          accountId: 0,
          accountName: 'Cuenta rollback',
          name: 'Oportunidad rollback',
          amount: MoneyValue(minorUnits: 0, currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 20),
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      await db.query(
        'clientes',
        where: 'nombre = ?',
        whereArgs: ['Cuenta rollback'],
      ),
      isEmpty,
    );
    expect(
      await db.query(
        'crm_contacts',
        where: 'first_name = ?',
        whereArgs: ['Contacto rollback'],
      ),
      isEmpty,
    );
    expect((await CrmLeadService().findById(leadId))?.converted, isFalse);
  });

  test('Lead marcado no convertible no crea entidades', () async {
    final leadId = await CrmLeadService().create(
      CrmLead(
        companyId: companyId,
        accountName: 'Lead rechazado',
        status: 'no_convertible',
        opportunityAmount: MoneyValue(minorUnits: 0, currency: cop),
      ),
    );
    await expectLater(
      () => CrmLeadService().convert(
        leadId: leadId,
        account: CrmAccount(companyId: companyId, name: 'No debe crear'),
        contact: CrmContact(
          companyId: companyId,
          accountId: 0,
          firstName: 'No',
        ),
        opportunity: CrmOpportunity(
          id: '',
          companyId: companyId,
          accountId: 0,
          accountName: 'No debe crear',
          name: 'No debe crear',
          amount: MoneyValue(minorUnits: 0, currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 20),
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'Las siete etapas tienen probabilidad automatica y no se puede retroceder',
    () async {
      expect(CrmSalesStage.values.map((stage) => stage.probability).toList(), [
        10,
        25,
        40,
        55,
        75,
        100,
        0,
      ]);
      final accountId = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cuenta etapas'),
      );
      final opportunityId = await CrmOpportunityService().create(
        CrmOpportunity(
          id: 'crm-stages-${DateTime.now().microsecondsSinceEpoch}',
          companyId: companyId,
          accountId: accountId,
          accountName: 'Cuenta etapas',
          name: 'Oportunidad etapas',
          amount: MoneyValue(minorUnits: 0, currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 20),
        ),
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.closedLost,
      );
      expect(
        (await CrmOpportunityService().findById(
          opportunityId,
        ))?.effectiveProbability,
        0,
      );
      await expectLater(
        () => CrmOpportunityService().moveToStage(
          opportunityId,
          CrmSalesStage.prospecting,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Opportunity aplica probabilidad y enlaza Closed Won con ventas',
    () async {
      final accountId = await CrmAccountService().create(
        CrmAccount(companyId: companyId, name: 'Cuenta oportunidad'),
      );
      final opportunityId = await CrmOpportunityService().create(
        CrmOpportunity(
          id: 'crm-test-${DateTime.now().microsecondsSinceEpoch}',
          companyId: companyId,
          accountId: accountId,
          accountName: 'Cuenta oportunidad',
          name: 'Venta futura',
          amount: MoneyValue.fromMajorUnits('3000', currency: cop),
          salesStage: CrmSalesStage.prospecting,
          nextFollowUpAt: DateTime(2026, 8, 21),
        ),
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.qualification,
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.needsAnalysis,
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.valueProposition,
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.negotiationReview,
      );
      await CrmOpportunityService().moveToStage(
        opportunityId,
        CrmSalesStage.closedWon,
      );
      final saleId = await db.insert('ventas', {
        'company_id': companyId,
        'producto': 'Venta desde oportunidad',
        'cantidad': 1,
        'subtotal': 300000,
        'impuesto_pct': 0,
        'impuesto_total': 0,
        'total': 300000,
        'fecha': DateTime.now().toIso8601String(),
        'metodo_pago_id': 1,
        'estado': 'emitida',
      });
      await CrmOpportunityService().linkClosedWonToSale(
        opportunityId: opportunityId,
        saleId: saleId,
      );

      final opportunity = await CrmOpportunityService().findById(opportunityId);
      expect(opportunity?.salesStage, CrmSalesStage.closedWon);
      expect(opportunity?.effectiveProbability, 100);
      expect(opportunity?.linkedSaleId, saleId);
    },
  );

  test('CustomerInteraction queda persistida en crm_interactions', () async {
    final accountId = await CrmAccountService().create(
      CrmAccount(companyId: companyId, name: 'Cuenta interaccion'),
    );
    final interactionId = await CrmInteractionService().create(
      CustomerInteraction(
        companyId: companyId,
        customerId: accountId,
        customerName: 'Cuenta interaccion',
        interactionType: 'call',
        subject: 'Llamada de seguimiento',
        interactionDate: DateTime(2026, 8, 8),
        createdAt: DateTime(2026, 8, 8),
      ),
    );

    final rows = await CrmInteractionService().listForCustomer(accountId);
    expect(interactionId, greaterThan(0));
    expect(rows.single.subject, 'Llamada de seguimiento');
    await expectLater(
      () => CrmInteractionService().create(
        CustomerInteraction(
          companyId: companyId,
          customerId: accountId,
          customerName: 'Cuenta interaccion',
          interactionType: 'call',
          subject: '',
          interactionDate: DateTime(2026, 8, 8),
          createdAt: DateTime(2026, 8, 8),
        ),
      ),
      throwsArgumentError,
    );
  });
}
