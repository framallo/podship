import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// podship console tokens (podship-design `mockups/podship.css`,
/// `specs/design-system.md`). Color means state and nothing else.
class PsColors extends ThemeExtension<PsColors> {
  const PsColors({
    required this.page,
    required this.surface,
    required this.container,
    required this.ink,
    required this.ink2,
    required this.hairline,
    required this.ok,
    required this.okC,
    required this.warn,
    required this.warnC,
    required this.danger,
    required this.dangerC,
    required this.run,
    required this.runC,
  });

  final Color page, surface, container, ink, ink2, hairline;
  final Color ok, okC, warn, warnC, danger, dangerC, run, runC;

  static const light = PsColors(
    page: Color(0xFFF9F9FC),
    surface: Color(0xFFFFFFFF),
    container: Color(0xFFF0F1F3),
    ink: Color(0xFF191C1E),
    ink2: Color(0xFF41484D),
    hairline: Color(0xFFDDE3EA),
    ok: Color(0xFF296B2A),
    okC: Color(0xFFE1F3D9),
    warn: Color(0xFF825500),
    warnC: Color(0xFFFFEBD4),
    danger: Color(0xFFAF2E27),
    dangerC: Color(0xFFFFE9E6),
    run: Color(0xFF2A6485),
    runC: Color(0xFFDFF0FF),
  );

  static const dark = PsColors(
    page: Color(0xFF111416),
    surface: Color(0xFF191C1E),
    container: Color(0xFF1D2022),
    ink: Color(0xFFE2E2E5),
    ink2: Color(0xFFC1C7CE),
    hairline: Color(0xFF41484D),
    ok: Color(0xFF91D888),
    okC: Color(0xFF1F2E1D),
    warn: Color(0xFFFFB94E),
    warnC: Color(0xFF372710),
    danger: Color(0xFFFFB4AB),
    dangerC: Color(0xFF3D2320),
    run: Color(0xFF97CDF3),
    runC: Color(0xFF1A2C38),
  );

  @override
  PsColors copyWith() => this;

  @override
  PsColors lerp(PsColors? other, double t) => t < .5 ? this : (other ?? this);
}

extension PsTheme on BuildContext {
  PsColors get ps => Theme.of(this).extension<PsColors>()!;
}

ThemeData buildTheme(Brightness b, {bool googleFonts = true}) {
  final c = b == Brightness.light ? PsColors.light : PsColors.dark;
  final primary = b == Brightness.light
      ? const Color(0xFF2A6485)
      : const Color(0xFF97CDF3);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF2A6485),
        brightness: b,
      ).copyWith(
        primary: primary,
        onPrimary: b == Brightness.light
            ? Colors.white
            : const Color(0xFF00344C),
        surface: c.surface,
        onSurface: c.ink,
        onSurfaceVariant: c.ink2,
        outlineVariant: c.hairline,
        error: c.danger,
      );
  final base = ThemeData(brightness: b).textTheme;
  final text = (googleFonts ? GoogleFonts.ibmPlexSansTextTheme(base) : base)
      .apply(bodyColor: c.ink, displayColor: c.ink);
  const control = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(6)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.page,
    textTheme: text,
    extensions: [c],
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: c.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: control,
        minimumSize: const Size(48, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: control,
        minimumSize: const Size(48, 44),
        foregroundColor: c.ink,
        side: BorderSide(color: c.hairline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: control,
        minimumSize: const Size(48, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      filled: true,
      fillColor: c.surface,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
  );
}

/// Monospace for ids, hints and account numbers.
TextStyle mono(BuildContext context, {double size = 13}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: context.ps.ink);
