import 'package:flutter/material.dart';

class AppColors {
  
  static const Color primary = Color(00192F); // أزرق غامق
  static const Color secondary = Color(2F4156); // تركواز
  static const Color background = Color(0xFFF5F7FA); // خلفية فاتحة
  static const Color surface = Colors.white;
  static const Color error = Color(0xFFD32F2F);

  // ألوان نصوص
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      background: AppColors.background,
      onBackground: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),

    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 16,
        color: AppColors.textSecondary,
      ),
    ),
  );
}
