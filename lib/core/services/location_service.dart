import 'package:geolocator/geolocator.dart';
import 'package:gp_hudai/core/models/landmark_point.dart';

class LocationServiceDisabledException implements Exception {
  const LocationServiceDisabledException();
}

class LocationService {
  const LocationService();

  Future<Position> getCurrentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationServiceDisabledException();
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  bool isInsideCircle(Position position, GeoCircle circle) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      circle.center.lat,
      circle.center.lng,
    );

    return distance <= circle.radiusMeters;
  }
}
