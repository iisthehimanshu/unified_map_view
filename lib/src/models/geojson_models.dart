// lib/src/models/geojson_models.dart

import 'dart:convert';
import 'dart:typed_data';
import '../utils/renderingUtilities.dart';
import 'map_location.dart';

export 'dart:typed_data';

/// Types of GeoJSON geometries
enum GeoJsonGeometryType {
  point,
  multiPoint,
  lineString,
  multiLineString,
  polygon,
  multiPolygon,
  geometryCollection,
}

/// Represents a GeoJSON Feature
class GeoJsonFeature {
  final String? building_ID;
  final String? id;
  final GeoJsonGeometry geometry;
  final Map<String, dynamic>? properties;

  GeoJsonFeature({
    this.building_ID,
    this.id,
    required this.geometry,
    this.properties,
  });

  factory GeoJsonFeature.fromJson(Map<String, dynamic> json) {
    return GeoJsonFeature(
      building_ID: json["building_ID"]?.toString(),
      id: json['id']?.toString(),
      geometry: GeoJsonGeometry.fromJson(json['geometry']),
      properties: json['properties'] as Map<String, dynamic>?,
    );
  }
}

/// Represents a GeoJSON Geometry
class GeoJsonGeometry {
  final GeoJsonGeometryType type;
  final dynamic coordinates;

  GeoJsonGeometry({
    required this.type,
    required this.coordinates,
  });

  factory GeoJsonGeometry.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = _parseGeometryType(typeStr);

    return GeoJsonGeometry(
      type: type,
      coordinates: json['coordinates'],
    );
  }

  static GeoJsonGeometryType _parseGeometryType(String type) {
    switch (type) {
      case 'Point':
        return GeoJsonGeometryType.point;
      case 'MultiPoint':
        return GeoJsonGeometryType.multiPoint;
      case 'LineString':
        return GeoJsonGeometryType.lineString;
      case 'MultiLineString':
        return GeoJsonGeometryType.multiLineString;
      case 'Polygon':
        return GeoJsonGeometryType.polygon;
      case 'MultiPolygon':
        return GeoJsonGeometryType.multiPolygon;
      case 'GeometryCollection':
        return GeoJsonGeometryType.geometryCollection;
      default:
        throw Exception('Unknown geometry type: $type');
    }
  }
}

/// Represents a GeoJSON FeatureCollection
class GeoJsonFeatureCollection {
  final List<GeoJsonFeature> features;
  final Map<String, dynamic>? properties;

  GeoJsonFeatureCollection({
    required this.features,
    this.properties,
  });

  factory GeoJsonFeatureCollection.fromJson(Map<String, dynamic> json) {
    final featuresJson = json['data'] as List;

    return GeoJsonFeatureCollection(
      features: featuresJson
          .map((f) => GeoJsonFeature.fromJson(f as Map<String, dynamic>))
          .toList(),
      properties: json['properties'] as Map<String, dynamic>?,
    );
  }

  factory GeoJsonFeatureCollection.fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return GeoJsonFeatureCollection.fromJson(json);
  }

  /// Get all features of a specific type
  List<GeoJsonFeature> getFeaturesByType(GeoJsonGeometryType type) {
    return features.where((f) => f.geometry.type == type).toList();
  }
}

/// Represents a GeoJSON Polygon for rendering
class GeoJsonPolygon {
  final String id;
  final List<MapLocation> points;
  final Map<String, dynamic>? properties;

  GeoJsonPolygon({
    required this.id,
    required this.points,
    this.properties,
  });

  /// Create from GeoJSON Feature
  static GeoJsonPolygon? fromFeature(GeoJsonFeature feature) {
    if (feature.geometry.type != GeoJsonGeometryType.polygon) return null;

    final coords = feature.geometry.coordinates as List;
    final ring = coords[0] as List; // First ring (outer boundary)

    return GeoJsonPolygon(
      id: "id:${feature.id} | buildingID:${feature.building_ID}" ?? DateTime.now().millisecondsSinceEpoch.toString(),
      points: ring.map((coord) => MapLocation(
        latitude: coord[1],
        longitude: coord[0],
      )).toList(),
      properties: feature.properties,
    );
  }
}

/// Represents a GeoJSON LineString/Polyline for rendering
class GeoJsonPolyline {
  final String id;
  final List<MapLocation> points;
  final Map<String, dynamic>? properties;

  GeoJsonPolyline({
    required this.id,
    required this.points,
    this.properties,
  });

  /// Create from GeoJSON Feature
  static GeoJsonPolyline? fromFeature(GeoJsonFeature feature) {
    if (feature.geometry.type != GeoJsonGeometryType.lineString) return null;

    final coords = feature.geometry.coordinates as List;

    return GeoJsonPolyline(
      id: "id:${feature.id} | buildingID:${feature.building_ID}" ?? DateTime.now().millisecondsSinceEpoch.toString(),
      points: coords.map((coord) => MapLocation(
        latitude: coord[1],
        longitude: coord[0],
      )).toList(),
      properties: feature.properties,
    );
  }
}

class GeoJsonMarker {
  final String id;
  final MapLocation position;
  final String? title;
  final String? snippet;
  final String? assetPath; // Add icon name/identifier
  final String? iconName;

  GeoJsonMarker({
    required this.id,
    required this.position,
    this.title,
    this.snippet,
    this.assetPath,
    this.iconName,
  });

  /// Create from GeoJSON Feature
  static GeoJsonMarker? fromFeature(GeoJsonFeature feature) {
    if (feature.geometry.type != GeoJsonGeometryType.point) return null;

    final coords = feature.geometry.coordinates[0];

    final assetPath = RenderingUtilities.getAssetNameForLandmark(feature.properties);
    final iconName = assetPath?.split('/').last.split('.').first;

    if(feature.properties?["landmarkId"] == "6889bb7cfe0f245a59f3cd7e"){
      print("feature.properties $assetPath $iconName ${feature.properties}");
    }

    return GeoJsonMarker(
      id: "id:${feature.id} | buildingID:${feature.building_ID}" ?? DateTime.now().millisecondsSinceEpoch.toString(),
      position: MapLocation(latitude: coords.last, longitude: coords.first),
      title: feature.properties?["name"],
      snippet: "",
      assetPath: assetPath,
      iconName: iconName
    );
  }
}