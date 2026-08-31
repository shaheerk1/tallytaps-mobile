import 'package:flutter/material.dart';

/// Central colour palette for Tally.
///
/// Light, warm and high-contrast so the app stays readable for everyone,
/// including older users. Colours are grouped by action category so each
/// big button is instantly recognisable.
class AppColors {
  AppColors._();

  // Base surfaces
  static const Color background = Color(0xFFF2F4F8);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF16212E);
  static const Color inkSoft = Color(0xFF5C6775);
  static const Color inkFaint = Color(0xFF8A93A0);
  static const Color line = Color(0xFFE4E8F0);

  // Brand (app identity + record button)
  static const Color brandtheme = Color(0xFF8BFF4D);
  static const Color brand = Color(0xFF0B7A5B);
  static const Color brandDark = Color(0xFF08634A);

  // Category accents
  static const Color cash = Color(0xFF12A150);
  static const Color card = Color(0xFF2F6BFF);
  static const Color stock = Color(0xFFE8890C);
  static const Color note = Color(0xFF7C3AED);

  // Soft category tints (for icons inside light chips)
  static const Color cashSoft = Color(0xFFE3F6EA);
  static const Color cardSoft = Color(0xFFE8F0FF);
  static const Color stockSoft = Color(0xFFFFF0DC);
  static const Color noteSoft = Color(0xFFF1EAFE);

  // Direction accents
  static const Color positive = Color(0xFF12A150);
  static const Color negative = Color(0xFFE03A3A);

  // Pad keys
  static const Color key = Colors.white;
  static const Color keyText = Color(0xFF1C2A38);
}
