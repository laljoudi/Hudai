import 'package:flutter/material.dart';
import 'package:gp_hudai/features/splash/splash_screen.dart';
import 'package:gp_hudai/features/onboarding/voice_instructions_screen.dart';
import 'package:gp_hudai/features/setup/setup_screen.dart';
import 'package:gp_hudai/features/camera/camera_screen.dart';
import 'package:gp_hudai/features/settings/settings_screen.dart';
import 'package:gp_hudai/features/settings/settings_emergency_screen.dart';
import 'package:gp_hudai/features/debug/yolo_debug_screen.dart';

class AppRoutes {
  AppRoutes._();

<<<<<<< HEAD
  static const String splash             = '/';
  static const String voiceInstructions  = '/voice-instructions';
  static const String setup              = '/setup';
  static const String camera             = '/camera';
  static const String settings           = '/settings';
  static const String settingsEmergency  = '/settings/emergency';
  static const String yoloDebug          = '/yolo-debug';
=======
  static const String splash = '/';
  static const String voiceInstructions = '/voice-instructions';
  static const String setup = '/setup';
  static const String camera = '/camera';
  static const String settings = '/settings';
  static const String settingsEmergency = '/settings/emergency';
  static const String yoloDebug = '/yolo-debug';
>>>>>>> 654d437 (Camera + Integration improvements)

  static final Map<String, WidgetBuilder> routes = {
    splash: (_) => const SplashScreen(),
    voiceInstructions: (_) => const VoiceInstructionsScreen(),
<<<<<<< HEAD
    setup:             (_) => const SetupScreen(),
    camera:            (_) => const CameraScreen(),
    settings:          (_) => const SettingsScreen(),
    settingsEmergency: (_) => const SettingsEmergencyScreen(),
    yoloDebug:         (_) => const YoloDebugScreen(),
=======
    setup: (_) => const SetupScreen(),
    camera: (_) => const CameraScreen(),
    settings: (_) => const SettingsScreen(),
    settingsEmergency: (_) => const SettingsEmergencyScreen(),
    yoloDebug: (_) => const YoloDebugScreen(),
>>>>>>> 654d437 (Camera + Integration improvements)
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final builder = routes[settings.name];

    if (builder == null) {
      return null;
    }

    if (settings.name == voiceInstructions) {
      return PageRouteBuilder(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 750),
        reverseTransitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) {
          return builder(context);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );

          return FadeTransition(
            opacity: curved,
            child: child,
          );
        },
      );
    }

    return MaterialPageRoute(
      settings: settings,
      builder: builder,
    );
  }
}