import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/ui/enterprise_design_system.dart';
import 'package:merka_erp/ui/merka_theme_tokens.dart';

double _contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance();
  final darker = background.computeLuminance();
  final high = lighter > darker ? lighter : darker;
  final low = lighter > darker ? darker : lighter;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  test('usa la paleta MerkaERP navy/oro en ambos temas', () {
    final light = EnterpriseThemeEngine.theme();
    final dark = EnterpriseThemeEngine.theme(brightness: Brightness.dark);

    expect(light.colorScheme.primary, MerkaThemeTokens.navy800);
    expect(light.colorScheme.secondary, MerkaThemeTokens.gold500);
    expect(dark.colorScheme.primary, MerkaThemeTokens.navy600);
    expect(dark.colorScheme.surface, MerkaThemeTokens.navy800);
  });

  test('contraste de marca alcanza WCAG AA para texto de controles', () {
    final light = EnterpriseThemeEngine.theme();
    final dark = EnterpriseThemeEngine.theme(brightness: Brightness.dark);

    expect(
      _contrast(light.colorScheme.onPrimary, light.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(light.colorScheme.onSecondary, light.colorScheme.secondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(dark.colorScheme.onPrimary, dark.colorScheme.primary),
      greaterThanOrEqualTo(4.5),
    );
  });
}
