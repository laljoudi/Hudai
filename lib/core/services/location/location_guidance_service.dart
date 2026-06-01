import 'package:geolocator/geolocator.dart';
import 'package:gp_hudai/core/constants/location_constants.dart';
import 'package:gp_hudai/core/services/location/location_service.dart';

/// Demo mode for testing location audio from anywhere.
///
/// Change [kDemoLocationMode] from `off` to one of the demo values below,
/// run the app, then tap the location button. The app will skip real GPS and
/// play the selected audio sequence directly. Before production/demo-day real
/// testing, set it back to `DemoLocationMode.off`.
enum DemoLocationMode {
  off,
  insideArafatNearJabal,
  nearNamirah,
  mediumFromJabal,
  farFromJabal,
  lowAccuracy,
}

// ignore: prefer_final_top_level
DemoLocationMode kDemoLocationMode = DemoLocationMode.off;

class LocationAudioPaths {
  const LocationAudioPaths._();

  static const String insideArafat = 'audio/location/inside_arafat.mp3';
  static const String outsideArafat = 'audio/location/outside_arafat.mp3';
  static const String nearNamirahMosque =
      'audio/location/near_namirah_mosque.mp3';
  static const String nearJabalArafat = 'audio/location/near_jabal_arafat.mp3';
  static const String mediumDistanceJabalArafat =
      'audio/location/medium_distance_jabal_arafat.mp3';
  static const String farFromJabalArafat =
      'audio/location/far_from_jabal_arafat.mp3';
  static const String locationLowAccuracy =
      'audio/location/location_low_accuracy.mp3';
  static const String locationUnavailable =
      'audio/location/location_unavailable.mp3';
}

class LocationGuidanceResult {
  const LocationGuidanceResult({
    required this.audioSequence,
    required this.insideArafat,
    required this.nearNamirah,
    required this.distanceToJabalMeters,
    required this.isLowAccuracy,
  });

  final List<String> audioSequence;
  final bool insideArafat;
  final bool nearNamirah;
  final double distanceToJabalMeters;
  final bool isLowAccuracy;
}

class LocationGuidanceService {
  const LocationGuidanceService({
    LocationService locationService = const LocationService(),
  }) : _locationService = locationService;

  final LocationService _locationService;

  bool get isDemoModeEnabled => kDemoLocationMode != DemoLocationMode.off;

  LocationGuidanceResult buildDemoGuidance() {
    switch (kDemoLocationMode) {
      case DemoLocationMode.insideArafatNearJabal:
        return const LocationGuidanceResult(
          audioSequence: [
            LocationAudioPaths.insideArafat,
            LocationAudioPaths.nearJabalArafat,
          ],
          insideArafat: true,
          nearNamirah: false,
          distanceToJabalMeters: 0,
          isLowAccuracy: false,
        );
      case DemoLocationMode.nearNamirah:
        return const LocationGuidanceResult(
          audioSequence: [
            LocationAudioPaths.insideArafat,
            LocationAudioPaths.nearNamirahMosque,
            LocationAudioPaths.mediumDistanceJabalArafat,
          ],
          insideArafat: true,
          nearNamirah: true,
          distanceToJabalMeters: 1850,
          isLowAccuracy: false,
        );
      case DemoLocationMode.mediumFromJabal:
        return const LocationGuidanceResult(
          audioSequence: [
            LocationAudioPaths.insideArafat,
            LocationAudioPaths.mediumDistanceJabalArafat,
          ],
          insideArafat: true,
          nearNamirah: false,
          distanceToJabalMeters: 1200,
          isLowAccuracy: false,
        );
      case DemoLocationMode.farFromJabal:
        return const LocationGuidanceResult(
          audioSequence: [LocationAudioPaths.farFromJabalArafat],
          insideArafat: false,
          nearNamirah: false,
          distanceToJabalMeters: 4000,
          isLowAccuracy: false,
        );
      case DemoLocationMode.lowAccuracy:
        return const LocationGuidanceResult(
          audioSequence: [LocationAudioPaths.locationLowAccuracy],
          insideArafat: false,
          nearNamirah: false,
          distanceToJabalMeters: 0,
          isLowAccuracy: true,
        );
      case DemoLocationMode.off:
        return const LocationGuidanceResult(
          audioSequence: [LocationAudioPaths.locationUnavailable],
          insideArafat: false,
          nearNamirah: false,
          distanceToJabalMeters: 0,
          isLowAccuracy: false,
        );
    }
  }

  LocationGuidanceResult buildGuidance(Position position) {
    final insideArafat = _locationService.isInsideCircle(
      position,
      LocationConstants.arafatZone,
    );
    final nearNamirah = _locationService.isInsideCircle(
      position,
      LocationConstants.namirahMosqueZone,
    );
    final distanceToJabal = _locationService.distanceToPoint(
      position,
      LocationConstants.jabalArafat,
    );
    final isLowAccuracy =
        position.accuracy > LocationConstants.lowAccuracyThresholdMeters;

    if (isLowAccuracy) {
      return LocationGuidanceResult(
        audioSequence: const [LocationAudioPaths.locationLowAccuracy],
        insideArafat: insideArafat,
        nearNamirah: nearNamirah,
        distanceToJabalMeters: distanceToJabal,
        isLowAccuracy: true,
      );
    }

    final sequence = <String>[];
    if (insideArafat) {
      sequence.add(LocationAudioPaths.insideArafat);
    }
    if (nearNamirah) {
      sequence.add(LocationAudioPaths.nearNamirahMosque);
    }
    if (distanceToJabal <= LocationConstants.jabalNearRadiusMeters) {
      sequence.add(LocationAudioPaths.nearJabalArafat);
    } else if (distanceToJabal <= LocationConstants.jabalMediumRadiusMeters) {
      sequence.add(LocationAudioPaths.mediumDistanceJabalArafat);
    } else {
      sequence.add(LocationAudioPaths.farFromJabalArafat);
    }

    return LocationGuidanceResult(
      audioSequence: List<String>.unmodifiable(sequence),
      insideArafat: insideArafat,
      nearNamirah: nearNamirah,
      distanceToJabalMeters: distanceToJabal,
      isLowAccuracy: false,
    );
  }
}
