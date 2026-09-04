/// Marcos tecnicos de informacion financiera configurables por empresa.
enum FinancialFrameworkGroup {
  grupo1,
  grupo2,
  grupo3;

  String get dbValue => switch (this) {
    FinancialFrameworkGroup.grupo1 => 'grupo_1',
    FinancialFrameworkGroup.grupo2 => 'grupo_2',
    FinancialFrameworkGroup.grupo3 => 'grupo_3',
  };

  static FinancialFrameworkGroup fromDbValue(String? value) {
    return switch (value) {
      'grupo_1' => FinancialFrameworkGroup.grupo1,
      'grupo_3' => FinancialFrameworkGroup.grupo3,
      _ => FinancialFrameworkGroup.grupo2,
    };
  }
}

/// Politica contable visible para reportes y futuras reglas por marco.
///
/// Esta clase describe el alcance configurado; no pretende afirmar que todas
/// las revelaciones o mediciones del marco ya esten implementadas.
class FinancialFrameworkPolicy {
  const FinancialFrameworkPolicy({
    required this.group,
    required this.frameworkName,
    required this.disclosureProfile,
    required this.inventoryImpairmentPolicy,
    required this.implementationStatus,
  });

  final FinancialFrameworkGroup group;
  final String frameworkName;
  final String disclosureProfile;
  final String inventoryImpairmentPolicy;
  final String implementationStatus;

  static FinancialFrameworkPolicy forGroup(FinancialFrameworkGroup group) {
    return switch (group) {
      FinancialFrameworkGroup.grupo1 => const FinancialFrameworkPolicy(
        group: FinancialFrameworkGroup.grupo1,
        frameworkName: 'NIIF plenas (Anexo 1/1.1)',
        disclosureProfile: 'Revelaciones completas del Grupo 1',
        inventoryImpairmentPolicy: 'NIC 36 y marco tecnico del Grupo 1',
        implementationStatus:
            'Configuracion disponible; revelaciones completas pendientes',
      ),
      FinancialFrameworkGroup.grupo2 => const FinancialFrameworkPolicy(
        group: FinancialFrameworkGroup.grupo2,
        frameworkName: 'NIIF para las PYMES (Anexo 2/2.1)',
        disclosureProfile: 'Revelaciones simplificadas de NIIF para PYMES',
        inventoryImpairmentPolicy: 'Seccion 27 - deterioro de activos',
        implementationStatus:
            'Politica de marco disponible; calculos especificos pendientes',
      ),
      FinancialFrameworkGroup.grupo3 => const FinancialFrameworkPolicy(
        group: FinancialFrameworkGroup.grupo3,
        frameworkName: 'NIF para microempresas (Anexo 3)',
        disclosureProfile: 'Revelaciones simplificadas de microempresas',
        inventoryImpairmentPolicy: 'Tratamiento simplificado del Anexo 3',
        implementationStatus:
            'Politica de marco disponible; calculos especificos pendientes',
      ),
    };
  }

  Map<String, dynamic> toMap() => {
    'grupo': group.dbValue,
    'marco': frameworkName,
    'perfil_revelacion': disclosureProfile,
    'politica_deterioro_inventarios': inventoryImpairmentPolicy,
    'estado_implementacion': implementationStatus,
  };
}
