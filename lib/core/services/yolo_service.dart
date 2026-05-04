import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:gp_hudai/core/constants/yolo_config.dart';

/// Wraps the TensorFlow Lite interpreter for the YOLO Hajj model.
///
/// Responsibilities:
///   - Load the .tflite model into memory at app startup
///   - Hold the interpreter and labels for use by other services
///   - Free resources when the app shuts down
///
/// This service does NOT process camera frames or decode detections.
/// Those are separate responsibilities (see frame_preprocessor.dart
/// and detection_decoder.dart).
class YoloService {
  /// The TFLite interpreter — does the actual model inference.
  Interpreter? _interpreter;

  /// Class labels loaded from labels.txt.
  List<String> _labels = const [];

  /// True once the model has been successfully loaded into memory.
  bool _isReady = false;

  /// Public read-only getters
  bool         get isReady     => _isReady;
  List<String> get labels      => _labels;
  Interpreter? get interpreter => _interpreter;

  /// Loads the model and labels from assets.
  /// Call this once at app startup (or when the camera screen opens).
  Future<void> loadModel() async {
    try {
      // Load the .tflite model from assets
      // Note: tflite_flutter strips the 'assets/' prefix automatically
      final options = InterpreterOptions()
  ..threads = 2
  ..useNnApiForAndroid = false;

_interpreter = await Interpreter.fromAsset(
  'assets/models/yolo_hajj.tflite',
  options: options,
);

      // Load the labels.txt file
      final labelsRaw = await rootBundle.loadString(YoloConfig.labelsPath);
      _labels = labelsRaw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      _isReady = true;

      // Print model info for debugging
      _printModelInfo();
    } catch (e, stack) {
      _isReady = false;
      // ignore: avoid_print
      print('🚨 YoloService: failed to load model: $e');
      // ignore: avoid_print
      print(stack);
      rethrow;
    }
  }

  /// Prints the model's input/output shapes for verification.
  /// Should match: input [1, 640, 640, 3], output depends on YOLO version.
  void _printModelInfo() {
    if (_interpreter == null) return;

    // ignore: avoid_print
    print('✅ YoloService: model loaded successfully');
    // ignore: avoid_print
    print('   Labels (${_labels.length}): $_labels');

    final inputTensors  = _interpreter!.getInputTensors();
    final outputTensors = _interpreter!.getOutputTensors();

    for (var i = 0; i < inputTensors.length; i++) {
      final t = inputTensors[i];
      // ignore: avoid_print
      print('   Input  $i: shape=${t.shape}  type=${t.type}');
    }

    for (var i = 0; i < outputTensors.length; i++) {
      final t = outputTensors[i];
      // ignore: avoid_print
      print('   Output $i: shape=${t.shape}  type=${t.type}');
    }
  }

  /// Frees the interpreter when no longer needed.
  /// Call this when the camera screen is disposed.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
  }
}