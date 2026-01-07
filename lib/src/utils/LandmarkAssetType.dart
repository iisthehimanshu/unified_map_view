import 'dart:ui';

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
  emergency,
  optionPinSelection,
  selectedPinSelection;

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
        return 'packages/unified_map_view/assets/markers/user.png';
      case LandmarkAssetType.source:
        return 'packages/unified_map_view/assets/markers/source.png';
      case LandmarkAssetType.destination:
        return 'packages/unified_map_view/assets/markers/destination.png';
      case LandmarkAssetType.floorConnection:
        return 'packages/unified_map_view/assets/markers/lift.png';
      case LandmarkAssetType.emergency:
        return 'packages/unified_map_view/assets/markers/entry.png';
      case LandmarkAssetType.optionPinSelection:
        return 'packages/unified_map_view/assets/markers/option_pin_selection.png';
      case LandmarkAssetType.selectedPinSelection:
        return 'packages/unified_map_view/assets/markers/selected_pin_selection.png';
    }
  }

  bool get textVisibility {
    switch (this) {
      case LandmarkAssetType.lift:
      case LandmarkAssetType.stairs:
      case LandmarkAssetType.escalator:
      case LandmarkAssetType.femaleWashroom:
      case LandmarkAssetType.maleWashroom:
      case LandmarkAssetType.accessibleWashroom:
      case LandmarkAssetType.washroom:
      case LandmarkAssetType.cafeteria:
      case LandmarkAssetType.entrance:
      case LandmarkAssetType.floorConnection:
      case LandmarkAssetType.emergency:
        return false;

      case LandmarkAssetType.waterFountain:
      case LandmarkAssetType.room:
      case LandmarkAssetType.genericMarker:
        return true;

      case LandmarkAssetType.user:
        return false;

      case LandmarkAssetType.source:
      case LandmarkAssetType.destination:
        return true;

      case LandmarkAssetType.optionPinSelection:
      case LandmarkAssetType.selectedPinSelection:
        return false;
    }
  }

  Offset get anchor {
    switch (this) {
      case LandmarkAssetType.lift:
      case LandmarkAssetType.stairs:
      case LandmarkAssetType.escalator:
      case LandmarkAssetType.entrance:
      case LandmarkAssetType.source:
        return const Offset(0.5, 0.5);

      case LandmarkAssetType.user:
        return const Offset(0.51, 0.785);

      case LandmarkAssetType.washroom:
      case LandmarkAssetType.femaleWashroom:
      case LandmarkAssetType.maleWashroom:
      case LandmarkAssetType.accessibleWashroom:
      case LandmarkAssetType.destination:
        return const Offset(0.5, 1.0);

      case LandmarkAssetType.cafeteria:
      case LandmarkAssetType.room:
      case LandmarkAssetType.genericMarker:
      case LandmarkAssetType.waterFountain:
      case LandmarkAssetType.floorConnection:
      case LandmarkAssetType.emergency:
        return const Offset(0.5, 0.5);

      case LandmarkAssetType.optionPinSelection:
      case LandmarkAssetType.selectedPinSelection:
        return const Offset(0.5, 0.5);
    }
  }

}