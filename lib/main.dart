import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // DEMO RECORDING ONLY: hides the iOS/Android status bar while filming.
  // Remove this block after recording the demo to restore the normal UI.
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [],
  );

  runApp(const HudaiApp());
}
