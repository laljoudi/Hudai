import 'package:gp_hudai/core/models/landmark_point.dart';

class LocationConstants {
  LocationConstants._();

  // Coordinates converted from:
  //   21°21'17"N, 39°59'02"E
  //   21 + 21/60 + 17/3600 = 21.354722...
  //   39 + 59/60 + 02/3600 = 39.983889...
  static const GeoPoint jabalArafat = GeoPoint(21.35472, 39.98389);

  // Coordinates converted from:
  //   21°21'10"N, 39°57'58"E
  //   21 + 21/60 + 10/3600 = 21.352778...
  //   39 + 57/60 + 58/3600 = 39.966111...
  static const GeoPoint namirahMosque = GeoPoint(21.35278, 39.96611);

  // Approximate Hajj guidance radii. Tune after testing on site.
  static const double arafatAreaRadiusMeters = 3000;
  static const double namirahNearRadiusMeters = 350;
  static const double jabalNearRadiusMeters = 500;
  // Namirah Mosque is about 1.8km from Jabal Arafat with the coordinates
  // above, so 2500m keeps it in the "medium distance" guidance band.
  static const double jabalMediumRadiusMeters = 2500;
  static const double lowAccuracyThresholdMeters = 80;

  static const GeoCircle arafatZone = GeoCircle(
    name: 'مشعر عرفات',
    center: jabalArafat,
    radiusMeters: arafatAreaRadiusMeters,
  );

  static const GeoCircle namirahMosqueZone = GeoCircle(
    name: 'مسجد نمرة',
    center: namirahMosque,
    radiusMeters: namirahNearRadiusMeters,
  );

  static const GeoCircle jabalArafatNearZone = GeoCircle(
    name: 'جبل عرفات',
    center: jabalArafat,
    radiusMeters: jabalNearRadiusMeters,
  );
}
