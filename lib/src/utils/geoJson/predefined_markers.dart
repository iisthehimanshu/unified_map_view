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
      anchor: LandmarkAssetType.genericMarker.anchor
    );
  }

  static GeoJsonMarker getUserMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.user.assetPath,
        iconName: "User",
        priority: true,
        imageSize: Size(35, 35),
      anchor: LandmarkAssetType.user.anchor,
      compassBasedRotation: true
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
        imageSize: Size(14, 14),
        anchor: LandmarkAssetType.source.anchor
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
        imageSize: Size(30, 30),
        anchor: LandmarkAssetType.destination.anchor
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
        priority: true,
        anchor: LandmarkAssetType.floorConnection.anchor
    );
  }

  static GeoJsonMarker getOptionPinSelectionMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.optionPinSelection.assetPath,
        iconName: "Option Pin Selection",
        priority: true,
        anchor: LandmarkAssetType.optionPinSelection.anchor
    );
  }

  static GeoJsonMarker getSelectedPinSelectionMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.selectedPinSelection.assetPath,
        iconName: "Selected Pin Selection",
        priority: true,
        anchor: LandmarkAssetType.selectedPinSelection.anchor
    );
  }
}