// flutter test test/unit/prefs_test.dart
//
// Test cases covered in this file (matching the testing report):
//   UN-4: Prefs.hasValidEmergencyNumber() returns true ONLY when the
//         stored value matches ^05\d{8}$.
//   UN-5: Prefs.saveEmergencyNumber() persists the value, and a
//         subsequent Prefs.getEmergencyNumber() returns the same value.
//
// The emergency number is stored in `flutter_secure_storage`, NOT in
// SharedPreferences. flutter_secure_storage does not ship with a built-in
// mock helper, so these tests register a method-channel mock that backs
// the plugin with a simple in-memory Map.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gp_hudai/core/storage/prefs.dart';

void main() {
  // Required so that the method-channel mocking infrastructure is set up.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Channel name used by flutter_secure_storage on all platforms.
  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  // In-memory backing store the mock handler reads/writes against.
  final Map<String, String> store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (
          MethodCall call,
        ) async {
          final Map<String, dynamic> args =
              (call.arguments as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          final String? key = args['key'] as String?;
          final String? value = args['value'] as String?;

          switch (call.method) {
            case 'write':
              if (key != null) {
                if (value == null) {
                  store.remove(key);
                } else {
                  store[key] = value;
                }
              }
              return null;
            case 'read':
              return key != null ? store[key] : null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'containsKey':
              return key != null && store.containsKey(key);
            case 'delete':
              if (key != null) store.remove(key);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  // ────────────────────────────────────────────────────────────────────
  // UN-4 — Emergency-number validity check
  // ────────────────────────────────────────────────────────────────────
  group('UN-4 Prefs.hasValidEmergencyNumber()', () {
    test('Step 1: "0501234567" → true', () async {
      await Prefs.saveEmergencyNumber('0501234567');
      expect(await Prefs.hasValidEmergencyNumber(), isTrue);
    });

    test('Step 2: "0612345678" → false (wrong prefix)', () async {
      await Prefs.saveEmergencyNumber('0612345678');
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);
    });

    test('Step 3: "050123" → false (too short)', () async {
      await Prefs.saveEmergencyNumber('050123');
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);
    });

    test('Step 4: cleared/unset → false', () async {
      // Nothing was ever written for this test case.
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────────
  // UN-5 — Save / get round trip
  // ────────────────────────────────────────────────────────────────────
  group('UN-5 Prefs.saveEmergencyNumber() persists to secure storage', () {
    test('A subsequent getEmergencyNumber() returns the saved value', () async {
      await Prefs.saveEmergencyNumber('0501234567');
      expect(await Prefs.getEmergencyNumber(), '0501234567');
    });
  });
}
