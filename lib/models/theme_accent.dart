import 'package:flutter/material.dart';

/// 全局强调色；浅色与深色各配一套，默认玫粉。
enum ThemeAccent {
  rose(
    '玫粉',
    lightAccent: Color(0xFFD81B60),
    lightDeep: Color(0xFFAD1457),
    lightSoft: Color(0xFFFCE4EC),
    darkAccent: Color(0xFFFF6BA5),
    darkDeep: Color(0xFFE84C8D),
    darkOnAccent: Color(0xFF2A0614),
  ),
  blue(
    '晴蓝',
    lightAccent: Color(0xFF2563EB),
    lightDeep: Color(0xFF1D4ED8),
    lightSoft: Color(0xFFE3EDFF),
    darkAccent: Color(0xFF6FA8FF),
    darkDeep: Color(0xFF4A8BFF),
    darkOnAccent: Color(0xFF06152E),
  ),
  teal(
    '青绿',
    lightAccent: Color(0xFF0B7A6A),
    lightDeep: Color(0xFF085E52),
    lightSoft: Color(0xFFDDF5F0),
    darkAccent: Color(0xFF63DFC6),
    darkDeep: Color(0xFF3FC9AE),
    darkOnAccent: Color(0xFF04231D),
  ),
  amber(
    '琥珀',
    lightAccent: Color(0xFFB45309),
    lightDeep: Color(0xFF92400E),
    lightSoft: Color(0xFFFEF3C7),
    darkAccent: Color(0xFFFFB067),
    darkDeep: Color(0xFFFF9440),
    darkOnAccent: Color(0xFF2A1400),
  ),
  violet(
    '紫罗兰',
    lightAccent: Color(0xFF7C3AED),
    lightDeep: Color(0xFF6D28D9),
    lightSoft: Color(0xFFEDE9FE),
    darkAccent: Color(0xFFB79CFF),
    darkDeep: Color(0xFF9B78FF),
    darkOnAccent: Color(0xFF160A33),
  );

  const ThemeAccent(
    this.label, {
    required this.lightAccent,
    required this.lightDeep,
    required this.lightSoft,
    required this.darkAccent,
    required this.darkDeep,
    required this.darkOnAccent,
  });

  final String label;
  final Color lightAccent;
  final Color lightDeep;
  final Color lightSoft;
  final Color darkAccent;
  final Color darkDeep;
  final Color darkOnAccent;

  /// 深色主题下用于浅强调底，透出背后深色背景。
  Color get darkSoft => darkAccent.withValues(alpha: 0.15);

  Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAccent : lightAccent;

  static ThemeAccent fromName(String? name, {ThemeAccent fallback = ThemeAccent.rose}) {
    return values.firstWhere((value) => value.name == name, orElse: () => fallback);
  }
}
