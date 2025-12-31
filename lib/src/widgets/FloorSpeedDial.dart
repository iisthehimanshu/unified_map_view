
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../../unified_map_view.dart';

class FloorSpeedDial extends StatelessWidget {

  final UnifiedMapController controller;

  const FloorSpeedDial({
    super.key,
    required this.controller
  });

  @override
  Widget build(BuildContext context) {
    if(controller.focusedBuildingAvailableFloors == null || controller.focusBuildingSelectedFloor == null) return SizedBox.shrink();
    var floors = controller.focusedBuildingAvailableFloors!;
    var  selectedFloor =  controller.focusBuildingSelectedFloor!;
    if (floors.isEmpty) return const SizedBox.shrink();

    return SafeArea(
      child: SpeedDial(
        activeIcon: Icons.close,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        overlayOpacity: 0.2,
        children: floors
            .map(
              (floor) => SpeedDialChild(
            child: _floorLabel(floor),
            onTap: (){
              controller.changeBuildingFloor(buildingID: controller.focusedBuilding!, floor: floor);
            },
          ),
        )
            .toList(),
        child: _floorLabel(selectedFloor, color: Colors.white),
      ),
    );
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
