import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color defaultSeed = Color(0xFF0F4C81);

  /// "#0F4C81" → Color. Cor da marca do cliente (White-Label).
  static Color parseHex(String? hex, {Color fallback = defaultSeed}) {
    if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) return fallback;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  static ThemeData build({Color seed = defaultSeed, Brightness brightness = Brightness.light}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
    );
  }
}
