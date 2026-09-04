class CompanyTemplate {
  const CompanyTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.features,
    required this.settings,
    this.baseCatalog = const [],
  });

  final String id;
  final String name;
  final String description;
  final Map<String, bool> features;
  final Map<String, String> settings;
  final List<Map<String, dynamic>> baseCatalog;

  factory CompanyTemplate.fromJson(Map<String, dynamic> json) {
    return CompanyTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      features: (json['features'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
      settings: (json['settings'] as Map? ?? {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      baseCatalog: ((json['base_catalog'] as List?) ?? [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList(),
    );
  }
}
