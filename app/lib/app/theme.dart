import 'package:flutter/material.dart';

/// Tokens de espaçamento (`space.4…32`) e raio (`radius.small…large`).
abstract final class Space {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
}

abstract final class Radii {
  static const small = Radius.circular(8);
  static const medium = Radius.circular(12);
  static const large = Radius.circular(20);
}

/// Base verde-azulada calma. Natureza pública/privada não recebe cor de
/// julgamento: ambas usam o mesmo estilo neutro.
const _seed = Color(0xFF00696E);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
    contrastLevel: 0.5,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    // Alvos de toque de pelo menos 48 dp.
    materialTapTargetSize: MaterialTapTargetSize.padded,
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: Space.s16, vertical: Space.s4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.medium),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radii.small),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radii.large)),
      filled: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
  );
}
