import 'package:material_ui/material_ui.dart';

const brandGreen = Color(0xFF0B7A6E);
const brandInk = Color(0xFF0F2A2E);
const brandSand = Color(0xFFF6F3EC);
const brandCoral = Color(0xFFE2603F);

/// Largeur maximale de l'app sur grand écran (PC, tablette).
const maxAppWidth = 600.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    primary: brandGreen,
    surface: Colors.white,
    error: const Color(0xFFB3261E),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: brandSand,
    appBarTheme: const AppBarTheme(
      backgroundColor: brandSand,
      foregroundColor: brandInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: brandInk,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E0D5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9D3C5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9D3C5)),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Color(0xFFD5EDE9),
    ),
  );
}
