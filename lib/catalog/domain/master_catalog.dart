class TaxOption {
  const TaxOption({
    required this.code,
    required this.label,
    required this.rate,
    this.sales = true,
    this.purchases = true,
  });

  final String code;
  final String label;
  final double rate;
  final bool sales;
  final bool purchases;
}

class UnitOption {
  const UnitOption({required this.code, required this.label});

  final String code;
  final String label;
}

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.code,
    required this.label,
    required this.origin,
    this.credit = false,
    this.mixed = false,
  });

  final String code;
  final String label;
  final String origin;
  final bool credit;
  final bool mixed;
}

class NiifAccountOption {
  const NiifAccountOption({
    required this.code,
    required this.name,
    required this.type,
    required this.nature,
  });

  final String code;
  final String name;
  final String type;
  final String nature;
}

class MasterCatalog {
  const MasterCatalog._();

  static const taxes = <TaxOption>[
    TaxOption(code: 'EXEMPT', label: 'Exento / No gravado (0%)', rate: 0),
    TaxOption(code: 'IVA_5', label: 'IVA 5%', rate: 5),
    TaxOption(code: 'IVA_8', label: 'IVA 8%', rate: 8),
    TaxOption(code: 'IVA_19', label: 'IVA 19%', rate: 19),
  ];

  static const units = <UnitOption>[
    UnitOption(code: 'UND', label: 'Unidad'),
    UnitOption(code: 'KG', label: 'Kilogramo'),
    UnitOption(code: 'LB', label: 'Libra'),
    UnitOption(code: 'L', label: 'Litro'),
    UnitOption(code: 'M', label: 'Metro'),
    UnitOption(code: 'CAJA', label: 'Caja'),
    UnitOption(code: 'SERV', label: 'Servicio'),
  ];

  static const paymentMethods = <PaymentMethodOption>[
    PaymentMethodOption(code: 'EFECTIVO', label: 'Efectivo', origin: 'caja'),
    PaymentMethodOption(
      code: 'TRANSFERENCIA',
      label: 'Transferencia',
      origin: 'banco',
    ),
    PaymentMethodOption(code: 'TARJETA', label: 'Tarjeta', origin: 'banco'),
    PaymentMethodOption(code: 'NEQUI', label: 'Nequi', origin: 'banco'),
    PaymentMethodOption(code: 'DAVIPLATA', label: 'Daviplata', origin: 'banco'),
    PaymentMethodOption(
      code: 'CREDITO',
      label: 'Credito',
      origin: 'cartera',
      credit: true,
    ),
    PaymentMethodOption(
      code: 'PAGO MIXTO',
      label: 'Pago mixto',
      origin: 'mixto',
      mixed: true,
    ),
  ];

  static const niifAccounts = <NiifAccountOption>[
    NiifAccountOption(
      code: '1105',
      name: 'Caja',
      type: 'activo',
      nature: 'debito',
    ),
    NiifAccountOption(
      code: '1110',
      name: 'Bancos',
      type: 'activo',
      nature: 'debito',
    ),
    NiifAccountOption(
      code: '1305',
      name: 'Cuentas por cobrar',
      type: 'activo',
      nature: 'debito',
    ),
    NiifAccountOption(
      code: '1355',
      name: 'Impuestos descontables',
      type: 'activo',
      nature: 'debito',
    ),
    NiifAccountOption(
      code: '1435',
      name: 'Inventarios',
      type: 'activo',
      nature: 'debito',
    ),
    NiifAccountOption(
      code: '2205',
      name: 'Proveedores nacionales',
      type: 'pasivo',
      nature: 'credito',
    ),
    NiifAccountOption(
      code: '2408',
      name: 'IVA generado',
      type: 'pasivo',
      nature: 'credito',
    ),
    NiifAccountOption(
      code: '4135',
      name: 'Ingresos por ventas',
      type: 'ingreso',
      nature: 'credito',
    ),
    NiifAccountOption(
      code: '6135',
      name: 'Costo de ventas',
      type: 'costo',
      nature: 'debito',
    ),
  ];
}
