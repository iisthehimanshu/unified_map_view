import 'package:flutter/material.dart';
import 'package:unified_map_view/unified_map_view.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unified Map View Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late UnifiedMapController _mapController;

  @override
  void initState() {
    super.initState();

    // Initialize the controller with Google Maps as default
    _mapController = UnifiedMapController(
      initialProvider: MapProvider.mappls,
      config: const MapConfig(
        initialLocation: MapLocation(
          latitude: 37.7749, // San Francisco
          longitude: -122.4194,
        ),
        initialZoom: 12.0,
        showUserLocation: true,
        zoomControlsEnabled: true,
      ),
    );

    // Add some initial markers
    _addSampleMarkers();
  }

  void _addSampleMarkers() {
    _mapController.addMarker(
      const MapMarker(
        id: 'marker_1',
        position: MapLocation(latitude: 37.7749, longitude: -122.4194),
        title: 'San Francisco',
        snippet: 'Golden Gate Bridge',
      ),
    );

    _mapController.addMarker(
      const MapMarker(
        id: 'marker_2',
        position: MapLocation(latitude: 37.8044, longitude: -122.4080),
        title: 'Alcatraz Island',
        snippet: 'Historic Site',
      ),
    );
  }

  void _switchToGoogleMaps() {
    _mapController.switchProvider(MapProvider.google);
    _showSnackBar('Switched to Google Maps');
  }

  void _switchToMapbox() {
    _mapController.switchProvider(MapProvider.mapbox);
    _showSnackBar('Switched to Mapbox');
  }

  void _switchToAppleMaps() {
    _mapController.switchProvider(MapProvider.apple);
    _showSnackBar('Switched to Apple Maps');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _moveToParis() {
    _mapController.animateCamera(
      const MapLocation(latitude: 48.8566, longitude: 2.3522),
      zoom: 13.0,
    );
  }

  void _moveToTokyo() {
    _mapController.animateCamera(
      const MapLocation(latitude: 35.6762, longitude: 139.6503),
      zoom: 13.0,
    );
  }

  void _addRandomMarker() {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _mapController.addMarker(
      MapMarker(
        id: 'marker_$id',
        position: MapLocation(
          latitude: 37.7749 + (DateTime.now().millisecond % 100) / 1000,
          longitude: -122.4194 + (DateTime.now().second % 100) / 1000,
        ),
        title: 'Random Marker',
        snippet: 'Added at ${DateTime.now().toLocal()}',
      ),
    );
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unified Map View Demo'),
        elevation: 2,
      ),
      body: Column(
        children: [
          // Map provider selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Map Provider:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _switchToGoogleMaps,
                      icon: const Icon(Icons.map, size: 18),
                      label: const Text('Google'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _switchToMapbox,
                      icon: const Icon(Icons.layers, size: 18),
                      label: const Text('Mapbox'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _switchToAppleMaps,
                      icon: const Icon(Icons.apple, size: 18),
                      label: const Text('Apple'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Map widget
          Expanded(
            child: UnifiedMapWidget(controller: _mapController),
          ),

          // Control buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: _moveToParis,
                      child: const Text('Paris'),
                    ),
                    ElevatedButton(
                      onPressed: _moveToTokyo,
                      child: const Text('Tokyo'),
                    ),
                    ElevatedButton(
                      onPressed: _addRandomMarker,
                      child: const Text('Add Marker'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _mapController.clearMarkers(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Clear All Markers'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// ADVANCED USAGE EXAMPLES
// ============================================

/// Example: Adding a custom map provider
/// 
/// import 'package:unified_map_view/unified_map_view.dart';
/// 
/// class CustomMapProvider extends BaseMapProvider {
///   @override
///   Widget buildMap({...}) {
///     // Your custom map implementation
///   }
///   
///   // Implement other required methods...
/// }
/// 
/// // Register the custom provider
/// enum CustomMapProviders {
///   osm, // OpenStreetMap
///   here, // HERE Maps
/// }
/// 
/// _mapController.registerCustomProvider(
///   MapProvider.values.first, // or extend the enum
///   CustomMapProvider(),
/// );

/// Example: Dynamic configuration updates
/// 
/// _mapController.updateConfig(
///   _mapController.config.copyWith(
///     showUserLocation: false,
///     initialZoom: 15.0,
///   ),
/// );

/// Example: Getting current location
/// 
/// final currentLocation = await _mapController.getCurrentLocation();
/// if (currentLocation != null) {
///   print('Lat: ${currentLocation.latitude}, Lng: ${currentLocation.longitude}');
/// }