class Company {
  const Company({
    this.id,
    required this.name,
    this.taxId = '',
    this.country = 'Colombia',
    this.currency = 'COP',
    this.timezone = 'America/Bogota',
    this.active = true,
  });

  final int? id;
  final String name;
  final String taxId;
  final String country;
  final String currency;
  final String timezone;
  final bool active;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'tax_id': taxId,
    'country': country,
    'currency': currency,
    'timezone': timezone,
    'active': active ? 1 : 0,
  };

  factory Company.fromMap(Map<String, dynamic> map) => Company(
    id: map['id'] as int?,
    name: map['name']?.toString() ?? 'MerkaERP',
    taxId: map['tax_id']?.toString() ?? '',
    country: map['country']?.toString() ?? 'Colombia',
    currency: map['currency']?.toString() ?? 'COP',
    timezone: map['timezone']?.toString() ?? 'America/Bogota',
    active: (map['active'] as num? ?? 1) == 1,
  );
}
