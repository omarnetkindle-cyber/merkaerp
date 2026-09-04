import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/company_template.dart';

class CompanyTemplateService {
  const CompanyTemplateService._();

  static const templateAssets = [
    'assets/templates/retail.json',
    'assets/templates/servicios.json',
    'assets/templates/restaurante.json',
    'assets/templates/manufactura.json',
  ];

  static Future<List<CompanyTemplate>> loadTemplates() async {
    final templates = <CompanyTemplate>[];
    for (final asset in templateAssets) {
      final content = await rootBundle.loadString(asset);
      templates.add(CompanyTemplate.fromJson(jsonDecode(content)));
    }
    return templates;
  }
}
