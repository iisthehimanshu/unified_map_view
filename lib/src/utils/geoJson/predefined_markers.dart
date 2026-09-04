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
      imageSize: Size(45, 45),
      anchor: LandmarkAssetType.genericMarker.anchor,
        customRendering: true
    );
  }

  /// The user puck.
  ///
  /// [style] lets a host swap the puck's artwork at runtime — pass null (the
  /// default) for the stock blue arrow. It is deliberately generic: any asset
  /// path the root bundle can resolve works, including one shipped by another
  /// package as `packages/<name>/...`. Applied here rather than at the call
  /// sites because this is the single place the puck marker is built, so an
  /// override automatically survives the marker being re-created on a floor
  /// change.
  static GeoJsonMarker getUserMarker(MapLocation location, String id,
      {UserMarkerStyle? style}){
    print("getUserMarker: asset=${style?.assetPath ?? LandmarkAssetType.user.assetPath} "
        "size=${style?.imageSize ?? const Size(35, 35)} (override=${style != null})");
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: style?.assetPath ?? LandmarkAssetType.user.assetPath,
        iconName: "User",
        priority: true,
        imageSize: style?.imageSize ?? Size(35, 35),
      anchor: LandmarkAssetType.user.anchor,
      renderAnchor: Offset(0.5, 0.5),
      // renderAnchor: Offset(0.515, 0.66),
      compassBasedRotation: style?.compassBasedRotation ?? true,
      customRendering: true
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
        anchor: LandmarkAssetType.source.anchor,
      customRendering: true
    );
  }

  static GeoJsonMarker getDestinationMarker(MapLocation location, String id, {String title = ""}){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: title,
        snippet: "",
        assetPath:LandmarkAssetType.destination.assetPath,
        iconName: "Destination",
        priority: true,
        imageSize: Size(30, 30),
        renderAnchor: Offset(0.5, 0.8),
        anchor: LandmarkAssetType.destination.anchor,
      customRendering: true,
      properties: {"fontSize":10.0}
    );
  }

  static GeoJsonMarker getFloorConnectionMarker(MapLocation location, String id, String? type){
    switch (type){
      case "Lift":
        return GeoJsonMarker(
            id: id,
            position: location,
            title: "",
            snippet: "",
            assetPath: LandmarkAssetType.lift.assetPath,
            iconName: "Floor Connection",
            priority: true,
            anchor: LandmarkAssetType.lift.anchor,
            imageSize: Size(30, 30),
            customRendering: true
        );
      case "Stair":
        return GeoJsonMarker(
            id: id,
            position: location,
            title: "",
            snippet: "",
            assetPath: LandmarkAssetType.stairs.assetPath,
            iconName: "Floor Connection",
            priority: true,
            anchor: LandmarkAssetType.stairs.anchor,
            imageSize: Size(30, 30),
            customRendering: true
        );
      case "Escalator":
        return GeoJsonMarker(
            id: id,
            position: location,
            title: "",
            snippet: "",
            assetPath: LandmarkAssetType.escalator.assetPath,
            iconName: "Floor Connection",
            priority: true,
            imageSize: Size(30, 30),
            anchor: LandmarkAssetType.escalator.anchor,
            customRendering: true
        );
      case "Ramp":
        return GeoJsonMarker(
            id: id,
            position: location,
            title: "",
            snippet: "",
            assetPath: LandmarkAssetType.ramp.assetPath,
            iconName: "Floor Connection",
            priority: true,
            imageSize: Size(30, 30),
            anchor: LandmarkAssetType.ramp.anchor,
            customRendering: true
        );
        default:
          return GeoJsonMarker(
              id: id,
              position: location,
              title: "",
              snippet: "",
              assetPath: LandmarkAssetType.lift.assetPath,
              iconName: "Floor Connection",
              priority: true,
              imageSize: Size(30, 30),
              anchor: LandmarkAssetType.lift.anchor,
              customRendering: true
          );
    }
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
        anchor: LandmarkAssetType.optionPinSelection.anchor,
        customRendering: true
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
        anchor: LandmarkAssetType.selectedPinSelection.anchor,
        customRendering: true
    );
  }

  static GeoJsonMarker getPathStopMarker(MapLocation location, String id, {String title = "", String stopName = ""}){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: title,
        snippet: "",
        assetPath:LandmarkAssetType.destination.assetPath,
        iconName: "Destination",
        priority: true,
        imageSize: Size(30, 30),
        renderAnchor: Offset(0.5, 0.8),
        anchor: LandmarkAssetType.destination.anchor,
        customRendering: true,
        properties: {
          "fontSize":10.0,
          "pathStop": true,
          "stopName": stopName,
        }
    );
  }

  static GeoJsonMarker getStartMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.start.assetPath,
        iconName: "start",
        priority: true,
        imageSize: Size(30, 30),
        anchor: LandmarkAssetType.start.anchor,
        customRendering: true
    );
  }

  static GeoJsonMarker getStopMarker(MapLocation location, String id){
    return GeoJsonMarker(
        id: id,
        position: location,
        title: "",
        snippet: "",
        assetPath: LandmarkAssetType.stop.assetPath,
        iconName: "stop",
        priority: true,
        imageSize: Size(30, 30),
        anchor: LandmarkAssetType.stop.anchor,
        customRendering: true
    );
  }
}