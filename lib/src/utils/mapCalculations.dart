
import 'package:unified_map_view/src/models/map_location.dart';
import 'dart:math' as Math;

class MapCalculations{

  static double distanceInMeters(MapLocation a, MapLocation b) {
    const double earthRadius = 6371000; // meters

    final dLat = _degToRad(b.latitude - a.latitude);
    final dLng = _degToRad(b.longitude - a.longitude);

    final lat1 = _degToRad(a.latitude);
    final lat2 = _degToRad(b.latitude);

    final h =
        (Math.sin(dLat / 2) * Math.sin(dLat / 2)) +
            (Math.cos(lat1) * Math.cos(lat2) *
                Math.sin(dLng / 2) * Math.sin(dLng / 2));

    return 2 * earthRadius * Math.asin(Math.sqrt(h));
  }

  static double _degToRad(double deg) => deg * (3.141592653589793 / 180);

  // Helper method to approximate zoom level from latitude difference
  static double approximateZoomLevel(double latDiff) {
    // Approximate formula: zoom ≈ log2(360 / latDiff)
    // This is a rough estimate; actual zoom may vary
    if (latDiff <= 0) return 21.0;
    return (Math.log(360 / latDiff) / Math.ln2).clamp(0.0, 21.0);
  }

}