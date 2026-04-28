import 'dart:ui';
 
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:gp_hudai/app/app_routes.dart';
import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/services/location_service.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
 
const bool kForceMockCamera = false;
 
// ─────────────────────────────────────────────────────────────────────────────
//  Audio file paths used by this screen.
//  Drop the MP3 files at these paths and they play automatically.
// ─────────────────────────────────────────────────────────────────────────────
class _CameraAudio {
  // Voice intro that explains the screen layout (plays once on first visit)
  static const String intro = 'assets/audio/camera/camera_intro.mp3';
 
  // Location feature audio
  static const String insideArafat     = 'assets/audio/location/inside_arafat.mp3';
  static const String outsideArafat    = 'assets/audio/location/outside_arafat.mp3';
  static const String permissionDenied = 'assets/audio/location/permission_denied.mp3';
  static const String gpsDisabled      = 'assets/audio/location/gps_disabled.mp3';
  static const String locationError    = 'assets/audio/location/location_error.mp3';
}
 
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
 
  final _permissionService     = const PermissionService();
  final _locationService       = const LocationService();
  final AudioPlayer _audioPlayer = AudioPlayer();
 
  bool _locationBusy = false;
 
  @override
  void initState() {
    super.initState();
    _initCamera();
    _playIntroOnce();
  }
 
  @override
  void dispose() {
    _audioPlayer.dispose();
    _controller?.dispose();
    super.dispose();
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Voice intro — plays only on first visit.
  //  Uses Prefs to remember if the user has already heard it.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _playIntroOnce() async {
    // final hasHeard = await Prefs.hasHeardCameraIntro();
   //  if (hasHeard) return;
 
    await Future.delayed(const Duration(milliseconds: 800));
    await _playAudio(_CameraAudio.intro);
    await Prefs.markCameraIntroHeard();
  }
 
  Future<void> _replayIntro() async {
    await _playAudio(_CameraAudio.intro);
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Camera lifecycle
  // ─────────────────────────────────────────────────────────────────────────
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
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
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
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Audio playback helper
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _playAudio(String path) async {
  debugPrint('🔊 STEP 1: trying to play $path');
  try {
    // audioplayers expects path WITHOUT "assets/" prefix
    final assetPath = path.replaceFirst('assets/', '');
    await _audioPlayer.play(AssetSource(assetPath));
    debugPrint('🔊 STEP 2: play() returned');
  } catch (e) {
    debugPrint('🔊 ERROR: $e');
  }
}
  // ─────────────────────────────────────────────────────────────────────────
  //  Quadrant actions
  // ─────────────────────────────────────────────────────────────────────────
  void _onSettingsTap() {
    Navigator.pushNamed(context, AppRoutes.settings);
  }
 
  void _onEmergencyTap() {
    // TODO: PhoneService().callEmergency() — your colleague's task
  }
 
  Future<void> _onLocationTap() async {
    if (_locationBusy) return;
    setState(() => _locationBusy = true);
 
    try {
      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        await _playAudio(_CameraAudio.permissionDenied);
        return;
      }
 
      final position = await _locationService.getCurrentPosition();
      debugPrint('GPS: ${position.latitude}, ${position.longitude}');
 
      final inside = _locationService.isInsideCircle(
        position,
        LocationConstants.arafatZone,
      );
 
      await _playAudio(
        inside ? _CameraAudio.insideArafat : _CameraAudio.outsideArafat,
      );
    } on LocationServiceDisabledException {
      await _playAudio(_CameraAudio.gpsDisabled);
    } catch (_) {
      await _playAudio(_CameraAudio.locationError);
    } finally {
      if (mounted) setState(() => _locationBusy = false);
    }
  }
  
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 0 — Camera feed
          _buildCamera(),
 
          // Layer 1 — 4 invisible quadrant tap zones (entire screen)
          Positioned.fill(child: _buildQuadrants()),
 
          // Layer 2 — Visual glassy header (icons appear in top corners)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _buildGlassyHeader(),
            ),
          ),
 
          // Layer 3 — Visual glassy footer (icons appear in bottom corners)
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildGlassyFooter(),
          ),
        ],
      ),
    );
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Quadrant tap zones — invisible, cover entire screen
  //  Top-left      = Settings
  //  Top-right     = Emergency
  //  Bottom-left   = Replay intro
  //  Bottom-right  = Location
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildQuadrants() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _quadrant(onTap: _onSettingsTap)),
              Expanded(child: _quadrant(onTap: _onEmergencyTap)),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _quadrant(onTap: _replayIntro)),
              Expanded(child: _quadrant(onTap: _onLocationTap)),
            ],
          ),
        ),
      ],
    );
  }
 
  Widget _quadrant({required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Glassy header — top capsule with Settings (left) + Emergency (right)
  //  IgnorePointer = lets taps pass through to the quadrants behind
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGlassyHeader() {
    return IgnorePointer(
      child: Container(
        margin:  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        height:  64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  _GlassyIconBadge(icon: Icons.settings),
                  _GlassyIconBadge(icon: Icons.call),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Glassy footer — bottom capsule with Replay (left) + Location (right)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildGlassyFooter() {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        height: 76,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(38),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(38),
                border: Border.all(
                  color: Colors.white.withOpacity(0.20),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _GlassyIconBadge(icon: Icons.replay),
                  _locationBusy
                      ? const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const _GlassyIconBadge(icon: Icons.location_on),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
 
  // ─────────────────────────────────────────────────────────────────────────
  //  Camera feed
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCamera() {
    if (_useMockCamera) return _buildMockCamera();
 
    if (_initializeFuture == null || _controller == null) {
      return const ColoredBox(color: Color(0xFF030A20));
    }
 
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const ColoredBox(color: Color(0xFF030A20));
        }
 
        final size      = MediaQuery.sizeOf(context);
        final camAspect = _controller!.value.aspectRatio;
 
        return OverflowBox(
          maxWidth:  double.infinity,
          maxHeight: double.infinity,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width:  size.width,
              height: size.width / camAspect,
              child:  CameraPreview(_controller!),
            ),
          ),
        );
      },
    );
  }
 
  Widget _buildMockCamera() {
    return Container(
      decoration: const BoxDecoration(
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
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white38, size: 52),
            const SizedBox(height: 14),
            Text(
              _cameraError ?? 'وضع تجريبي بدون كاميرا',
              style: const TextStyle(color: Colors.white60, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
 
// ─────────────────────────────────────────────────────────────────────────────
//  Glassy icon badge — small frosted circular icon
// ─────────────────────────────────────────────────────────────────────────────
 
class _GlassyIconBadge extends StatelessWidget {
  const _GlassyIconBadge({required this.icon});
  final IconData icon;
 
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width:  46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.22),
                const Color(0xFF40E0FF).withOpacity(0.10),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.32),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color:      const Color(0xFF1855FF).withOpacity(0.18),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}