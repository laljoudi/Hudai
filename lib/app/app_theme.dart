import 'package:flutter/material.dart';
import 'package:gp_hudai/core/constants/colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: AppColors.danger,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: 'IBMPlexSansArabic',
        bodyColor: AppColors.bodyText,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      iconTheme: const IconThemeData(color: Colors.black),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(56, 56),
          shape: const StadiumBorder(),
        ),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(),
    );
  }
}
