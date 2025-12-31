
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

class FloorSpeedDial extends StatelessWidget {
  final int selectedFloor;
  final List<int> floors;
  final ValueChanged<int> onFloorSelected;

  const FloorSpeedDial({
    super.key,
    required this.selectedFloor,
    required this.floors,
    required this.onFloorSelected,
  });

  @override
  Widget build(BuildContext context) {
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
            onTap: () => onFloorSelected(floor),
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
