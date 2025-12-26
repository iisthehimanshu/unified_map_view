
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

    return SpeedDial(
      activeIcon: Icons.close,
      backgroundColor: Colors.blue,
      foregroundColor: Colors.white,
      overlayOpacity: 0.2,
      child: _floorLabel(selectedFloor),
      children: floors
          .map(
            (floor) => SpeedDialChild(
          child: _floorLabel(floor),
          label: _floorName(floor),
          onTap: () => onFloorSelected(floor),
        ),
      )
          .toList(),
    );
  }

  Widget _floorLabel(int floor) {
    return Text(
      floor == 0 ? 'G' : floor.toString(),
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  String _floorName(int floor) {
    if (floor == 0) return 'Ground Floor';
    return 'Floor $floor';
  }
}
