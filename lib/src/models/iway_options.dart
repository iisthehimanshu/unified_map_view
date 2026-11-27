import 'package:flutter/foundation.dart';

/// How room names are drawn by the iway_indoor_map provider.
enum IwayRoomLabels {
  /// Lying flat on each room, turned along it and sized to fit inside it
  /// (iway_indoor_map's room-label renderer, as in its IwayplusVenue).
  flat,

  /// The upright point labels the MapLibre provider draws.
  upright,
}

/// The light on the 3D rooms (iway_indoor_map `IwayMapController.setLight`).
@immutable
class IwayLight {
  /// `'map'` keeps the light fixed on the map; `'viewport'` keeps it fixed on
  /// screen as the map turns.
  final String? anchor;

  /// `[radius, azimuth, polar]`: azimuth in degrees clockwise from north
  /// (`map`) or the top of the screen (`viewport`); polar in degrees from
  /// straight up (0) to the horizon (90). A larger radius lights walls more.
  final List<double>? position;

  /// CSS colour, e.g. `'#ffffff'`.
  final String? color;

  /// 0..1; higher makes lit and shaded sides differ more.
  final double? intensity;

  const IwayLight({this.anchor, this.position, this.color, this.intensity});

  bool get isEmpty =>
      anchor == null && position == null && color == null && intensity == null;
}

/// Gesture switches for the iway map. Null fields keep the current setting.
@immutable
class IwayGestures {
  final bool? rotate;
  final bool? tilt;
  final bool? zoom;
  final bool? scroll;
  final bool? doubleTapZoom;

  const IwayGestures(
      {this.rotate, this.tilt, this.zoom, this.scroll, this.doubleTapZoom});
}

/// Options for features of the iway_indoor_map package, from the `iway:`
/// block of a map config file (see [MapStyleConfig.iway]).
///
/// Only the iway provider reads these; the others ignore them. Every field is
/// optional — a field the file leaves out keeps the provider's default.
///
/// ```yaml
/// iway:
///   roomLabels: flat            # flat | upright
///   patchLabels: flat           # flat | upright (section patch names)
///   light:
///     anchor: map               # map | viewport
///     position: [1.5, 210, 30]  # radius, azimuth, polar
///     color: "#ffffff"
///     intensity: 0.5
///   view3D:
///     tilt: 45                  # camera tilt when switching to 3D
///   zoom:
///     min: 0
///     max: 25.5
///   gestures:
///     rotate: true
///     tilt: true
///     zoom: true
///     scroll: true
///     doubleTapZoom: true
/// ```
///
/// Fine-tuning of the flat room labels goes through the per-layer `layers:`
/// block on `room-name-flat-layer` (text-room-fill, text-room-max-height,
/// text-room-keep-inside, text-room-hide-behind-walls, text-room-turn,
/// text-keep-upright, text-size, text-color, ...).
@immutable
class IwayOptions {
  final IwayRoomLabels? roomLabels;

  /// How section patch names are drawn, independently of [roomLabels].
  final IwayRoomLabels? patchLabels;
  final IwayLight? light;

  /// Camera tilt in degrees when switching to 3D (0..60).
  final double? tilt3D;

  final double? minZoom;
  final double? maxZoom;
  final IwayGestures? gestures;

  const IwayOptions({
    this.roomLabels,
    this.patchLabels,
    this.light,
    this.tilt3D,
    this.minZoom,
    this.maxZoom,
    this.gestures,
  });

  /// Parses an `iway:` block. Problems are appended to [warnings] (as
  /// `iway.key: ...`) rather than thrown, like the rest of the config file.
  factory IwayOptions.fromMap(Map<String, Object?> map, List<String> warnings) {
    double? number(Object? v, String key) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      final parsed = double.tryParse(v.toString());
      if (parsed == null) warnings.add('iway.$key: expected a number, got "$v"');
      return parsed;
    }

    bool? flag(Object? v, String key) {
      if (v == null) return null;
      if (v is bool) return v;
      warnings.add('iway.$key: expected true/false, got "$v"');
      return null;
    }

    Map<String, Object?>? section(String key) {
      final v = map[key];
      if (v == null) return null;
      if (v is Map) return v.cast<String, Object?>();
      warnings.add('iway.$key: expected a mapping, got "$v"');
      return null;
    }

    void unknownKeys(Map<String, Object?> m, Set<String> known, String prefix) {
      for (final k in m.keys) {
        if (!known.contains(k)) warnings.add('$prefix$k: unknown key — ignored');
      }
    }

    unknownKeys(map, const {'roomLabels', 'patchLabels', 'light', 'view3D', 'zoom', 'gestures'}, 'iway.');

    IwayRoomLabels? labels(String key) {
      final v = map[key];
      if (v == null) return null;
      final parsed = IwayRoomLabels.values
          .where((e) => e.name == v.toString().trim())
          .firstOrNull;
      if (parsed == null) {
        warnings.add('iway.$key: expected flat or upright, got "$v"');
      }
      return parsed;
    }

    final roomLabels = labels('roomLabels');
    final patchLabels = labels('patchLabels');

    IwayLight? light;
    final l = section('light');
    if (l != null) {
      unknownKeys(l, const {'anchor', 'position', 'color', 'intensity'}, 'iway.light.');
      final anchor = l['anchor']?.toString();
      if (anchor != null && anchor != 'map' && anchor != 'viewport') {
        warnings.add('iway.light.anchor: expected map or viewport, got "$anchor"');
      }
      List<double>? position;
      final p = l['position'];
      if (p != null) {
        if (p is List && p.length == 3) {
          final values = [for (var i = 0; i < 3; i++) number(p[i], 'light.position')];
          if (values.every((v) => v != null)) position = values.cast<double>();
        } else {
          warnings.add('iway.light.position: expected [radius, azimuth, polar], got "$p"');
        }
      }
      light = IwayLight(
        anchor: anchor == 'map' || anchor == 'viewport' ? anchor : null,
        position: position,
        color: l['color']?.toString(),
        intensity: number(l['intensity'], 'light.intensity')?.clamp(0.0, 1.0),
      );
      if (light.isEmpty) light = null;
    }

    double? tilt3D;
    final v3 = section('view3D');
    if (v3 != null) {
      unknownKeys(v3, const {'tilt'}, 'iway.view3D.');
      tilt3D = number(v3['tilt'], 'view3D.tilt')?.clamp(0.0, 60.0);
    }

    double? minZoom, maxZoom;
    final z = section('zoom');
    if (z != null) {
      unknownKeys(z, const {'min', 'max'}, 'iway.zoom.');
      minZoom = number(z['min'], 'zoom.min');
      maxZoom = number(z['max'], 'zoom.max');
      if (minZoom != null && maxZoom != null && minZoom > maxZoom) {
        warnings.add('iway.zoom: min ($minZoom) is above max ($maxZoom) — ignored');
        minZoom = maxZoom = null;
      }
    }

    IwayGestures? gestures;
    final g = section('gestures');
    if (g != null) {
      unknownKeys(g, const {'rotate', 'tilt', 'zoom', 'scroll', 'doubleTapZoom'}, 'iway.gestures.');
      gestures = IwayGestures(
        rotate: flag(g['rotate'], 'gestures.rotate'),
        tilt: flag(g['tilt'], 'gestures.tilt'),
        zoom: flag(g['zoom'], 'gestures.zoom'),
        scroll: flag(g['scroll'], 'gestures.scroll'),
        doubleTapZoom: flag(g['doubleTapZoom'], 'gestures.doubleTapZoom'),
      );
    }

    return IwayOptions(
      roomLabels: roomLabels,
      patchLabels: patchLabels,
      light: light,
      tilt3D: tilt3D,
      minZoom: minZoom,
      maxZoom: maxZoom,
      gestures: gestures,
    );
  }
}
