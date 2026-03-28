import 'package:flutter/foundation.dart';

class TtsService {
  const TtsService();

  Future<void> speak(String text) async {
    // TODO: اربط مزود الصوت الحقيقي لاحقاً.
    debugPrint('TTS: $text');
  }
}
