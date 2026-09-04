import 'package:flutter/material.dart';

import '../merka_theme_tokens.dart';

typedef SemanticZoomRecordBuilder<T> =
    Widget Function(
      BuildContext context,
      T record, {
      required bool initiallyExpanded,
    });

/// Presentation-only zoom for an already loaded collection of records.
class SemanticZoomRecordList<T> extends StatefulWidget {
  const SemanticZoomRecordList({
    super.key,
    required this.records,
    required this.statusOf,
    required this.itemBuilder,
    this.initialZoom = 3,
    this.title = 'Zoom semántico',
  });

  final List<T> records;
  final String Function(T record) statusOf;
  final SemanticZoomRecordBuilder<T> itemBuilder;
  final int initialZoom;
  final String title;

  @override
  State<SemanticZoomRecordList<T>> createState() =>
      _SemanticZoomRecordListState<T>();
}

class _SemanticZoomRecordListState<T> extends State<SemanticZoomRecordList<T>> {
  late int _zoom = widget.initialZoom.clamp(1, 5).toInt();

  Map<String, List<T>> get _groups {
    final result = <String, List<T>>{};
    for (final record in widget.records) {
      result.putIfAbsent(widget.statusOf(record), () => <T>[]).add(record);
    }
    return result;
  }

  void _setZoom(double value) {
    final next = value.round().clamp(1, 5).toInt();
    if (next == _zoom) return;
    setState(() => _zoom = next);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SemanticZoomControl(
          title: widget.title,
          value: _zoom.toDouble(),
          onChanged: _setZoom,
        ),
        Expanded(
          child: groups.isEmpty
              ? const Center(child: Text('Sin registros'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: groups.entries
                      .map(
                        (entry) => _buildGroup(context, entry.key, entry.value),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildGroup(BuildContext context, String status, List<T> records) {
    final theme = Theme.of(context);
    if (_zoom == 1) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(
            Icons.layers_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(status),
          trailing: CircleAvatar(
            radius: 14,
            backgroundColor: MerkaThemeTokens.navy700,
            foregroundColor: MerkaThemeTokens.onDark,
            child: Text('${records.length}'),
          ),
        ),
      );
    }

    final showItems = _zoom >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$status (${records.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: MerkaThemeTokens.graphite900,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_zoom == 2)
                Text(
                  'Resumen agrupado',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: MerkaThemeTokens.graphite600,
                  ),
                ),
            ],
          ),
        ),
        if (!showItems)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: MerkaThemeTokens.paper100,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '${records.length} registros en estado "$status". Acerca el zoom para ver acciones.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...records.map(
            (record) => widget.itemBuilder(
              context,
              record,
              initiallyExpanded: _zoom == 5,
            ),
          ),
      ],
    );
  }
}

class _SemanticZoomControl extends StatelessWidget {
  const _SemanticZoomControl({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Icon(Icons.zoom_in_map, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: theme.textTheme.labelLarge),
          Expanded(
            child: Slider(
              min: 1,
              max: 5,
              divisions: 4,
              value: value,
              label: 'Nivel ${value.round()}',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              'Nivel ${value.round()}',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: MerkaThemeTokens.graphite600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
