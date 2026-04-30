// lib/unified_map_view.dart

library unified_map_view;

import 'package:hive/hive.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:unified_map_view/src/apis/BuildingByVenue.dart';
import 'package:unified_map_view/src/apis/GlobalGeoJSONVenueAPI.dart';
import 'package:unified_map_view/src/config.dart';
import 'package:unified_map_view/src/database/model/BuildingByVenueAPIModel.dart';
import 'package:unified_map_view/src/database/model/GlobalGeoJSONVenueAPIModel.dart';

// Enums
export 'src/enums/map_provider.dart';

// Models
export 'src/models/map_config.dart';
export 'src/models/map_location.dart';
export 'src/models/camera_position.dart';
export 'src/models/geojson_models.dart';
export 'src/models/user.dart';
export 'src/models/CameraBound.dart';

// Controllers
export 'src/controllers/unified_map_controller.dart';
export 'src/controllers/annotation_controller.dart';

// Widgets
export 'src/widgets/unified_map_widget.dart';
export 'src/widgets/FloorSpeedDial.dart';
export 'src/widgets/ExtrusionToggleButton.dart';

// Providers (for custom implementations)
export 'src/providers/base_map_provider.dart';

// Utilities
export 'src/utils/geoJson/geojson_loader.dart';
export 'src/utils/geoJson/geoJsonUtils.dart';
export 'src/utils/geoJson/predefined_markers.dart';

class UnifiedMapViewPackage {
  static bool _initialized = false;

  static Future<void> initialize({required String venueName,String? url}) async {
    AppConfig.url = url;
    if (_initialized) return;

    // Initialize Hive
    await Hive.initFlutter();

    // Register adapters
    Hive.registerAdapter(BuildingByVenueAPIModelAdapter());
    await Hive.openBox<BuildingByVenueAPIModel>('UNifiedBuildingByVenueAPIModelFile');

    Hive.registerAdapter(GlobalGeoJSONVenueAPIModelAdapter());
    await Hive.openBox<GlobalGeoJSONVenueAPIModel>('GlobalGeoJSONVenueAPIModelFile');
    _initialized = true;

   await BuildingByVenue().fetchBuildingIDS(venueName);
   await GlobalGeoJSONVenueAPI().getGeoJSONData(venueName);
  }

  static bool get isInitialized => _initialized;
}