class FeatureDefinition {
  const FeatureDefinition({
    required this.key,
    required this.name,
    required this.description,
    this.defaultEnabled = false,
    this.dependencies = const [],
  });

  final String key;
  final String name;
  final String description;
  final bool defaultEnabled;
  final List<String> dependencies;
}
