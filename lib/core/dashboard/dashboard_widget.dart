// ============================================================
// dashboard_widget.dart
// Modelo para widgets del dashboard personalizable
// ============================================================

import 'package:flutter/material.dart';

enum DashboardWidgetType {
  salesToday,
  topProducts,
  lowStockAlerts,
  cashFlow,
  frequentCustomers,
  upcomingExpirations,
  goalsVsActual,
  pendingOrders,
  accountsReceivable,
  accountsPayable,
}

class DashboardWidget {
  final String id;
  final DashboardWidgetType type;
  final String title;
  final IconData icon;
  final int rowSpan;
  final int colSpan;
  final int position;
  final bool isEnabled;
  final Map<String, dynamic> config;

  DashboardWidget({
    required this.id,
    required this.type,
    required this.title,
    required this.icon,
    this.rowSpan = 1,
    this.colSpan = 1,
    required this.position,
    this.isEnabled = true,
    this.config = const {},
  });

  DashboardWidget copyWith({
    String? id,
    DashboardWidgetType? type,
    String? title,
    IconData? icon,
    int? rowSpan,
    int? colSpan,
    int? position,
    bool? isEnabled,
    Map<String, dynamic>? config,
  }) {
    return DashboardWidget(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      rowSpan: rowSpan ?? this.rowSpan,
      colSpan: colSpan ?? this.colSpan,
      position: position ?? this.position,
      isEnabled: isEnabled ?? this.isEnabled,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'title': title,
      'icon': icon.codePoint,
      'rowSpan': rowSpan,
      'colSpan': colSpan,
      'position': position,
      'isEnabled': isEnabled,
      'config': config,
    };
  }

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    final type = DashboardWidgetType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => DashboardWidgetType.salesToday,
    );
    return DashboardWidget(
      id: json['id'] as String,
      type: type,
      title: json['title'] as String,
      icon: iconForType(type),
      rowSpan: json['rowSpan'] as int? ?? 1,
      colSpan: json['colSpan'] as int? ?? 1,
      position: json['position'] as int,
      isEnabled: json['isEnabled'] as bool? ?? true,
      config: json['config'] as Map<String, dynamic>? ?? {},
    );
  }

  static IconData iconForType(DashboardWidgetType type) {
    return switch (type) {
      DashboardWidgetType.salesToday => Icons.trending_up,
      DashboardWidgetType.topProducts => Icons.star,
      DashboardWidgetType.lowStockAlerts => Icons.warning,
      DashboardWidgetType.cashFlow => Icons.account_balance_wallet,
      DashboardWidgetType.frequentCustomers => Icons.people,
      DashboardWidgetType.upcomingExpirations => Icons.event,
      DashboardWidgetType.goalsVsActual => Icons.flag,
      DashboardWidgetType.pendingOrders => Icons.pending_actions,
      DashboardWidgetType.accountsReceivable => Icons.request_quote,
      DashboardWidgetType.accountsPayable => Icons.payments,
    };
  }

  static List<DashboardWidget> getDefaultWidgets() {
    return [
      DashboardWidget(
        id: 'sales_today',
        type: DashboardWidgetType.salesToday,
        title: 'Ventas Hoy',
        icon: Icons.trending_up,
        position: 0,
        rowSpan: 1,
        colSpan: 1,
      ),
      DashboardWidget(
        id: 'top_products',
        type: DashboardWidgetType.topProducts,
        title: 'Productos Más Vendidos',
        icon: Icons.star,
        position: 1,
        rowSpan: 1,
        colSpan: 1,
      ),
      DashboardWidget(
        id: 'low_stock',
        type: DashboardWidgetType.lowStockAlerts,
        title: 'Alertas de Stock Bajo',
        icon: Icons.warning,
        position: 2,
        rowSpan: 1,
        colSpan: 1,
      ),
      DashboardWidget(
        id: 'cash_flow',
        type: DashboardWidgetType.cashFlow,
        title: 'Flujo de Caja Diario',
        icon: Icons.account_balance_wallet,
        position: 3,
        rowSpan: 1,
        colSpan: 1,
      ),
      DashboardWidget(
        id: 'frequent_customers',
        type: DashboardWidgetType.frequentCustomers,
        title: 'Clientes Frecuentes',
        icon: Icons.people,
        position: 4,
        rowSpan: 1,
        colSpan: 1,
      ),
      DashboardWidget(
        id: 'upcoming_expirations',
        type: DashboardWidgetType.upcomingExpirations,
        title: 'Próximos Vencimientos',
        icon: Icons.event,
        position: 5,
        rowSpan: 1,
        colSpan: 1,
      ),
    ];
  }
}
