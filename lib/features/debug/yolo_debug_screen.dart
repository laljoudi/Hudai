import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'package:gp_hudai/core/constants/yolo_config.dart';
import 'package:gp_hudai/core/models/detection.dart';
import 'package:gp_hudai/core/services/detection_decoder.dart';
import 'package:gp_hudai/core/services/yolo_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// A debug screen that runs the YOLO pipeline on static test images.
///
/// This screen is for development/verification only. It bypasses the camera
/// and feeds pre-loaded Hajj images directly through the model.
class YoloDebugScreen extends StatefulWidget {
  const YoloDebugScreen({super.key});

  @override
  State<YoloDebugScreen> createState() => _YoloDebugScreenState();
}

class _YoloDebugScreenState extends State<YoloDebugScreen> {

  final YoloService      _yoloService = YoloService();
  final DetectionDecoder _decoder     = const DetectionDecoder();

  bool _isLoading = true;
  String? _statusMessage;

  // Map of imagePath → list of detections (or null if not yet tested)
  final Map<String, List<Detection>?> _results = {};

  static const List<String> _testImages = [
    'assets/test_images/crowd2_00.jpg',
    'assets/test_images/crowd2_01.jpg',
    'assets/test_images/crowd2_02.jpg',
    'assets/test_images/OtherMountains4_00.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      setState(() => _statusMessage = 'Loading model...');
      await _yoloService.loadModel();
      setState(() {
        _isLoading = false;
        _statusMessage = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = '🚨 Model failed to load: $e';
      });
    }
  }

  @override
  void dispose() {
    _yoloService.dispose();
    super.dispose();
  }

  Future<void> _testImage(String imagePath) async {
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🧪 Testing: $imagePath');

    setState(() {
      _results[imagePath] = null; // null = currently processing
    });

    try {
      // 1. Load the image bytes from assets
      final byteData = await rootBundle.load(imagePath);
      final bytes = byteData.buffer.asUint8List();

      // 2. Decode the image
      final originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        debugPrint('🚨 Failed to decode image');
        return;
      }
      debugPrint(
          '   Original size: ${originalImage.width}x${originalImage.height}');

      // 3. Resize to 640×640
      final resized = img.copyResize(
        originalImage,
        width:  YoloConfig.inputSize,
        height: YoloConfig.inputSize,
        interpolation: img.Interpolation.linear,
      );

      // 4. Convert to Float32List normalized 0-1
      final input = _imageToFloat32List(resized);
      debugPrint('   Input prepared: ${input.length} floats');

      // 5. Run inference
      final stopwatch = Stopwatch()..start();
      final output = _runInference(input);
      stopwatch.stop();
      debugPrint('   Inference took: ${stopwatch.elapsedMilliseconds}ms');

      // 6. Decode detections
      final detections = _decoder.decode(output);
      debugPrint('   Decoded ${detections.length} detection(s):');
      for (final d in detections) {
        debugPrint('      → ${d.className} @ ${d.confidencePercent}');
      }

      setState(() {
        _results[imagePath] = detections;
      });
    } catch (e, stack) {
      debugPrint('🚨 Test failed: $e');
      debugPrint(stack.toString());
      setState(() {
        _results[imagePath] = [];
      });
    }
  }

  /// Converts a 640×640 RGB image into a normalized Float32List.
  Float32List _imageToFloat32List(img.Image image) {
    const size = YoloConfig.inputSize;
    final out = Float32List(size * size * 3);

    int idx = 0;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final p = image.getPixel(x, y);
        out[idx++] = p.r / 255.0;
        out[idx++] = p.g / 255.0;
        out[idx++] = p.b / 255.0;
      }
    }
    return out;
  }

  /// Runs inference on the loaded model and returns the flat output array.
  List<double> _runInference(Float32List input) {
    final interpreter = _yoloService.interpreter!;

    // Reshape input to [1, 640, 640, 3] for the model
    final reshapedInput = input.reshape([1, YoloConfig.inputSize, YoloConfig.inputSize, 3]);

    // Output shape: [1, 9, 8400]
    final outputShape = interpreter.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
      (_) => List.generate(
        outputShape[1],
        (_) => List<double>.filled(outputShape[2], 0.0),
      ),
    );

    interpreter.run(reshapedInput, output);

    // Flatten the output to a 1D list (matching what decoder expects)
    final flat = <double>[];
    for (final dim1 in output[0]) {
      flat.addAll(dim1);
    }
    return flat;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030A20),
      appBar: AppBar(
        backgroundColor: const Color(0xFF071540),
        title: const Text(
          'YOLO Debug',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading model...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          : _statusMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _testImages.length,
                  itemBuilder: (context, index) {
                    final path = _testImages[index];
                    return _buildTestCard(path);
                  },
                ),
    );
  }

  Widget _buildTestCard(String imagePath) {
    final result = _results[imagePath];
    final isProcessing = _results.containsKey(imagePath) && result == null;
    final hasResult = result != null;

    final filename = imagePath.split('/').last;

    return Card(
      color: const Color(0xFF0E2360),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                imagePath,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),

            // Filename
            Text(
              filename,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Test button or results
            if (isProcessing)
              const Row(
                children: [
                  SizedBox(
                    width:  16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyan,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Processing...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              )
            else if (hasResult)
              _buildResults(result)
            else
              ElevatedButton.icon(
                onPressed: () => _testImage(imagePath),
                icon: const Icon(Icons.science),
                label: const Text('Run YOLO'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E5FFF),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<Detection> detections) {
    if (detections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '⚠️ No detections found',
          style: TextStyle(color: Colors.amber),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Found ${detections.length} detection(s):',
          style: const TextStyle(color: Colors.cyan, fontSize: 13),
        ),
        const SizedBox(height: 6),
        ...detections.map((d) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Text('✅ ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      '${d.className}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  Text(
                    d.confidencePercent,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}