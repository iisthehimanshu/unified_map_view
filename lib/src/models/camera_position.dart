import 'package:unified_map_view/src/models/map_location.dart';

class UnifiedCameraPosition {
  final MapLocation mapLocation;
  final double zoom;
  final double bearing;

  const UnifiedCameraPosition({
    required this.mapLocation,
    required this.zoom,
    required this.bearing,
  });

}