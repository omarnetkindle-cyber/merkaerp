class PageRequest {
  const PageRequest({this.limit = 50, this.offset = 0});

  final int limit;
  final int offset;

  factory PageRequest.fromQuery(Map<String, String> query) {
    return PageRequest(
      limit: _boundedInt(query['limit'], fallback: 50, min: 1, max: 200),
      offset: _boundedInt(query['offset'], fallback: 0, min: 0, max: 1000000),
    );
  }

  List<T> apply<T>(List<T> items) {
    if (items.isEmpty || offset >= items.length) return const [];
    final end = (offset + limit).clamp(0, items.length);
    return items.sublist(offset, end);
  }

  Map<String, int> meta(int total) => {
    'limit': limit,
    'offset': offset,
    'count': offset >= total ? 0 : (total - offset).clamp(0, limit),
    'total': total,
  };

  static int _boundedInt(
    String? value, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = int.tryParse(value ?? '') ?? fallback;
    return parsed.clamp(min, max);
  }
}
