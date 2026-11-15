import 'package:flutter/material.dart' hide Text;

/// ألوان الهوية (من التصميم المعتمد).
class Brand {
  static const green = Color(0xFF126B4B); // Tijaro Green: اللون الأساسي
  static const fresh = Color(0xFF39B982); // Fresh Green: الحيوية والتفاعل
  static const orange = Color(0xFFF7931E); // البرتقالي: لمسة الشعار
  static const soft = Color(0xFFF4F8F5); // Soft White: الخلفيات
  static const forest = Color(0xFF172B27); // Deep Forest: النص
}

/// واجهة بيضاء نظيفة، والأخضر للأزرار والعناصر المهمة.
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.green,
    brightness: Brightness.light,
  ).copyWith(
    primary: Brand.green,
    onPrimary: Colors.white,
    secondary: Brand.fresh,
    surface: Colors.white,
    onSurface: Brand.forest,
    surfaceContainerHighest: Brand.soft,
    surfaceContainerLow: Colors.white,
    primaryContainer: const Color(0xFFD9F1E5),
    onPrimaryContainer: Brand.green,
  );
  final border = BorderRadius.circular(16);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Brand.forest,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE3ECE6)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: border),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.green,
        side: const BorderSide(color: Brand.green),
        shape: RoundedRectangleBorder(borderRadius: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.soft,
      border: OutlineInputBorder(borderRadius: border, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: border, borderSide: const BorderSide(color: Brand.green, width: 1.5)),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xFFD9F1E5),
    ),
    chipTheme: ChipThemeData(
      selectedColor: Brand.green,
      backgroundColor: Brand.soft,
      labelStyle: const TextStyle(color: Brand.forest),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      checkmarkColor: Colors.white,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE3ECE6)),
  );
}
