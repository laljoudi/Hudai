import 'package:flutter/material.dart';
import 'app_routes.dart';
import 'app_theme.dart';

class HudaiApp extends StatelessWidget {
  const HudaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GP Hudai',
      theme: AppTheme.light(),
      initialRoute: AppRoutes.splash,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      
    );
  }
}
