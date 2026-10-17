import '../../models/geojson_models.dart';
import '../../models/map_location.dart';
import 'geoJsonUtils.dart';

/// Utility class for loading and parsing GeoJSON data
class GeoJsonLoader {

  /// Parse GeoJSON data and extract all polygons
  static List<GeoJsonPolygon> extractPolygons(GeoJsonFeatureCollection collection) {
    return collection.features
        .map((f) => GeoJsonPolygon.fromFeature(f))
        .where((p) => p != null)
        .cast<GeoJsonPolygon>()
        .toList();
  }

  /// Parse GeoJSON data and extract all polylines
  static List<GeoJsonPolyline> extractPolylines(GeoJsonFeatureCollection collection) {
    return collection.features
        .map((f) => GeoJsonPolyline.fromFeature(f))
        .where((p) => p != null)
        .cast<GeoJsonPolyline>()
        .toList();
  }

  static List<GeoJsonMarker> extractMarkers(GeoJsonFeatureCollection collection) {
    final markers = collection.features
        .expand((f) => GeoJsonMarker.fromFeatureList(f))
        .toList();
    for (final feature in collection.features) {
      if (feature.geometry.type != GeoJsonGeometryType.polygon) continue;
      final outlet = feature.properties?['outletRef'];
      if (outlet is! Map) continue;
      final outletName = outlet['name']?.toString().trim();
      if (outletName == null || outletName.isEmpty) continue;
      final polygonId = feature.id;
      if (polygonId == null || polygonId.isEmpty) continue;

      final pointIndex = markers.indexWhere((marker) =>
          GeoJsonUtils.extractKeyValueMap(marker.id)['polyId'] == polygonId);
      if (pointIndex >= 0 && markers[pointIndex].textVisibility &&
          !markers[pointIndex].customRendering) {
        markers[pointIndex] = markers[pointIndex].copyWith(title: outletName);
        continue;
      }

      final polygon = GeoJsonPolygon.fromFeature(feature);
      if (polygon == null || polygon.points.isEmpty) continue;
      final points = polygon.points;
      final center = MapLocation(
        latitude: points.map((p) => p.latitude).reduce((a, b) => a + b) /
            points.length,
        longitude: points.map((p) => p.longitude).reduce((a, b) => a + b) /
            points.length,
      );
      markers.add(GeoJsonMarker(
        id: GeoJsonUtils.buildKey(
            id: 'outlet-label-$polygonId',
            polyId: polygonId,
            buildingID: feature.buildingId),
        position: center,
        title: outletName,
        properties: {'type': 'Store', 'floor': feature.properties?['floor']},
      ));
    }
    return markers;
  }
}
