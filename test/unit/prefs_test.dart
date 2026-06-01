// flutter test test/unit/prefs_test.dart
//
// Test cases (matching the testing report — 2 tests):
//   UN-10: Prefs.hasValidEmergencyNumber() returns true ONLY when the
//          stored value matches ^05\d{8}$.
//   UN-11: Prefs.saveEmergencyNumber() persists the value, and a
//          subsequent Prefs.getEmergencyNumber() returns the same value.
//
// The emergency number is stored in `flutter_secure_storage`, NOT in
// SharedPreferences. flutter_secure_storage does not ship with a built-in
// mock helper, so these tests register a method-channel mock that backs
// the plugin with a simple in-memory Map.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gp_hudai/core/storage/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

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

  // UN-10 ───────────────────────────────────────────────────────────────
  test(
    'UN-10: hasValidEmergencyNumber() returns true ONLY for ^05\\d{8}\$',
    () async {
      // Step 1 — valid 10-digit Saudi mobile number
      await Prefs.saveEmergencyNumber('0501234567');
      expect(await Prefs.hasValidEmergencyNumber(), isTrue);

      // Step 2 — wrong prefix
      await Prefs.saveEmergencyNumber('0612345678');
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);

      // Step 3 — too short
      await Prefs.saveEmergencyNumber('050123');
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);

      // Step 4 — cleared / nothing stored
      store.clear();
      expect(await Prefs.hasValidEmergencyNumber(), isFalse);
    },
  );

  // UN-11 ───────────────────────────────────────────────────────────────
  test(
    'UN-11: saveEmergencyNumber() persists; getEmergencyNumber() reads it',
    () async {
      await Prefs.saveEmergencyNumber('0501234567');
      expect(await Prefs.getEmergencyNumber(), '0501234567');
    },
  );
}
