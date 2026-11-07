import 'package:flutter/material.dart';

abstract final class AppTokens {
  static const font = 'DM Sans';
  static const primary = Color(0xFF24564B);
  static const paper = Color(0xFFF7F7F2);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1C2926);
  static const muted = Color(0xFF576963);
  static const sage = Color(0xFFE4EEE6);
  static const clay = Color(0xFFB95D44);
  static const line = Color(0xFFDEE4DC);
  static const control = Color(0xFF76857E);
  static const quiet = Color(0xFFEEF1EB);
  static const info = Color(0xFF345962);
  static const infoSurface = Color(0xFFE5EFF0);
  static const warning = Color(0xFF70491F);
  static const warningSurface = Color(0xFFF6EBD9);
  static const error = Color(0xFF8C3427);
  static const errorSurface = Color(0xFFF8E8E3);
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const gap = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;
  static const gutter = 16.0;
  static const cardRadius = 16.0;
  static const controlRadius = 12.0;
  static const maxWidth = 960.0;
  static const formWidth = 560.0;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppTokens.primary).copyWith(
    primary: AppTokens.primary,
    onPrimary: AppTokens.surface,
    primaryContainer: AppTokens.sage,
    onPrimaryContainer: AppTokens.primary,
    secondary: AppTokens.primary,
    onSecondary: AppTokens.surface,
    secondaryContainer: AppTokens.sage,
    onSecondaryContainer: AppTokens.ink,
    surface: AppTokens.paper,
    surfaceContainerLowest: AppTokens.surface,
    surfaceContainerLow: AppTokens.quiet,
    surfaceContainer: AppTokens.surface,
    onSurface: AppTokens.ink,
    onSurfaceVariant: AppTokens.muted,
    outline: AppTokens.control,
    outlineVariant: AppTokens.line,
    error: AppTokens.error,
    errorContainer: AppTokens.errorSurface,
    onErrorContainer: AppTokens.error,
    inverseSurface: AppTokens.ink,
    onInverseSurface: AppTokens.paper,
    inversePrimary: AppTokens.sage,
  );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: AppTokens.font,
    fontFamilyFallback: const ['Roboto'],
    colorScheme: scheme,
    scaffoldBackgroundColor: AppTokens.paper,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
  TextStyle type(double size, FontWeight weight, double height) => TextStyle(
    fontFamily: AppTokens.font,
    fontFamilyFallback: const ['Roboto'],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: AppTokens.ink,
  );
  final text = base.textTheme.copyWith(
    headlineLarge: type(34, FontWeight.w700, 1.14),
    headlineMedium: type(28, FontWeight.w700, 1.18),
    headlineSmall: type(26, FontWeight.w700, 1.2),
    titleLarge: type(22, FontWeight.w700, 1.25),
    titleMedium: type(16, FontWeight.w600, 1.34),
    titleSmall: type(15, FontWeight.w600, 1.35),
    bodyLarge: type(16, FontWeight.w400, 1.44),
    bodyMedium: type(15, FontWeight.w400, 1.44),
    bodySmall: type(13, FontWeight.w400, 1.4),
    labelLarge: type(15, FontWeight.w600, 1.3),
    labelMedium: type(13, FontWeight.w600, 1.32),
    labelSmall: type(12, FontWeight.w600, 1.32),
  );
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.controlRadius),
  );
  OutlineInputBorder inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.controlRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppTokens.paper,
      foregroundColor: AppTokens.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      toolbarHeight: 60,
      titleSpacing: AppTokens.gutter,
      titleTextStyle: type(18, FontWeight.w700, 1.24),
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppTokens.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppTokens.surface,
      labelStyle: text.labelMedium!.copyWith(color: AppTokens.muted),
      hintStyle: text.bodyMedium!.copyWith(color: AppTokens.muted),
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: inputBorder(AppTokens.control),
      enabledBorder: inputBorder(AppTokens.control),
      focusedBorder: inputBorder(AppTokens.primary, width: 2),
      errorBorder: inputBorder(AppTokens.error),
      focusedErrorBorder: inputBorder(AppTokens.error, width: 2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: text.labelLarge,
        shape: controlShape,
        disabledForegroundColor: AppTokens.muted,
        disabledBackgroundColor: AppTokens.quiet,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: text.labelLarge,
        shape: controlShape,
        side: const BorderSide(color: AppTokens.control),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: text.labelLarge,
        shape: controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size.square(48)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppTokens.surface,
      selectedColor: AppTokens.sage,
      disabledColor: AppTokens.quiet,
      labelStyle: text.labelMedium,
      side: const BorderSide(color: AppTokens.control),
      shape: controlShape,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      checkmarkColor: AppTokens.primary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppTokens.sage,
      indicatorShape: controlShape,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppTokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: AppTokens.line, space: 1),
    listTileTheme: const ListTileThemeData(
      minTileHeight: 56,
      selectedColor: AppTokens.primary,
      selectedTileColor: AppTokens.sage,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTokens.ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: AppTokens.paper),
      shape: controlShape,
    ),
  );
}
