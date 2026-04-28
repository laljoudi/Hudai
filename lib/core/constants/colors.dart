
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Main palette
  static const Color primary = Color(0xFF415664);
  static const Color secondary = Color(0xFF9DB9CC);
  static const Color danger = Color(0xFFFF0000);
  static const Color button = Color(0xFFF5EFEB);

  // Gradients
  static const LinearGradient header = LinearGradient(
    colors: [
      Color(0xFF00192F),
      Color(0xFF9DB9CC),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient footer = LinearGradient(
    colors: [
      Color(0xFF00192F),
      Color(0xFF9DB9CC),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Voice/orb palette
  static const Color pageBackground = Color(0xFFF5EFEB);
  static const Color orbInnerStart = Color(0xFF8393A4);
  static const Color orbInnerEnd = Color(0xFFDAE5ED);
  static const Color orbShadow1 = Color(0xFFDAE5ED);
  static const Color orbShadow2 = Color(0xFFBCCADA);
  static const Color orbArc = Color(0xFF2F4156);
}

