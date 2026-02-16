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
  bool _isPinDropMode = false;
  MapLocation? _pendingPinLocation;

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
    print("tapped on map");
    if (_isPinDropMode) {

      _onMapTap(location);
    }
  }

  /// Toggle pin drop mode
  void _togglePinDropMode() {
    setState(() {
      _isPinDropMode = !_isPinDropMode;
    });

    if (_isPinDropMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Tap on the map to drop a pin'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pin drop mode disabled'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  /// Handle map tap for pin dropping
  void _onMapTap(MapLocation location) {
    if (!_isPinDropMode) return;

    setState(() {
      _pendingPinLocation = location;
    });

    _showPinConfirmationDialog(location);
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
              onPressed: () => Navigator.of(context).pop(true),
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

    if (confirmed == true) {
      _confirmPinDrop(location);
    } else {
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
      _isPinDropMode = false;
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
        if (_isPinDropMode)
          Positioned(
            top: 260,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Tap anywhere to drop pin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Pin drop toggle button (only if enabled)
        if (widget.enablePinDrop)
          Positioned(
            bottom: 80,
            right: 16,
            child: FloatingActionButton(
              onPressed: _togglePinDropMode,
              backgroundColor: _isPinDropMode ? Colors.red : Colors.blue,
              child: Icon(
                _isPinDropMode ? Icons.close : Icons.add_location,
                color: Colors.white,
              ),
              heroTag: 'pin_drop_fab',
            ),
          ),
      ],
    );
  }
}