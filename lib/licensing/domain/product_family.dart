enum ProductFamily { commercial, publicSector }

extension ProductFamilyWire on ProductFamily {
  String get wireValue => switch (this) {
    ProductFamily.commercial => 'COMMERCIAL',
    ProductFamily.publicSector => 'PUBLIC',
  };

  String get storageValue => switch (this) {
    ProductFamily.commercial => 'commercial',
    ProductFamily.publicSector => 'public',
  };

  String get label => switch (this) {
    ProductFamily.commercial => 'MerkaERP Comercial',
    ProductFamily.publicSector => 'MerkaERP Público',
  };
}

ProductFamily parseProductFamily(
  Object? raw, {
  Iterable<Object?> modules = const [],
}) {
  final value = raw?.toString().trim().toUpperCase();
  if (value == 'PUBLIC' ||
      value == 'PUBLIC_SECTOR' ||
      value == 'PUBLICO' ||
      value == 'PÚBLICO') {
    return ProductFamily.publicSector;
  }
  if (value == 'COMMERCIAL' ||
      value == 'PRIVATE' ||
      value == 'PRIVADA' ||
      value == 'COMERCIAL') {
    return ProductFamily.commercial;
  }

  // Compatibilidad controlada con licencias emitidas antes de incorporar
  // product_family. Nunca se consulta una preferencia local editable: la
  // familia se infiere únicamente del conjunto de módulos firmado.
  const publicMarkers = {
    'presupuesto_publico',
    'contabilidad_nicsp',
    'contratacion_publica',
    'nomina_publica',
    'predial',
    'rentas_departamentales',
    'planeacion',
    'activos_estado',
    'auditoria_forense',
    'transparencia',
    'sgdea_publico',
  };
  final normalized = modules
      .map((module) => module?.toString().trim().toLowerCase())
      .whereType<String>()
      .toSet();
  if (normalized.any(publicMarkers.contains)) {
    return ProductFamily.publicSector;
  }
  return ProductFamily.commercial;
}
