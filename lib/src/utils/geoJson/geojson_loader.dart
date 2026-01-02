import '../../models/geojson_models.dart';

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
    return collection.features
        .map((f) => GeoJsonMarker.fromFeature(f))
        .where((m) => m != null)
        .cast<GeoJsonMarker>()
    .toList();
  }
}