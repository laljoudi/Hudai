import 'package:flutter/material.dart';
import 'package:gp_hudai/features/splash/splash_screen.dart';
import 'package:gp_hudai/features/camera/camera_screen.dart';
import 'package:gp_hudai/features/settings/settings_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String camera = '/camera';
  static const String settings = '/settings';

  static final Map<String, WidgetBuilder> routes = {
    splash: (_) => const SplashScreen(),
    camera: (_) => const CameraScreen(),
    settings: (_) => const SettingsScreen(),
  };
}
