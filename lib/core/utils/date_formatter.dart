import 'package:intl/intl.dart';

class DateFormatter {
  static final _formatter = DateFormat('dd/MM/yyyy', 'es_CO');

  static String format(DateTime fecha) => _formatter.format(fecha);
}
