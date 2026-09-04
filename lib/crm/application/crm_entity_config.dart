enum CrmEntityType { comercial, publico }

/// Punto unico para interpretar la bandera de tipo de entidad del CRM.
/// Las entidades y repositorios solo persisten [value]; las politicas que
/// distingan comercial/publico deben depender de esta configuracion central.
class CrmEntityConfig {
  const CrmEntityConfig({required this.type});

  factory CrmEntityConfig.fromValue(String? value) {
    return CrmEntityConfig(
      type: value == CrmEntityType.publico.name
          ? CrmEntityType.publico
          : CrmEntityType.comercial,
    );
  }

  final CrmEntityType type;

  String get value => type.name;
  bool get isPublic => type == CrmEntityType.publico;
}
