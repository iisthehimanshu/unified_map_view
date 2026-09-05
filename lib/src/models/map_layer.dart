import 'package:flutter/foundation.dart';

/// A semantic group of map content.
///
/// Groups are named after the *element* they draw, never after the renderer's
/// layer ids — those are an implementation detail and are deliberately not
/// reachable from host code.
///
/// Groups form two tiers:
///
/// * a **family** — [markers], [polygons], [route], [furniture],
///   [userLocation], [selection]
/// * its **members** — e.g. [landmarkMarkers] and [rooms]
///
/// Setting a family applies to all of its members; a member set afterwards
/// overrides the family for that member only, and only for the fields it
/// actually specifies. So `polygons: opacity 0.4` combined with
/// `rooms: visible false` leaves rooms hidden and every other polygon group at
/// opacity 0.4.
///
/// [furniture], [userLocation] and [selection] are families with no members —
/// they are already a single element.
enum MapLayer {
  // ── families ──────────────────────────────────────────────────────────────
  /// Every marker and label except the user's own position and the current
  /// selection, both of which are deliberately separate so that hiding markers
  /// cannot blank the user puck mid-navigation or kill tap feedback.
  markers,

  /// Every polygon: rooms, sections, sub-sections, the venue boundary and 3D
  /// extrusions.
  polygons,

  /// Navigation route lines, the travelled-path overlay, and generic polylines
  /// the host drew itself.
  route,

  /// 3D furniture and its flat 2D footprint.
  furniture,

  /// The user position puck and its accuracy circle.
  userLocation,

  /// The highlight drawn on the currently selected landmark. Spans both a
  /// marker and polygon layers, which is why it is its own family.
  selection,

  // ── members of [markers] ──────────────────────────────────────────────────
  /// Ordinary landmark markers: text labels, icons, custom-rendered composites,
  /// and the small dots they collapse to when they lose a collision.
  ///
  /// Also covers markers force-pinned through
  /// `UnifiedMapController.setMarkersAllowOverlap` — hiding this group hides
  /// those too.
  landmarkMarkers,

  /// Bearing-carrying pins, such as building entries.
  ///
  /// These are already hidden by the renderer in 3D; a policy cannot force them
  /// back on.
  entryMarkers,

  /// Source and destination pins.
  priorityMarkers,

  /// Section name labels.
  sectionLabels,

  /// Sub-section name labels.
  subSectionLabels,

  /// The venue name label shown when zoomed out.
  venueLabel,

  // ── members of [polygons] ─────────────────────────────────────────────────
  /// Room and unit polygons, including textured ones.
  ///
  /// **In 3D this group may draw nothing.** Height is only attached to features
  /// while the map is in immersive mode, and a polygon that has a height is
  /// drawn by [extrusions] instead. To hide rooms regardless of 2D/3D, set the
  /// [polygons] family rather than this member.
  rooms,

  /// Section polygons.
  sections,

  /// Sub-section polygons.
  subSections,

  /// The venue footprint / campus boundary.
  venueBoundary,

  /// Extruded 3D building volumes and walls. See the note on [rooms].
  extrusions,

  // ── members of [route] ────────────────────────────────────────────────────
  /// The navigation path itself — solid, its outline halo, and dashed segments.
  routeLine,

  /// The greyed-out overlay drawn over the already-travelled part of the path.
  routeTraveled,

  /// Generic polylines the host added that are not a navigation route.
  polylines;

  /// The family this group belongs to, or `null` when it is itself a family.
  MapLayer? get family {
    switch (this) {
      case landmarkMarkers:
      case entryMarkers:
      case priorityMarkers:
      case sectionLabels:
      case subSectionLabels:
      case venueLabel:
        return markers;
      case rooms:
      case sections:
      case subSections:
      case venueBoundary:
      case extrusions:
        return polygons;
      case routeLine:
      case routeTraveled:
      case polylines:
        return route;
      default:
        return null;
    }
  }

  /// The members of this family, or `const []` when this group is a member or a
  /// family that has none.
  List<MapLayer> get members {
    switch (this) {
      case markers:
        return const [
          landmarkMarkers,
          entryMarkers,
          priorityMarkers,
          sectionLabels,
          subSectionLabels,
          venueLabel,
        ];
      case polygons:
        return const [rooms, sections, subSections, venueBoundary, extrusions];
      case route:
        return const [routeLine, routeTraveled, polylines];
      default:
        return const [];
    }
  }

  bool get isFamily => family == null;

  /// Every leaf group under this one. A group with no members is its own leaf,
  /// so this never returns an empty list.
  List<MapLayer> get leaves => members.isEmpty ? [this] : members;

  /// Every leaf group across the whole taxonomy.
  static List<MapLayer> get allLeaves =>
      values.where((g) => g.members.isEmpty).toList(growable: false);
}

/// Visibility, opacity and tappability for one [MapLayer].
///
/// Every field is nullable, and `null` means *not specified*: it falls through
/// to the group's family, and then to the defaults (visible, the renderer's own
/// opacity, tappable).
@immutable
class MapLayerState {
  /// When false the group's layers are hidden outright.
  ///
  /// This is not the same as `opacity: 0`. A marker layer at zero opacity still
  /// takes part in collision and still suppresses neighbouring markers, and is
  /// still returned by hit testing. Use [visible] to actually remove content.
  final bool? visible;

  /// Absolute opacity override, 0.0–1.0.
  ///
  /// When set, every layer in the group is given this flat value, replacing
  /// per-feature opacity and any zoom fade ramp the layer would otherwise use.
  /// When null the group keeps the renderer's own expression untouched.
  final double? opacity;

  /// When false, taps on this group are fully inert: no selection highlight, no
  /// camera movement, and no `onPolygonTap` / `onMarkerTap` callback.
  ///
  /// Selecting a landmark programmatically through
  /// `UnifiedMapController.selectLocation` is unaffected — search results and
  /// deep links keep working with taps switched off.
  final bool? tappable;

  const MapLayerState({this.visible, this.opacity, this.tappable});

  /// Hidden, with tap behaviour left unspecified.
  static const MapLayerState hidden = MapLayerState(visible: false);

  /// Visible but inert.
  static const MapLayerState untappable = MapLayerState(tappable: false);

  /// What a group resolves to when nothing specifies otherwise.
  static const MapLayerState defaults =
      MapLayerState(visible: true, tappable: true);

  /// Pass `clearOpacity: true` to drop an override and return the group to the
  /// renderer's own opacity — passing `opacity: null` cannot express that,
  /// since null already means "unchanged".
  MapLayerState copyWith({
    bool? visible,
    double? opacity,
    bool? tappable,
    bool clearOpacity = false,
  }) {
    return MapLayerState(
      visible: visible ?? this.visible,
      opacity: clearOpacity ? null : (opacity ?? this.opacity),
      tappable: tappable ?? this.tappable,
    );
  }

  /// Field-wise override: fields specified on [other] win, the rest are kept.
  MapLayerState overrideWith(MapLayerState other) {
    return MapLayerState(
      visible: other.visible ?? visible,
      opacity: other.opacity ?? opacity,
      tappable: other.tappable ?? tappable,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapLayerState &&
          other.visible == visible &&
          other.opacity == opacity &&
          other.tappable == tappable;

  @override
  int get hashCode => Object.hash(visible, opacity, tappable);

  @override
  String toString() =>
      'MapLayerState(visible: $visible, opacity: $opacity, tappable: $tappable)';
}

/// An immutable description of which map content is drawn, how strongly, and
/// what responds to taps.
///
/// A policy is absolute rather than a delta — it fully describes the desired
/// state, and any group it does not mention keeps the defaults.
///
/// ```dart
/// // Markers off, polygons visible and tappable.
/// controller.setLayers(MapLayerPolicy.polygonsOnly);
///
/// // Same, but polygons no longer respond to taps.
/// controller.setLayers(MapLayerPolicy.polygonsOnlyNoTap);
///
/// // Dim one member.
/// controller.setLayer(MapLayer.subSections, opacity: 0.3);
/// ```
@immutable
class MapLayerPolicy {
  final Map<MapLayer, MapLayerState> states;

  const MapLayerPolicy([this.states = const {}]);

  /// Everything visible, at the renderer's own opacity, everything tappable.
  static const MapLayerPolicy all = MapLayerPolicy();

  /// Polygons only. Markers, route and furniture are hidden.
  ///
  /// [MapLayer.userLocation] and [MapLayer.selection] are deliberately left
  /// alone, so the user puck still shows and tapping a room still highlights it.
  static const MapLayerPolicy polygonsOnly = MapLayerPolicy({
    MapLayer.markers: MapLayerState.hidden,
    MapLayer.route: MapLayerState.hidden,
    MapLayer.furniture: MapLayerState.hidden,
  });

  /// [polygonsOnly], plus the polygons that remain are fully inert to taps.
  static const MapLayerPolicy polygonsOnlyNoTap = MapLayerPolicy({
    MapLayer.markers: MapLayerState.hidden,
    MapLayer.route: MapLayerState.hidden,
    MapLayer.furniture: MapLayerState.hidden,
    MapLayer.polygons: MapLayerState.untappable,
    MapLayer.selection: MapLayerState.untappable,
  });

  /// Markers only. Polygons, route and furniture are hidden.
  static const MapLayerPolicy markersOnly = MapLayerPolicy({
    MapLayer.polygons: MapLayerState.hidden,
    MapLayer.route: MapLayerState.hidden,
    MapLayer.furniture: MapLayerState.hidden,
  });

  bool get isEmpty => states.isEmpty;

  /// This policy with [group] set to [state], replacing any existing entry.
  MapLayerPolicy withGroup(MapLayer group, MapLayerState state) =>
      MapLayerPolicy({...states, group: state});

  /// This policy with [group]'s entry removed.
  MapLayerPolicy withoutGroup(MapLayer group) =>
      MapLayerPolicy({...states}..remove(group));

  /// Field-wise merge; entries in [patch] win over this policy's.
  MapLayerPolicy merge(MapLayerPolicy patch) {
    final merged = {...states};
    patch.states.forEach((group, state) {
      final existing = merged[group];
      merged[group] = existing == null ? state : existing.overrideWith(state);
    });
    return MapLayerPolicy(merged);
  }

  /// The fully resolved state for [group]: its own entry layered over its
  /// family's, over the defaults.
  ///
  /// [MapLayerState.visible] and [MapLayerState.tappable] are never null on the
  /// result; [MapLayerState.opacity] is null when no override applies.
  MapLayerState resolve(MapLayer group) {
    var resolved = MapLayerState.defaults;
    final family = group.family;
    if (family != null && states[family] != null) {
      resolved = resolved.overrideWith(states[family]!);
    }
    final own = states[group];
    if (own != null) resolved = resolved.overrideWith(own);
    return resolved;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapLayerPolicy && mapEquals(other.states, states);

  @override
  int get hashCode => Object.hashAllUnordered(
      states.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'MapLayerPolicy($states)';
}
