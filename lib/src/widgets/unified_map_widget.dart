// lib/src/widgets/unified_map_widget.dart

import 'package:flutter/material.dart';
import '../controllers/unified_map_controller.dart';
import 'FloorSpeedDial.dart';

/// Main widget that displays the map based on the current provider
class UnifiedMapWidget extends StatelessWidget {
  final UnifiedMapController controller;
  final EdgeInsets padding;

  const UnifiedMapWidget({
    Key? key,
    required this.controller,
    this.padding = EdgeInsets.zero,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Padding(
          padding: padding,
          child: Stack(
            children: [
              controller.currentProviderImplementation.buildMap(config: controller.config),
              if(controller.focusedBuilding != null && controller.focusBuildingSelectedFloor != null && controller.focusedBuildingAvailableFloors != null && controller.focusedBuildingAvailableFloors!.isNotEmpty) Positioned(
                bottom: 24,
                right: 16,
                child: FloorSpeedDial(
                  floors: controller.focusedBuildingAvailableFloors!,
                  selectedFloor: controller.focusBuildingSelectedFloor!,
                  onFloorSelected: (floor) {
                    controller.changeBuildingFloor(buildingID: controller.focusedBuilding!, floor: floor);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}