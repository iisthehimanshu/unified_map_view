import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../../unified_map_view.dart';

class FloorSpeedDial extends StatefulWidget {
  final UnifiedMapController controller;
  final Color color;

  const FloorSpeedDial({
    super.key,
    required this.controller,
    this.color = Colors.blue,
  });

  @override
  State<FloorSpeedDial> createState() => _FloorSpeedDialState();
}

class _FloorSpeedDialState extends State<FloorSpeedDial> {
  bool _isOpen = false;

  UnifiedMapController get controller => widget.controller;
  Color get color => widget.color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
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
        final buildingName = controller.focusedBuildingName;
        final hasBuildingName = buildingName != null && buildingName.isNotEmpty;

        return SafeArea(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Building name sits to the left of the (close) button while open.
              if (_isOpen && hasBuildingName) ...[
                Flexible(child: _buildingNameLabel(buildingName)),
                const SizedBox(width: 12),
              ],
              SpeedDial(
                activeIcon: Icons.close,
                backgroundColor: color,
                foregroundColor: Colors.white,
                activeBackgroundColor: color,
                overlayOpacity: 0.2,
                spacing: spacing,
                onOpen: () => setState(() => _isOpen = true),
                onClose: () => setState(() => _isOpen = false),
                children: floorsChildren,
                child: _floorLabel(selectedFloor, controller.focusedBuilding??"", color: Colors.white),
              ),
            ],
          ),
        );
      },
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
          floor, controller.focusedBuilding??"",
          color: isSelected ? Colors.white : Colors.black,
        ),
        backgroundColor: isSelected ? Colors.blue : Colors.white,
        onTap: () {
          controller.changeAllBuildingsFloor(floor: floor);
        },
      );
    }).toList();
  }

  Widget _buildingNameLabel(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _floorLabel(int floor, String bid, {Color? color}) {
    // Show the user-facing render level (matched to floorNumber in floorConfig),
    // while the actual level is still used for floor changes.
    final renderLevel = controller.getFloorRenderLevel(floor, bid);
    return Text(
      renderLevel == 0 ? 'G' : renderLevel.toString(),
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