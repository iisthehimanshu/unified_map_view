import 'dart:ui';

import '../../../unified_map_view.dart';
import '../LandmarkAssetType.dart';

class PredefinedMarkers{
  static GeoJsonMarker getGenericMarker(GeoJsonMarker marker){
    return GeoJsonMarker(
        id: marker.id,
        position: marker.position,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.genericMarker.assetPath,
        iconName: "Generic Marker",
        properties: marker.properties,
        priority: true,
      iconSizeRatio: marker.iconSizeRatio
    );
  }

  static GeoJsonMarker getUserMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: "user",
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.user.assetPath,
        iconName: "User",
        priority: true
    );
  }

  static GeoJsonMarker getSourceMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.source.assetPath,
        iconName: "source",
        priority: true,
        imageSize: Size(15, 15)
    );
  }

  static GeoJsonMarker getDestinationMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.destination.assetPath,
        iconName: "Destination",
        priority: true,
        imageSize: Size(30, 30)
    );
  }

  static GeoJsonMarker getFloorConnectionMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.floorConnection.assetPath,
        iconName: "Floor Connection",
        priority: true
    );
  }
}