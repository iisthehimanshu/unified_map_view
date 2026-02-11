import 'dart:ui';
import 'dart:ui';

enum LandmarkAssetType {
  lift,
  stairs,
  escalator,
  ramp,
  femaleWashroom,
  maleWashroom,
  accessibleWashroom,
  washroom,
  waterFountain,
  cafeteria,
  room,
  doorOnly,
  mainEntry,
  counter,
  genericMarker,
  user,
  source,
  destination,
  optionPinSelection,
  selectedPinSelection,
  sofa,
  assemblyRoom,
  conferenceRoom,
  emergencyExit,
  fireExtinguisher,
  firstAid,
  meetingRoom,
  registrationDesk,
  unisexWashroom,
  smokingArea,
  gadgets,
  garments
  ;

  String get assetPath {
    switch (this) {
      case LandmarkAssetType.lift:
        return 'packages/unified_map_view/assets/markers/lift.png';
      case LandmarkAssetType.stairs:
        return 'packages/unified_map_view/assets/markers/stairs.png';
      case LandmarkAssetType.escalator:
        return 'packages/unified_map_view/assets/markers/escalator.png';
      case LandmarkAssetType.ramp:
        return 'packages/unified_map_view/assets/markers/ramp.png';
      case LandmarkAssetType.femaleWashroom:
        return 'packages/unified_map_view/assets/markers/female_washroom.png';
      case LandmarkAssetType.maleWashroom:
        return 'packages/unified_map_view/assets/markers/male_washroom.png';
      case LandmarkAssetType.accessibleWashroom:
        return 'packages/unified_map_view/assets/markers/unisex_washroom.png';
      case LandmarkAssetType.washroom:
        return 'packages/unified_map_view/assets/markers/washroom.png';
      case LandmarkAssetType.waterFountain:
        return 'packages/unified_map_view/assets/markers/water_fountain.png';
      case LandmarkAssetType.cafeteria:
        return 'packages/unified_map_view/assets/markers/cafeteria.png';
      case LandmarkAssetType.room:
        return 'packages/unified_map_view/assets/markers/room.png';
      case LandmarkAssetType.doorOnly:
        return 'packages/unified_map_view/assets/markers/entry.png';
      case LandmarkAssetType.mainEntry:
        return 'packages/unified_map_view/assets/markers/building_entry.png';
      case LandmarkAssetType.genericMarker:
        return 'packages/unified_map_view/assets/markers/generic_marker.png';
      case LandmarkAssetType.counter:
        return 'packages/unified_map_view/assets/markers/counter.png';
      case LandmarkAssetType.user:
        return 'packages/unified_map_view/assets/markers/user.png';
      case LandmarkAssetType.source:
        return 'packages/unified_map_view/assets/markers/source.png';
      case LandmarkAssetType.destination:
        return 'packages/unified_map_view/assets/markers/destination.png';
      case LandmarkAssetType.optionPinSelection:
        return 'packages/unified_map_view/assets/markers/option_pin_selection.png';
      case LandmarkAssetType.selectedPinSelection:
        return 'packages/unified_map_view/assets/markers/selected_pin_selection.png';
      case LandmarkAssetType.sofa:
        return 'packages/unified_map_view/assets/isometric_elements/sofa.png';

      case LandmarkAssetType.assemblyRoom:
        return 'packages/unified_map_view/assets/markers/assembly_Room.png';
      case LandmarkAssetType.conferenceRoom:
        return 'packages/unified_map_view/assets/markers/conference_room.png';
      case LandmarkAssetType.emergencyExit:
        return 'packages/unified_map_view/assets/markers/emergency_exit.png';
      case LandmarkAssetType.fireExtinguisher:
        return 'packages/unified_map_view/assets/markers/fire_extinguisher.png';
      case LandmarkAssetType.firstAid:
        return 'packages/unified_map_view/assets/markers/first_aid.png';
      case LandmarkAssetType.meetingRoom:
        return 'packages/unified_map_view/assets/markers/meeting_room.png';
      case LandmarkAssetType.registrationDesk:
        return 'packages/unified_map_view/assets/markers/registration_Desk.png';
      case LandmarkAssetType.unisexWashroom:
        return 'packages/unified_map_view/assets/markers/unisex_washroom.png';
      case LandmarkAssetType.smokingArea:
        return 'packages/unified_map_view/assets/markers/smoking_area.png';
      case LandmarkAssetType.gadgets:
        return 'packages/unified_map_view/assets/markers/gadgets.png';
      case LandmarkAssetType.garments:
        return 'packages/unified_map_view/assets/markers/garments.png';
    }
  }

  bool get textVisibility {
    switch (this) {
      case LandmarkAssetType.lift:
      case LandmarkAssetType.stairs:
      case LandmarkAssetType.escalator:
      case LandmarkAssetType.ramp:
      case LandmarkAssetType.femaleWashroom:
      case LandmarkAssetType.maleWashroom:
      case LandmarkAssetType.accessibleWashroom:
      case LandmarkAssetType.washroom:
      case LandmarkAssetType.cafeteria:
      case LandmarkAssetType.doorOnly:
      case LandmarkAssetType.mainEntry:
      case LandmarkAssetType.unisexWashroom:
      case LandmarkAssetType.assemblyRoom:
      case LandmarkAssetType.conferenceRoom:
      case LandmarkAssetType.emergencyExit:
      case LandmarkAssetType.fireExtinguisher:
      case LandmarkAssetType.firstAid:
      case LandmarkAssetType.meetingRoom:
      case LandmarkAssetType.registrationDesk:
      case LandmarkAssetType.smokingArea:
      case LandmarkAssetType.counter:
      case LandmarkAssetType.waterFountain:
      case LandmarkAssetType.room:
      case LandmarkAssetType.genericMarker:
      case LandmarkAssetType.user:
      case LandmarkAssetType.source:
      case LandmarkAssetType.destination:
      case LandmarkAssetType.optionPinSelection:
      case LandmarkAssetType.selectedPinSelection:
      case LandmarkAssetType.sofa:
      case LandmarkAssetType.gadgets:
      case LandmarkAssetType.garments:
        return false;
    }
  }

  Offset get anchor {
    switch (this) {
      case LandmarkAssetType.lift:
      case LandmarkAssetType.stairs:
      case LandmarkAssetType.escalator:
      case LandmarkAssetType.ramp:
      case LandmarkAssetType.doorOnly:
      case LandmarkAssetType.mainEntry:
      case LandmarkAssetType.source:
      case LandmarkAssetType.counter:
      case LandmarkAssetType.accessibleWashroom:
      case LandmarkAssetType.user:
      case LandmarkAssetType.sofa:
      case LandmarkAssetType.optionPinSelection:
      case LandmarkAssetType.selectedPinSelection:
      case LandmarkAssetType.firstAid:
        return const Offset(0.5, 0.5);

      case LandmarkAssetType.room:
      case LandmarkAssetType.genericMarker:
      case LandmarkAssetType.washroom:
      case LandmarkAssetType.femaleWashroom:
      case LandmarkAssetType.maleWashroom:
      case LandmarkAssetType.cafeteria:
      case LandmarkAssetType.unisexWashroom:
      case LandmarkAssetType.smokingArea:
      case LandmarkAssetType.destination:
      case LandmarkAssetType.waterFountain:
      case LandmarkAssetType.assemblyRoom:
      case LandmarkAssetType.conferenceRoom:
      case LandmarkAssetType.emergencyExit:
      case LandmarkAssetType.fireExtinguisher:
      case LandmarkAssetType.meetingRoom:
      case LandmarkAssetType.registrationDesk:
      case LandmarkAssetType.gadgets:
      case LandmarkAssetType.garments:
        return const Offset(0.5, 1.0);

    }
  }
}