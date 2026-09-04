import 'package:flutter/material.dart';
import '../../ui/merka_theme_tokens.dart';

import '../application/hrm_leave_service.dart';

class HrmLeaveCalendarPage extends StatefulWidget {
  const HrmLeaveCalendarPage({super.key});

  @override
  State<HrmLeaveCalendarPage> createState() => _HrmLeaveCalendarPageState();
}

class _HrmLeaveCalendarPageState extends State<HrmLeaveCalendarPage> {
  final _service = HrmLeaveService();
  late Future<List<Map<String, dynamic>>> _leaves;
  late final DateTime _month = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  @override
  void initState() {
    super.initState();
    _leaves = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    return _service.approvedForPeriod(
      from: _month,
      to: DateTime(_month.year, _month.month + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _leaves,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('No se pudo cargar ausencias: ${snapshot.error}'),
          );
        }
        return _calendar(context, snapshot.data ?? const []);
      },
    );
  }

  Widget _calendar(BuildContext context, List<Map<String, dynamic>> leaves) {
    final byDay = <int, List<Map<String, dynamic>>>{};
    for (final leave in leaves) {
      final date = DateTime.tryParse(leave['date']?.toString() ?? '');
      if (date == null) continue;
      byDay.putIfAbsent(date.day, () => []).add(leave);
    }
    final offset = _month.weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cellCount = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final labels = ['Lun', 'Mar', 'Mie', 'Jue', 'Vie', 'Sab', 'Dom'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              const Icon(Icons.circle, size: 10, color: MerkaThemeTokens.navy600),
              const SizedBox(width: 4),
              const Text('Ausencia aprobada'),
            ],
          ),
        ),
        Row(
          children: labels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(label),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (context, index) {
              final day = index - offset + 1;
              final events = day > 0 && day <= daysInMonth
                  ? byDay[day] ?? const []
                  : const <Map<String, dynamic>>[];
              return Container(
                margin: const EdgeInsets.all(2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(4),
                  color: day > 0 && day <= daysInMonth
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: day <= 0 || day > daysInMonth
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$day'),
                          ...events
                              .take(3)
                              .map(
                                (event) => Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  color: _colorFor(
                                    event['leave_code']?.toString(),
                                  ),
                                  child: Text(
                                    event['employee_name']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              ),
                        ],
                      ),
              );
            },
          ),
        ),
        if (leaves.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No hay ausencias aprobadas este mes.'),
          ),
      ],
    );
  }

  Color _colorFor(String? code) {
    switch (code) {
      case 'vacaciones':
        return MerkaThemeTokens.gold200;
      case 'incapacidad_eps':
        return MerkaThemeTokens.warning.withValues(alpha: 0.18);
      case 'incapacidad_arl':
        return MerkaThemeTokens.danger.withValues(alpha: 0.14);
      case 'licencia_maternidad':
        return MerkaThemeTokens.gold400.withValues(alpha: 0.35);
      case 'licencia_paternidad':
        return MerkaThemeTokens.navy600.withValues(alpha: 0.16);
      case 'luto':
        return MerkaThemeTokens.graphite600.withValues(alpha: 0.18);
      default:
        return MerkaThemeTokens.success.withValues(alpha: 0.16);
    }
  }
}
