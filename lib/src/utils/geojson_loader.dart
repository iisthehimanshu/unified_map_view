// lib/src/utils/geojson_loader.dart

import 'package:flutter/services.dart' show rootBundle;
import '../models/geojson_models.dart';

/// Utility class for loading and parsing GeoJSON data
class GeoJsonLoader {
  /// Load GeoJSON from assets
  static Future<GeoJsonFeatureCollection> loadFromAsset(String assetPath) async {
    try {
      final jsonString = await rootBundle.loadString(assetPath);
      return GeoJsonFeatureCollection.fromJsonString(jsonString);
    } catch (e) {
      throw Exception('Failed to load GeoJSON from $assetPath: $e');
    }
  }

  /// Load GeoJSON from JSON string
  static GeoJsonFeatureCollection loadFromString(String jsonString) {
    return GeoJsonFeatureCollection.fromJsonString(jsonString);
  }

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
}