
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/constants/app_strings.dart';
import 'package:gp_hudai/core/constants/colors.dart';
import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/services/location_service.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/services/tts_service.dart';

// اجعليها true لتفعيل وضع تجريبي بدون كاميرا.
const bool kForceMockCamera = false;

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeFuture;
  String? _cameraError;
  bool _useMockCamera = false;

  final _permissionService = const PermissionService();
  final _locationService = const LocationService();
  final _ttsService = const TtsService();

  bool _locationBusy = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kForceMockCamera) {
      if (mounted) setState(() => _useMockCamera = true);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _useMockCamera = true;
          _cameraError = 'لا توجد كاميرا متاحة، تم تفعيل الوضع التجريبي.';
        });
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );

      _initializeFuture = _controller!.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {
          _useMockCamera = true;
          _cameraError = 'تعذر تشغيل الكاميرا، تم تفعيل الوضع التجريبي.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleLocationTap() async {
    if (_locationBusy) return;

    setState(() => _locationBusy = true);

    try {
      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        await _ttsService.speak(AppStrings.locationPermissionDenied);
        return;
      }

      final position = await _locationService.getCurrentPosition();
      debugPrint('GPS: ${position.latitude}, ${position.longitude}');

      final inside = _locationService.isInsideCircle(
        position,
        LocationConstants.arafatZone,
      );

      final message = inside
          ? AppStrings.locationInsideArafat
          : AppStrings.locationOutside;

      await _ttsService.speak(message);
    } on LocationServiceDisabledException {
      await _ttsService.speak(AppStrings.locationServiceDisabled);
    } catch (_) {
      await _ttsService.speak(AppStrings.locationError);
    } finally {
      if (mounted) {
        setState(() => _locationBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCamera(),

          // Header (Emergency + Settings)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                height: 60,
                decoration: BoxDecoration(
                  gradient: AppColors.header,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onLongPress: () {
                        // TODO: اتصال طوارئ
                      },
                      child: Icon(
                        Icons.call,
                        color: AppColors.button,
                        size: 28,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        color: AppColors.button,
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, AppRoutes.settings);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Footer (Notched capsule)
          Align(
            alignment: Alignment.bottomCenter,
            child: ClipPath(
              clipper: NotchedCapsuleClipper(),
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppColors.footer,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.replay,
                          color: AppColors.button,
                          size: 30,
                        ),
                        onPressed: () {
                          // TODO: إعادة آخر جملة
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.location_on,
                          color: AppColors.button,
                          size: 30,
                        ),
                        onPressed: _handleLocationTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCamera() {
    if (_useMockCamera) {
      return _buildMockCamera();
    }

    if (_initializeFuture == null || _controller == null) {
      return const SizedBox.expand();
    }

    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return CameraPreview(_controller!);
        }
        return const SizedBox.expand();
      },
    );
  }

  Widget _buildMockCamera() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F1720), Color(0xFF1B2430)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        child: Text(
          _cameraError ?? 'وضع تجريبي بدون كاميرا',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class NotchedCapsuleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final r = size.height / 2; // حواف دائرية للكبسولة
    final dipDepth = size.height * 0.55; // عمق النزول
    final dipWidth = size.width * 0.55; // عرض النزول

    final left = (size.width - dipWidth) / 2;
    final right = (size.width + dipWidth) / 2;
    final c = dipWidth * 0.40; // تحكم بنعومة المنحنى

    final path = Path();

    // زوايا الكبسولة
    path.moveTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);

    // خط علوي حتى بداية النزول
    path.lineTo(left, 0);

    // نزول ناعم شبه دائري
    path.cubicTo(
      left + c, 0,
      size.width / 2 - c, dipDepth,
      size.width / 2, dipDepth,
    );
    path.cubicTo(
      size.width / 2 + c, dipDepth,
      right - c, 0,
      right, 0,
    );

    // خط علوي حتى الزاوية اليمنى
    path.lineTo(size.width - r, 0);

    // زوايا الكبسولة
    path.quadraticBezierTo(size.width, 0, size.width, r);
    path.lineTo(size.width, size.height - r);
    path.quadraticBezierTo(size.width, size.height, size.width - r, size.height);
    path.lineTo(r, size.height);
    path.quadraticBezierTo(0, size.height, 0, size.height - r);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
515b0f7 (Update camera UI and location feature)
