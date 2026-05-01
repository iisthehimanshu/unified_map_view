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
    this.color = Colors.blue,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.focusedBuildingAvailableFloors == null ||
        controller.focusBuildingSelectedFloor == null) {
      return const SizedBox.shrink();
    }

    var selectedFloor = controller.focusBuildingSelectedFloor!;
    List<SpeedDialChild> floorsChildren = floorChildren();

    if (floorsChildren.isEmpty || floorsChildren.length == 1) {
      return const SizedBox.shrink();
    }

    double spacing = MediaQuery.of(context).size.height * 0.015;

    return SafeArea(
      child: SpeedDial(
        activeIcon: Icons.close,
        backgroundColor: color,
        foregroundColor: Colors.white,
        activeBackgroundColor: color,
        overlayOpacity: 0.2,
        spacing: spacing,
        children: floorsChildren,
        child: _floorLabel(selectedFloor, color: Colors.white),
      ),
    );
  }

  List<SpeedDialChild> floorChildren() {
    final floors = controller.floorsContainingPath.isNotEmpty
        ? controller.floorsContainingPath
        : (controller.focusedBuildingAvailableFloors ?? []);

    return floors.map((floor) {
      final isSelected = controller.focusBuildingSelectedFloor == floor;

      return SpeedDialChild(
        shape: const CircleBorder(),
        child: _floorLabel(
          floor,
          color: isSelected ? Colors.white : Colors.black,
        ),
        backgroundColor: isSelected ? Colors.blue : Colors.white,
        onTap: () {
          controller.changeBuildingFloor(
            buildingID: controller.focusedBuilding!,
            floor: floor,
          );
        },
      );
    }).toList();
  }

  Widget _floorLabel(int floor, {Color? color}) {
    return Text(
      floor == 0 ? 'G' : floor.toString(),
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: color ?? Colors.black,
      ),
    );
  }

  String _floorName(int floor) {
    if (floor == 0) return 'Ground Floor';
    return 'Floor $floor';
  }
}