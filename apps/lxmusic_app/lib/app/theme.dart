import 'package:flutter/material.dart';

const _seedColor = Color(0xFF146356);
const _scaffoldBg = Color(0xFFF4F1E8);
const _gradientStart = Color(0xFFF5ECD8);
const _gradientEnd = Color(0xFFE6F2EF);

const backgroundGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[_gradientStart, _gradientEnd],
);

ThemeData buildTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: _scaffoldBg,
    useMaterial3: true,
  );

  return base.copyWith(
    cardTheme: base.cardTheme.copyWith(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0x1A000000)),
      ),
    ),
  );
}
