enum LandmarkAssetType {
  lift,
  stairs,
  escalator,
  femaleWashroom,
  maleWashroom,
  accessibleWashroom,
  washroom,
  waterFountain,
  cafeteria,
  room,
  entrance,
  genericMarker,
  user,
  source,
  destination,
  floorConnection,
  emergency;

  String get assetPath {
    switch (this) {
      case LandmarkAssetType.lift:
        return 'packages/unified_map_view/assets/markers/lift.png';
      case LandmarkAssetType.stairs:
        return 'packages/unified_map_view/assets/markers/stairs.png';
      case LandmarkAssetType.escalator:
        return 'packages/unified_map_view/assets/markers/escalator.png';
      case LandmarkAssetType.femaleWashroom:
        return 'packages/unified_map_view/assets/markers/female_washroom.png';
      case LandmarkAssetType.maleWashroom:
        return 'packages/unified_map_view/assets/markers/male_washroom.png';
      case LandmarkAssetType.accessibleWashroom:
        return 'packages/unified_map_view/assets/markers/male_washroom.png';
      case LandmarkAssetType.washroom:
        return 'packages/unified_map_view/assets/markers/washroom.png';
      case LandmarkAssetType.waterFountain:
        return 'packages/unified_map_view/assets/markers/water_fountain.png';
      case LandmarkAssetType.cafeteria:
        return 'packages/unified_map_view/assets/markers/cafeteria.png';
      case LandmarkAssetType.room:
        return 'packages/unified_map_view/assets/markers/room.png';
      case LandmarkAssetType.entrance:
        return 'packages/unified_map_view/assets/markers/building_entry.png';
      case LandmarkAssetType.genericMarker:
        return 'packages/unified_map_view/assets/markers/generic_marker.png';
      case LandmarkAssetType.user:
        return 'packages/unified_map_view/assets/markers/generic_marker.png';
      case LandmarkAssetType.source:
        return 'packages/unified_map_view/assets/markers/source.png';
      case LandmarkAssetType.destination:
        return 'packages/unified_map_view/assets/markers/destination.png';
      case LandmarkAssetType.floorConnection:
        return 'packages/unified_map_view/assets/markers/lift.png';
      case LandmarkAssetType.emergency:
        return 'packages/unified_map_view/assets/markers/entry.png';
    }
  }



  double get iconSize {
    switch (this) {
      case LandmarkAssetType.lift:
        return 0.3;
      case LandmarkAssetType.stairs:
        return 0.3;
      case LandmarkAssetType.escalator:
        return 0.3;
      case LandmarkAssetType.femaleWashroom:
        return 0.3;
      case LandmarkAssetType.maleWashroom:
        return 0.3;
      case LandmarkAssetType.accessibleWashroom:
        return 0.3;
      case LandmarkAssetType.washroom:
        return 0.3;
      case LandmarkAssetType.waterFountain:
        return 0.3;
      case LandmarkAssetType.cafeteria:
        return 0.3;
      case LandmarkAssetType.room:
        return 0.3;
      case LandmarkAssetType.entrance:
        return 0.3;
      case LandmarkAssetType.genericMarker:
        return 0.1;
      case LandmarkAssetType.emergency:
        return 0.3;
      case LandmarkAssetType.source:
        return 0.3;
      case LandmarkAssetType.destination:
        return 0.3;
      case LandmarkAssetType.floorConnection:
        return 0.3;
      case LandmarkAssetType.emergency:
        return 0.3;
      case LandmarkAssetType.user:
        return 0.3;
    }
  }
}