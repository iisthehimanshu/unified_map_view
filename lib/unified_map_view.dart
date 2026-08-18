// lib/unified_map_view.dart

library unified_map_view;

import 'package:hive/hive.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:unified_map_view/src/apis/BuildingByVenue.dart';
import 'package:unified_map_view/src/apis/GlobalGeoJSONVenueAPI.dart';
import 'package:unified_map_view/src/config.dart';
import 'package:unified_map_view/src/utils/perf_trace.dart';
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
export 'src/utils/perf_trace.dart';
export 'src/utils/geoJson/geojson_loader.dart';
export 'src/utils/geoJson/geoJsonUtils.dart';
export 'src/utils/geoJson/predefined_markers.dart';

class UnifiedMapViewPackage {
  static bool _initialized = false;
  static Future<void>? _initFuture;

  /// Concurrent callers share a single initialization.
  ///
  /// A plain `if (_initialized) return;` guard was not enough: the flag was only
  /// set after several awaits, so a second call arriving while the first was
  /// still in flight slipped past it and re-ran `Hive.registerAdapter`, throwing
  /// `HiveError: There is already a TypeAdapter for typeId 79`. That killed the
  /// map on web, where startNavigation is dispatched from a post-frame callback
  /// and can fire twice. Memoizing the future makes the second caller await the
  /// first run instead of starting its own.
  static Future<void> initialize({required String venueName,String? url}) {
    AppConfig.url = url;
    return _initFuture ??= _initializeOnce(venueName);
  }

  static Future<void> _initializeOnce(String venueName) async {
    try {
      PerfTrace.mark('UnifiedMapViewPackage.initialize start');
      // Initialize Hive
      await PerfTrace.timeAsync('Hive.initFlutter', () => Hive.initFlutter());

      // Register adapters
      Hive.registerAdapter(BuildingByVenueAPIModelAdapter());
      // On web a non-lazy openBox deserialises every record up front, so this
      // pays a full decode of the cached venue blob before returning.
      await PerfTrace.timeAsync('openBox BuildingByVenue',
          () => Hive.openBox<BuildingByVenueAPIModel>('UNifiedBuildingByVenueAPIModelFile'));

      Hive.registerAdapter(GlobalGeoJSONVenueAPIModelAdapter());
      await PerfTrace.timeAsync('openBox GlobalGeoJSONVenue',
          () => Hive.openBox<GlobalGeoJSONVenueAPIModel>('GlobalGeoJSONVenueAPIModelFile'));
      _initialized = true;

      await PerfTrace.timeAsync('initialize: fetchBuildingIDS',
          () => BuildingByVenue().fetchBuildingIDS(venueName));
      await PerfTrace.timeAsync('initialize: getGeoJSONData',
          () => GlobalGeoJSONVenueAPI().getGeoJSONData(venueName));
    } catch (_) {
      // Don't cache a failed init — a later call should be able to retry, which
      // is what the old flag did implicitly by never being set.
      _initFuture = null;
      rethrow;
    }
  }

  static bool get isInitialized => _initialized;
}