import 'package:flutter/services.dart';

class NumericInput {
  static final decimal = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  static final integer = FilteringTextInputFormatter.digitsOnly;
}
