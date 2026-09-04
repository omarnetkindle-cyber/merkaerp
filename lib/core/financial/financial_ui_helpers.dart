class FinancialUiHelpers {
  const FinancialUiHelpers._();

  static String formatCurrency(num value) {
    final rounded = value.toDouble().toStringAsFixed(0);
    final chars = rounded.split('').reversed.toList();
    final buffer = <String>[];
    for (var index = 0; index < chars.length; index++) {
      if (index > 0 && index % 3 == 0) {
        buffer.add('.');
      }
      buffer.add(chars[index]);
    }
    return '\$${buffer.reversed.join()}';
  }

  static String accountStatusLabel(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'pagada':
        return 'Pagada';
      case 'parcial':
        return 'Parcial';
      case 'pendiente':
        return 'Pendiente';
      case 'anulada':
        return 'Anulada';
      default:
        return normalized.isEmpty ? 'Sin estado' : normalized[0].toUpperCase() + normalized.substring(1);
    }
  }
}
