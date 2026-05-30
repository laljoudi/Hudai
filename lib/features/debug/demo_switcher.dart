import 'package:flutter/material.dart';
import 'package:gp_hudai/core/constants/colors.dart';
import 'package:gp_hudai/core/services/location/location_guidance_service.dart';

/// Opens a modal bottom sheet for changing [kDemoLocationMode] at runtime.
/// Triggered by a hidden long-press on the camera screen's middle dead zone.
void showDemoSwitcherModal(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _DemoLocationSheet(),
  );
}

class _DemoLocationSheet extends StatefulWidget {
  const _DemoLocationSheet();

  @override
  State<_DemoLocationSheet> createState() => _DemoLocationSheetState();
}

class _DemoLocationSheetState extends State<_DemoLocationSheet> {
  late DemoLocationMode _selected;

  static const Map<DemoLocationMode, String> _labels = {
    DemoLocationMode.off: 'Off, real GPS',
    DemoLocationMode.insideArafatNearJabal: 'Inside Arafat, near Jabal',
    DemoLocationMode.nearNamirah: 'Inside Arafat, near Namirah',
    DemoLocationMode.mediumFromJabal: 'Inside Arafat, medium distance',
    DemoLocationMode.farFromJabal: 'Outside Arafat, far from Jabal',
    DemoLocationMode.lowAccuracy: 'Low-accuracy GPS',
  };

  @override
  void initState() {
    super.initState();
    _selected = kDemoLocationMode;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                'Demo, Location Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ...DemoLocationMode.values.map((mode) {
              final isSelected = mode == _selected;
              return ListTile(
                dense: true,
                onTap: () {
                  setState(() => _selected = mode);
                  kDemoLocationMode = mode;
                },
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? AppColors.accentCyan
                      : Colors.white.withValues(alpha: 0.40),
                  size: 20,
                ),
                title: Text(
                  _labels[mode] ?? mode.name,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
