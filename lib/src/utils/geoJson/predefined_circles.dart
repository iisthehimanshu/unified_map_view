import '../../../unified_map_view.dart';

class PredefinedCircles{
  static GeoJsonCircle getGenericMarker(MapLocation position, String id){
    return GeoJsonCircle(
      id: id,
      position: position,
      animated: true,
      properties: {
        "radius":5.0
      }
    );
  }
}