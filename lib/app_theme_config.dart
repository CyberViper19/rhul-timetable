import 'package:flutter/material.dart';

/// Configuration for customizable application themes
class AppThemeConfig {
  final String key;
  final String displayName;
  final Color primaryColor;
  final Color secondaryColor;
  final Color scaffoldBackgroundColor;
  final Color cardBackgroundColor;
  final Color containerBackgroundColor;
  final Color borderColor;
  final Color textColor;
  final Color subtitleTextColor;
  final Color assessmentColor;
  final Color optionalColor;

  const AppThemeConfig({
    required this.key,
    required this.displayName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.scaffoldBackgroundColor,
    required this.cardBackgroundColor,
    required this.containerBackgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.subtitleTextColor,
    required this.assessmentColor,
    required this.optionalColor,
  });

  static AppThemeConfig getTheme(String key, Brightness systemBrightness) {
    switch (key) {
      case 'colourful':
        return const AppThemeConfig(
          key: 'colourful',
          displayName: 'Colourful',
          primaryColor: Color(0xFF6366F1),
          secondaryColor: Color(0xFF818CF8),
          scaffoldBackgroundColor: Color(0xFF0F172A),
          cardBackgroundColor: Color(0xFF1E293B),
          containerBackgroundColor: Color(0xFF0F172A),
          borderColor: Color(0xFF334155),
          textColor: Colors.white,
          subtitleTextColor: Color(0xFF94A3B8),
          assessmentColor: Color(0xFFF59E0B),
          optionalColor: Color(0xFF10B981),
        );
      case 'system':
        return systemBrightness == Brightness.dark ? _darkTheme : _lightTheme;
      case 'dark':
        return _darkTheme;
      case 'light':
        return _lightTheme;
      case 'ios_default':
        return const AppThemeConfig(
          key: 'ios_default',
          displayName: 'iOS Default',
          primaryColor: Color(0xFF0A84FF),
          secondaryColor: Color(0xFF64D2FF),
          scaffoldBackgroundColor: Color(0xFF000000),
          cardBackgroundColor: Color(0xFF1C1C1E),
          containerBackgroundColor: Color(0xFF121214),
          borderColor: Color(0xFF2C2C2E),
          textColor: Colors.white,
          subtitleTextColor: Color(0xFF8E8E93),
          assessmentColor: Color(0xFFFF9500),
          optionalColor: Color(0xFF30D158),
        );
      case 'rhul':
      default:
        return const AppThemeConfig(
          key: 'rhul',
          displayName: 'RHUL Theme',
          primaryColor: Color(0xFFF97316), // Royal Holloway Orange
          secondaryColor: Color(0xFF3B82F6), // Blue for Lectures
          scaffoldBackgroundColor: Color(0xFF000000), // Pure Black
          cardBackgroundColor: Color(0xFF121212), // Deep Pitch Black Card
          containerBackgroundColor: Color(0xFF000000), // Pure Black Container
          borderColor: Color(0xFF27272A),
          textColor: Colors.white,
          subtitleTextColor: Color(0xFFA1A1AA),
          assessmentColor: Color(0xFFF97316), // Royal Holloway Orange for Assessments
          optionalColor: Color(0xFF10B981),
        );
    }
  }

  static const AppThemeConfig _darkTheme = AppThemeConfig(
    key: 'dark',
    displayName: 'Dark Mode',
    primaryColor: Colors.white,
    secondaryColor: Color(0xFF3B82F6),
    scaffoldBackgroundColor: Color(0xFF000000),
    cardBackgroundColor: Color(0xFF141414),
    containerBackgroundColor: Color(0xFF000000),
    borderColor: Color(0xFF2E2E2E),
    textColor: Colors.white,
    subtitleTextColor: Color(0xFFA0A0A0),
    assessmentColor: Color(0xFFF97316),
    optionalColor: Color(0xFF10B981),
  );

  static const AppThemeConfig _lightTheme = AppThemeConfig(
    key: 'light',
    displayName: 'Light Mode',
    primaryColor: Color(0xFFE55B13),
    secondaryColor: Color(0xFFF97316),
    scaffoldBackgroundColor: Color(0xFFF8FAFC),
    cardBackgroundColor: Color(0xFFFFFFFF),
    containerBackgroundColor: Color(0xFFF1F5F9),
    borderColor: Color(0xFFE2E8F0),
    textColor: Color(0xFF0F172A),
    subtitleTextColor: Color(0xFF64748B),
    assessmentColor: Color(0xFFE55B13),
    optionalColor: Color(0xFF059669),
  );
}
