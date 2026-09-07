import 'package:flutter/foundation.dart';

import '../utils/LandmarkAssetType.dart';

/// One landmark type present in the currently loaded venue.
///
/// Venues do not share a type vocabulary — one has `Male Washroom` and
/// `First Aid`, the next has neither and adds `Ticket Counter` — so the set of
/// types a host can offer is a property of the *data*, not something that can
/// be hardcoded. Read it from
/// `UnifiedMapController.availableMarkerTypes` and build the UI from what comes
/// back, rather than from a fixed list that will show dead options on one venue
/// and miss types on another.
@immutable
class MarkerTypeInfo {
  /// The type exactly as the venue's GeoJSON spells it — show this to users and
  /// pass it back to `showMarkerTypes`.
  final String rawType;

  /// The icon this type resolves to, or null when the renderer has no case for
  /// it. Useful for drawing a chip's icon; NOT an identity — several raw types
  /// can share one asset (`entry`, `entrance` and `exit` are all
  /// [LandmarkAssetType.mainEntry]), which is exactly why filtering matches on
  /// [rawType] instead.
  final LandmarkAssetType? assetType;

  /// How many markers of this type the venue currently holds.
  final int count;

  const MarkerTypeInfo({
    required this.rawType,
    required this.assetType,
    required this.count,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerTypeInfo &&
          other.rawType == rawType &&
          other.assetType == assetType &&
          other.count == count;

  @override
  int get hashCode => Object.hash(rawType, assetType, count);

  @override
  String toString() =>
      'MarkerTypeInfo($rawType, asset: ${assetType?.name}, count: $count)';
}
