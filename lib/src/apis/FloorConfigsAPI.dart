import 'package:data_repository/data_repository.dart';

import '../apimodels/GlobalAppGeoJsonDataModel.dart';
import '../data/data_repository_bridge.dart';

/// The venue's floor configs (`floor-configs-venue`): every building's floor
/// names, render levels and orientations. The venue GeoJSON no longer carries
/// them.
class FloorConfigsAPI {
  /// The cached list, else the network; empty when neither has it. A host
  /// such as navigation_sdk refreshes the cached copy itself.
  Future<List<FloorConfigs>> fetchFloorConfigs(String venueName) async {
    try {
      final body = await (await dataRepository())
          .venue
          .get(VenueData.floorConfigs, venueName);
      if (body is! List) return const [];
      return [
        for (final config in body)
          if (config is Map) FloorConfigs.fromJson(config),
      ];
    } catch (e) {
      print("FloorConfigsAPI: no floor configs for $venueName: $e");
      return const [];
    }
  }
}
