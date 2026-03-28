import 'package:gp_hudai/core/models/landmark_point.dart';

class LocationConstants {
  LocationConstants._();

  static const GeoCircle arafatZone = GeoCircle(
    name: 'جبل عرفات',
    center: GeoPoint(21.35472, 39.98389),
    radiusMeters: 1000,
  );
}
