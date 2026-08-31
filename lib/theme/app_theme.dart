import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// A single place where every widget pulls its look from.
/// Big radii, generous padding and chunky controls are deliberate:
/// the app is meant to be used with a thumb while standing in a shop.
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.5,
          height: 1.05,
        ),
        headlineLarge: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
          letterSpacing: -0.3,
        ),
        headlineMedium: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
        bodyMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
        bodySmall: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.inkSoft,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// Format a Sri Lankan Rupee amount with the Sinhala symbol.
class Money {
  Money._();

  static const String symbol = 'රු.';

  /// `1250.5` -> `රු. 1,250.50`
  static String format(double amount) {
    final abs = amount.abs();
    final isNeg = amount < 0;
    final digits = abs.toStringAsFixed(2);
    final parts = digits.split('.');
    final intPart = _commaGroup(parts[0]);
    return '${isNeg ? '−' : ''}$symbol $intPart.${parts[1]}';
  }

  /// Live preview of typed input, e.g. `1250.5` -> `රු. 1,250.50`
  static String formatInput(String input) {
    if (input.isEmpty) return '$symbol 0.00';
    final negative = input.startsWith('-');
    var digits = input;
    if (negative) digits = digits.substring(1);
    final hasDot = digits.contains('.');
    final parts = digits.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final decPart = hasDot ? '.${parts.length > 1 ? parts[1] : ''}' : '';
    return '${negative ? '−' : ''}$symbol ${_commaGroup(intPart)}$decPart';
  }

  static String _commaGroup(String digits) {
    if (digits.length <= 3) return digits;
    final sb = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      sb.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) sb.write(',');
    }
    return sb.toString();
  }

  static double parseInput(String input) {
    final clean = input.replaceAll(',', '');
    if (clean.isEmpty) return 0;
    return double.tryParse(clean) ?? 0;
  }

  /// Live preview of a plain typed number (no currency symbol),
  /// e.g. `1250.5` -> `1,250.5`, `''` -> `0`.
  static String formatNumberInput(String input) {
    if (input.isEmpty) return '0';
    final hasDot = input.contains('.');
    final parts = input.split('.');
    final intPart = parts[0].isEmpty ? '0' : parts[0];
    final decPart = hasDot ? '.${parts.length > 1 ? parts[1] : ''}' : '';
    return '${_commaGroup(intPart)}$decPart';
  }

  /// `5.0` -> `5`, `5.5` -> `5.5`, `5.25` -> `5.25`.
  static String formatQty(double qty) {
    final s = qty.toStringAsFixed(2);
    if (s.endsWith('.00')) return s.substring(0, s.length - 3);
    if (s.endsWith('0')) return s.substring(0, s.length - 1);
    return s;
  }
}

/// Short, terse haptic feedback that makes each tap feel real.
void tapHaptic() => HapticFeedback.selectionClick();

void successHaptic() => HapticFeedback.heavyImpact();

/// Soft drop shadow used under cards and the bottom dock.
List<BoxShadow> cardShadow = [
  BoxShadow(
    color: Colors.black.withValues(alpha: 0.06),
    blurRadius: 16,
    offset: const Offset(0, 6),
  ),
];
