// lib/src/models/geojson_models.dart

import 'dart:ui';
import 'dart:developer' as developer;
import 'dart:convert';

import '../../unified_map_view.dart';
import '../utils/renderingUtilities.dart';

export 'dart:typed_data';

/// Types of GeoJSON geometries
enum GeoJsonGeometryType {
  point,
  circle,
  multiPoint,
  lineString,
  multiLineString,
  polygon,
  multiPolygon,
  geometryCollection,
}

/// Represents a GeoJSON Feature
class GeoJsonFeature {
  final String? buildingId;
  final String? id;
  final GeoJsonGeometry geometry;
  final Map<String, dynamic>? properties;

  GeoJsonFeature({
    this.buildingId,
    this.id,
    required this.geometry,
    this.properties,
  });

  factory GeoJsonFeature.fromJson(Map<String, dynamic> json) {
    return GeoJsonFeature(
      buildingId: json["building_ID"]?.toString(),
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
      case 'Circle':
        return GeoJsonGeometryType.circle;
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
      id: GeoJsonUtils.buildKey(id:feature.id, buildingID:feature.buildingId),
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
      id: GeoJsonUtils.buildKey(id:feature.id, buildingID:feature.buildingId),
      points: coords.map((coord) => MapLocation(
        latitude: coord[1],
        longitude: coord[0],
      )).toList(),
      properties: feature.properties,
    );
  }

  factory GeoJsonPolyline.fromJson(Map<String, dynamic> json) {
    return GeoJsonPolyline(
      id: json['id'] as String,
      points: (json['points'] as List)
          .map(
            (e) => MapLocation.fromJson(
          Map<String, dynamic>.from(e),
        ),
      )
          .toList(),
      properties: json['properties'] != null
          ? Map<String, dynamic>.from(json['properties'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'points': points.map((p) => p.toJson()).toList(),
      if (properties != null) 'properties': properties,
    };
  }

}

class GeoJsonMarker {
  final String id;
  MapLocation position;
  final String? title;
  final String? snippet;
  final String? assetPath; // Add icon name/identifier
  final String? iconName;
  final bool? priority;
  final Map<String, dynamic>? properties;
  final Size? imageSize;
  final bool? textVisibility;
  final bool compassBasedRotation;
  final double? bearing;
  Offset? anchor;

  GeoJsonMarker({
    required this.id,
    required this.position,
    this.title,
    this.snippet,
    this.assetPath,
    this.iconName,
    this.priority,
    this.properties,
    this.imageSize,
    this.textVisibility = false,
    this.compassBasedRotation = false,
    this.bearing,
    this.anchor
  });


  @override
  String toString() {
    return 'GeoJsonMarker{id: $id, position: $position}';
  }

  /// Create from GeoJSON Feature
  static GeoJsonMarker? fromFeature(GeoJsonFeature feature) {
    if (feature.geometry.type != GeoJsonGeometryType.point) return null;
    if(feature.properties?["landmarkId"] == "69662a60a8a7487d6e1ba3c3"){
      print("getAssetForLandmark isGlobal ${feature.properties}");
    }

    if (feature.properties?["global"] == true &&
        (
                feature.properties?["type"] == "Centroid" ||
                feature.properties?["type"] == "BP" ||
                feature.properties?["type"] == "Wall" ||
                feature.properties?["polygonType"] == "Wall"
        )
    ) {
      return null;
    }

    var coords = feature.geometry.coordinates[0];
    if(feature.properties?["global"] == true && feature.properties?["centroid"] != null){
      coords = feature.properties?["centroid"];
    }

    if(coords == null || coords.first == null || coords.last == null){
      print(feature.id);
    }


    final asset = RenderingUtilities.getAssetForLandmark(feature.properties);
    if(feature.id=="68aef48d96d312628c092985"){
      print("assetPath:${asset!.assetPath}");
    }
    String? assetPath;
    String? iconName;
    bool? getTextVisibility;
    Offset? anchor;
    if(asset != null){
      assetPath = asset.assetPath;
      iconName = assetPath.split('/').last.split('.').first;
      getTextVisibility = asset.textVisibility;
      anchor = asset.anchor;
      feature.properties?['bearing'] = null;
    }

    String? polyId = feature.properties?["polyId"];
    final associatedPolygons = feature.properties?['associatedPolygons'];
    if (associatedPolygons is List && associatedPolygons.isNotEmpty) {
      polyId = associatedPolygons.first;
    }

    print("feature.properties?[bearing] ${feature.properties?["bearing"]}");

    return GeoJsonMarker(
      id: GeoJsonUtils.buildKey(id:feature.id, buildingID:feature.buildingId, polyId:polyId),
      position: MapLocation(latitude: coords.last, longitude: coords.first),
      title: feature.properties?["name"],
      snippet: "",
      assetPath: assetPath,
      iconName: iconName,
      properties: feature.properties,
      textVisibility: getTextVisibility,
      priority: false,
      anchor: anchor,
    );
  }
}

class GeoJsonCircle {
  final String id;
  MapLocation position;
  bool animated;
  final Map<String, dynamic>? properties;

  GeoJsonCircle({
    required this.id,
    required this.position,
    this.animated = false,
    this.properties,
  });

  /// Create from GeoJSON Feature
  static GeoJsonCircle? fromFeature(GeoJsonFeature feature) {
    if (feature.geometry.type != GeoJsonGeometryType.circle) return null;

    var coords = feature.geometry.coordinates[0];

    return GeoJsonCircle(
        id: GeoJsonUtils.buildKey(id:feature.id, buildingID:feature.buildingId, floor: feature.properties?['floor']),
        position: MapLocation(latitude: coords.last, longitude: coords.first),
        properties: feature.properties,
    );
  }
}