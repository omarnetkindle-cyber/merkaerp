import '../data/hrm_job_title_repository.dart';
import '../domain/hrm_job_title.dart';

class HrmJobTitleService {
  HrmJobTitleService({HrmJobTitleRepository? repository})
    : _repository = repository ?? SqliteHrmJobTitleRepository();
  final HrmJobTitleRepository _repository;
  Future<int> create(HrmJobTitle value) {
    _validate(value);
    return _repository.save(value);
  }

  Future<void> update(HrmJobTitle value) async {
    if (value.id == null) {
      throw ArgumentError('El cargo requiere id para actualizarse.');
    }
    _validate(value);
    await _repository.save(value);
  }

  void _validate(HrmJobTitle value) {
    if (value.title.trim().isEmpty) {
      throw ArgumentError('El cargo requiere nombre.');
    }
    final hours = value.contractualHoursPerDay;
    if (hours != null && (hours <= 0 || hours > 24)) {
      throw ArgumentError(
        'Las horas contractuales por dia deben estar entre 0 y 24.',
      );
    }
    if (value.mrpWorkstationId != null && hours == null) {
      throw ArgumentError(
        'Un cargo vinculado a produccion requiere horas contractuales configuradas.',
      );
    }
  }

  Future<List<HrmJobTitle>> list() => _repository.findAll();
}
