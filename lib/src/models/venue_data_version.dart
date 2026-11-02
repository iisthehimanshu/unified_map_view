/// Which venue GeoJSON the map is drawing, and whether a newer one is on its
/// way. Read through `UnifiedMapViewPackage.venueDataVersion`.
///
/// A version is the host's key of every building's `globalAnnotationVersion`
/// from `data-versions-multiple`, e.g. `65d8…:4,680a…:64`.
class VenueDataVersion {
  /// Version of the data the map is showing. Null until a load completes, or
  /// when that data was cached before versions were recorded with it.
  final String? showing;

  /// True while a newer version is downloading.
  final bool fetching;

  /// A newer version that has been downloaded and cached. The map keeps
  /// [showing] until the venue is next opened (the load is cache-first).
  final String? pending;

  const VenueDataVersion({this.showing, this.fetching = false, this.pending});

  VenueDataVersion copyWith({String? showing, bool? fetching, String? pending}) =>
      VenueDataVersion(
        showing: showing ?? this.showing,
        fetching: fetching ?? this.fetching,
        pending: pending ?? this.pending,
      );

  /// [showing] as a short label.
  String get label => format(showing);

  /// `v<n>`, where n is the sum of the buildings' `globalAnnotationVersion`s:
  /// one number that rises whenever any building's data is republished.
  /// `v—` when the version is unknown.
  static String format(String? version) {
    if (version == null || version.isEmpty) return 'v—';
    var sum = 0;
    for (final entry in version.split(',')) {
      sum += int.tryParse(entry.substring(entry.lastIndexOf(':') + 1)) ?? 0;
    }
    return 'v$sum';
  }
}
