// lib/src/widgets/unified_map_widget.dart

import 'package:flutter/material.dart';
import '../../unified_map_view.dart';
import '../controllers/unified_map_controller.dart';
import '../utils/LandmarkAssetType.dart';
import 'FloorSpeedDial.dart';

/// Main widget that displays the map based on the current provider
class UnifiedMapWidget extends StatefulWidget {
  final UnifiedMapController controller;
  final EdgeInsets padding;
  final bool enablePinDrop;
  final Function(MapLocation)? onPinDropped;

  const UnifiedMapWidget({
    Key? key,
    required this.controller,
    this.padding = EdgeInsets.zero,
    this.enablePinDrop = false,
    this.onPinDropped,
  }) : super(key: key);

  @override
  State<UnifiedMapWidget> createState() => _UnifiedMapWidgetState();
}

class _UnifiedMapWidgetState extends State<UnifiedMapWidget> {
  MapLocation? _pendingPinLocation;
  bool _isPinDropMode = false;
  Offset? _dragPosition;


  @override
  void initState() {
    super.initState();
    // Set up the map tap callback handler
    widget.controller.setOnMapTapCallback(_handleMapTap);
  }

  @override
  void dispose() {
    // Clean up the callback
    widget.controller.setOnMapTapCallback(null);
    super.dispose();
  }

  /// Handle map tap - this gets called by the map provider
  void _handleMapTap(MapLocation location) {
    print("tapped on map ${_isPinDropMode}");
    if (_isPinDropMode) {
      _onMapTap(location);
    }
  }

  /// Toggle pin drop mode

  /// Handle map tap for pin dropping
  void _onMapTap(MapLocation location) {
    setState(() {
      _pendingPinLocation = location;
    });
    // _showPinConfirmationDialog(location);
  }

  /// Show confirmation dialog for pin drop
  Future<void> _showPinConfirmationDialog(MapLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.location_on, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Drop Pin Here?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Do you want to drop a pin at this location?',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.my_location, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Coordinates:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Latitude: ${location.latitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Longitude: ${location.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
             onPressed:(){
               Navigator.of(context).pop(true);
             },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Drop Pin'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    print("confirmed:${confirmed}");

    if (confirmed == true) {
      _confirmPinDrop(location);
    }else{
      setState(() {
        _pendingPinLocation = null;
      });
    }
  }

  /// Confirm and process pin drop
  void _confirmPinDrop(MapLocation location) {
    // Print the lat/lng
    print('═══════════════════════════════════════');
    print('📍 PIN DROPPED');
    print('═══════════════════════════════════════');
    print('Latitude:  ${location.latitude}');
    print('Longitude: ${location.longitude}');
    print('Formatted: (${location.latitude}, ${location.longitude})');
    print('═══════════════════════════════════════');
    // Add a marker at the dropped location
    _addPinMarker(location);
    // Call the callback if provided
    widget.onPinDropped?.call(location);
    // Exit pin drop mode
    setState(() {
      _pendingPinLocation = null;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Pin dropped at (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View Console',
          textColor: Colors.white,
          onPressed: () {
            // User can check console for full coordinates
          },
        ),
      ),
    );
  }

  /// Add a marker at the pin drop location
  Future<void> _addPinMarker(MapLocation location) async {
    try {
      final pinMarker = GeoJsonMarker(
        id: 'pin-${DateTime.now().millisecondsSinceEpoch}',
        position: location,
        title: "Dropped Pin",
        snippet: "Lat: ${location.latitude.toStringAsFixed(4)}, Lng: ${location.longitude.toStringAsFixed(4)}",
        assetPath: LandmarkAssetType.genericMarker.assetPath,
        iconName: "Dropped Pin",
        properties: {
          'type': 'dropped_pin',
          'timestamp': DateTime.now().toIso8601String(),
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        priority: true,
        imageSize: const Size(45, 45),
        anchor: LandmarkAssetType.genericMarker.anchor,
      );

      await widget.controller.addMarker(pinMarker);

      // Optional: animate camera to the pin
      await widget.controller.animateCamera(
        location,
        zoom: 15.0,
      );
    } catch (e) {
      debugPrint('Error adding pin marker: $e');
    }
  }

  Future<void> _confirmCrosshairPin() async {
    try {
      final cameraPosition = widget.controller.cameraPosition;

      final MapLocation centerLocation = MapLocation(
        latitude: cameraPosition.mapLocation.latitude,
        longitude: cameraPosition.mapLocation.longitude,
      );

      // Exit pin drop mode
      setState(() {
        _pendingPinLocation = centerLocation;
        _isPinDropMode = false;
      });

      // Trigger same dialog as map tap
      _confirmPinDrop(centerLocation);

    } catch (e) {
      debugPrint("Error getting camera center: $e");
    }
  }





  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main map widget - NO GestureDetector here!
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, child) {
            return Padding(
              padding: widget.padding,
              child: widget.controller.currentProviderImplementation.buildMap(
                config: widget.controller.config,
                context: context,
              ),
            );
          },
        ),

        // Pin drop mode indicator
        if (_isPinDropMode) ...[
          // Darken edges
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Colors.transparent, Colors.black26],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Center crosshair pin (visual only, map scrolls under it)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, color: Colors.red, size: 50,
                        shadows: [Shadow(color: Colors.black45, blurRadius: 8)]),
                    SizedBox(height: 2),
                    CircleAvatar(radius: 3, backgroundColor: Colors.black38),
                  ],
                ),
              ),
            ),
          ),

          // Top instruction banner
          Positioned(
            top: 260,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_with, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Move map to position pin',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),

          // Bottom confirm + cancel buttons
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _isPinDropMode = false),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _confirmCrosshairPin,
                    icon: const Icon(Icons.location_on),
                    label: const Text('Drop Pin Here'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

// FAB to enter pin drop mode
        if (widget.enablePinDrop && !_isPinDropMode)
          Positioned(
            bottom: 80,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: () => setState(() => _isPinDropMode = true),
                  backgroundColor: Colors.blue,
                  heroTag: 'pin_drop_fab',
                  child: const Icon(Icons.add_location, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text('Drop Pin',
                    style: TextStyle(fontSize: 10, color: Colors.black54)),
              ],
            ),
          ),
      ],
    );
  }
}