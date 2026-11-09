import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';

/// Material 3 theme for Discord Media Sender 2.0.
///
/// The dark theme is the primary "premium developer tool" presentation; a light
/// theme is provided as an option. Both use the same 2.0 palette and the
/// bundled Inter / Manrope typefaces (no runtime font download).
class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Inter';
  static const String _displayFontFamily = 'Manrope';

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final ColorScheme scheme =
        ColorScheme.fromSeed(
          seedColor: AppConstants.colorPrimary,
          brightness: brightness,
        ).copyWith(
          primary: AppConstants.colorPrimary,
          onPrimary: Colors.white,
          secondary: AppConstants.colorSuccess,
          error: AppConstants.colorError,
          surface: isDark
              ? AppConstants.colorSurface
              : AppConstants.colorLightSurface,
          onSurface: isDark
              ? AppConstants.colorTextPrimary
              : const Color(0xFF14161F),
          outline: AppConstants.colorBorder,
        );

    final Color onSurface = scheme.onSurface;
    final Color muted = isDark
        ? AppConstants.colorTextSecondary
        : const Color(0xFF5A6072);

    final TextTheme textTheme = TextTheme(
      displaySmall: TextStyle(
        fontFamily: _displayFontFamily,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.6,
      ),
      headlineMedium: TextStyle(
        fontFamily: _displayFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: onSurface,
        letterSpacing: -0.4,
      ),
      headlineSmall: TextStyle(
        fontFamily: _displayFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontFamily: _displayFontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 15,
        height: 1.45,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13.5,
        height: 1.45,
        color: muted,
      ),
      bodySmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        height: 1.4,
        color: muted,
      ),
      labelLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: muted,
      ),
      labelSmall: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
    );

    final Color cardColor = isDark
        ? AppConstants.colorSurface
        : AppConstants.colorLightSurface;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark
          ? AppConstants.colorBackground
          : AppConstants.colorLightBackground,
      canvasColor: isDark
          ? AppConstants.colorBackground
          : AppConstants.colorLightBackground,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark
                ? AppConstants.colorBorder.withValues(alpha: 0.7)
                : Colors.black12,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.headlineSmall,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppConstants.colorPrimary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          textTheme.labelSmall ?? const TextStyle(fontSize: 11),
        ),
        height: 68,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppConstants.colorSurfaceElevated
            : const Color(0xFFF0F1F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppConstants.colorPrimary,
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppConstants.colorError),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppConstants.colorPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppConstants.colorBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.colorPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark
            ? AppConstants.colorSurfaceElevated
            : const Color(0xFFEBECF2),
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium ?? const TextStyle(fontSize: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? AppConstants.colorBorder.withValues(alpha: 0.6)
            : Colors.black12,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? AppConstants.colorSurfaceElevated
            : const Color(0xFF23262F),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppConstants.colorPrimary,
        linearTrackColor: AppConstants.colorBorder,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppConstants.colorPrimary,
        unselectedLabelColor: muted,
        indicatorColor: AppConstants.colorPrimary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
      ),
    );
  }
}
