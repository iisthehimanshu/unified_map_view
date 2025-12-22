import '../../unified_map_view.dart';

class MapMarker {
  final String id;
  final MapLocation position;
  final String? title;
  final String? snippet;

  const MapMarker({
    required this.id,
    required this.position,
    this.title,
    this.snippet,
  });
}