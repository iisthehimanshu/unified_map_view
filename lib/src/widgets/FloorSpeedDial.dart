
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../../unified_map_view.dart';

class FloorSpeedDial extends StatelessWidget {

  final UnifiedMapController controller;
  final Color color;

  const FloorSpeedDial({
    super.key,
    required this.controller,
    this.color= Colors.blue
  });

  @override
  Widget build(BuildContext context) {
    if(controller.focusedBuildingAvailableFloors == null || controller.focusBuildingSelectedFloor == null) return SizedBox.shrink();
    var  selectedFloor =  controller.focusBuildingSelectedFloor!;
    List<SpeedDialChild> floorsChildren = floorChildren();
    if (floorsChildren.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: SpeedDial(
        activeIcon: Icons.close,
        backgroundColor: color,
        foregroundColor: Colors.white,
        activeBackgroundColor: color,
        overlayOpacity: 0.2,
        children: floorsChildren,
        child: _floorLabel(selectedFloor, color: Colors.white),
      ),
    );
  }

  List<SpeedDialChild> floorChildren(){
    if(controller.floorsContainingPath.isNotEmpty){
      return controller.floorsContainingPath
          .map(
              (floor) => SpeedDialChild(
            child: _floorLabel(floor),
            backgroundColor: Colors.blue,
            onTap: (){
              controller.changeBuildingFloor(buildingID: controller.focusedBuilding!, floor: floor);
            },
          )
      ).toList();
    }else if(controller.focusedBuildingAvailableFloors != null && controller.focusedBuildingAvailableFloors!.isNotEmpty){
      return controller.focusedBuildingAvailableFloors!
          .map(
              (floor) => SpeedDialChild(
            child: _floorLabel(floor),
                backgroundColor: Colors.white,
            onTap: (){
              controller.changeBuildingFloor(buildingID: controller.focusedBuilding!, floor: floor);
            },
          )
      ).toList();
    }else{
      return [];
    }
  }

  Widget _floorLabel(int floor,{Color? color}) {
    return Text(
      floor == 0 ? 'G' : floor.toString(),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: color??Colors.black,
      ),
    );
  }

  String _floorName(int floor) {
    if (floor == 0) return 'Ground Floor';
    return 'Floor $floor';
  }
}
