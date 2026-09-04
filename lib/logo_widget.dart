import 'package:flutter/material.dart';

import 'ui/merka_theme_tokens.dart';

/// Legacy brand API kept for source compatibility.
///
/// Use [MerkaThemeTokens] and [EnterpriseThemeEngine] for new UI code.
@Deprecated('Use MerkaThemeTokens and EnterpriseThemeEngine instead.')
class AppBrand {
  const AppBrand._();

  static const name = 'MerkaERP';
  static const tagline = 'Plataforma ERP empresarial';
  static const description =
      'Operacion, finanzas, contabilidad y control en un solo sistema.';

  static const primary = MerkaThemeTokens.navy800;
  static const secondary = MerkaThemeTokens.gold500;
  static const accent = MerkaThemeTokens.gold400;
  static const success = MerkaThemeTokens.success;
  static const warning = MerkaThemeTokens.warning;
  static const error = MerkaThemeTokens.danger;
  static const info = MerkaThemeTokens.info;
  static const ink = MerkaThemeTokens.graphite900;
  static const muted = MerkaThemeTokens.graphite600;
  static const surface = MerkaThemeTokens.paper50;
  static const darkSurface = MerkaThemeTokens.navy800;
  static const darkBackground = MerkaThemeTokens.navy900;
}

class MerkaLogo extends StatelessWidget {
  const MerkaLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppBrand.primary,
        borderRadius: BorderRadius.circular(size * 0.2),
        boxShadow: [
          BoxShadow(
            color: AppBrand.secondary.withValues(alpha: 0.22),
            blurRadius: size * 0.16,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Text(
                'M',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.55,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.12,
            child: Container(
              width: size * 0.18,
              height: size * 0.18,
              decoration: const BoxDecoration(
                color: AppBrand.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MerkaBrandHeader extends StatelessWidget {
  const MerkaBrandHeader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleStyle = compact
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.headlineSmall;
    return Row(
      children: [
        MerkaLogo(size: compact ? 42 : 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppBrand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppBrand.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppBrand.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
