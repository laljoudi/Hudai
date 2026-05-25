// flutter test test/unit/saudi_number_parser_test.dart
// Edit-Emergency-Number flows.
//
// Test cases (matching the testing report — 3 tests):
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
  // UN-1 ────────────────────────────────────────────────────────────────
  test('UN-1: Arabic spoken digit words → "0501234567"', () {
    const spoken = 'صفر خمسة صفر واحد اثنان ثلاثة أربعة خمسة ستة سبعة';
    expect(arabicSpeechToDigits(spoken), '0501234567');
  });

  // UN-2 ────────────────────────────────────────────────────────────────
  test('UN-2: Eastern Arabic numerals (٠–٩) → "0501234567"', () {
    expect(arabicSpeechToDigits('٠٥٠١٢٣٤٥٦٧'), '0501234567');
  });

  // UN-3 ────────────────────────────────────────────────────────────────
  test('UN-3: Saudi normaliser strips +966 / 00966 / 966 prefixes', () {
    // The "+" of "+966..." is stripped upstream by arabicSpeechToDigits,
    // so the digits-only forms are what reach this function.
    expect(normalizeSaudiNumber('966501234567'), '0501234567');
    expect(normalizeSaudiNumber('00966501234567'), '0501234567');
    expect(normalizeSaudiNumber('966501234567'), '0501234567');
  });

  // ──────────────────────────────────────────────────────────────────────
  // Manual (keyboard) emergency-number entry — used by the Setup screen's
  // manual mode. Validates isValidEmergencyNumber():
  //   - must start with "05" and be exactly 10 digits
  //   - accepts both English (0-9) and Arabic (٠-٩) numerals
  //   - empty input is rejected
  // ──────────────────────────────────────────────────────────────────────

  // UN-4: Valid English number
  test('UN-4: valid English number is accepted', () {
    expect(isValidEmergencyNumber('0501234567'), isTrue);
  });

  // UN-5: Valid Arabic number
  test('UN-5: valid Arabic number is accepted', () {
    expect(isValidEmergencyNumber('٠٥٠١٢٣٤٥٦٧'), isTrue);
  });

  // UN-6: Empty input
  test('UN-6: empty input is rejected', () {
    expect(isValidEmergencyNumber(''), isFalse);
  });

  // UN-7: Wrong prefix (does not start with 05)
  test('UN-7: number not starting with 05 is rejected', () {
    expect(isValidEmergencyNumber('0601234567'), isFalse);
  });

  // UN-8: Too short
  test('UN-8: number shorter than 10 digits is rejected', () {
    expect(isValidEmergencyNumber('050123456'), isFalse);
  });

  // UN-9: Too long
  test('UN-9: number longer than 10 digits is rejected', () {
    expect(isValidEmergencyNumber('05012345678'), isFalse);
  });
}

