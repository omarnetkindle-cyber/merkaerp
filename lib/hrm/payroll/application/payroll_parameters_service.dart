// lib/hrm/payroll/application/payroll_parameters_service.dart
//
// Servicio para administrar los parámetros legales de nómina (payroll_parameters).
// Cada fila está versionada por (company_id, year) y es auditable.
// Los valores son obtenidos de la BD — nunca hardcodeados en el motor.

import '../../../db_helper.dart';

/// Valores legales Colombia 2025 — Decretos oficiales.
const _kSeed2025 = {
  'year': 2025,
  'smmlv': 1423500, // Decreto (entero COP — minor units COP0dec)
  'transportation_allowance': 200000, // Decreto
  'uvt': 47065, // Resolución DIAN
  'health_employee_rate': 0.04,
  'health_employer_rate': 0.085,
  'health_exonerated': 0,
  'pension_employee_rate': 0.04,
  'pension_employer_rate': 0.12,
  'fsp_trigger_smmlv': 4.0,
  'fsp_rate_1': 0.01,
  'fsp_rate_2': 0.012,
  'fsp_rate_3': 0.014,
  'fsp_rate_4': 0.016,
  'fsp_rate_5': 0.018,
  'fsp_rate_6': 0.02,
  'arl_level_1_rate': 0.00522,
  'arl_level_2_rate': 0.01044,
  'arl_level_3_rate': 0.02436,
  'arl_level_4_rate': 0.04350,
  'arl_level_5_rate': 0.06960,
  'parafiscal_sena_rate': 0.02,
  'parafiscal_icbf_rate': 0.03,
  'parafiscal_caja_rate': 0.04,
  'severance_rate': 0.0833,
  'service_bonus_rate': 0.0833,
  'severance_interest_rate': 0.01,
  'vacation_rate': 0.0417,
};

/// Valores legales Colombia 2026 — Decretos 1469/1470 del 29-dic-2025
/// y Resolución DIAN 000238 del 15-dic-2025.
const _kSeed2026 = {
  'year': 2026,
  'smmlv': 1750905, // Decreto 1469/2025
  'transportation_allowance': 249095, // Decreto 1470/2025
  'uvt': 52374, // Resolución DIAN 000238/2025
  'health_employee_rate': 0.04,
  'health_employer_rate': 0.085,
  'health_exonerated': 0,
  'pension_employee_rate': 0.04,
  'pension_employer_rate': 0.12,
  'fsp_trigger_smmlv': 4.0,
  'fsp_rate_1': 0.01,
  'fsp_rate_2': 0.012,
  'fsp_rate_3': 0.014,
  'fsp_rate_4': 0.016,
  'fsp_rate_5': 0.018,
  'fsp_rate_6': 0.02,
  'arl_level_1_rate': 0.00522,
  'arl_level_2_rate': 0.01044,
  'arl_level_3_rate': 0.02436,
  'arl_level_4_rate': 0.04350,
  'arl_level_5_rate': 0.06960,
  'parafiscal_sena_rate': 0.02,
  'parafiscal_icbf_rate': 0.03,
  'parafiscal_caja_rate': 0.04,
  'severance_rate': 0.0833,
  'service_bonus_rate': 0.0833,
  'severance_interest_rate': 0.01,
  'vacation_rate': 0.0417,
};

/// Fuente de verdad oficial para las semillas por año.
const Map<int, Map<String, Object>> _kSeeds = {
  2025: _kSeed2025,
  2026: _kSeed2026,
};

class PayrollParametersService {
  const PayrollParametersService._();

  static const PayrollParametersService instance = PayrollParametersService._();

  // ── Lectura ────────────────────────────────────────────────────────────────

  /// Devuelve los parámetros para [year] y [companyId].
  /// Prioridad: fila de la empresa > fila global (company_id IS NULL).
  /// Retorna null si no hay parámetros configurados.
  Future<Map<String, dynamic>?> find(int companyId, int year) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'payroll_parameters',
      where: 'year = ? AND (company_id = ? OR company_id IS NULL)',
      whereArgs: [year, companyId],
      orderBy: 'company_id DESC', // empresa antes que global
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Devuelve los años que ya tienen parámetros configurados para [companyId].
  Future<List<int>> configuredYears(int companyId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      'SELECT year FROM payroll_parameters '
      'WHERE company_id = ? OR company_id IS NULL '
      'GROUP BY year ORDER BY year DESC',
      [companyId],
    );
    return rows.map((r) => (r['year'] as num).toInt()).toList();
  }

  // ── Escritura ──────────────────────────────────────────────────────────────

  /// Inserta o actualiza los parámetros para [year] / [companyId].
  /// Registra auditoría. Retorna el id de la fila.
  Future<int> save({
    required int companyId,
    required int year,
    required int smmlv,
    required int transportationAllowance,
    required int uvt,
    double healthEmployeeRate = 0.04,
    double healthEmployerRate = 0.085,
    bool healthExonerated = false,
    double pensionEmployeeRate = 0.04,
    double pensionEmployerRate = 0.12,
    double fspTriggerSmmlv = 4.0,
    double fspRate1 = 0.01,
    double fspRate2 = 0.012,
    double fspRate3 = 0.014,
    double fspRate4 = 0.016,
    double fspRate5 = 0.018,
    double fspRate6 = 0.02,
    double arlLevel1Rate = 0.00522,
    double arlLevel2Rate = 0.01044,
    double arlLevel3Rate = 0.02436,
    double arlLevel4Rate = 0.04350,
    double arlLevel5Rate = 0.06960,
    double parafiscalSenaRate = 0.02,
    double parafiscalIcbfRate = 0.03,
    double parafiscalCajaRate = 0.04,
    double severanceRate = 0.0833,
    double serviceBonusRate = 0.0833,
    double severanceInterestRate = 0.01,
    double vacationRate = 0.0417,
  }) async {
    if (smmlv <= 0) throw ArgumentError('SMMLV debe ser mayor a 0.');
    if (transportationAllowance < 0) {
      throw ArgumentError('Auxilio de transporte no puede ser negativo.');
    }
    if (uvt <= 0) throw ArgumentError('UVT debe ser mayor a 0.');

    final now = DateTime.now().toIso8601String();
    final db = await DatabaseHelper.instance.database;

    final data = <String, Object?>{
      'company_id': companyId,
      'year': year,
      'smmlv': smmlv,
      'transportation_allowance': transportationAllowance,
      'uvt': uvt,
      'health_employee_rate': healthEmployeeRate,
      'health_employer_rate': healthEmployerRate,
      'health_exonerated': healthExonerated ? 1 : 0,
      'pension_employee_rate': pensionEmployeeRate,
      'pension_employer_rate': pensionEmployerRate,
      'fsp_trigger_smmlv': fspTriggerSmmlv,
      'fsp_rate_1': fspRate1,
      'fsp_rate_2': fspRate2,
      'fsp_rate_3': fspRate3,
      'fsp_rate_4': fspRate4,
      'fsp_rate_5': fspRate5,
      'fsp_rate_6': fspRate6,
      'arl_level_1_rate': arlLevel1Rate,
      'arl_level_2_rate': arlLevel2Rate,
      'arl_level_3_rate': arlLevel3Rate,
      'arl_level_4_rate': arlLevel4Rate,
      'arl_level_5_rate': arlLevel5Rate,
      'parafiscal_sena_rate': parafiscalSenaRate,
      'parafiscal_icbf_rate': parafiscalIcbfRate,
      'parafiscal_caja_rate': parafiscalCajaRate,
      'severance_rate': severanceRate,
      'service_bonus_rate': serviceBonusRate,
      'severance_interest_rate': severanceInterestRate,
      'vacation_rate': vacationRate,
      'updated_at': now,
    };

    // Verificar si ya existe para esa empresa y año.
    final existing = await db.query(
      'payroll_parameters',
      columns: ['id'],
      where: 'company_id = ? AND year = ?',
      whereArgs: [companyId, year],
      limit: 1,
    );

    late int resultId;
    if (existing.isEmpty) {
      data['created_at'] = now;
      resultId = await db.insert('payroll_parameters', data);
    } else {
      final id = (existing.first['id'] as num).toInt();
      await db.update(
        'payroll_parameters',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
      resultId = id;
    }

    await DatabaseHelper.instance.registrarEventoAuditoria(
      accion: 'PAYROLL_PARAMETERS_SAVED',
      entidad: 'payroll_parameters',
      entidadId: resultId,
      detalle: 'year=$year company_id=$companyId smmlv=$smmlv',
    );

    return resultId;
  }

  // ── Semillas oficiales ─────────────────────────────────────────────────────

  /// Retorna la semilla oficial para [year] si existe, o null.
  static Map<String, Object>? officialSeed(int year) => _kSeeds[year];

  /// Inserta los parámetros oficiales para [year] en [companyId]
  /// únicamente si no existen aún. Idempotente.
  /// Retorna true si se insertó, false si ya existía.
  Future<bool> seedOfficialIfAbsent(int companyId, int year) async {
    final existing = await find(companyId, year);
    if (existing != null) return false;
    final seed = _kSeeds[year];
    if (seed == null) return false;
    await save(
      companyId: companyId,
      year: year,
      smmlv: seed['smmlv']! as int,
      transportationAllowance: seed['transportation_allowance']! as int,
      uvt: seed['uvt']! as int,
      healthEmployeeRate: (seed['health_employee_rate']! as num).toDouble(),
      healthEmployerRate: (seed['health_employer_rate']! as num).toDouble(),
      healthExonerated: seed['health_exonerated'] == 1,
      pensionEmployeeRate: (seed['pension_employee_rate']! as num).toDouble(),
      pensionEmployerRate: (seed['pension_employer_rate']! as num).toDouble(),
      fspTriggerSmmlv: (seed['fsp_trigger_smmlv']! as num).toDouble(),
      fspRate1: (seed['fsp_rate_1']! as num).toDouble(),
      fspRate2: (seed['fsp_rate_2']! as num).toDouble(),
      fspRate3: (seed['fsp_rate_3']! as num).toDouble(),
      fspRate4: (seed['fsp_rate_4']! as num).toDouble(),
      fspRate5: (seed['fsp_rate_5']! as num).toDouble(),
      fspRate6: (seed['fsp_rate_6']! as num).toDouble(),
      arlLevel1Rate: (seed['arl_level_1_rate']! as num).toDouble(),
      arlLevel2Rate: (seed['arl_level_2_rate']! as num).toDouble(),
      arlLevel3Rate: (seed['arl_level_3_rate']! as num).toDouble(),
      arlLevel4Rate: (seed['arl_level_4_rate']! as num).toDouble(),
      arlLevel5Rate: (seed['arl_level_5_rate']! as num).toDouble(),
      parafiscalSenaRate: (seed['parafiscal_sena_rate']! as num).toDouble(),
      parafiscalIcbfRate: (seed['parafiscal_icbf_rate']! as num).toDouble(),
      parafiscalCajaRate: (seed['parafiscal_caja_rate']! as num).toDouble(),
      severanceRate: (seed['severance_rate']! as num).toDouble(),
      serviceBonusRate: (seed['service_bonus_rate']! as num).toDouble(),
      severanceInterestRate: (seed['severance_interest_rate']! as num)
          .toDouble(),
      vacationRate: (seed['vacation_rate']! as num).toDouble(),
    );
    return true;
  }

  /// Llave de los años oficialmente soportados.
  static List<int> get supportedYears => _kSeeds.keys.toList()..sort();
}
