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

  /// The group named [name], or null when [name] is not a group.
  ///
  /// Used by the config loader to tell a group key (`rooms`) apart from a
  /// style-layer id (`normal-polygons-layer`) — the two share one `layers:`
  /// block and are distinguished only by whether this returns null.
  static MapLayer? byName(String name) {
    for (final group in values) {
      if (group.name == name) return group;
    }
    return null;
  }
}

/// The style-layer ids this package's MapLibre provider creates.
///
/// Config files may key on any of these directly, alongside the [MapLayer]
/// group names, when a single layer needs settings the whole group should not
/// get. Mirrors `_layerGroups` in `mapLibre_map_provider.dart`; it exists so the
/// loader can warn on a misspelled key rather than silently ignoring it, and an
/// id missing from here is still applied — it is a warning list, not a gate.
abstract final class MapStyleLayers {
  static const String collisionDotMarkers = 'collision-dot-markers-layer';
  static const String normalTextMarkers = 'normalText-markers-layer';
  static const String normalIconMarkersWithSectionId =
      'normalIcon-markers-layer-withSectionId';
  static const String normalIconMarkersWithoutSectionId =
      'normalIcon-markers-layer-withoutSectionId';
  static const String customRenderingMarkers =
      'customRendering-markers-layer';
  static const String overlapOverrideMarkers =
      'overlap-override-markers-layer';
  static const String fixedMarkers = 'fixed-markers-layer';
  static const String priorityMarkers = 'priority-marker-layer';
  static const String sectionMarkers = 'section-markers-layer';
  static const String subSectionMarkers = 'subSection-markers-layer';
  static const String patchAboveMarkers = 'patch-above-markers-layer';

  static const String normalPolygons = 'normal-polygons-layer';
  static const String patternPolygons = 'pattern-polygons-layer';
  static const String extrudedPolygon = 'extruded-polygon-layer';
  static const String sectionPolygon = 'section-polygon-layer';
  static const String subSectionPolygon = 'subSection-polygon-layer';
  static const String patchBelowPolygon = 'patch-below-polygon-layer';
  static const String patchAbovePolygon = 'patch-above-polygon-layer';

  static const String pathSolidPolyline = 'path-solid-polyline-layer';
  static const String pathSolidOutlinePolyline =
      'path-solid-outline-polyline-layer';
  static const String pathDashedPolyline = 'path-dashed-polyline-layer';
  static const String greyOverlayPolyline = 'grey-overlay-polyline-layer';
  static const String normalPolyline = 'normal-polyline-layer';

  static const String furnitureFill = 'furniture-fill-layer';
  static const String furniture = 'furniture-layer';

  static const String rotationMarker = 'rotation-marker-layer';
  static const String normalCircle = 'normal-circle-layer';

  static const String selectedMarker = 'selected-marker-layer';
  static const String selectedPlainPolygon = 'selected-plain-polygon-layer';
  static const String selectedPlainPolygonStroke =
      'selected-plain-polygon-stroke-layer';
  static const String selectedExtrudedPolygon =
      'selected-extruded-polygon-layer';

  /// The basemap raster. Outside the [MapLayer] taxonomy — greyscale reaches it
  /// through `raster-saturation`, and a config file can now address it by id.
  static const String baseMapRaster = 'osm-tiles-layer';

  static const Set<String> known = {
    collisionDotMarkers,
    normalTextMarkers,
    normalIconMarkersWithSectionId,
    normalIconMarkersWithoutSectionId,
    customRenderingMarkers,
    overlapOverrideMarkers,
    fixedMarkers,
    priorityMarkers,
    sectionMarkers,
    subSectionMarkers,
    patchAboveMarkers,
    normalPolygons,
    patternPolygons,
    extrudedPolygon,
    sectionPolygon,
    subSectionPolygon,
    patchBelowPolygon,
    patchAbovePolygon,
    pathSolidPolyline,
    pathSolidOutlinePolyline,
    pathDashedPolyline,
    greyOverlayPolyline,
    normalPolyline,
    furnitureFill,
    furniture,
    rotationMarker,
    normalCircle,
    selectedMarker,
    selectedPlainPolygon,
    selectedPlainPolygonStroke,
    selectedExtrudedPolygon,
    baseMapRaster,
  };
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

  /// Raw MapLibre style properties written over whatever the renderer built for
  /// this layer — `fill-color`, `text-size`, `line-width`, `icon-offset`, any
  /// paint or layout key the layer's type accepts.
  ///
  /// This is the escape hatch [visible]/[opacity]/[tappable] are not: those
  /// three are semantic and cross-cutting (opacity resolves into *every* opacity
  /// expression a layer has, symbol layers included), while this is a literal
  /// key/value overwrite of the renderer's own property set. Keys not named here
  /// keep the renderer's value, which is what makes a config file able to say
  /// only `fill-color: red` and inherit the other nineteen properties.
  ///
  /// Keys may be written in the style-spec's kebab-case (`fill-color`) or in
  /// Dart camelCase (`fillColor`); the provider normalises before applying, so
  /// the two are interchangeable. Values are passed to MapLibre untouched, so
  /// anything the style spec accepts works — a literal (`0.7`, `"red"`,
  /// `"#ff0000"`) or a full expression (`["get", "fillColor"]`).
  ///
  /// Two keys are deliberately not honoured here:
  /// * `visibility` — [visible] wins, so one field owns whether a layer draws.
  /// * a group hidden by the renderer for coherence (entry pins in 3D) stays
  ///   hidden; a property override cannot force it back.
  final Map<String, Object?> properties;

  const MapLayerState({
    this.visible,
    this.opacity,
    this.tappable,
    this.properties = const {},
  });

  /// [key] in the style spec's kebab-case, whatever case it was written in.
  ///
  /// `fillColor` → `fill-color`, `iconHaloWidth` → `icon-halo-width`. Already
  /// kebab-case keys pass through untouched, so this is safe to apply twice.
  static String normalizeKey(String key) => key.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (m) => '-${m[0]!.toLowerCase()}',
      );

  /// [properties] with every key run through [normalizeKey].
  static Map<String, Object?> normalizeKeys(Map<String, Object?> properties) {
    if (properties.isEmpty) return const {};
    return {
      for (final entry in properties.entries)
        normalizeKey(entry.key): entry.value,
    };
  }

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
  /// Pass [clearProperties] to drop every property override, for the same
  /// reason [clearOpacity] exists — an empty map means "add nothing", not
  /// "remove what is there".
  MapLayerState copyWith({
    bool? visible,
    double? opacity,
    bool? tappable,
    Map<String, Object?>? properties,
    bool clearOpacity = false,
    bool clearProperties = false,
  }) {
    return MapLayerState(
      visible: visible ?? this.visible,
      opacity: clearOpacity ? null : (opacity ?? this.opacity),
      tappable: tappable ?? this.tappable,
      properties: clearProperties
          ? const {}
          : (properties == null
              ? this.properties
              : {...this.properties, ...properties}),
    );
  }

  /// Field-wise override: fields specified on [other] win, the rest are kept.
  ///
  /// [properties] merges per key rather than replacing wholesale — that is what
  /// lets a family set `fill-opacity` and a single layer add `fill-color`
  /// without either erasing the other.
  MapLayerState overrideWith(MapLayerState other) {
    return MapLayerState(
      visible: other.visible ?? visible,
      opacity: other.opacity ?? opacity,
      tappable: other.tappable ?? tappable,
      properties: properties.isEmpty
          ? other.properties
          : (other.properties.isEmpty
              ? properties
              : {...properties, ...other.properties}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapLayerState &&
          other.visible == visible &&
          other.opacity == opacity &&
          other.tappable == tappable &&
          mapEquals(other.properties, properties);

  @override
  int get hashCode => Object.hash(
        visible,
        opacity,
        tappable,
        Object.hashAllUnordered(
            properties.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'MapLayerState(visible: $visible, opacity: $opacity, '
      'tappable: $tappable, properties: $properties)';
}

/// An immutable description of which map content is drawn, how strongly, and
/// what responds to taps.
///
/// A policy is absolute rather than a delta — it fully describes the desired
/// state, and any group it does not mention keeps the defaults.
///
/// Content is addressed at two levels, and both live in one policy:
///
/// * by **[MapLayer] group** — [states] — the semantic taxonomy (family →
///   member), for "dim every polygon" or "no marker responds to taps";
/// * by **style-layer id** — [layers] — the exact layers in [MapStyleLayers],
///   for "`normal-polygons-layer` is red at 0.7 opacity" without touching the
///   patterned rooms drawn beside it.
///
/// A layer resolves through the whole chain, most specific last:
/// **defaults → family → member → layer id**. Every field is nullable and every
/// unset field falls to the previous link, so a config that names one property
/// changes exactly that property and inherits the rest.
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
///
/// // Restyle one style layer, inheriting everything else it draws with.
/// controller.setStyleLayer(
///   MapStyleLayers.normalPolygons,
///   properties: {'fill-color': 'red', 'fill-opacity': 0.7},
/// );
/// ```
@immutable
class MapLayerPolicy {
  /// Settings keyed by semantic group. Applied to every style layer in the
  /// group, family first and member second.
  final Map<MapLayer, MapLayerState> states;

  /// Settings keyed by exact style-layer id, applied last and so winning over
  /// anything [states] said about the group that layer belongs to.
  ///
  /// A layer id here need not belong to the taxonomy at all — `osm-tiles-layer`
  /// is reachable this way and by no other route.
  final Map<String, MapLayerState> layers;

  const MapLayerPolicy([this.states = const {}, this.layers = const {}]);

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

  bool get isEmpty => states.isEmpty && layers.isEmpty;

  /// This policy with [group] set to [state], replacing any existing entry.
  MapLayerPolicy withGroup(MapLayer group, MapLayerState state) =>
      MapLayerPolicy({...states, group: state}, layers);

  /// This policy with [group]'s entry removed.
  MapLayerPolicy withoutGroup(MapLayer group) =>
      MapLayerPolicy({...states}..remove(group), layers);

  /// This policy with the style layer [layerId] set to [state], replacing any
  /// existing entry. See [MapStyleLayers] for the ids.
  MapLayerPolicy withLayer(String layerId, MapLayerState state) =>
      MapLayerPolicy(states, {...layers, layerId: state});

  /// This policy with [layerId]'s entry removed.
  MapLayerPolicy withoutLayer(String layerId) =>
      MapLayerPolicy(states, {...layers}..remove(layerId));

  /// Field-wise merge; entries in [patch] win over this policy's.
  MapLayerPolicy merge(MapLayerPolicy patch) {
    final mergedStates = {...states};
    patch.states.forEach((group, state) {
      final existing = mergedStates[group];
      mergedStates[group] =
          existing == null ? state : existing.overrideWith(state);
    });
    final mergedLayers = {...layers};
    patch.layers.forEach((layerId, state) {
      final existing = mergedLayers[layerId];
      mergedLayers[layerId] =
          existing == null ? state : existing.overrideWith(state);
    });
    return MapLayerPolicy(mergedStates, mergedLayers);
  }

  /// The fully resolved state for [group]: its own entry layered over its
  /// family's, over the defaults.
  ///
  /// [MapLayerState.visible] and [MapLayerState.tappable] are never null on the
  /// result; [MapLayerState.opacity] is null when no override applies.
  ///
  /// This is the GROUP-level answer and deliberately ignores [layers] — a
  /// per-layer entry cannot speak for the whole group. Renderers resolving one
  /// concrete style layer want [resolveLayer].
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

  /// The fully resolved state for one style layer: **defaults → family →
  /// member → layer id**, each link overriding only the fields it specifies.
  ///
  /// [group] is the [MapLayer] that [layerId] belongs to, or null for a layer
  /// outside the taxonomy (the basemap raster) — such a layer is still
  /// configurable, just only by its own id.
  MapLayerState resolveLayer(String layerId, MapLayer? group) {
    var resolved = group == null ? MapLayerState.defaults : resolve(group);
    final own = layers[layerId];
    if (own != null) resolved = resolved.overrideWith(own);
    return resolved;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MapLayerPolicy &&
          mapEquals(other.states, states) &&
          mapEquals(other.layers, layers);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(
            states.entries.map((e) => Object.hash(e.key, e.value))),
        Object.hashAllUnordered(
            layers.entries.map((e) => Object.hash(e.key, e.value))),
      );

  @override
  String toString() => 'MapLayerPolicy(states: $states, layers: $layers)';
}
