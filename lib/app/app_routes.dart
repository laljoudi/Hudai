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

  static const String splash             = '/';
  static const String voiceInstructions  = '/voice-instructions';
  static const String setup              = '/setup';
  static const String camera             = '/camera';
  static const String settings           = '/settings';
  static const String settingsEmergency  = '/settings/emergency';
  static const String yoloDebug          = '/yolo-debug';

  static final Map<String, WidgetBuilder> routes = {
    splash:            (_) => const SplashScreen(),
    voiceInstructions: (_) => const VoiceInstructionsScreen(),
    setup:             (_) => const SetupScreen(),
    camera:            (_) => const CameraScreen(),
    settings:          (_) => const SettingsScreen(),
    settingsEmergency: (_) => const SettingsEmergencyScreen(),
    yoloDebug:         (_) => const YoloDebugScreen(),
  };
}
