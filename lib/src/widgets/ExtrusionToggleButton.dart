import 'package:flutter/material.dart';
import '../controllers/unified_map_controller.dart';

class ExtrusionToggleButton extends StatefulWidget {
  final UnifiedMapController controller;
  final Color color;

  const ExtrusionToggleButton({
    super.key,
    required this.controller,
    this.color = Colors.blue,
  });

  @override
  State<ExtrusionToggleButton> createState() =>
      _ExtrusionToggleButtonState();
}

class _ExtrusionToggleButtonState extends State<ExtrusionToggleButton> {
  late bool immersive;

  @override
  void initState() {
    super.initState();
    immersive = widget.controller.config.immersive;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FloatingActionButton(
        onPressed: () {
          setState(() {
            immersive = !immersive;
          });
          widget.controller.toggle3DView();
        },
        backgroundColor: Colors.white,
        foregroundColor: widget.color,
        shape: const CircleBorder(),
        elevation: 4,
        child: Text(
          immersive ? "3D" : "2D",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: widget.color
          ),
        ),
      ),
    );
  }
}