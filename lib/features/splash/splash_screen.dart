import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigateTimer;

  @override
  void initState() {
    super.initState();
    _navigateTimer = Timer(const Duration(milliseconds: 3000), _goToVoice);
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    super.dispose();
  }

  void _goToVoice() {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AppRoutes.voiceInstructions);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Dark blue radial gradient background
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, 0.0),
                  radius: 1.0,
                  colors: [
                    Color(0xFF1A3A8A),
                    Color(0xFF0E2360),
                    Color(0xFF071540),
                    Color(0xFF030A20),
                  ],
                  stops: [0.0, 0.30, 0.65, 1.0],
                ),
              ),
            ),
          ),

          // Centered white circle (logo placeholder)
          Center(
            child: Container(
              width:  MediaQuery.sizeOf(context).width * 0.40,
              height: MediaQuery.sizeOf(context).width * 0.40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              // When logo is ready: child: Image.asset('assets/images/logo.png'),
            ),
          ),
        ],
      ),
    );
  }
}