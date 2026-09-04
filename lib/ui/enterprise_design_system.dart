import 'package:flutter/material.dart';

import 'merka_theme_tokens.dart';

enum EnterpriseViewport { mobile, tablet, desktop, ultraWide }

class EnterpriseBreakpoints {
  const EnterpriseBreakpoints._();

  static const mobileMax = 767.0;
  static const tabletMax = 1199.0;
  static const ultraWideMin = 1600.0;

  static EnterpriseViewport fromWidth(double width) {
    if (width <= mobileMax) return EnterpriseViewport.mobile;
    if (width <= tabletMax) return EnterpriseViewport.tablet;
    if (width >= ultraWideMin) return EnterpriseViewport.ultraWide;
    return EnterpriseViewport.desktop;
  }
}

extension EnterpriseViewportX on EnterpriseViewport {
  bool get isMobile => this == EnterpriseViewport.mobile;
  bool get isTablet => this == EnterpriseViewport.tablet;
  bool get isDesktop =>
      this == EnterpriseViewport.desktop ||
      this == EnterpriseViewport.ultraWide;
}

class EnterpriseSpacing {
  const EnterpriseSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

class EnterpriseRadii {
  const EnterpriseRadii._();

  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
}

/// Responsive sizing helpers for dialogs and dense administrative forms.
/// Keeps desktop dialogs comfortable without overflowing small windows.
class EnterpriseDialogSizing {
  const EnterpriseDialogSizing._();

  static double width(BuildContext context, double preferred) {
    final available = MediaQuery.sizeOf(context).width - 72;
    if (available <= 240) return 240;
    return available < preferred ? available : preferred;
  }

  static double height(BuildContext context, double preferred) {
    final available = MediaQuery.sizeOf(context).height - 160;
    if (available <= 220) return 220;
    return available < preferred ? available : preferred;
  }
}

class EnterpriseThemeEngine {
  const EnterpriseThemeEngine._();

  static ThemeData theme({
    Brightness brightness = Brightness.light,
    bool highContrast = false,
  }) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? MerkaThemeTokens.navy600 : MerkaThemeTokens.navy800,
      onPrimary: Colors.white,
      secondary: MerkaThemeTokens.gold500,
      onSecondary: MerkaThemeTokens.navy900,
      tertiary: MerkaThemeTokens.gold400,
      onTertiary: MerkaThemeTokens.navy900,
      error: MerkaThemeTokens.danger,
      onError: Colors.white,
      surface: dark ? MerkaThemeTokens.navy800 : MerkaThemeTokens.paper50,
      onSurface: dark ? MerkaThemeTokens.onDark : MerkaThemeTokens.onLight,
      surfaceContainerHighest: dark
          ? MerkaThemeTokens.navy700
          : MerkaThemeTokens.paper100,
      outline: highContrast
          ? (dark ? Colors.white : MerkaThemeTokens.navy800)
          : (dark ? MerkaThemeTokens.graphite600 : MerkaThemeTokens.paper100),
    );

    final background = dark
        ? MerkaThemeTokens.navy900
        : MerkaThemeTokens.paper50;
    final panel = dark ? MerkaThemeTokens.navy800 : Colors.white;
    final border = highContrast
        ? scheme.outline
        : (dark ? MerkaThemeTokens.navy600 : MerkaThemeTokens.paper100);
    final textTheme = _textTheme(dark);

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Roboto'],
      textTheme: textTheme,
      canvasColor: panel,
      disabledColor: (dark ? MerkaThemeTokens.paper100 : MerkaThemeTokens.graphite600)
          .withValues(alpha: 0.45),
      hoverColor: scheme.secondary.withValues(alpha: 0.08),
      highlightColor: scheme.secondary.withValues(alpha: 0.10),
      splashColor: scheme.secondary.withValues(alpha: 0.12),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.secondary,
        selectionColor: scheme.secondary.withValues(alpha: 0.24),
        selectionHandleColor: scheme.secondary,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: panel,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: EnterpriseSpacing.xs),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel,
        prefixIconColor: MerkaThemeTokens.graphite600,
        suffixIconColor: MerkaThemeTokens.graphite600,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          borderSide: BorderSide(color: scheme.secondary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EnterpriseSpacing.lg,
          vertical: 14,
        ),
        isDense: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: border),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 40)),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(EnterpriseRadii.md),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: border, width: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.sm),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.secondary : MerkaThemeTokens.graphite600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.onSecondary : Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? scheme.secondary
                : (dark ? MerkaThemeTokens.navy700 : MerkaThemeTokens.paper100)),
        trackOutlineColor: WidgetStatePropertyAll(border),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? MerkaThemeTokens.navy700
            : MerkaThemeTokens.paper100,
        selectedColor: dark
            ? MerkaThemeTokens.navy600
            : MerkaThemeTokens.gold200,
        disabledColor: dark
            ? MerkaThemeTokens.navy900
            : MerkaThemeTokens.paper100,
        labelStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: scheme.onSurface),
        checkmarkColor: scheme.secondary,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 48,
        iconColor: scheme.secondary,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.secondary,
        unselectedLabelColor: dark
            ? MerkaThemeTokens.paper100
            : MerkaThemeTokens.graphite600,
        indicatorColor: scheme.secondary,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: panel,
        indicatorColor: scheme.secondary.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: scheme.secondary),
        unselectedIconTheme: IconThemeData(
          color: dark
              ? MerkaThemeTokens.paper100
              : MerkaThemeTokens.graphite600,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.secondary,
          fontWeight: FontWeight.w900,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: scheme.secondary.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.secondary
              : (dark ? MerkaThemeTokens.paper100 : MerkaThemeTokens.graphite600),
        )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            textTheme.labelSmall?.copyWith(
              color: states.contains(WidgetState.selected)
                  ? scheme.secondary
                  : (dark ? MerkaThemeTokens.paper100 : MerkaThemeTokens.graphite600),
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w900
                  : FontWeight.w700,
            )),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
            borderSide: BorderSide(color: scheme.secondary, width: 2),
          ),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: WidgetStatePropertyAll(BorderSide(color: border)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EnterpriseRadii.md),
          ),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
        hintStyle: WidgetStatePropertyAll(textTheme.bodyMedium?.copyWith(color: MerkaThemeTokens.graphite600)),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: scheme.secondary,
        collapsedIconColor: MerkaThemeTokens.graphite600,
        textColor: scheme.onSurface,
        collapsedTextColor: scheme.onSurface,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.secondary,
        linearTrackColor: dark ? MerkaThemeTokens.navy700 : MerkaThemeTokens.paper100,
        circularTrackColor: dark ? MerkaThemeTokens.navy700 : MerkaThemeTokens.paper100,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: panel,
        modalBarrierColor: Colors.black.withValues(alpha: 0.36),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.lg),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: scheme.onSurface,
        ),
        dataTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
        headingRowColor: WidgetStatePropertyAll(
          dark ? MerkaThemeTokens.navy900 : MerkaThemeTokens.paper100,
        ),
        dividerThickness: 1,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: const WidgetStatePropertyAll(false),
        thumbColor: WidgetStatePropertyAll(
          scheme.secondary.withValues(alpha: dark ? 0.55 : 0.36),
        ),
        radius: const Radius.circular(EnterpriseRadii.md),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? MerkaThemeTokens.paper100 : MerkaThemeTokens.navy800,
          borderRadius: BorderRadius.circular(EnterpriseRadii.sm),
        ),
        textStyle: TextStyle(
          color: dark ? MerkaThemeTokens.navy900 : Colors.white,
        ),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.secondary,
        textColor: scheme.onSecondary,
        textStyle: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: scheme.primary,
        headerForegroundColor: scheme.onPrimary,
        todayBorder: BorderSide(color: scheme.secondary),
        todayForegroundColor: WidgetStatePropertyAll(scheme.secondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.lg),
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: panel,
        dialBackgroundColor: dark ? MerkaThemeTokens.navy700 : MerkaThemeTokens.paper100,
        dialHandColor: scheme.secondary,
        hourMinuteColor: dark ? MerkaThemeTokens.navy700 : MerkaThemeTokens.paper100,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.lg),
        ),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: panel,
        contentTextStyle: textTheme.bodyMedium,
        padding: const EdgeInsets.all(EnterpriseSpacing.lg),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? MerkaThemeTokens.paper100
            : MerkaThemeTokens.navy800,
        contentTextStyle: TextStyle(
          color: dark ? MerkaThemeTokens.navy900 : Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
      ),
      focusColor: scheme.secondary.withValues(
        alpha: highContrast ? 0.35 : 0.18,
      ),
    );
  }

  static TextTheme _textTheme(bool dark) {
    final color = dark ? MerkaThemeTokens.onDark : MerkaThemeTokens.onLight;
    final muted = dark
        ? MerkaThemeTokens.paper100
        : MerkaThemeTokens.graphite600;
    return TextTheme(
      displaySmall: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 34,
        height: 1.08,
        fontWeight: FontWeight.w900,
        color: color,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 24,
        height: 1.16,
        fontWeight: FontWeight.w900,
        color: color,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: color,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: color,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: color,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: color),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: color),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: muted),
      labelLarge: TextStyle(
        fontSize: 13,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: color,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: muted,
      ),
    );
  }
}

class EnterprisePanel extends StatelessWidget {
  const EnterprisePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(EnterpriseSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outline.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(EnterpriseRadii.md),
      ),
      child: child,
    );
  }
}

class EnterpriseStatusPill extends StatelessWidget {
  const EnterpriseStatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(EnterpriseRadii.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
