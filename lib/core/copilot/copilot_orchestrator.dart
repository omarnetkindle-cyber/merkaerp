import 'dart:convert';

import '../../db_helper.dart';
import '../../services/merka_intelligence_service.dart';
import '../../document_management/application/document_management_service.dart';
import '../predictive/predictive_analytics.dart';
import '../../crm/application/crm_customer_intelligence_service.dart';
import 'copilot_models.dart';
import 'copilot_configuration_service.dart';
import 'copilot_tool_registry.dart';
import 'local_llm_client.dart';

class CopilotOrchestrator {
  CopilotOrchestrator({
    DatabaseHelper? databaseHelper,
    MerkaIntelligenceService? intelligence,
    LocalLlmClient? localLlm,
  }) : _db = databaseHelper ?? DatabaseHelper.instance,
       _intelligence = intelligence ?? MerkaIntelligenceService(),
       _localLlm = localLlm ?? LocalLlmClient(),
       _configuration = CopilotConfigurationService(
         databaseHelper: databaseHelper ?? DatabaseHelper.instance,
       ) {
    _registerTools();
  }

  final DatabaseHelper _db;
  final MerkaIntelligenceService _intelligence;
  final LocalLlmClient _localLlm;
  final CopilotConfigurationService _configuration;
  final CopilotToolRegistry tools = CopilotToolRegistry();

  Future<CopilotResponse> respond({
    required String prompt,
    required CopilotIdentity identity,
    List<CopilotConversationTurn> history = const [],
  }) async {
    final normalized = _normalize(prompt);
    if (normalized.isEmpty) {
      return const CopilotResponse(
        intent: 'empty',
        text: 'Escribe una consulta para poder ayudarte.',
        provider: 'deterministic',
      );
    }

    CopilotResponse response;
    Object? error;
    try {
      _registerNavigationTools(identity);
      final configuration = await _configuration.load();
      CopilotToolCall? call;
      var provider = 'deterministic';
      if (configuration.enabled) {
        try {
          final localResult = await _localLlm.complete(
            configuration: configuration,
            prompt: prompt,
            history: history.takeLast(8),
            tools: tools.schemas(identity),
          );
          call = localResult?.toolCall;
          if (call != null) provider = 'local_llm';
        } catch (_) {
          // El modelo es opcional. Un fallo nunca bloquea el ERP.
        }
      }
      call ??= _deterministicCall(normalized, identity);
      if (call == null) {
        response = CopilotResponse(
          intent: 'fallback',
          provider: provider,
          text:
              'Puedo consultar ventas, inventario, cartera y cuentas por pagar, '
              'o preparar navegación y borradores autorizados. No encontré una '
              'operación segura para esa solicitud.',
        );
      } else {
        final executed = await tools.execute(call, identity);
        response = CopilotResponse(
          intent: executed.intent,
          text: executed.text,
          provider: provider,
          toolId: call.name,
          priority: executed.priority,
          sources: executed.sources,
          actions: executed.actions,
        );
      }
    } catch (caught) {
      error = caught;
      response = CopilotResponse(
        intent: 'denied_or_failed',
        provider: 'policy',
        priority: CopilotPriority.warning,
        text: _safeError(caught),
      );
    }
    await _audit(prompt, response, identity, error: error);
    return response;
  }

  Future<List<OperationalAlert>> authorizedAlerts(
    CopilotIdentity identity,
  ) async {
    final canInventory = identity.canAccess('inventory');
    final canReceivables = identity.canAccess('receivables');
    if (!canInventory && !canReceivables) return const [];
    final alerts = await _intelligence.operationalAlerts();
    return alerts
        .where((alert) {
          if (alert.kind == 'receivable') return canReceivables;
          return canInventory;
        })
        .toList(growable: false);
  }

  Future<void> auditAction({
    required CopilotActionProposal action,
    required CopilotIdentity identity,
    required String outcome,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    await db.insert('conversaciones_copilot', {
      'company_id': companyId,
      'usuario': identity.userName,
      'usuario_id': identity.userId,
      'modulo': action.moduleId,
      'rol': identity.role,
      'mensaje_usuario': 'accion:${action.id}',
      'respuesta': outcome,
      'intent': 'copilot_action',
      'tool_id': action.id,
      'proveedor': 'policy',
      'resultado': outcome,
      'acciones': jsonEncode(action.arguments),
      'creada_en': DateTime.now().toIso8601String(),
    });
  }

  void _registerTools() {
    for (final spec
        in <({String id, String description, String module, String query})>[
          (
            id: 'sales_today',
            description: 'Consulta el total real de ventas emitidas hoy.',
            module: 'sales',
            query: 'ventas hoy',
          ),
          (
            id: 'sales_month',
            description: 'Consulta el total real de ventas del mes actual.',
            module: 'sales',
            query: 'ventas del mes',
          ),
          (
            id: 'critical_stock',
            description:
                'Lista productos de la empresa activa con stock crítico.',
            module: 'inventory',
            query: 'productos criticos',
          ),
          (
            id: 'expiring_products',
            description: 'Lista lotes próximos a vencer de la empresa activa.',
            module: 'inventory',
            query: 'productos por vencer',
          ),
          (
            id: 'receivables_total',
            description: 'Consulta el total real de cartera pendiente.',
            module: 'receivables',
            query: 'cartera pendiente',
          ),
          (
            id: 'payables_total',
            description: 'Consulta el total real de cuentas por pagar.',
            module: 'payables',
            query: 'cuentas por pagar',
          ),
        ]) {
      tools.register(
        CopilotToolDefinition(
          id: spec.id,
          description: spec.description,
          moduleId: spec.module,
          handler: (_, _) async {
            final reply = await _intelligence.answer(
              spec.query,
              persistConversation: false,
            );
            return CopilotResponse(
              intent: reply.intent,
              text: reply.response,
              provider: 'tool',
              toolId: spec.id,
              sources: [
                CopilotSource(
                  label: spec.description,
                  entity: spec.module,
                  asOf: DateTime.now(),
                ),
              ],
              actions: [
                CopilotActionProposal(
                  id: 'navigate.${spec.module}',
                  label: 'Abrir módulo',
                  kind: CopilotActionKind.navigate,
                  moduleId: spec.module,
                ),
              ],
            );
          },
        ),
      );
    }

    tools.register(
      CopilotToolDefinition(
        id: 'business_health',
        description: 'Resume cómo va la empresa usando ventas, margen, liquidez, cartera e inventario.',
        moduleId: 'reports',
        handler: (_, _) async {
          final data = await _intelligence.dashboardSnapshot();
          return CopilotResponse(
            intent: 'business_health', provider: 'tool',
            text: 'Puntuación operativa ${data.businessHealthScore}/100. Ventas del mes ${data.salesMonth.toStringAsFixed(2)}, margen bruto ${data.grossMarginPct.toStringAsFixed(1)}%, cartera vencida ${data.overdueReceivables.toStringAsFixed(2)}, cuentas por pagar ${data.payables.toStringAsFixed(2)} e inventario valorizado ${data.inventoryValue.toStringAsFixed(2)}. Esta puntuación es orientativa y no sustituye análisis financiero profesional.',
            sources: [CopilotSource(label: 'Dashboard gerencial', entity: 'workspace', asOf: DateTime.now())],
            actions: const [CopilotActionProposal(id: 'navigate.reports', label: 'Abrir reportes', kind: CopilotActionKind.navigate, moduleId: 'reports')],
          );
        },
      ),
    );
    tools.register(
      CopilotToolDefinition(
        id: 'purchase_suggestions',
        description: 'Sugiere qué productos comprar según demanda histórica y stock actual, sin crear compras automáticamente.',
        moduleId: 'inventory',
        handler: (_, _) async {
          final db = await DatabaseHelper.instance.database;
          final companyId = await DatabaseHelper.instance.obtenerEmpresaActivaId();
          final rows = await PredictiveAnalytics.instance.forecastStockRequirements(db, companyId, days: 15);
          if (rows.isEmpty) return const CopilotResponse(intent: 'purchase_suggestions', provider: 'tool', text: 'No encontré productos con necesidad de reposición en el horizonte analizado.');
          final top = rows.take(8).map((r) => '${r['product_name'] ?? r['nombre']}: ${r['recommended_purchase'] ?? r['cantidad_sugerida'] ?? 0}').join('\n');
          return CopilotResponse(
            intent: 'purchase_suggestions', provider: 'tool',
            text: 'Sugerencias de reposición para los próximos 15 días:\n$top\nRevisa y confirma siempre la orden desde Compras.',
            sources: [CopilotSource(label: 'Pronóstico de inventario', entity: 'inventory', asOf: DateTime.now())],
            actions: const [CopilotActionProposal(id: 'navigate.inventory', label: 'Abrir Inventario', kind: CopilotActionKind.navigate, moduleId: 'inventory')],
          );
        },
      ),
    );
    tools.register(
      CopilotToolDefinition(
        id: 'crm_customer_risk',
        description: 'Resume clientes VIP, inactivos y en riesgo de recompra.',
        moduleId: 'crm',
        handler: (_, _) async {
          final rows = await const CrmCustomerIntelligenceService().analyze();
          final vip = rows.customers.where((c) => c.segment == 'VIP').length;
          final inactive = rows.customers.where((c) => c.segment == 'Inactivo').length;
          final risk = rows.customers.where((c) => c.segment == 'En riesgo').length;
          return CopilotResponse(intent: 'crm_customer_risk', provider: 'tool', text: 'CRM detecta $vip clientes VIP, $risk en riesgo y $inactive inactivos. Abre Inteligencia CRM para revisar frecuencia, ticket promedio, recompra y cartera.', sources: [CopilotSource(label: 'Inteligencia CRM', entity: 'crm', asOf: DateTime.now())], actions: const [CopilotActionProposal(id: 'navigate.crm', label: 'Abrir CRM', kind: CopilotActionKind.navigate, moduleId: 'crm')]);
        },
      ),
    );

    tools.register(
      CopilotToolDefinition(
        id: 'prepare_sale',
        description:
            'Prepara, sin guardar ni cobrar, una venta para un producto.',
        moduleId: 'sales',
        parameters: const {
          'product_query': {'type': 'string'},
        },
        handler: (arguments, _) async {
          final query = arguments['product_query']?.toString().trim() ?? '';
          if (query.isEmpty) {
            throw StateError('Indica qué producto deseas preparar para venta.');
          }
          final product = await _intelligence.findProduct(query);
          if (product == null) {
            throw StateError('No encontré ese producto en la empresa activa.');
          }
          return CopilotResponse(
            intent: 'prepare_sale',
            provider: 'tool',
            text:
                'Encontré ${product.name}, con existencia ${product.stock.toStringAsFixed(0)}. '
                'Puedo abrir Ventas y precargar la búsqueda; todavía no se '
                'guardará ni cobrará nada.',
            sources: [
              CopilotSource(
                label: 'Producto de la empresa activa',
                entity: 'productos',
                recordId: product.product['id']?.toString(),
                asOf: DateTime.now(),
              ),
            ],
            actions: [
              CopilotActionProposal(
                id: 'prepare.sale',
                label: 'Preparar en Ventas',
                kind: CopilotActionKind.prepareSale,
                moduleId: 'sales',
                arguments: {'query': query},
                requiresConfirmation: true,
              ),
            ],
          );
        },
      ),
    );
    tools.register(
      CopilotToolDefinition(
        id: 'prepare_purchase',
        description: 'Abre Compras para preparar una orden sin guardarla.',
        moduleId: 'purchases',
        handler: (_, _) async => const CopilotResponse(
          intent: 'prepare_purchase',
          provider: 'tool',
          text:
              'Puedo abrir Compras para preparar una orden. La orden no se '
              'creará hasta que completes los datos y confirmes en el módulo.',
          actions: [
            CopilotActionProposal(
              id: 'prepare.purchase',
              label: 'Abrir Compras',
              kind: CopilotActionKind.preparePurchase,
              moduleId: 'purchases',
              requiresConfirmation: true,
            ),
          ],
        ),
      ),
    );
  }

  void _registerNavigationTools(CopilotIdentity identity) {
    for (final moduleId in identity.allowedModuleIds) {
      final toolId =
          'open_${moduleId.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')}';
      tools.register(
        CopilotToolDefinition(
          id: toolId,
          description:
              'Abre el modulo $moduleId si esta visible para el usuario.',
          moduleId: moduleId,
          handler: (_, _) async => CopilotResponse(
            intent: 'navigate',
            provider: 'tool',
            text: 'El modulo $moduleId esta disponible para tu rol.',
            actions: [
              CopilotActionProposal(
                id: 'navigate.$moduleId',
                label: 'Abrir modulo',
                kind: CopilotActionKind.navigate,
                moduleId: moduleId,
              ),
            ],
          ),
        ),
      );
    }
    final documentModule = identity.allowedModuleIds.contains('gestion_documental')
        ? 'gestion_documental'
        : identity.allowedModuleIds.contains('document_management')
            ? 'document_management'
            : null;
    if (documentModule != null) {
      tools.register(CopilotToolDefinition(
        id: 'documents_pending',
        description: 'Consulta radicados pendientes y vencidos sin modificar documentos.',
        moduleId: documentModule,
        handler: (_, _) async {
          final dashboard = await DocumentManagementService.instance.dashboard();
          return CopilotResponse(
            intent: 'documents_pending', provider: 'tool',
            text: 'Gestión documental registra ${dashboard.pending} radicados pendientes, '
                '${dashboard.overdue} vencidos y ${dashboard.forSignature} para firma.',
            sources: [CopilotSource(label: 'Resumen de gestión documental', entity: 'gd_radicados', asOf: DateTime.now())],
            actions: [CopilotActionProposal(id: 'navigate.$documentModule', label: 'Abrir Gestión Documental', kind: CopilotActionKind.navigate, moduleId: documentModule)],
          );
        },
      ));
      tools.register(CopilotToolDefinition(
        id: 'documents_search',
        description: 'Busca radicados por número, asunto, remitente o destinatario.',
        moduleId: documentModule,
        parameters: const {'query': {'type': 'string'}},
        handler: (arguments, _) async {
          final query = arguments['query']?.toString().trim() ?? '';
          if (query.isEmpty) throw StateError('Indica qué documento deseas buscar.');
          final rows = await DocumentManagementService.instance.listRadicados(search: query, limit: 8);
          if (rows.isEmpty) return CopilotResponse(intent: 'documents_search', provider: 'tool', text: 'No encontré radicados que coincidan con “$query”.');
          final text = rows.map((r) => '${r['number']}: ${r['subject']} (${r['status']})').join('\n');
          return CopilotResponse(
            intent: 'documents_search', provider: 'tool', text: 'Encontré ${rows.length} coincidencia(s):\n$text',
            sources: rows.map((r) => CopilotSource(label: r['number']?.toString() ?? 'Radicado', entity: 'gd_radicados', recordId: r['id']?.toString(), asOf: DateTime.now())).toList(),
            actions: [CopilotActionProposal(id: 'navigate.$documentModule', label: 'Abrir Gestión Documental', kind: CopilotActionKind.navigate, moduleId: documentModule)],
          );
        },
      ));
    }
  }

  CopilotToolCall? _deterministicCall(String text, CopilotIdentity identity) {
    final hasDocuments = identity.allowedModuleIds.contains('gestion_documental') ||
        identity.allowedModuleIds.contains('document_management');
    if (hasDocuments && _contains(text, ['documentos pendientes', 'radicados pendientes', 'documentos vencidos', 'radicados vencidos', 'gestion documental'])) {
      return const CopilotToolCall(name: 'documents_pending');
    }
    if (hasDocuments && text.startsWith('buscar documento ')) {
      return CopilotToolCall(name: 'documents_search', arguments: {'query': text.substring('buscar documento '.length).trim()});
    }
    if (hasDocuments && text.startsWith('buscar radicado ')) {
      return CopilotToolCall(name: 'documents_search', arguments: {'query': text.substring('buscar radicado '.length).trim()});
    }
    if (_contains(text, ['ventas hoy', 'vendi hoy'])) {
      return const CopilotToolCall(name: 'sales_today');
    }
    if (_contains(text, ['ventas mes', 'ventas del mes', 'vendido mes'])) {
      return const CopilotToolCall(name: 'sales_month');
    }
    if (_contains(text, ['como va mi empresa', 'salud de mi empresa', 'estado del negocio', 'rentabilidad del negocio'])) {
      return const CopilotToolCall(name: 'business_health');
    }
    if (_contains(text, ['que debo comprar', 'comprar esta semana', 'reposicion sugerida', 'sugerencia de compra'])) {
      return const CopilotToolCall(name: 'purchase_suggestions');
    }
    if (_contains(text, ['clientes inactivos', 'clientes vip', 'clientes en riesgo', 'recompra'])) {
      return const CopilotToolCall(name: 'crm_customer_risk');
    }
    if (_contains(text, [
      'stock critico',
      'productos criticos',
      'bajo stock',
    ])) {
      return const CopilotToolCall(name: 'critical_stock');
    }
    if (_contains(text, ['por vencer', 'vencimiento', 'vence'])) {
      return const CopilotToolCall(name: 'expiring_products');
    }
    if (_contains(text, ['cartera', 'cobranza', 'deuda'])) {
      return const CopilotToolCall(name: 'receivables_total');
    }
    if (_contains(text, ['cuentas por pagar', 'proveedores'])) {
      return const CopilotToolCall(name: 'payables_total');
    }
    if (text.startsWith('vender ') && text.length > 7) {
      return CopilotToolCall(
        name: 'prepare_sale',
        arguments: {'product_query': text.substring(7).trim()},
      );
    }
    if (_contains(text, ['crear compra', 'orden de compra'])) {
      return const CopilotToolCall(name: 'prepare_purchase');
    }
    if (text.startsWith('abrir ')) {
      final requested = text.substring(6).trim().replaceAll(' ', '_');
      if (requested.isNotEmpty) {
        return CopilotToolCall(name: 'open_$requested');
      }
    }
    return null;
  }

  Future<void> _audit(
    String prompt,
    CopilotResponse response,
    CopilotIdentity identity, {
    Object? error,
  }) async {
    final db = await _db.database;
    final companyId = await _db.obtenerEmpresaActivaId();
    await db.insert('conversaciones_copilot', {
      'company_id': companyId,
      'usuario': identity.userName,
      'usuario_id': identity.userId,
      'modulo': 'workspace',
      'rol': identity.role,
      'mensaje_usuario': prompt,
      'respuesta': response.text,
      'intent': response.intent,
      'tool_id': response.toolId,
      'proveedor': response.provider,
      'resultado': error == null ? 'exitoso' : 'rechazado',
      'detalle_error': error?.toString(),
      'acciones': jsonEncode(
        response.actions
            .map((action) => {'id': action.id, 'module': action.moduleId})
            .toList(),
      ),
      'creada_en': DateTime.now().toIso8601String(),
    });
  }

  String _safeError(Object error) {
    final text = error.toString().replaceFirst('Bad state: ', '');
    if (text.contains('permiso')) return text;
    if (error is StateError) return text;
    return 'No pude completar la consulta de forma segura. Revisa la '
        'configuración o intenta nuevamente.';
  }

  bool _contains(String value, List<String> patterns) =>
      patterns.any((pattern) => value.contains(pattern));

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[áàä]'), 'a')
      .replaceAll(RegExp('[éèë]'), 'e')
      .replaceAll(RegExp('[íìï]'), 'i')
      .replaceAll(RegExp('[óòö]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .trim();
}

extension<T> on List<T> {
  List<T> takeLast(int count) =>
      length <= count ? this : sublist(length - count, length);
}
