import 'package:flutter/material.dart';

/// Single source of truth for MerkaERP visual tokens.
///
/// The same tokens are used by commercial and public-sector workspaces. The
/// semantic colors are intentionally separate from the brand accent so status
/// information remains distinguishable in light, dark and high-contrast modes.
class MerkaThemeTokens {
  const MerkaThemeTokens._();

  static const navy900 = Color(0xFF071522);
  static const navy800 = Color(0xFF0A2540);
  static const navy700 = Color(0xFF123057);
  static const navy600 = Color(0xFF1B3F70);

  static const graphite900 = Color(0xFF444B58);
  static const graphite600 = Color(0xFF7A8393);

  static const paper50 = Color(0xFFF4F6F9);
  static const paper100 = Color(0xFFE9ECF2);

  static const gold500 = Color(0xFFC6A15B);
  static const gold400 = Color(0xFFD8B87A);
  static const gold200 = Color(0xFFE9D6AA);

  static const success = Color(0xFF237A57);
  static const warning = Color(0xFF9A6700);
  static const danger = Color(0xFFB42318);
  static const info = navy600;

  static const onDark = Color(0xFFF8FAFC);
  static const onLight = graphite900;
}
