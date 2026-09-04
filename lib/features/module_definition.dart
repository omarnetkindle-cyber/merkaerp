import 'package:flutter/material.dart';

enum ModuleCategory { operation, accounting, control, management }

class ModuleDefinition {
  const ModuleDefinition({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    required this.category,
    required this.builder,
    this.featureKey,
    this.permissionLabel,
    this.requiresAdmin = false,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final ModuleCategory category;
  final WidgetBuilder builder;
  final String? featureKey;
  final String? permissionLabel;
  final bool requiresAdmin;
}
