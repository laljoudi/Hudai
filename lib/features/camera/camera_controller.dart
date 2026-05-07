import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart' as cam;
import 'package:flutter/foundation.dart';

import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/services/yolo_service.dart';
import 'package:gp_hudai/core/services/frame_preprocessor.dart';
import 'package:gp_hudai/core/services/detection_decoder.dart';
import 'package:gp_hudai/core/services/inference_throttler.dart';
import 'package:gp_hudai/core/services/location_service.dart';
import 'package:gp_hudai/core/services/permission_service.dart';
import 'package:gp_hudai/core/storage/prefs.dart';
import 'package:gp_hudai/features/camera/camera_state.dart';

const bool kForceMockCamera = false;

/// Audio file paths used by the camera screen.
/// Note: audioplayers uses paths WITHOUT the 'assets/' prefix.
class _CameraAudio {
  static const String intro                = 'audio/camera/camera_intro.mp3';
  static const String insideArafat         = 'audio/location/inside_arafat.mp3';
  static const String outsideArafat        = 'audio/location/outside_arafat.mp3';
  static const String locationUnavailable  = 'audio/location/location_unavailable.mp3';
}

/// The brain of the camera screen.
///
/// Manages: camera lifecycle, audio playback, location queries,
/// AI pipeline (added in Phase C).
///
/// The view (camera_screen.dart) only displays state and forwards
/// user input here. All business logic lives in this file.
class CameraController extends ChangeNotifier {
  // ──────────────────────────────────────────────────────────────────
  // Services
  // ──────────────────────────────────────────────────────────────────
  final YoloService          _yoloService       = YoloService();
  final FramePreprocessor    _preprocessor      = const FramePreprocessor();
  final DetectionDecoder     _decoder           = const DetectionDecoder();
  final InferenceThrottler   _throttler         = InferenceThrottler();
  final LocationService      _locationService   = const LocationService();
  final PermissionService    _permissionService = const PermissionService();
  final AudioPlayer          _audioPlayer       = AudioPlayer();

  cam.CameraController? _cameraController;
  Future<void>?         _initializeFuture;

  // ──────────────────────────────────────────────────────────────────
  // Public state
  // ──────────────────────────────────────────────────────────────────
  CameraState _state = const CameraState();
  CameraState get state => _state;

  cam.CameraController? get cameraController => _cameraController;
  Future<void>?         get initializeFuture => _initializeFuture;

  bool   _useMockCamera = false;
  String? _cameraError;
  bool    _locationBusy = false;

  bool   get useMockCamera => _useMockCamera;
  String? get cameraError  => _cameraError;
  bool   get locationBusy  => _locationBusy;

  // ──────────────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────────────

  /// Initialize everything: camera, AI model, audio intro.
  /// Call once when the screen opens.
  Future<void> initialize() async {
    debugPrint('🎬 CameraController: initialize()');

    // Run all three in parallel — they don't depend on each other
    await Future.wait([
      _initCamera(),
      _loadYoloModel(),
      _playIntroOnce(),
    ]);
  }

  @override
  void dispose() {
    debugPrint('🛑 CameraController: dispose()');
   _yoloService.dispose();
    _audioPlayer.dispose();

    // Stop receiving frames before disposing the camera
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────
  // Camera setup
  // ──────────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    if (kForceMockCamera) {
      _useMockCamera = true;
      notifyListeners();
      return;
    }

    try {
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        _useMockCamera = true;
        _cameraError   = 'لا توجد كاميرا متاحة، تم تفعيل الوضع التجريبي.';
        notifyListeners();
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = cam.CameraController(
        back,
        cam.ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: cam.ImageFormatGroup.yuv420,
      );

  _initializeFuture = _cameraController!.initialize();
      await _initializeFuture;

      _updateState(_state.copyWith(isCameraReady: true));

      // Start receiving camera frames for AI processing
      await _startFrameStream();
    } catch (_) {
      _useMockCamera = true;
      _cameraError   = 'تعذر تشغيل الكاميرا، تم تفعيل الوضع التجريبي.';
      notifyListeners();
    }
  }
/// Subscribe to the camera's frame stream.
  /// Each frame is sent to _onCameraFrame() for processing.
  Future<void> _startFrameStream() async {
    if (_cameraController == null) {
      debugPrint('⚠️ _startFrameStream: _cameraController is null');
      return;
    }

    try {
      debugPrint('📹 Attempting to start frame stream...');
      await _cameraController!.startImageStream(_onCameraFrame);
      debugPrint('📹 Camera frame stream started successfully');
    } catch (e) {
      debugPrint('🚨 Failed to start frame stream: $e');
    }
  }

  /// Called for every camera frame (~30 times per second).
  /// We count them here in C1. Real AI processing is added in C2.
  void _onCameraFrame(cam.CameraImage image) {
    // For now, just count and log occasionally
    final newCount = _state.framesProcessed + 1;

    // Log every 30 frames (~1 per second) so we don't flood the console
    if (newCount % 30 == 0) {
      debugPrint('📸 Camera frames received: $newCount');
    }

    _updateState(_state.copyWith(framesProcessed: newCount));
  }
  // ──────────────────────────────────────────────────────────────────
  // YOLO model loading
  // ──────────────────────────────────────────────────────────────────
  Future<void> _loadYoloModel() async {
    try {
      await _yoloService.loadModel();
      _updateState(_state.copyWith(isAiReady: true));
    } catch (e) {
      debugPrint('🚨 CameraController: YOLO model failed to load: $e');
      _updateState(_state.copyWith(lastError: 'YOLO load failed'));
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Audio
  // ──────────────────────────────────────────────────────────────────
  Future<void> _playAudio(String path) async {
    debugPrint('🔊 Playing: $path');
    try {
      await _audioPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('🔊 Audio error: $e');
    }
  }

  Future<void> _playIntroOnce() async {
    // Voice intro currently plays every visit (commented-out check).
    // Uncomment the lines below to play only once per app install.
    // final hasHeard = await Prefs.hasHeardCameraIntro();
    // if (hasHeard) return;

    await Future.delayed(const Duration(milliseconds: 800));
    await _playAudio(_CameraAudio.intro);
    await Prefs.markCameraIntroHeard();
  }

  // ──────────────────────────────────────────────────────────────────
  // User actions (called by view when a quadrant is tapped)
  // ──────────────────────────────────────────────────────────────────

  /// Top-right: emergency call.
  /// Empty for now — your colleague will wire PhoneService here.
  Future<void> onEmergencyTap() async {
    debugPrint('👆 onEmergencyTap');
    // TODO: PhoneService().callEmergency() — colleague's task
  }

  /// Bottom-left: replay the intro instructions.
  Future<void> onReplayInstructionsTap() async {
    debugPrint('👆 onReplayInstructionsTap');
    await _playAudio(_CameraAudio.intro);
  }

  /// Bottom-right: get current location and announce it.
  Future<void> onLocationTap() async {
    debugPrint('👆 onLocationTap');
    if (_locationBusy) return;

    _locationBusy = true;
    notifyListeners();

    try {
      final granted = await _permissionService.ensureLocationPermission();
      if (!granted) {
        await _playAudio(_CameraAudio.locationUnavailable);
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
    } catch (_) {
      await _playAudio(_CameraAudio.locationUnavailable);
    } finally {
      _locationBusy = false;
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // State helpers
  // ──────────────────────────────────────────────────────────────────
  void _updateState(CameraState newState) {
    _state = newState;
    notifyListeners();
  }
}