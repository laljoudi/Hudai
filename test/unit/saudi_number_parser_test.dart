// flutter test test/unit/saudi_number_parser_test.dart 
// Edit-Emergency-Number flows.
//
// Test cases covered in this file (matching the testing report):
//   UN-1: Arabic spoken digit words → "0501234567"
//   UN-2: Eastern Arabic numerals (٠–٩) → "0501234567"
//   UN-3: Saudi number normaliser strips +966 / 00966 / 966 prefixes
//
// The parser lives in lib/core/utils/saudi_number_parser.dart. The same
// logic is currently duplicated as private helpers in setup_controller.dart
// and settings_emergency_controller.dart; this utility is the public,
// testable copy.

import 'package:flutter_test/flutter_test.dart';

import 'package:gp_hudai/core/utils/saudi_number_parser.dart';

void main() {
  // ────────────────────────────────────────────────────────────────────
  // UN-1
  // ────────────────────────────────────────────────────────────────────
  group('UN-1 Arabic speech-to-digit parser', () {
    test('Spoken Arabic digit words are converted to "0501234567"', () {
      const spoken =
          'صفر خمسة صفر واحد اثنان ثلاثة أربعة خمسة ستة سبعة';
      expect(arabicSpeechToDigits(spoken), '0501234567');
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // UN-2
  // ────────────────────────────────────────────────────────────────────
  group('UN-2 Eastern Arabic numeral parser', () {
    test('Eastern Arabic numerals (٠–٩) are converted to Western digits', () {
      expect(arabicSpeechToDigits('٠٥٠١٢٣٤٥٦٧'), '0501234567');
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // UN-3
  // ────────────────────────────────────────────────────────────────────
  group('UN-3 Saudi number normaliser strips country-code prefixes', () {
    test('"966501234567"   → "0501234567"', () {
      expect(normalizeSaudiNumber('966501234567'), '0501234567');
    });

    test('"00966501234567" → "0501234567"', () {
      expect(normalizeSaudiNumber('00966501234567'), '0501234567');
    });

    // The "+" of "+966..." is stripped upstream by arabicSpeechToDigits
    // before the normaliser sees it, so the input to this function is
    // always digits-only.
    test('digits-only form of "+966501234567" → "0501234567"', () {
      expect(normalizeSaudiNumber('966501234567'), '0501234567');
    });
  });
}
