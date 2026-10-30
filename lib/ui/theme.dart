import 'dart:typed_data';

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cream = Color(0xFFFFF8F2),
      pink = Color(0xFFAA496C),
      palePink = Color(0xFFF8E4EA),
      ink = Color(0xFF402D37),
      muted = Color(0xFF7D6872),
      line = Color(0xFFEADBD9),
      green = Color(0xFF356A56),
      lightGreen = Color(0xFFE8F2E9);
}

class AppAppearance extends ThemeExtension<AppAppearance> {
  const AppAppearance({this.backgroundImage});
  final Uint8List? backgroundImage;
  @override
  AppAppearance copyWith({Uint8List? backgroundImage}) =>
      AppAppearance(backgroundImage: backgroundImage ?? this.backgroundImage);
  @override
  AppAppearance lerp(covariant AppAppearance? other, double t) =>
      t < .5 ? this : other ?? this;
}

ThemeData appTheme({
  Color? textColor,
  Color? primaryColor,
  Uint8List? backgroundImage,
}) {
  final text = textColor ?? AppColors.ink;
  final primary = primaryColor ?? AppColors.pink;
  final muted = text == AppColors.ink
      ? AppColors.muted
      : Color.lerp(text, Colors.white, .35)!;
  final container = primary == AppColors.pink
      ? AppColors.palePink
      : Color.lerp(primary, Colors.white, .86)!;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: primary,
        onPrimary: primary.computeLuminance() > .179
            ? Colors.black
            : Colors.white,
        primaryContainer: container,
        onPrimaryContainer: text,
        surface: AppColors.cream,
        onSurface: text,
        onSurfaceVariant: muted,
        outline: AppColors.line,
        secondary: AppColors.green,
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'BeVietnamPro',
    extensions: [AppAppearance(backgroundImage: backgroundImage)],
    colorScheme: scheme,
    iconTheme: IconThemeData(color: primary),
    scaffoldBackgroundColor: AppColors.cream,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Lora',
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -.8,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Lora',
        fontSize: 25,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -.6,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.45,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6),
      bodyMedium: TextStyle(fontSize: 13, height: 1.55),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ).apply(bodyColor: text, displayColor: text),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
      labelStyle: TextStyle(color: muted, fontSize: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.cream,
      indicatorColor: container,
      height: 78,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      space: 24,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
