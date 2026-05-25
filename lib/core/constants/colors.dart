
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

  // ── Unified UI theme ────────────────────────────────────────────────
  /// Scaffold / page background.
  static const Color bg           = Color(0xFF0F2350);
  /// Card / container fill (use .withOpacity(0.55)).
  static const Color cardBg       = Color(0xFF0F2350);
  /// Border base (use .withOpacity(0.20) for cards, 0.25 for chips).
  static const Color borderBase   = Color(0xFF8CBEFF);
  /// Chip / badge background (use .withOpacity(0.10)).
  static const Color chipBg       = Color(0xFF8CBEFF);
  /// Chip / badge text.
  static const Color chipText     = Color(0xFF9ACFFF);
  /// Audio bars & active indicators.
  static const Color audioBars    = Color(0xFF6AB8FF);
  /// Body / content text.
  static const Color bodyText     = Color(0xFFC8D8F0);
  /// Gradient stop — slightly darker top.
  static const Color bgTop        = Color(0xFF081840);
  /// Gradient stop — slightly lighter bottom.
  static const Color bgBottom     = Color(0xFF1B3878);
}

