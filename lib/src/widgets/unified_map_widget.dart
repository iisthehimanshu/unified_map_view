// lib/src/widgets/unified_map_widget.dart

import 'package:flutter/material.dart';
import '../controllers/unified_map_controller.dart';

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
          child: controller.currentProviderImplementation.buildMap(
            config: controller.config,
            onMapCreated: controller.onMapCreated,
            markers: controller.markers,
          ),
        );
      },
    );
  }
}