import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:unified_map_view/src/utils/perf_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:unified_map_view/src/config.dart';
import 'package:unified_map_view/src/database/cache/cache_controller.dart';
import 'package:unified_map_view/src/models/CameraBound.dart';
import 'package:unified_map_view/src/models/camera_position.dart';
import 'package:unified_map_view/src/models/selectedLocation.dart';
import '../utils/UnifiedMarkerCreator.dart';
import '../utils/geoJson/geoJsonUtils.dart';
import '../utils/geoJson/predefined_markers.dart';
import '../utils/renderingUtilities.dart';
import '../enums/Theme.dart';
import '../VenueManager/VenueData.dart';
import 'base_map_provider.dart';
import '../models/map_config.dart';
import '../models/map_location.dart';
import '../models/geojson_models.dart';
import '../models/map_layer.dart';
import 'package:flutter_compass/flutter_compass.dart';

import '../heading/heading_source.dart';
import 'package:http/http.dart' as http;
import '../utils/LandmarkAssetType.dart';
import '../models/marker_type_info.dart';

/// Substitutes a host's absolute opacity override for the value a layer would
/// natively use. Returns [base] unchanged when no override applies.
typedef _OpacityResolver = dynamic Function(dynamic base);

/// Everything a custom-rendering marker needs registered with the map style,
/// kept so a style reload — which wipes every addImage() call — can re-upload
/// without re-fetching the source photo or re-entering the bake path.
class _BakedMarkerIcon {
  /// Full composite, with the label baked in. Registered under the marker id.
  final Uint8List main;

  /// Image id the zoomed-out (label-less) variant is registered under. Shared
  /// between every marker whose photo and pill geometry match; equal to the
  /// marker id when the label is hidden, since both bakes are then identical.
  final String smallIconId;

  /// Bytes for [smallIconId]. Null when it aliases [main].
  final Uint8List? small;

  /// Museum POI highlight variant, registered under '<id>-selected'.
  final Uint8List? selected;

  final Offset anchor;

  const _BakedMarkerIcon({
    required this.main,
    required this.smallIconId,
    required this.anchor,
    this.small,
    this.selected,
  });
}

/// MapLibre GL implementation of BaseMapProvider
/// Supports MapLibre — an open-source vector map rendering engine
/// How a marker reacts when it is tapped / selected.
///
/// [none] is the default — the marker just gets highlighted, with no motion.
/// Set [MaplibreMapProvider.markerSelectionAnimationStyle] to one of the other
/// values when you actually want the tap animation.
enum MarkerSelectionAnimationStyle { none, growShrink, shakeVertical }
class MaplibreMapProvider extends BaseMapProvider {
  MapLibreMapController? _controller;
  final List<GeoJsonMarker> _symbols = [];
  final List<GeoJsonCircle> _circles = [];
  final List<GeoJsonMarker> _rotatingSymbols = [];
  final List<GeoJsonPolygon> _polygons = [];
  final List<GeoJsonPolyline> _lines = [];

  /// Raw GeoJSON point-feature maps whose properties carry a "3dRef"
  /// part list — rendered as extruded 3D furniture. Kept so the source
  /// can be re-pushed after a style reload.
  final List<Map<String, dynamic>> _furnitureItems = [];

  late MapConfig _config;

  SelectedLocation? selectedLocation;

  final String _clusterSourceId = 'markers-source';
  final String _normalTextMarkerLayerId = 'normalText-markers-layer';
  final String _normalIconMarkerLayerId = 'normalIcon-markers-layer';
  final String _customRenderingMarkerLayerId = 'customRendering-markers-layer';
  final String _fixedMarkerLayerId = 'fixed-markers-layer';
  final String _priorityMarkerLayerId = 'priority-marker-layer';
  final String _selectedMarkerLayerId = 'selected-marker-layer';
  final String _animatedMarkerSourceId = 'animated-marker-source';
  final String _animatedMarkerLayerId = 'animated-marker-layer';
  final String _sectionMarkerLayerId = 'section-markers-layer';
  final String _patchAboveMarkerLayerId = 'patch-above-markers-layer';
  final String _subSectionMarkerLayerId = 'subSection-markers-layer';
  final String _overlapOverrideMarkerLayerId = 'overlap-override-markers-layer';

  /// Collision-fallback "dot" layer. When a normal marker loses a collision it
  /// would normally be hidden; instead we render a small dot at its location.
  /// See [_collisionBase] / [enableMarkerLayers] for the ordering that makes a
  /// loser fall back to a dot, and a dot-vs-dot loser hide entirely.
  final String _dotMarkerLayerId = 'collision-dot-markers-layer';

  /// Map image id + asset for the collision-fallback dot.
  static const String _kDotImageId = '__collision_dot__';
  static const String _kDotAssetPath =
      'packages/unified_map_view/assets/markers/room_dot.png';

  /// Map image id for the path direction arrow.
  static const String _kPathArrowImageId = '__path_arrow__'; 
  static const String _kPathBigArrowImageId = '__path_big_arrow__';

  /// Marker ids for which icon/text overlap is temporarily forced on. These
  /// markers are routed into a dedicated always-visible layer (and excluded
  /// from the collision-subject normal layers) so they are never hidden by
  /// collision, until cleared.
  final Set<String> _overlapOverrideIds = {};

  /// Landmark types the host wants drawn, normalised, or null for "draw
  /// everything".
  ///
  /// Holds raw GeoJSON type strings rather than [LandmarkAssetType] because the
  /// vocabulary is per-venue: the enum is an *icon* choice, it collapses
  /// distinct types onto one asset (`entry`/`entrance`/`exit` all become
  /// [LandmarkAssetType.mainEntry]) and resolves to null for anything it has no
  /// case for, so it can neither address every type a venue has nor tell two of
  /// them apart.
  ///
  /// Applied where the cluster source is built rather than as a per-layer
  /// filter: a filtered-out marker is then absent from the source entirely, so
  /// it takes no part in MapLibre's collision pass. A layer filter would leave
  /// it competing for space and suppressing neighbours it is no longer drawn
  /// next to — and it would have to be repeated across all ten marker layers.
  Set<String>? _markerTypeFilter;

  final String _rotationSourceId = 'rotation-markers-source';
  final String _rotationMarkerLayerId = 'rotation-marker-layer';

  final String _circleSourceId = 'circle-source';
  final String _normalCircleLayerId = 'normal-circle-layer';

  final String _polygonSourceId = 'polygons-source';
  final String _normalPolygonLayerId = 'normal-polygons-layer';
  final String _patternPolygonLayerId = 'pattern-polygons-layer';
  final String _selectedPlainPolygonLayerId = 'selected-plain-polygon-layer';
  final String _selectedPlainPolygonStrokeLayerId = 'selected-plain-polygon-stroke-layer';
  final String _selectedExtrudedPolygonLayerId = 'selected-extruded-polygon-layer';
  final String _patchBelowPolygonLayerId = 'patch-below-polygon-layer';
  final String _patchAbovePolygonLayerId = 'patch-above-polygon-layer';
  final String _sectionPolygonLayerId = 'section-polygon-layer';
  final String _subSectionPolygonLayerId = 'subSection-polygon-layer';
  final String _extrudedPolygonLayerId = 'extruded-polygon-layer';

  /// The basemap raster layer declared in [osmRasterStyle]. Named here so
  /// greyscale can set raster-saturation on it.
  final String _baseMapRasterLayerId = 'osm-tiles-layer';
  final String _furnitureSourceId = 'furniture-source';

  /// 3D extruded furniture (shown in immersive/3D mode).
  final String _furnitureLayerId = 'furniture-layer';

  /// Flat footprint of the same furniture (shown in 2D mode instead of
  /// the extrusion).
  final String _furnitureFillLayerId = 'furniture-fill-layer';

  /// Furniture is fine detail, so it only appears once zoomed in past the
  /// section/sub-section view. Zoom out to where sections show and it hides.
  static const double _furnitureMinZoom = 17.5;

  final String _polylineSourceId = 'polylines-source';
  final String _pathCornerSourceId = 'path-corners-source';
  final String _pathBigArrowLayerId = 'path-big-arrow-layer';
  final String _pathShineSourceId = 'path-shine-source';
  final String _pathShineLayerId = 'path-shine-layer';
  static const String _kShineImageId = '__path_shine__';
  Timer? _pathShineTimer;
  double _pathShineProgress = 0.0;
  List<Map<String, dynamic>> _allCornerFeatures = [];

  /// Wall-clock time of the last `onCameraMove` from the native map. Used to
  /// pause cosmetic per-frame source rewrites (the travelling path "shine")
  /// while the camera is actually moving — those rewrites force a native
  /// GeoJSON re-parse + relayout on the render thread and were competing with
  /// the camera during guided navigation, which is when it pans continuously.
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _cameraMovingNow =>
      DateTime.now().difference(_lastCameraMove).inMilliseconds < 180;

  /// Signature (`id:pointCount|…`) of the route-path lines the corner
  /// arrows/bubbles in [_allCornerFeatures] were last computed from. The corner
  /// pass walks every segment of every path line and awaits an image bake per
  /// bend, so it is skipped entirely when the route geometry is unchanged —
  /// which is the case on every grey-overlay add/remove during navigation.
  String? _cornerFeaturesSignature;
  final String _turnBubbleLayerId = 'turn-bubble-layer';
  final String _pathSolidLayerId = 'path-solid-polyline-layer';
  final String _pathOutlineLayerId = 'path-solid-outline-polyline-layer';
  final String _pathDashedLayerId = 'path-dashed-polyline-layer';
  final String _pathArrowLayerId = 'path-arrow-layer';
  final String _polylineLayerId = 'normal-polyline-layer';
  final String _greyOverlayLayerId = 'grey-overlay-polyline-layer';

  // ---------------------------------------------------------------------------
  // Layer policy
  // ---------------------------------------------------------------------------

  /// Which [MapLayer] leaf group each real style layer belongs to.
  ///
  /// This is the only place layer ids are tied to the host-facing taxonomy, and
  /// it must cover every layer this provider actually creates. Note
  /// [_normalIconMarkerLayerId] is deliberately absent: no layer is ever created
  /// under that bare id, it only serves as a `belowLayerId` anchor. The two
  /// `-with/withoutSectionId` variants are the real layers.
  late final Map<String, MapLayer> _layerGroups = {
    // markers
    _dotMarkerLayerId: MapLayer.landmarkMarkers,
    _normalTextMarkerLayerId: MapLayer.landmarkMarkers,
    '$_normalIconMarkerLayerId-withSectionId': MapLayer.landmarkMarkers,
    '$_normalIconMarkerLayerId-withoutSectionId': MapLayer.landmarkMarkers,
    _customRenderingMarkerLayerId: MapLayer.landmarkMarkers,
    _overlapOverrideMarkerLayerId: MapLayer.landmarkMarkers,
    _fixedMarkerLayerId: MapLayer.entryMarkers,
    _priorityMarkerLayerId: MapLayer.priorityMarkers,
    _sectionMarkerLayerId: MapLayer.sectionLabels,
    _subSectionMarkerLayerId: MapLayer.subSectionLabels,
    _patchAboveMarkerLayerId: MapLayer.venueLabel,
    // polygons
    _normalPolygonLayerId: MapLayer.rooms,
    _patternPolygonLayerId: MapLayer.rooms,
    // _sectionPolygonLayerId: MapLayer.sections,
    // _subSectionPolygonLayerId: MapLayer.subSections,
    // _patchBelowPolygonLayerId: MapLayer.venueBoundary,
    // _patchAbovePolygonLayerId: MapLayer.venueBoundary,
    _extrudedPolygonLayerId: MapLayer.extrusions,
    // polylines
    _pathSolidLayerId: MapLayer.routeLine,
    _pathOutlineLayerId: MapLayer.routeLine,
    _pathDashedLayerId: MapLayer.routeLine,
    _greyOverlayLayerId: MapLayer.routeTraveled,
    _polylineLayerId: MapLayer.polylines,
    // furniture
    _furnitureFillLayerId: MapLayer.furniture,
    _furnitureLayerId: MapLayer.furniture,
    // user location
    _rotationMarkerLayerId: MapLayer.userLocation,
    _normalCircleLayerId: MapLayer.userLocation,
    // selection
    _selectedMarkerLayerId: MapLayer.selection,
    _selectedPlainPolygonLayerId: MapLayer.selection,
    _selectedPlainPolygonStrokeLayerId: MapLayer.selection,
    _selectedExtrudedPolygonLayerId: MapLayer.selection,
  };

  MapLayerPolicy _policy = MapLayerPolicy.all;

  /// Full-property builders, keyed by layer id, registered by [_layerProps] as
  /// each layer is created or refreshed.
  ///
  /// These have to be *full* property sets, not partial ones:
  /// `MapLibreMapController.setLayerProperties` serialises with
  /// `toJson(skipNulls: false)`, so every field left unset is sent as an
  /// explicit null and resets that property to its default. Re-applying a
  /// policy therefore has to be able to regenerate everything the layer had.
  final Map<String, LayerProperties Function(_OpacityResolver)> _propBuilders =
      {};

  /// How to REBUILD a layer that `setLayerProperties` cannot touch.
  ///
  /// maplibre_gl's Android `layer#setProperties` handler is an if-chain over
  /// Line/Fill/Circle/Symbol/Raster/Hillshade and falls through to
  /// `UNSUPPORTED_LAYER_TYPE` for anything else — so **every fill-extrusion
  /// layer silently rejects every property push**, opacity included. That is a
  /// plugin gap, not something this file can set differently.
  ///
  /// The way through is the one already used for `patch-above-markers-layer`:
  /// remove the layer and add it again with the properties we want. Each entry
  /// re-adds one layer with its original source, filter, anchor and zoom range —
  /// those MUST match the creation call or the layer silently changes z-order or
  /// stops matching features.
  final Map<String, Future<void> Function()> _layerReAdders = {};

  /// Last state actually pushed through a re-adder, per layer.
  ///
  /// A re-add is a remove + add of a real layer — visibly a flicker, and far
  /// more expensive than setting a property. [_applyLayerPolicy] runs on far
  /// more than policy changes (selection, camera idle, furniture setup), so
  /// without this every one of those rebuilds all three extrusion layers for no
  /// change at all. Keyed absent = never pushed.
  ///
  /// Compares the whole [MapLayerState], not just its opacity: a config that
  /// repaints an extrusion layer changes `properties` with the opacity untouched
  /// and must still trigger the rebuild that is the only way to apply it.
  final Map<String, MapLayerState> _reAddedState = {};

  /// Layers we have written a policy value to at least once.
  ///
  /// [_applyLayerPolicy] skips layers whose resolved state is the default, so a
  /// host that never touches this API sees no extra channel traffic at all.
  /// Without this set, that fast path would also skip the write that *restores*
  /// a layer after a host un-hides it or clears an opacity override.
  final Set<String> _everApplied = {};

  /// The resolved settings for one style layer: defaults → family → member →
  /// layer id, each link overriding only the fields it names.
  ///
  /// A layer with no [_layerGroups] entry — the basemap raster — still resolves,
  /// it just has nothing above it to inherit from. That is what makes
  /// `osm-tiles-layer` configurable from a config file even though it is
  /// deliberately outside the [MapLayer] taxonomy.
  MapLayerState _stateForLayer(String layerId) =>
      _policy.resolveLayer(layerId, _layerGroups[layerId]);

  /// [built] with the layer's configured style properties written over it.
  ///
  /// Property overrides cannot go through the [_OpacityResolver] the way
  /// [MapLayerState.opacity] does: they are arbitrary keys, and a builder
  /// constructs a typed `LayerProperties` whose fields this code cannot reach by
  /// name. So the merge happens on the serialised form — the exact map
  /// `setLayerProperties` would have sent — and the result is rebuilt through
  /// the matching `fromJson`. Round-tripping is lossless: `toJson`/`fromJson`
  /// name the same keys, and `skipNulls: false` keeps the unset ones present so
  /// nothing is silently dropped.
  ///
  /// Idempotent, so it is safe on a property set that already went through
  /// [_layerProps].
  P _withStyleOverrides<P extends LayerProperties>(String layerId, P built) {
    final state = _stateForLayer(layerId);
    final overrides = MapLayerState.normalizeKeys(state.properties);
    if (overrides.isEmpty) return built;

    final json = built.toJson(skipNulls: false);
    // `visible` owns visibility. A config naming `visibility` was warned about
    // at parse time; restoring the renderer's value here covers a hand-built
    // policy too, so there is exactly one answer to "is this layer drawn".
    final visibility = json['visibility'];
    json.addAll(overrides);
    json['visibility'] = visibility;

    final merged = switch (built) {
      SymbolLayerProperties _ => SymbolLayerProperties.fromJson(json),
      CircleLayerProperties _ => CircleLayerProperties.fromJson(json),
      LineLayerProperties _ => LineLayerProperties.fromJson(json),
      FillLayerProperties _ => FillLayerProperties.fromJson(json),
      FillExtrusionLayerProperties _ =>
        FillExtrusionLayerProperties.fromJson(json),
      RasterLayerProperties _ => RasterLayerProperties.fromJson(json),
      HillshadeLayerProperties _ => HillshadeLayerProperties.fromJson(json),
      HeatmapLayerProperties _ => HeatmapLayerProperties.fromJson(json),
      // Unknown LayerProperties subclass: nothing to rebuild it with, so leave
      // the layer exactly as the renderer built it rather than dropping it.
      _ => built,
    };
    return merged as P;
  }

  /// [MapLibreMapController.setLayerProperties] with the layer's configured
  /// style properties merged in.
  ///
  /// For the call sites that build their property set OUTSIDE [_layerProps] and
  /// so have not been through [_withStyleOverrides] already — the ones that
  /// deliberately push a PARTIAL set: the native branch of
  /// [_refreshMarkerLayerMinZooms], and greyscale's raster saturation. A partial
  /// push must still carry the host's overrides, or it silently undoes them
  /// until the next full re-apply.
  ///
  /// A set that came from [_layerProps] is already merged and can be pushed
  /// through the controller directly; sending it through here anyway is
  /// harmless, since the merge is idempotent.
  Future<void> _pushLayerProperties(
    MapLibreMapController controller,
    String layerId,
    LayerProperties properties,
  ) =>
      controller.setLayerProperties(
          layerId, _withStyleOverrides(layerId, properties));

  /// Registers [layerId]'s full property set as a function of the opacity
  /// resolver, and returns the properties to push right now.
  ///
  /// Every opacity write in this file goes through here. [build] receives a
  /// resolver: wrap each opacity value the layer would natively use in
  /// `op(...)`, and the host's absolute override is substituted when one is set.
  P _layerProps<P extends LayerProperties>(
      String layerId, P Function(_OpacityResolver op) build) {
    _propBuilders[layerId] = build;
    final override = _stateForLayer(layerId).opacity;
    // Overrides are applied on the way OUT rather than inside the builder, so
    // what gets registered stays the renderer's own intent and a later policy
    // change re-resolves against the current config instead of a baked-in one.
    return _withStyleOverrides(layerId, build((base) => override ?? base));
  }

  /// Registers [layerId]'s full property set without pushing it.
  ///
  /// For the handful of call sites that deliberately push a *partial* set —
  /// the native branch of [_refreshMarkerLayerMinZooms] — so that a later
  /// policy re-apply regenerates the state that branch intended rather than the
  /// creation-time one.
  void _registerLayerProps<P extends LayerProperties>(
      String layerId, P Function(_OpacityResolver op) build) {
    _propBuilders[layerId] = build;
  }

  /// The opacity resolver for [layerId], for call sites that build their own
  /// property set rather than going through [_layerProps].
  _OpacityResolver _opFor(String layerId) {
    final override = _stateForLayer(layerId).opacity;
    return (base) => override ?? base;
  }

  /// The `visibility` layout value for [layerId], composing the host policy with
  /// the renderer's own intent.
  ///
  /// The host can subtract but never add: passing `internalVisible: false` (the
  /// 2D/3D rules) hides the layer no matter what the policy says, because those
  /// rules exist to stop the renderer drawing something incoherent.
  String _visibility(String layerId, {bool internalVisible = true}) =>
      (_stateForLayer(layerId).visible == false || !internalVisible)
          ? "none"
          : "visible";

  /// Whether taps on [layerId] should be acted on.
  ///
  /// Layers with no binding — the basemap raster, anything added outside this
  /// provider — are always tappable, so behaviour is unchanged for them.
  bool _tapAllowedForLayer(String layerId) =>
      _stateForLayer(layerId).tappable != false;

  /// Whether any marker group is still drawn under the current policy.
  ///
  /// [_selectedMarkerLayerId] belongs to [MapLayer.selection], which presets
  /// like [MapLayerPolicy.polygonsOnly] deliberately leave alone so that
  /// tapping a room still highlights it. That exemption is meant for the
  /// selected-POLYGON layers; applied to the selected-marker layer it resurrects
  /// a marker the host just hid — tap a room with markers off and one marker
  /// pops back, because selectLocation flags the tapped landmark's feature
  /// `isSelected` and that layer's filter is exactly `isSelected`.
  ///
  /// So the marker half of the selection is additionally gated on markers being
  /// drawn at all. The polygon half is untouched.
  bool get _anyMarkerGroupVisible => MapLayer.markers.leaves
      .any((g) => _policy.resolve(g).visible != false);

  /// Re-push the full property set for [only], or every registered layer.
  ///
  /// Wrapped per layer: `furniture-layer`, `patch-above-markers-layer` and
  /// `section-markers-layer` are removed and re-added at runtime, so a write can
  /// legitimately land on a layer that does not exist right now.
  /// Tail of the serialised chain of policy applies.
  ///
  /// Applies MUST NOT interleave. A fill-extrusion layer is updated by removing
  /// and re-adding it (see [_layerReAdders]), so two overlapping applies run
  /// remove(A) → remove(B) → add(A) → add(B), and the second add throws
  /// `CannotAddLayerException: already exists`. An opacity slider produces
  /// exactly that overlap, several times a second.
  ///
  /// Chaining rather than dropping: the last value dragged to is the one that
  /// must end up applied, so every request has to run, just strictly in order.
  Future<void>? _policyApplyChain;

  Future<void> _applyLayerPolicy(
    MapLibreMapController controller, {
    Iterable<String>? only,
    bool force = false,
  }) {
    final next = (_policyApplyChain ?? Future<void>.value())
        .then((_) => _applyLayerPolicyOnce(controller, only: only, force: force));
    // The chain must survive a failed link, or one error strands every later
    // apply behind it.
    _policyApplyChain = next.catchError((_) {});
    return next;
  }

  Future<void> _applyLayerPolicyOnce(
    MapLibreMapController controller, {
    Iterable<String>? only,
    bool force = false,
  }) async {
    final ids = (only ?? _propBuilders.keys).toList(growable: false);
    for (final id in ids) {
      final build = _propBuilders[id];
      if (build == null) continue;
      final state = _stateForLayer(id);
      final isDefault = state.opacity == null &&
          state.visible != false &&
          state.properties.isEmpty;
      if (!force && isDefault && !_everApplied.contains(id)) continue;
      if (!isDefault) _everApplied.add(id);
      try {
        final reAdd = _layerReAdders[id];
        if (reAdd != null) {
          // Fill-extrusion: setLayerProperties would throw
          // UNSUPPORTED_LAYER_TYPE, so rebuild the layer instead. The builder
          // registered for it reads the live policy, so the re-add picks up the
          // override on its own.
          if (_reAddedState[id] == state) {
            continue; // nothing changed — do not pay a rebuild
          }
          await reAdd();
          _reAddedState[id] = state;
          print('layer policy: $id rebuilt <- $state');
        } else {
          await _pushLayerProperties(
              controller, id, build((base) => state.opacity ?? base));
        }
      } catch (e) {
        // Usually benign: the layer is not present right now (furniture in 2D,
        // or mid re-add). It was swallowed silently, which also hid real
        // failures — a push that throws here is indistinguishable from one that
        // worked, and the group simply never changes.
        print('layer policy: $id push failed: $e');
      }
    }
  }

  @override
  Future<void> setLayerPolicy(
      dynamic controller, MapLayerPolicy policy) async {
    _policy = policy;
    if (controller is! MapLibreMapController) return;
    await _applyLayerPolicy(controller, force: true);
  }

  /// Resolves a `belowLayerId` anchor safely.
  ///
  /// On Android/iOS this returns [layerId] untouched — the native SDKs ignore
  /// an anchor that does not exist yet, and mobile behaviour must not change.
  /// MapLibre GL JS instead *throws* ("Cannot add layer X before non-existing
  /// layer Y"), which aborts the whole enclosing layer-setup batch and leaves
  /// the polygon/polyline layers uncreated. On web we therefore drop the
  /// anchor when it is not present yet; the layer is added on top instead.
  Future<String?> _webSafeBelowLayerId(
      MapLibreMapController controller, String? layerId) async {
    if (layerId == null || !kIsWeb) return layerId;
    try {
      final ids = await controller.getLayerIds();
      return ids.contains(layerId) ? layerId : null;
    } catch (_) {
      return null;
    }
  }

  bool _isClusteringEnabled = false;
  bool _isPolygonLayersEnabled = false;
  bool _isPolylineLayersEnabled = false;
  bool _isCircleLayersEnabled = false;
  bool _isFurnitureLayerEnabled = false;

  /// Pending self-heal retry timers per GeoJSON source id — see the comment
  /// in [setGeoJsonSource].
  final Map<String, List<Timer>> _settleTimers = {};

  /// Whether [_clusterSourceId]/[_rotationSourceId] currently exist natively.
  /// A style reload wipes every source, so anything pushing GeoJSON from a
  /// timer/stream (compass ticks, marker animation) must check this first —
  /// otherwise the native controller NPEs on a null source.
  bool _markerSourcesReady = false;

  /// Whether the furniture fill-extrusion layer currently exists on the map.
  /// It is added only in 3D mode and removed entirely when switching to 2D.
  bool _isFurnitureExtrusionAdded = false;

  Size? _screenSize;
  double? _fadeOutZoom;

  // ---------------------------------------------------------------------------
  // Priority collision key
  //
  // MapLibre's symbol-sort-key: lower value = rendered first = wins collision.
  // We negate the marker priority so that a higher priority number wins.
  // All layers that participate in collision detection must declare this key.
  // ---------------------------------------------------------------------------

  /// GeoJSON property name that carries the numeric priority value.
  static const String _kPriorityKey = 'markerPriority';

  /// MapLibre expression: negate priority so higher number → lower sort key → wins.
  static const List<dynamic> _kSortKeyExpression = [
    "+",
    // Priority dominates: negated so a HIGHER priority number sorts lower and
    // therefore places first and wins collision.
    // coalesce because the rotation source builds its own features and writes
    // neither key; a bare `get` there yields null and taints the arithmetic.
    ["*", ["coalesce", ["get", _kPriorityKey], 0], -1],
    // Stable tiebreaker, < 0.5. See 'sortBias' in setGeoJsonSource for why an
    // all-equal sort key makes a whole layer vanish as one block. coalesce
    // because the rotation source builds its own features and has no bias.
    ["coalesce", ["get", "sortBias"], 0],
  ];

  /// Markers whose full marker only appears from zoom 18 — text markers
  /// (collisionBase 0), whose layer still carries `minzoom: 18`. Their dot is
  /// held at 0 until 18 so nothing is drawn where the full marker cannot be.
  ///
  /// icon-with-sectionId (base 3000) used to be in here too. Its layer's z18
  /// gate was removed, so it now fades in 12→14 like every other icon marker
  /// and its dot follows the ordinary ramp; leaving it listed here would hide
  /// the dot below 18 and break the fallback. Used to pick the dot's opacity
  /// ramp; see [enableMarkerLayers].
  static const List<dynamic> _kDotStepGroupExpression = [
    "any",
    ["==", ["get", "collisionBase"], 0],
  ];

  // ---------------------------------------------------------------------------
  // Styles
  // ---------------------------------------------------------------------------

  @override
  /// Captured from [buildMap]'s config, because `config` is a parameter there
  /// rather than a field and [_refreshPatchAboveOpacity] — which is where the
  /// venue actually finishes drawing — cannot reach it.
  void Function()? _onVenueRenderedCb;

  final Completer<void> _venueRenderedCompleter = Completer<void>();

  /// Completes when the venue geometry is drawn. See [BaseMapProvider.venueRendered].
  @override
  Future<void> get venueRendered => _venueRenderedCompleter.future;

  Widget buildMap({required MapConfig config, required BuildContext context, Function(UnifiedCameraPosition position)? onCameraMove}) {
    _onVenueRenderedCb = config.onVenueRendered;
    // ── Android platform-view composition mode ─────────────────────────────
    //
    // maplibre_gl 0.26.2 offers exactly two modes on Android (see
    // maplibre_gl_platform_interface `buildView`):
    //   • false → `AndroidView` = Virtual Display. The GL SurfaceView renders
    //     into an offscreen buffer that Flutter copies through an ImageReader
    //     and re-uploads as a texture every frame.
    //   • true → `PlatformViewLink` + `initAndroidView` = Hybrid Composition.
    //     The SurfaceView is embedded directly; no per-frame copy.
    //
    // Measured on a moto g64 (120Hz), aggressive synthetic panning of the
    // zoo venue:
    //   Virtual Display : median 16.6ms, p90 58ms, 31% of frames dropped, 124ms freezes
    //   Hybrid Comp.    : median  8.3ms, p90 25ms,  2% of frames dropped,  33ms worst
    // The native MapLibre SurfaceView itself renders a rock-steady 120fps in
    // both cases — the Virtual Display copy/upload is the entire cost. HC also
    // fixes the extruded-furniture transparency flicker during camera rotate.
    // So: HC, decisively. Do not switch to Virtual Display.
    MapLibreMap.useHybridComposition = true;
    // Seeded on every rebuild, not just the first: this is the only path by
    // which the policy reaches the provider before onMapCreated and the
    // enableXxxLayers calls run, so the layers are created in the state the host
    // asked for instead of flashing the default first. UnifiedMapController
    // mirrors every runtime change back into the config, so the two never drift.
    _policy = config.initialLayerPolicy;
    return Stack(
      children: [
        MapLibreMap(
          trackCameraPosition: true,
          initialCameraPosition: CameraPosition(
              target: LatLng(
                config.initialLocation.mapLocation.latitude,
                config.initialLocation.mapLocation.longitude,
              ),
              zoom: config.initialLocation.zoom,
              tilt: config.initialLocation.tilt,
              bearing: config.initialLocation.bearing
          ),
          styleString: osmRasterStyle,
          onMapCreated: (MapLibreMapController controller) async {
            _config = config;
            _controller = controller;

            config.onMapCreated(controller);

            // Handle feature taps (polygons & markers).
            //
            // maplibre_gl 0.26 OnFeatureInteractionCallback — note the arg
            // ORDER, which differs from 0.21's (that one led with a dynamic id
            // and had no annotation):
            //   (Point<double> point, LatLng coordinates, String id,
            //    String layerId, Annotation? annotation)
            // The controller normalises the id with `payload["id"].toString()`
            // before calling us, so `id` is always a String and never null.
            // It CAN be empty: symbol layers deliver no feature id (observed on
            // collision-dot and normalIcon taps), so the `id.isNotEmpty` gate
            // further down skips them and markers are resolved by
            // queryRenderedFeatures instead. Only polygon layers arrive here
            // with a usable composite id.
            controller.onFeatureTapped.add((Point<double> point,
                LatLng coordinates,
                String id,
                String layerId,
                Annotation? annotation) async {
              print("MapLibre onFeatureTapped id $id $point $coordinates layerId $layerId");
              // if (_symbols
              //     .where((s) => s.id.toLowerCase().contains("path"))
              //     .isNotEmpty) return;
              try {
                // Query rendered features at the tap point for marker layers
                // Only query layers whose group still accepts taps. Hidden
                // layers are already excluded by MapLibre's own query, so
                // `visible: false` implies untappable for free.
                final tappableMarkerLayers = <String>[
                  _normalTextMarkerLayerId,
                  "$_normalIconMarkerLayerId-withSectionId",
                  "$_normalIconMarkerLayerId-withoutSectionId",
                  _fixedMarkerLayerId,
                  _customRenderingMarkerLayerId,
                  _priorityMarkerLayerId,
                  _rotationMarkerLayerId,
                  _dotMarkerLayerId,
                ].where(_tapAllowedForLayer).toList();

                // An empty layer list is NOT "query nothing" — MapLibre drops
                // the `layers` option entirely and queries the whole style,
                // basemap raster included. Skip the call instead.
                final markerFeatures = tappableMarkerLayers.isEmpty
                    ? const <dynamic>[]
                    : await controller.queryRenderedFeatures(
                        point,
                        tappableMarkerLayers,
                        null,
                      );

                print("queryRenderedFeatures count: ${markerFeatures.length}");

                if (markerFeatures.isNotEmpty) {
                  final feature = markerFeatures.first;
                  print(
                      "feature $feature ${feature['properties']?['id']}");
                  final markerId =
                  _extractPolygonIdFromTap(feature['properties']?['id']);
                  print("Marker tapped with ID: $markerId");

                  if (markerId != null) {
                    _selectFromTap(controller, markerId,
                        _markerGroupFor(feature['properties'] as Map?));
                    return;
                  }
                }

                final tappedPolygon = _hitTestPolygons(
                  coordinates.latitude,
                  coordinates.longitude,
                  allow: (p) => _tapAllowedForGroup(_polygonGroupFor(p)),
                );

                print("tappedPolygon.id ${tappedPolygon?.id}");

                if (tappedPolygon != null &&
                    !tappedPolygon.id.toLowerCase().contains("boundary")) {
                  final polygonId = _extractPolygonIdFromTap(tappedPolygon.id);
                  if (polygonId != null &&
                      !polygonId.toLowerCase().contains("boundary")) {
                    _selectFromTap(controller, polygonId,
                        _polygonGroupFor(tappedPolygon));
                  }
                  return;
                }

                // Fall through to polygon tap. This is the only route by which
                // the label and selected-marker layers reach selection — none of
                // them are in the query list above — so gate on the layer the
                // tap actually came from, which every platform populates.
                if (id.isNotEmpty && _tapAllowedForLayer(layerId)) {
                  final polygonId = _extractPolygonIdFromTap(id);
                  if (polygonId != null &&
                      !polygonId.toLowerCase().contains("boundary")) {
                    GeoJsonPolygon? matched;
                    for (final p in _polygons) {
                      if (p.id.contains(polygonId)) {
                        matched = p;
                        break;
                      }
                    }
                    _selectFromTap(
                      controller,
                      polygonId,
                      matched == null
                          ? MapLayer.rooms
                          : _polygonGroupFor(matched),
                    );
                  }
                }
              } catch (e) {
                print("Error handling feature tap: $e");
              }
            });
          },
          onStyleLoadedCallback: () async {
            if (_controller != null) {
              // Host-supplied; a throw here would skip the entire layer rebuild
              // below and leave the map permanently blank. Same reasoning as
              // the try around the icon rebake.
              try {
                await config.onStyleLoadedCallback(_controller);
              } catch (e) {
                print('style-loaded: host onStyleLoadedCallback threw: $e');
              }
              // Style reload wipes ALL sources, layers, and addImage() calls —
              // reset flags so enableXxxLayers() re-creates everything cleanly.
              _isClusteringEnabled = false;
              // Sources are gone until enableMarkerLayers() re-adds them below;
              // block async GeoJSON pushes for the whole rebuild window.
              _markerSourcesReady = false;
              _isPolygonLayersEnabled = false;
              _isPolylineLayersEnabled = false;
              // Registered dot images are wiped too; allow re-registration.
              _registeredDotImageIds.clear();
              _registeredCornerArrowAngles.clear();
              // Corner arrow/bubble images are wiped with the style, so the next
              // _updatePolylineSource must re-run the full corner pass (which
              // re-registers them) instead of taking the "route unchanged" skip.
              _cornerFeaturesSignature = null;
              // Registered path arrow is wiped too.
              await _loadPathArrowImage(_controller!);
              // Same for the shared label-less icons. The baked bytes in
              // _bakedIconCache stay valid — only the addImage() registration
              // is gone — so the rebake pass below is upload-only.
              _registeredSmallIconIds.clear();
              // Registered animal icons are wiped too (the composited bytes in
              // _animalIconCache are still valid and get reused, only the
              // addImage() registration needs to happen again).
              _loadedAnimalIcons.clear();
              // Same reset for regular/customRendering marker icons — the loop
              // below re-registers every current marker's icon from scratch.
              _registeredMarkerIconIds.clear();
              // Re-arm the deferred labelled bake: its addImage() calls are
              // gone with the style, so the next camera idle at label zoom has
              // to re-register them. The bytes survive in _animalIconCache, so
              // that pass is upload-only.
              _labelledAnimalsStarted = false;
              _isCircleLayersEnabled = false;
              _isFurnitureLayerEnabled = false;
              _isFurnitureExtrusionAdded = false;
              // The layers this was building are gone with the style, so a
              // fresh setup must be allowed to start rather than joining it.
              _furnitureLayerSetup = null;
              // Every layer is about to be rebuilt, and each builder closes over
              // the fade zoom and 2D/3D mode of the style it was registered
              // under — so the stale ones must go. `_policy` deliberately does
              // NOT reset: it is the host's setting, not style state, and the
              // enableXxxLayers calls below read it to recreate the layers in
              // the state the host asked for.
              _propBuilders.clear();
              _everApplied.clear();
              // These close over layers the style reload just destroyed; the
              // re-creation below registers fresh ones.
              _layerReAdders.clear();
              _reAddedState.clear();

              // Re-register all marker icons — style reload wipes addImage() calls
              //
              // Animal markers are split out and rebaked through
              // _batchLoadAnimalIcons below. _loadMarkerIcon is the *generic*
              // path: it re-registers an image under the marker's own id but
              // never repopulates _loadedAnimalIcons, which is the set
              // _animalDisplayIconId consults to decide between the real
              // composite and the paw placeholder. Since the reset above
              // clears that set and _batchLoadAnimalIcons only otherwise runs
              // from addMarkers (which does not re-run after a style reload),
              // sending animals through the generic path left every one of
              // them pinned to its paw placeholder for good, at every zoom.
              final allIconMarkers = [..._symbols, ..._rotatingSymbols];
              final animalIconMarkers =
                  allIconMarkers.where(_isAnimalMarker).toList();
              final iconMarkers =
                  allIconMarkers.where((m) => !_isAnimalMarker(m)).toList();
              // The enable*Layers calls below MUST run. Every layer flag was
              // reset to false at the top of this callback, so if anything in
              // the icon rebake throws and we bail out here, those flags stay
              // false for the lifetime of the map — and setGeoJsonSource,
              // _updatePolygonSource and _updatePolylineSource all silently
              // early-return on a false flag. The result is a permanent grey
              // basemap with no venue and no error anywhere: the exact symptom
              // seen on web on 2026-08-27. A missing icon is cosmetic; a
              // missing layer is fatal. So the bake is best-effort and the
              // enables are unconditional.
              try {
              await PerfTrace.timeAsync(
                  'style-loaded: rebake of ${iconMarkers.length} icons', () async {
                if (kIsWeb) {
                  // Fanned out instead of a sequential `for ... await`. This
                  // pass runs *after* the basemap paints, so serially baking
                  // ~190 icons was the bulk of "base map instant, then elements
                  // trickle in for ~12s". The wall-clock total barely moves
                  // (single-threaded, CPU-bound), but the work interleaves and
                  // the URL-icon fetches overlap, which reads as noticeably
                  // faster. Sequencing is preserved: every icon is registered
                  // before enable*Layers below.
                  // Tracked, so an icon that fails to re-register after a
                  // style reload demotes its marker to a text marker instead
                  // of leaving it pointing at a wiped image.
                  await Future.wait(iconMarkers.map(
                      (marker) => _loadAndTrackMarkerIcon(_controller!, marker)));
                } else {
                  for (final marker in iconMarkers) {
                    await _loadAndTrackMarkerIcon(_controller!, marker);
                  }
                }
              });

              // NOT awaited — this is the single biggest cost on the whole web
              // load path. Measured on device (NationalZoologicalPark, 112
              // animals, release): **14,053ms**, against a 25,725ms
              // time-to-venue. Skipping markers entirely rendered the venue in
              // 11,446ms, so this one call was 14.3s of the 14.3s that markers
              // cost. It ran here, awaited, *before* enable*Layers — so the map
              // sat blank for 14s re-registering icons for a venue it could
              // already have drawn.
              //
              // The comment this replaces argued it had to be awaited so
              // _loadedAnimalIcons was filled before enableMarkerLayers pushes
              // the source, "otherwise that push serialises every animal
              // feature with the paw id". That is true and it is fine: the paw
              // IS the designed load-state fallback (_animalDisplayIconId), and
              // _scheduleAnimalIconRefresh re-pushes the source as each icon
              // lands. Paws for a couple of seconds beats a blank map for
              // fourteen.
              if (animalIconMarkers.isNotEmpty) {
                unawaited(PerfTrace.timeAsync(
                        'style-loaded: rebake of ${animalIconMarkers.length} animal icons',
                        () => _batchLoadAnimalIcons(
                            _controller!, animalIconMarkers))
                    .catchError((e) {
                  // Unawaited, so a throw here would be an unhandled async
                  // error rather than something the try below can catch.
                  print('style-loaded: animal rebake failed: $e');
                }));
              }
              } catch (e, stack) {
                print('style-loaded: icon rebake failed, continuing to enable '
                    'layers anyway: $e');
                print(stack);
              }

              await enablePolygonLayers(_controller!);
              await enablePolylineLayers(_controller!);
              await enableCircleLayers(_controller!);
              await enableMarkerLayers(_controller!);

              // enableMarkerLayers re-pushes _symbols, but not _rotatingSymbols
              if (_rotatingSymbols.isNotEmpty) {
                await setGeoJsonSource(_controller!, _rotatingSymbols, _rotationSourceId);
              }
              // Re-push polygons, polylines, and circles that existed before reload.
              // Style reload wipes addImage() pattern bitmaps too, so re-register
              // them BEFORE re-pushing the source — otherwise fill-pattern resolves
              // to a missing image and the polygon renders grey.
              if (_polygons.isNotEmpty) {
                await Future.wait(
                  _polygons.map((polygon) async {
                    try {
                      await RenderingUtilities.registerLandmarkPattern(_controller!, polygon);
                    } catch (e) {
                      print('Warning: failed to re-register pattern for ${polygon.id}: $e');
                    }
                  }),
                );
                await _updatePolygonSource(_controller!);
              }
              if (_lines.isNotEmpty) {
                await _updatePolylineSource(_controller!);
              }
              if (_circles.isNotEmpty) {
                await _setGeoJsonCircle(_controller!);
              }
              if (_furnitureItems.isNotEmpty) {
                await _enableFurnitureLayer(_controller!);
                await _updateFurnitureSource(_controller!);
              }
              _screenSize = MediaQuery.of(context).size;
              await _refreshPatchAboveOpacity(_controller!, screenSize: _screenSize);
            }
          },
          onCameraIdle: () async {
            if (_controller != null) {
              try {
                if (_allCornerFeatures.isNotEmpty && _controller != null) {
                  _refreshCornerVisibility(_controller!);
                }
                // The puck glide defers its source pushes while the camera moves
                // (see _animateMarkerToPosition). The camera just settled, so land
                // the puck on its current position now that a push is free.
                if (_rotatingSymbols.isNotEmpty) {
                  unawaited(_updateUserLocation(_controller!));
                }
                final cameraPos = _controller!.cameraPosition;
                if(cameraPos == null) return;
                final target = cameraPos.target;
                final bearing = cameraPos.bearing;
                final tilt = cameraPos.tilt;
                final zoom = cameraPos.zoom;
                print("tilt $tilt");
                print("zoom $zoom");
                print("bearing $bearing");
                if (_kDebugLayerCensus) {
                  unawaited(_debugLayerCensus(_controller!, zoom));
                }
                // The labelled animal composites are only drawn from
                // _kLabelZoomThreshold up, so they are baked the first time the
                // camera actually settles there instead of during load. Not
                // awaited: this callback should not block the camera.
                if (zoom >= _kLabelZoomThreshold) {
                  unawaited(_ensureLabelledAnimalIcons(_controller!));
                }
                var unifiedCameraPosition = UnifiedCameraPosition(
                    mapLocation: MapLocation(
                      latitude: target.latitude,
                      longitude: target.longitude,
                    ),
                    zoom: zoom,
                    bearing: bearing,
                    tilt: tilt
                );
                config.onCameraMove(unifiedCameraPosition);

                if(onCameraMove != null){
                  onCameraMove(unifiedCameraPosition);
                }
              } catch (e) {
                print("Error getting camera position: $e");
              }
            }
          },
          // Fires every frame the camera is moving (gesture or animated follow).
          // Kept trivial — just a timestamp — so cosmetic per-frame work elsewhere
          // can back off while the map is in motion. `trackCameraPosition: true`
          // already streams these events, so handling them adds no channel traffic.
          onCameraMove: (_) => _lastCameraMove = DateTime.now(),
          myLocationEnabled: config.showUserLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: false,
          rotateGesturesEnabled: config.rotateGesturesEnabled,
          scrollGesturesEnabled: config.scrollGesturesEnabled,
          tiltGesturesEnabled: config.tiltGesturesEnabled,
          zoomGesturesEnabled: config.zoomControlsEnabled,
          minMaxZoomPreference: const MinMaxZoomPreference(0.0, 23.0),
          logoViewMargins: const Point(50, 5),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  @override
  Future<void> moveCamera(
      dynamic controller, MapLocation location, double zoom) async {
    if (controller is MapLibreMapController) {
      await controller.moveCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
      );
    }
  }

  @override
  Future<void> animateCamera(
      dynamic controller,
      MapLocation location,
      double zoom, {
        double? bearing,
        double? tilt,
        Duration? duration
      }) async {
    if (controller is! MapLibreMapController) return;

    // Heading-up navigation drives this on every location fix. With the
    // plugin's ~300ms default, each call eases for 300ms then sits frozen
    // until the next fix (~1s later) — the camera "freezes then jumps". A ~1s
    // glide is still running when the next fix lands, so the plugin restarts
    // it from the current pose and the follow stays continuous. One-shot
    // moves (no bearing supplied) keep the snappy default.
    final effectiveDuration = duration ??
        (bearing != null ? const Duration(milliseconds: 1000) : null);

    if (bearing != null || tilt != null) {
      final current = controller.cameraPosition;
      // Single animation. The old code, when given only a bearing, ran a
      // newLatLngZoom animation and THEN a separate bearingTo animation —
      // two chained camera eases back to back, which always hitched.
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(location.latitude, location.longitude),
            zoom: zoom,
            bearing: bearing ?? current?.bearing ?? 0.0,
            tilt: tilt ?? current?.tilt ?? 0.0,
          ),
        ),
        duration: effectiveDuration,
      );
    } else {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(location.latitude, location.longitude),
          zoom,
        ),
        duration: effectiveDuration,
      );
    }
  }

  @override
  Future<void> setContentInsets(dynamic controller, EdgeInsets insets, {bool animated = true}) async {
    if (controller is MapLibreMapController) {
      await controller.updateContentInsets(insets, animated);
    }
  }

  Future<void> set3DViewEnabled(
      dynamic controller, {
        required bool isEnabled,
        double? tiltWhen3D,
      }) async {
    if (controller is! MapLibreMapController) return;
    if (_config.immersive == isEnabled) return;

    _config = _config.copyWith(immersive: isEnabled);

    // Keep map perspective in sync with 2D/3D state.
    final targetTilt = isEnabled ? (tiltWhen3D ?? (_config.initialLocation.tilt > 0 ? _config.initialLocation.tilt : 45.0)) : 0.0;
    await controller.animateCamera(CameraUpdate.tiltTo(targetTilt));

    // Explicitly disable extrusion rendering in 2D to avoid any residual shading.
    // Both of these are fill-extrusion layers, so setLayerProperties is
    // rejected with UNSUPPORTED_LAYER_TYPE — it always was, silently, under the
    // bare catches that used to be here. Rebuilding is the only way to change
    // them, and the registered builders read `_config.immersive`, which was
    // updated above, so the re-add picks up the new mode by itself.
    for (final id in [_selectedExtrudedPolygonLayerId, _extrudedPolygonLayerId]) {
      try {
        await _layerReAdders[id]?.call();
      } catch (e) {
        print('set3DViewEnabled: rebuild of $id failed: $e');
      }
    }
    try {
      // Full property set. This used to send `visibility` alone, which — given
      // setLayerProperties replaces rather than merges — also reset this
      // layer's icon-image, text-field and symbol-sort-key every time the user
      // toggled 2D/3D.
      await controller.setLayerProperties(
        _fixedMarkerLayerId,
        _layerProps(
            _fixedMarkerLayerId,
            (op) => _fixedMarkerLayerProps(
                  iconOpacity: op(_kDefaultMarkerOpacity),
                  textOpacity: op(null),
                  visibility: _visibility(_fixedMarkerLayerId,
                      internalVisible: !isEnabled),
                )),
      );
    } catch (_) {}

    // Furniture: extrude in 3D, flat fill in 2D. Switching to 2D removes the
    // extrusion layer entirely (not just hides it); switching back re-adds it.
    if (_isFurnitureLayerEnabled) {
      if (isEnabled) {
        await _addFurnitureExtrusionLayer(controller);
      } else {
        await _removeFurnitureExtrusionLayer(controller);
      }
      try {
        // Full property set, not just `visibility`: setLayerProperties
        // *replaces* the layer's whole paint property set rather than
        // merging into it (see _customRenderingLayerProps/_fixedMarkerLayerProps
        // for the same gotcha elsewhere in this file). A visibility-only call
        // here wiped `fill-color`/`fill-outline-color`, and the style-spec
        // default fill-color when unset is black — which is exactly why every
        // piece of furniture rendered solid black the moment 2D mode was
        // entered, regardless of its actual per-part color.
        await controller.setLayerProperties(
          _furnitureFillLayerId,
          _layerProps(_furnitureFillLayerId, (op) => FillLayerProperties(
            fillColor: ['get', 'color'],
            fillOutlineColor: ['get', 'color'],
            visibility: _visibility(_furnitureFillLayerId,
                internalVisible: !isEnabled),
            fillOpacity: op(null),
          )),
        );
      } catch (_) {}
    }

    // Rebuild polygon source so height/base_height are removed in 2D.
    await _updatePolygonSource(
      controller,
      selectPolygonIds: _currentSelectionGroup,
    );
  }

  Future<void> toggle3DView(dynamic controller, {double? tiltWhen3D}) async {
    await set3DViewEnabled(
      controller,
      isEnabled: !_config.immersive,
      tiltWhen3D: tiltWhen3D,
    );
  }

  @override
  Future<MapLocation?> getCurrentLocation(dynamic controller) async {
    if (controller is MapLibreMapController) {
      try {
        final cameraPosition = controller.cameraPosition;
        if (cameraPosition == null) return null;
        return MapLocation(
          latitude: cameraPosition.target.latitude,
          longitude: cameraPosition.target.longitude,
        );
      } catch (e) {
        print('Error getting current location: $e');
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> setMapStyle(dynamic controller, String? styleJson) async {
    if (controller is MapLibreMapController && styleJson != null) {
      // await controller.setStyleString(styleJson);
    }
  }

  // ---------------------------------------------------------------------------
  // Circles
  // ---------------------------------------------------------------------------

  @override
  Future<void> addCircle(controller, GeoJsonCircle circle) async {
    if (controller is MapLibreMapController) {
      _circles.removeWhere((c) => c.id == circle.id);
      _circles.add(circle);
      try {
        await _setGeoJsonCircle(controller);
        if (circle.animated) {
          _startCircleAnimation(controller, circle);
        }
      } catch (e) {
        print("error adding circle $e");
      }
    }
  }

  @override
  Future<void> removeCircle(controller, String id) async {
    if (controller is MapLibreMapController) {
      _circles.removeWhere((c) => c.id.toLowerCase().contains(id));
      try {
        await _setGeoJsonCircle(controller);
      } catch (e) {
        print("error removing circle $e");
      }
    }
  }

  Future<void> _setGeoJsonCircle(MapLibreMapController controller) async {
    // The 60fps move animation pushes this source every frame, so it lands mid
    // style reload, when the source has been wiped and not yet re-added.
    if (!_isCircleLayersEnabled) return;
    try {
      final features = _circles.map((circle) {
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [
              circle.position.longitude,
              circle.position.latitude
            ],
          },
          'properties': {
            if (circle.properties?['radius'] != null)
              'radius': circle.properties?['radius'],
          }
        };
      }).toList();

      await controller.setGeoJsonSource(_circleSourceId, {
        "type": "FeatureCollection",
        "features": features,
      });
    } catch (e) {
      print('Error updating circle source: $e');
    }
  }

  /// Upper zoom edge for the flat "section" fill (the coloured campus patches
  /// that sit on top of the buildings). At this zoom the patches are gone and
  /// the buildings show unobstructed; they ramp out over the 0.2 levels below
  /// it. The *lower* edge is not fixed — the patches stay visible all the way
  /// down until the "<venue name>" boundary layer fades in, then hand off to
  /// it. Tune per venue via `_maplibreProvider.sectionLayerMaxZoom = ...`
  /// before the map is built.
  double sectionLayerMaxZoom = 18.0;

  /// Fallback lower edge used only before the venue's real fit zoom is known
  /// (i.e. for the section layer's initial creation, before
  /// [_refreshPatchAboveOpacity] runs).
  double sectionLayerMinZoom = 15.0;

  /// Zoom at which plain building-name labels (text-only markers, and the
  /// icon+text markers grouped under a sectionId) start to appear. Was a hard
  /// 18.0; lowered so the building name is already readable while the coloured
  /// section patch is still up (the patch spans up to [sectionLayerMaxZoom]).
  double buildingLabelMinZoom = 17.0;

  /// Opacity `interpolate` expression for the section fill / labels.
  ///
  /// Visible from [lowEdge] (where the boundary layer hands off) up to
  /// [sectionLayerMaxZoom] (where the buildings take over), fading in/out over
  /// a short ramp at each end. [lowEdge] defaults to [sectionLayerMinZoom]; the
  /// runtime refresh passes the venue's boundary fade-out zoom so the patches
  /// only disappear on zoom-out once the "<venue name>" layer appears.
  List<dynamic> _sectionZoomWindowOpacity({double? lowEdge}) {
    final hi = sectionLayerMaxZoom;
    final loFull = lowEdge ?? sectionLayerMinZoom;
    // Keep the four zoom stops strictly increasing regardless of tuning.
    final a = loFull - 0.2;
    final b = max(loFull, a + 0.01);
    final c = max(hi - 0.2, b + 0.01);
    final d = max(hi, c + 0.01);
    return [
      "interpolate", ["linear"], ["zoom"],
      a, 0.0,
      b, 1.0,
      c, 1.0,
      d, 0.0,
    ];
  }

  /// Animation played when a marker is tapped / selected. Defaults to
  /// [MarkerSelectionAnimationStyle.none] (highlight only, no motion) — set
  /// it to [MarkerSelectionAnimationStyle.growShrink] or
  /// [MarkerSelectionAnimationStyle.shakeVertical] when the tap animation is
  /// wanted.
  MarkerSelectionAnimationStyle markerSelectionAnimationStyle =
      MarkerSelectionAnimationStyle.none;

  /// Whether tapping a plain marker glides the camera in to it (zoom ~19).
  /// Default `false`: a marker tap just selects + enlarges it in place, with no
  /// camera movement. Pure-polygon taps still fit the polygon, and animal
  /// markers with an enclosure still do their focus-then-pull-back sequence.
  bool zoomToMarkerOnSelect = false;

  Timer? _circleAnimationTimer;
  bool _circleExpanding = true;

  Timer? _iconAnimationTimer;
  final Map<String, double> _markerIconScale = {};
  final Map<String, double> _markerIconShakeDeg = {};
  String? _animatingMarkerId;

  /// How much larger than its resting size a marker renders while it is the
  /// tapped/selected one. Applied as the per-feature `iconScaleFactor` that the
  /// selected-marker layer multiplies into `icon-size`, so it scales every
  /// marker type proportionally. Only used when [markerSelectionAnimationStyle]
  /// is `none` — the animated styles manage `iconScaleFactor` themselves.
  /// Tune here: 1.0 = same size as unselected, 2.0 = double size.
  static const double _kSelectedMarkerRestScale = 1.5;

  /// The marker id currently carrying [_kSelectedMarkerRestScale] in
  /// [_markerIconScale], so it can be reset when the selection changes.
  String? _restScaledMarkerId;

  void _startCircleAnimation(
      MapLibreMapController controller, GeoJsonCircle circle) {
    _circleAnimationTimer?.cancel();
    var circleRadius = circle.properties?['radius'] ?? 5.0;

    // DIAGNOSTIC (temporary — revert once measured): paint the circle once at a
    // static mid-pulse size and skip the periodic timer entirely. Each timer
    // tick's setLayerProperties makes MapLibre re-parse the whole style on the
    // render thread, which showed up as exactly 10 [ParseStyle] logs/sec while
    // standing still. If panning is smooth with this in place, that timer is
    // the cause. Delete this block to restore the pulse.
    const bool kDisableCirclePulseForDiagnostics = true;
    if (kDisableCirclePulseForDiagnostics) {
      const double staticRadius = 12.0;
      const double opacity = 1.0 - ((staticRadius - 5.0) / 15.0) * 0.7;
      controller
          .setLayerProperties(
            _normalCircleLayerId,
            _layerProps(_normalCircleLayerId, (op) => CircleLayerProperties(
              visibility: _visibility(_normalCircleLayerId),
              circleRadius: staticRadius,
              circleColor: '#4CAF50',
              circleOpacity: op(opacity * 0.3),
              circleStrokeWidth: 2.0,
              circleStrokeColor: '#4CAF50',
              circleStrokeOpacity: op(opacity * 0.8),
            )),
          )
          .catchError((_) {});
      return;
    }

    // 20Hz of `setLayerProperties` ran forever once the user marker appeared.
    // Halved to 10Hz with a doubled step, so the pulse keeps its period while
    // sending half the platform-channel calls.
    _circleAnimationTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (_circleExpanding) {
            circleRadius += 1.0;
            if (circleRadius >= 20.0) _circleExpanding = false;
          } else {
            circleRadius -= 1.0;
            if (circleRadius <= 5.0) _circleExpanding = true;
          }

          final double opacity = 1.0 - ((circleRadius - 5.0) / 15.0) * 0.7;

          try {
            await controller.setLayerProperties(
              _normalCircleLayerId,
              _layerProps(_normalCircleLayerId, (op) => CircleLayerProperties(
                visibility: _visibility(_normalCircleLayerId),
                circleRadius: circleRadius,
                circleColor: '#4CAF50',
                circleOpacity: op(opacity * 0.3),
                circleStrokeWidth: 2.0,
                circleStrokeColor: '#4CAF50',
                circleStrokeOpacity: op(opacity * 0.8),
              )),
            );
          } catch (e) {
            // Ignore animation errors
          }
        });
  }

  void stopCircleAnimation() {
    _circleAnimationTimer?.cancel();
    _circleAnimationTimer = null;
  }
  ///
  Future<void> animateMarkerSelection(
      MapLibreMapController controller,
      String markerId, {
        MarkerSelectionAnimationStyle style = MarkerSelectionAnimationStyle.none,
      }) async {
    // `none` means "no tap animation" — nothing to run.
    if (style == MarkerSelectionAnimationStyle.none) return;
    if (_animatingMarkerId != null && _animatingMarkerId != markerId) {
      _markerIconScale[_animatingMarkerId!] = 1.0;
      _markerIconShakeDeg[_animatingMarkerId!] = 0.0;
    }
    _iconAnimationTimer?.cancel();
    _animatingMarkerId = markerId;

    final matches = _symbols.where((m) => m.id == markerId);
    if (matches.isEmpty) return;
    final marker = matches.first;
    if (marker.assetPath == null) return;

    // Awaited: static icon must be confirmed hidden before the animated
    // layer starts drawing, otherwise both are visible for a frame or two.
    // Selection push: skip the settle re-pushes (see setGeoJsonSource) so the
    // tap doesn't drag three more full-collection rebuilds behind it.
    await setGeoJsonSource(controller, _symbols, _clusterSourceId,
        selectedMarkerId: markerId, scheduleSettleRepushes: false);
    await Future.delayed(const Duration(milliseconds: 200)); // let native finish hiding it

    const growShrinkDuration = Duration(milliseconds: 2400);
    const shakeDuration = Duration(milliseconds: 1400);
    final totalDuration = style == MarkerSelectionAnimationStyle.growShrink
        ? growShrinkDuration
        : shakeDuration;

    final startTime = DateTime.now();
    bool pushBusy = false;
    // These scale the *unselected* baseline icon/text size (see
    // _normalIconLayerProps etc.), which was retuned down after previously
    // being halved. peakLabelScale in particular was left at 1.6 through that
    // retune, so tapping a marker grew its label 60% off an already-larger
    // baseline than before — reading as the label "becoming too big" on
    // selection. Trimmed both peaks down to keep the pop noticeable without
    // overshooting.
    const double peakScale = 1.8;
    const double peakLabelScale = 1.3;

    Future<void> pushAnimatedFeature(double scale, double shakeDeg, double labelScale) async {
      if (pushBusy) return;
      pushBusy = true;
      try {
        await controller.setGeoJsonSource(_animatedMarkerSourceId, {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [marker.position.longitude, marker.position.latitude],
              },
              'properties': {
                // Animal/POI photo markers are registered under a
                // content-derived id (see _animalDisplayIconId), not
                // marker.id — using marker.id here for them referenced an
                // image that was never registered, so the animated layer
                // had nothing to draw and the marker visually vanished for
                // the whole tap animation instead of growing/shrinking.
                'icon': _isAnimalMarker(marker)
                    ? _animalDisplayIconId(marker)
                    : marker.id,
                'iconScaleFactor': scale,
                'iconShake': shakeDeg,
                'labelScale': labelScale,
                // Custom-rendering markers bake their label into the icon, so
                // the animated layer must not draw ["get","title"] on top of
                // it — same duplicate-label glitch as the selected layer.
                'title': (marker.textVisibility && !marker.customRendering)
                    ? creator.formatText(marker.title ?? "", TextFormat.smartWrap)
                    : '',
              },
            }
          ],
        });
      } finally {
        pushBusy = false;
      }
    }

    // First animated frame pushed and awaited BEFORE starting the timer, so
    // there's no gap where neither the static nor animated icon is on screen.
    await pushAnimatedFeature(1.0, 0.0, 1.0);

    _iconAnimationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) async {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      final t = (elapsedMs / totalDuration.inMilliseconds).clamp(0.0, 1.0);

      const double growPhaseEnd = 0.45;
      const double shakeStart = 0.55;
      double scale;
      double shakeDeg = 0.0;

      if (style == MarkerSelectionAnimationStyle.growShrink) {
        const p1 = 0.25, p2 = 0.5, p3 = 0.75;
        if (t < p1) {
          scale = 1.0 + (peakScale - 1.0) * (t / p1);
        } else if (t < p2) {
          scale = peakScale + (1.0 - peakScale) * ((t - p1) / (p2 - p1));
        } else if (t < p3) {
          scale = 1.0 + (peakScale - 1.0) * ((t - p2) / (p3 - p2));
        } else {
          scale = peakScale;
        }
      } else {
        if (t < growPhaseEnd) {
          scale = 1.0 + (peakScale - 1.0) * (t / growPhaseEnd);
        } else {
          scale = peakScale;
          if (t >= shakeStart) {
            final settleT = ((t - shakeStart) / (1.0 - shakeStart)).clamp(0.0, 1.0);
            final decay = (1.0 - settleT).clamp(0.0, 1.0);
            shakeDeg = sin(settleT * pi * 6) * 14.0 * decay;
          }
        }
      }

      final growthFraction = ((scale - 1.0) / (peakScale - 1.0)).clamp(0.0, 1.0);
      final labelScale = 1.0 + (peakLabelScale - 1.0) * growthFraction;

      await pushAnimatedFeature(scale, shakeDeg, labelScale);

      if (t >= 1.0) {
        timer.cancel();
        _markerIconScale[markerId] = peakScale;
        _markerIconShakeDeg[markerId] = 0.0;
        await pushAnimatedFeature(peakScale, 0.0, peakLabelScale);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Markers
  // ---------------------------------------------------------------------------

  @override
  Future<void> localizeUser(controller, GeoJsonMarker marker) async {
    if (controller is MapLibreMapController) {
      if (_rotatingSymbols
          .where((e) => e.id.toLowerCase().contains("user"))
          .isNotEmpty) {
        return;
      }
      // dart2js stack capture/format is expensive; native keeps the trace.
      if (!kIsWeb) print("localizeUser ${StackTrace.current}");
      _rotatingSymbols.add(marker);
      await _loadMarkerIcon(controller, marker);
      try {
        await setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
        _startCompassListening(controller, _rotationSourceId);
      } catch (e) {
        print("error localizing user $e");
      }
    }
  }

  @override
  Future<void> addMarker(dynamic controller, GeoJsonMarker marker, {String? selectedMarkerId}) async {
    if (controller is MapLibreMapController) {
      await _loadAndTrackMarkerIcon(controller, marker);
      // Upsert by id — re-adding an existing marker replaces it rather than
      // stacking a duplicate.
      _symbols.removeWhere((m) => m.id == marker.id);
      _symbols.add(marker);
      try {
        setGeoJsonSource(controller, _symbols, _clusterSourceId, selectedMarkerId: selectedMarkerId);
      } catch (e) {
        print("error adding marker $e");
      }
    }
  }

  /// Diagnostic switch: build with `--dart-define=SKIP_MARKERS=true` to render
  /// the venue with NO markers at all — no icon bake, no symbol push, and
  /// nothing for the style-loaded rebake to redo (it iterates `_symbols`, which
  /// stays empty because this returns before the adds).
  ///
  /// Exists to answer one question: is the load time dominated by the marker
  /// bake specifically, or is the whole pipeline slow? Compare time-to-
  /// `fadeOutZoom` with and without it. Not a feature — never ship it true.
  static const bool kSkipMarkersForProfiling =
      bool.fromEnvironment('SKIP_MARKERS');

  @override
  Future<void> addMarkers(controller, List<GeoJsonMarker> markers) async {
    if (kSkipMarkersForProfiling) {
      print('PROFILE: skipping ${markers.length} markers (SKIP_MARKERS=true)');
      return;
    }
    return _addMarkers(controller, markers);
  }

  Future<void> _addMarkers(controller, List<GeoJsonMarker> markers) async {
    // Calls toString() on every marker in the venue, and addMarkers runs 3-4
    // times per render, so this stringifies the whole marker set repeatedly.
    if (!kIsWeb) print("markers $markers");
    if (controller is MapLibreMapController) {
      final animalMarkers = <GeoJsonMarker>[];
      final otherMarkers = <GeoJsonMarker>[];
      for (var marker in markers) {
        if (_isAnimalMarker(marker)) {
          // Animal icons are batch-loaded below (cached/deduped by content,
          // downscaled, loaded in parallel); skip the generic per-marker path.
          animalMarkers.add(marker);
        } else {
          otherMarkers.add(marker);
        }
        // Upsert by id (same as addPolyline does for `_lines`): re-adding a
        // marker that's already present — a re-render, or two overlapping add
        // paths — must replace it, not stack a duplicate that then can't be
        // fully cleared and shows as a doubled icon/label.
        _symbols.removeWhere((m) => m.id == marker.id);
        _symbols.add(marker);
      }
      // Load every non-animal marker's icon concurrently instead of one at a
      // time — _loadMarkerIcon already fetches/decodes/registers everything
      // this loop used to redundantly fetch a second time, so there's no
      // separate per-marker fetch here anymore, just the fan-out await.
      //
      // DO NOT skip, defer or reorder this bake. Three attempts on 2026-08-12
      // each left the map a blank grey canvas with no base map at all:
      //   • push the source first and stream icons in afterwards;
      //   • skip baking while `!_isClusteringEnabled` and let
      //     onStyleLoadedCallback do it — the reasoning looked sound (the push
      //     is dropped anyway, and the style load that follows wipes every
      //     addImage this loop makes) but the style-loaded handler does not
      //     recover it in practice;
      //   • bake only markers inside the viewport, rest on camera idle — this
      //     one WORKED (4.6s → 3ms) and was reverted by request.
      // There is an ordering dependency here that is not yet understood. Fix the
      // style-ready race first (setGeoJsonSource/_updatePolygonSource/
      // _updatePolylineSource silently early-return when their layer flag is
      // false) before touching this again.
      //
      // Cost, for the record: ~4.5s for 189 markers on a Redmi. Each marker's
      // label is painted into its own PNG (UnifiedMarkerCreator keys its cache
      // on the text), so the images are genuinely unique — neither dedup nor
      // concurrency can help, since web is single-threaded.
      // The result is recorded, not discarded: a marker whose image did not
      // register must not be built claiming an icon. See
      // [_iconRegistrationFailed].
      await Future.wait(otherMarkers.map(
          (marker) => _loadAndTrackMarkerIcon(controller, marker)));
      try {
        // Pushed immediately: animal markers reference their paw placeholder
        // (or the shared icon, if it's already loaded from an earlier call)
        // via _animalDisplayIconId, so nothing renders blank while the real
        // photos are still being fetched/decoded.
        setGeoJsonSource(controller, _symbols, _clusterSourceId);
      } catch (e) {
        print("error adding markers $e");
      }
      if (animalMarkers.isNotEmpty) {
        await _batchLoadAnimalIcons(controller, animalMarkers);
      }
    }
  }

  @override
  Future<void> moveUser(controller, String id, MapLocation location, Duration duration) async {
    if (controller is MapLibreMapController) {
      await _animateMarkerToPosition(controller, id, location, duration);
    }
  }

  Future<void> _updateUserLocation(MapLibreMapController controller) async {
    // Animation ticks can land mid style reload, when the source doesn't exist.
    if (!_markerSourcesReady) return;
    final features = _rotatingSymbols
        .map((marker) => {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [
          marker.position.longitude,
          marker.position.latitude
        ],
      },
      'properties': {
        'title': '',
        'id': marker.id,
        if (marker.iconName != null || true) 'icon': marker.id,
        'isPriority': marker.priority ?? false,
        'intractable': marker.properties?["polyId"] != null,
        if (_currentHeading != null) "bearing": _currentHeading!,
      }
    })
        .toList();

    await controller.setGeoJsonSource(_rotationSourceId, {
      "type": "FeatureCollection",
      "features": features,
    });
  }

  /// Incremented on every new animation so an in-flight loop can detect it has
  /// been superseded. Without this, a fix arriving before the previous glide
  /// finishes leaves two loops writing interpolated positions into the *same*
  /// marker object, fighting each other and doubling the channel traffic.
  int _markerAnimationToken = 0;

  /// True while [_animateMarkerToPosition] is running its interpolation loop.
  /// The loop already re-pushes the rotation source every frame with the
  /// latest [_currentHeading] baked in, so the compass throttle
  /// ([_requestRotationPush]) stands down for the duration rather than writing
  /// the *same* source a second time — that duplicate native re-parse +
  /// symbol relayout on the render thread is what makes a concurrent camera
  /// pan stutter during guided navigation.
  bool _userMarkerAnimating = false;

  /// Wall-clock time the puck's GeoJSON source was last pushed to the map.
  /// While the camera is moving (a pinch/pan gesture or the nav follow
  /// animation) the glide below defers its per-frame pushes and leans on this
  /// for a low-rate keepalive, so a manual zoom isn't fighting a full symbol
  /// relayout every frame.
  DateTime _lastPuckSourcePush = DateTime.fromMillisecondsSinceEpoch(0);

  /// Longest the puck may go without a real source push while the camera is in
  /// motion. Its on-screen spot is carried by the camera transform meanwhile,
  /// so this only bounds map-coordinate drift, not visible smoothness.
  static const int _kPuckMovingKeepaliveMs = 500;

  Future<void> _animateMarkerToPosition(
      MapLibreMapController controller,
      String id,
      MapLocation targetLocation,
      Duration duration
      ) async {
    // Wall-clock frame pacing at this target rate. Each frame costs a
    // `setGeoJsonSource` round trip (native source re-parse + symbol relayout
    // on the render thread), so the loop is deliberately kept well under 60fps.
    //
    // The old loop ran a fixed `steps` count and slept a flat 33ms *after*
    // already awaiting the two pushes, so a "300ms" glide actually took
    // 400–800ms on a real device. The next fix then arrived mid-glide, bumped
    // the token, and cut the loop off before it reached the target — the puck
    // was permanently chasing and never settled, which reads as lag + jitter.
    // Pacing off a Stopwatch instead: the glide always finishes in real
    // `duration`, and a device that can't keep up drops frames rather than
    // overrunning.
    //
    // 14fps, not 20: during guided navigation the follow-camera keeps the puck
    // near screen-centre, so its frame-to-frame *screen* travel is small and a
    // slightly lower interpolation rate is invisible — while every frame saved
    // is one fewer full rotation-source push (and render-thread symbol
    // placement pass) fighting the camera pan. The puck layer is also
    // ignore-placement now (see enableMarkerLayers Layer 8) so each of these
    // pushes is far cheaper than before, but fewer still is better.
    const fps = 14;
    const frameMs = 1000 ~/ fps;
    // The accuracy halo barely moves at walking speed; refreshing it at ~10Hz
    // instead of every frame drops a second per-frame source write.
    const circleIntervalMs = 100;
    // Below this total displacement the move is GPS noise, not a step. Snap
    // once instead of spinning a full interpolation loop (25+ source pushes)
    // to crawl the puck a few centimetres — that idle churn was a big part of
    // the "jitter while standing still / walking slowly" report.
    const double minGlideMeters = 0.30;

    final markers =
    _rotatingSymbols.where((s) => s.id.toLowerCase().contains(id));
    final circles =
    _circles.where((c) => c.id.toLowerCase().contains(id));

    if (markers.isEmpty) return;

    final marker = markers.first;
    GeoJsonCircle? circle;
    if (circles.isNotEmpty) circle = circles.first;

    final startLat = marker.position.latitude;
    final startLng = marker.position.longitude;
    final endLat = targetLocation.latitude;
    final endLng = targetLocation.longitude;

    if (startLat == endLat && startLng == endLng) return;

    final token = ++_markerAnimationToken;
    _userMarkerAnimating = true;

    // Tiny hop: skip the loop, place the puck (and halo) on the target once.
    if (_haversineMeters(
            MapLocation(latitude: startLat, longitude: startLng),
            targetLocation) <
        minGlideMeters) {
      try {
        marker.position = targetLocation;
        if (circle != null) circle.position = targetLocation;
        await Future.wait([
          _updateUserLocation(controller),
          if (circle != null) _setGeoJsonCircle(controller),
        ]);
      } finally {
        _releaseUserMarkerAnimation(controller, token);
      }
      return;
    }

    final totalMs = duration.inMilliseconds;
    final stopwatch = Stopwatch()..start();
    int lastCircleMs = -circleIntervalMs;
    bool didFirstPush = false;

    try {
      while (true) {
        if (token != _markerAnimationToken) return;

        final elapsed = stopwatch.elapsedMilliseconds;
        final progress =
            totalMs <= 0 ? 1.0 : (elapsed / totalMs).clamp(0.0, 1.0);
        final currentLat = startLat + (endLat - startLat) * progress;
        final currentLng = startLng + (endLng - startLng) * progress;

        marker.position =
            MapLocation(latitude: currentLat, longitude: currentLng);

        final pushCircle = circle != null &&
            (progress >= 1.0 || elapsed - lastCircleMs >= circleIntervalMs);
        if (pushCircle) {
          circle!.position =
              MapLocation(latitude: currentLat, longitude: currentLng);
          lastCircleMs = elapsed;
        }

        // While the camera is moving — a user pinch/pan, or the guided-nav
        // follow animation — the puck's on-screen position is driven by the
        // camera transform, not by this source. Pushing the source (and paying
        // a render-thread symbol-placement pass) every frame in that window is
        // exactly what makes a hand gesture feel like it lags the fingers.
        // Skip the push while moving; a keepalive still bounds drift, and both
        // the final frame and onCameraIdle land the puck exactly.
        final now = DateTime.now();
        // Always land the first and last frame of a glide, plus a keepalive
        // while the camera keeps moving; everything in between yields to the
        // gesture / follow animation.
        final mustPush = !didFirstPush ||
            progress >= 1.0 ||
            now.difference(_lastPuckSourcePush).inMilliseconds >=
                _kPuckMovingKeepaliveMs;
        if (mustPush || !_cameraMovingNow) {
          didFirstPush = true;
          _lastPuckSourcePush = now;
          // Independent sources — push them concurrently so a frame costs one
          // round trip's worth of wall time, not two chained ones.
          await Future.wait([
            _updateUserLocation(controller),
            if (pushCircle) _setGeoJsonCircle(controller),
          ]);
        }

        if (token != _markerAnimationToken) return;
        // progress == 1.0 means the frame just pushed sits exactly on
        // `targetLocation` (and the circle went with it) — nothing left to do.
        if (progress >= 1.0) break;

        final nextFrame =
            ((stopwatch.elapsedMilliseconds ~/ frameMs) + 1) * frameMs;
        final wait = nextFrame - stopwatch.elapsedMilliseconds;
        if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      }
    } finally {
      _releaseUserMarkerAnimation(controller, token);
    }
  }

  /// Clears [_userMarkerAnimating] when [token] still owns the animation (a
  /// newer glide that superseded this one keeps the flag and releases it
  /// itself), and flushes any compass heading that arrived while the throttle
  /// was standing down for the glide.
  void _releaseUserMarkerAnimation(
      MapLibreMapController controller, int token) {
    if (token != _markerAnimationToken) return;
    _userMarkerAnimating = false;
    if (_pendingCompassHeading != null &&
        _compassThrottleTimer == null &&
        !_compassPushInFlight) {
      _armCompassTimer(controller, _rotationSourceId);
    }
  }

  /// Marker ids whose icon image could not be registered with the style.
  ///
  /// [_loadMarkerIcon] answers this already, but every caller used to discard
  /// its return value, so a marker whose image never uploaded was still built
  /// claiming `icon`. It then sat in an icon layer referencing an image that
  /// does not exist, and MapLibre drew its label with the icon silently
  /// omitted — a marker that renders as a bare floating label.
  ///
  /// Membership is what [_hasUsableIcon] consults, so a failure routes the
  /// marker to the text layer instead. Entries are removed on a later success:
  /// a style reload re-runs registration, and an asset that was broken server
  /// side may have been re-uploaded since.
  final Set<String> _iconRegistrationFailed = {};

  /// Whether [marker] has an icon that is actually drawable right now.
  ///
  /// Animal markers are exempt: they always resolve through
  /// [_animalDisplayIconId], which falls back to the paw placeholder, so they
  /// are never icon-less even before their photo arrives.
  bool _hasUsableIcon(GeoJsonMarker marker) =>
      marker.assetPath != null &&
      (_isAnimalMarker(marker) || !_iconRegistrationFailed.contains(marker.id));

  /// [_loadMarkerIcon] plus bookkeeping for [_iconRegistrationFailed].
  ///
  /// Use this rather than calling [_loadMarkerIcon] directly anywhere the
  /// result feeds a source push, so the feature and the registered images
  /// cannot disagree.
  Future<bool> _loadAndTrackMarkerIcon(
      MapLibreMapController controller, GeoJsonMarker marker) async {
    bool ok = false;
    try {
      ok = await _loadMarkerIcon(controller, marker);
    } catch (e) {
      print('icon registration threw for ${marker.id}: $e');
      ok = false;
    }
    if (ok) {
      _iconRegistrationFailed.remove(marker.id);
    } else if (!_isAnimalMarker(marker)) {
      if (_iconRegistrationFailed.add(marker.id)) {
        // Title first: the id is a composite blob, and the only question worth
        // answering from a log is WHICH landmark on screen has no icon.
        print('NOICON "${marker.title}" asset=${marker.assetPath}');
      }
    }
    return ok;
  }

  /// Set true to log, on every camera idle, what each marker layer is actually
  /// DRAWING and whether any rendered feature references an unregistered image.
  ///
  /// This is what identified the empty-200 icon bug: it distinguishes a feature
  /// filtered out of a layer, one that lost its collision, and one drawn without
  /// its icon — three states that look identical on screen. Off by default: it
  /// runs eight full-viewport queryRenderedFeatures calls per idle.
  static const bool _kDebugLayerCensus = false;

  /// Every image id successfully handed to addImage(). Read by the census.
  /// Compared against the `icon` of each rendered feature to prove whether a
  /// missing icon is an unregistered image or a placement loss.
  final Set<String> _dbgRegisteredImages = {};

  /// TEMPORARY DIAGNOSTIC — remove once the marker-persistence work is closed.
  ///
  /// Counts what each marker layer is actually DRAWING at the current zoom, by
  /// querying rendered features over the whole viewport. Rendered means it
  /// survived collision, so this distinguishes the three things that look
  /// identical on screen: a feature filtered out of a layer, a feature in the
  /// layer that lost its collision, and a feature drawn as a dot instead.
  ///
  /// Also reports which layer is drawing the currently selected marker, which
  /// is the question the source alone cannot answer.
  String _dbgReg(String id) { _dbgRegisteredImages.add(id); return id; }

  Future<void> _debugLayerCensus(
      MapLibreMapController controller, double zoom) async {
    final layerIds = <String>[
      _dotMarkerLayerId,
      _normalTextMarkerLayerId,
      "$_normalIconMarkerLayerId-withSectionId",
      "$_normalIconMarkerLayerId-withoutSectionId",
      _customRenderingMarkerLayerId,
      _fixedMarkerLayerId,
      _priorityMarkerLayerId,
      _selectedMarkerLayerId,
    ];
    // Deliberately far larger than any viewport: queryRenderedFeaturesInRect
    // takes screen coordinates whose scale (logical vs device pixels) differs
    // per platform, and a rect built from _screenSize returned 0 everywhere
    // while markers were plainly drawn. Oversizing removes the unit question.
    final rect = const Rect.fromLTWH(-5000, -5000, 20000, 20000);
    final selectedId = selectedLocation?.marker?.id;
    final counts = <String, int>{};
    String selectedDrawnIn = 'NONE';
    final missingIcons = <String>{};
    for (final id in layerIds) {
      try {
        final feats = await controller.queryRenderedFeaturesInRect(
            rect, <String>[id], null);
        counts[id] = feats.length;
        for (final f in feats) {
          final props = (f is Map) ? f['properties'] : null;
          if (props is! Map) continue;
          if (selectedId != null && props['id'] == selectedId) {
            selectedDrawnIn = id;
          }
          // The question this whole diagnostic exists to answer: is the icon
          // image this feature asks for actually registered right now?
          final iconId = props['icon'];
          if (iconId is String && !_dbgRegisteredImages.contains(iconId)) {
            missingIcons.add(iconId);
          }
        }
      } catch (e) {
        counts[id] = -1; // layer absent right now
      }
    }
    final summary = counts.entries
        .map((e) =>
            '${e.key.replaceAll("-markers-layer", "").replaceAll("-marker-layer", "")}=${e.value}')
        .join(' ');
    print('CENSUS z=${zoom.toStringAsFixed(2)} $summary '
        'selected=${selectedId ?? "-"} drawnIn=$selectedDrawnIn '
        'registeredImages=${_dbgRegisteredImages.length} '
        'MISSING=${missingIcons.length}${missingIcons.isEmpty ? "" : " ${missingIcons.take(4).toList()}"}');
  }

  /// Reads the numeric priority from a marker's properties.
  /// Returns 0 if the property is absent or not a number.
  int _markerPriority(GeoJsonMarker marker) {
    final raw = marker.properties?['priority'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  /// The per-layer base offset of the full marker's [symbolSortKey] for a
  /// collision-participating marker. Mirrors the layer filters/bases in
  /// [enableMarkerLayers] (text=0, fixed/bearing=1000, customRendering=1500,
  /// icon-withoutSectionId=2000, icon-withSectionId=3000). Used by the dot
  /// layer so a feature's dot sorts right after its own full marker.
  ///
  /// customRendering sits ahead of the plain icon layers (see the "Zoo fix"
  /// in [_refreshMarkerLayerMinZooms]) so a zoo's animal photo composites —
  /// the content the map actually exists to show — don't routinely lose
  /// collisions to incidental amenity icons and fall back to their paw dot.
  /// It still loses to text/fixed, which are wayfinding furniture rather
  /// than content.
  int _collisionBase({
    required bool hasIcon,
    required double bearing,
    required bool customRendering,
    required bool sectionId,
  }) {
    if (bearing != 0.0) return 1000; // Layer 4: fixed/bearing
    if (!hasIcon) return 0; // Layer 1: text-only
    if (customRendering) return 1500; // Layer 3: custom rendering
    return sectionId ? 3000 : 2000; // Layer 2 / 2b: icon markers
  }

  Future<void> setGeoJsonSource(
      dynamic controller,
      List<GeoJsonMarker> symbols,
      String sourceID,
      {String? selectedMarkerId,
      // The 500ms/2s/5s "settle" re-pushes below exist purely to recover
      // markers that fail to draw during heavy *startup* load. A marker tap
      // (selectLocation / animateMarkerSelection / deSelectLocation) flips one
      // feature's `isSelected` and re-pushes the whole collection — by then
      // every marker is already on screen, so scheduling three more full
      // rebuilds just janks the map for ~5s and makes the tap feel slow to
      // register. Pass false from the selection paths to push once and skip
      // the settle machinery (any startup timers already pending keep running).
      bool scheduleSettleRepushes = true}
      ) async {
    if (controller is MapLibreMapController) {
      if (!_isClusteringEnabled) {
        print("Clustering not enabled yet");
        return;
      }

      // The type filter belongs to the landmark cluster source only. The
      // rotation source carries the user puck, which is not host content and
      // must never be filtered away.
      final visible = sourceID == _clusterSourceId
          ? symbols.where(_passesMarkerTypeFilter).toList(growable: false)
          : symbols;

      // Diagnostic for the type filter. Deliberately does NOT report
      // _bakedIconCache/_smallIconIds: plain icon markers register their image
      // through a direct addImage() that never touches those maps, so a "not
      // baked" reading there means nothing for them.
      if (sourceID == _clusterSourceId && _markerTypeFilter != null) {
        print('marker type filter: kept ${visible.length}/${symbols.length}'
            ' types=${_markerTypeFilter!.join(",")}');
      }

      // Named rather than inlined into the push below: the settle re-pushes
      // rebuild features from live marker/icon state instead of resending a
      // stale snapshot, so they need the same builder.
      List<Map<String, dynamic>> buildFeatures(List<GeoJsonMarker> list) {
        // Denominator for the per-feature sort bias below. Guarded so a single
        // marker cannot divide by zero.
        final biasDenominator = list.isEmpty ? 1 : list.length;

        return list.indexed.map((entry) {
          final (index, marker) = entry;
          // The tap animation scales and rotates about the icon centre, so the
          // marker being animated is anchored centrally for its duration.
          final bool isAnimatingThisMarker = marker.id == _animatingMarkerId;
          final anchor = isAnimatingThisMarker
              ? "center"
              : (marker.anchor?.dx == 0.5 && marker.anchor?.dy == 0.5)
                  ? "center"
                  : "bottom";
          bool hasSectionId = (marker.properties?['sectionId'] != null && marker.properties?['sectionId'].isNotEmpty);
          double? entryDirection;
          if(marker.id.contains("_entryDirection") && marker.properties?['entryDirection'] != null){
            entryDirection = (marker.properties?['entryDirection'] as num).toDouble();
          }

          // Effective bearing matches the 'bearing' property written below, after
          // the entryDirection override. A truthy (non-zero) bearing routes a
          // marker into the fixed/bearing layer.
          final double effectiveBearing = entryDirection ??
              (marker.compassBasedRotation
                  ? 0.0
                  : ((marker.properties?["bearing"] ?? 0.0) as num).toDouble());

          return {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [
                marker.position.longitude,
                marker.position.latitude
              ],
            },
            'properties': {
              'title': marker.textVisibility
                  ? creator.formatText(
                  marker.title ?? "", TextFormat.smartWrap)
                  : '',
              'id': marker.id,
              // _hasUsableIcon, not `assetPath != null`: an asset path the server
              // never served leaves the image unregistered, and claiming `icon`
              // anyway puts the feature in an icon layer pointing at nothing —
              // MapLibre then draws the label with no icon. Dropping the property
              // routes it to the text layer, which is what it actually is.
              if (_hasUsableIcon(marker))
                'icon': _isAnimalMarker(marker)
                    ? _animalDisplayIconId(marker)
                    : marker.id,
              // Image id for the zoomed-out (label-less) variant. Shared between
              // every marker with the same photo and pill geometry, so ~190
              // byte-identical uploads collapse to one per distinct photo.
              // Animals are absent from the map and fall through to the
              // '<icon>-small' branch of the layer expression — their ids are
              // already content-keyed.
              if (marker.assetPath != null && _smallIconIds[marker.id] != null)
                'smallIcon': _smallIconIds[marker.id],
              'isPriority': marker.priority ?? false,
              'intractable': marker.properties?["polyId"] != null,
              'bearing': marker.compassBasedRotation
                  ? 0.0
                  : (marker.properties?["bearing"] ?? 0.0),
              'iconAnchor': anchor,
              'section': marker.properties?['type'] == "Section",
              'subSection': marker.properties?['type'] == "Sub Section",
              'sectionId': hasSectionId,
              'boundary':marker.properties?["type"]=="Boundary",
              'isSelected': marker.id == selectedMarkerId,
              'customRendering':marker.customRendering,
              // POI markers bake a separate '<id>-selected' highlight image; this
              // flag tells the selected-marker layer to use it.
              'hasSelectedIcon': RenderingTheme.current.isMuseum &&
                  marker.properties?['poiRef'] != null,
              'overlapOverride': _overlapOverrideIds.any((id) => marker.id.contains(id)),
              // Numeric priority used by symbolSortKey: higher value → higher sort
              // precedence (wins collision). Negated inside the layer expression.
              _kPriorityKey: _markerPriority(marker),
              'iconScaleFactor': _markerIconScale[marker.id] ?? 1.0,
              'iconShake': _markerIconShakeDeg[marker.id] ?? 0.0,
              'isAnimating': marker.id == _animatingMarkerId,
              // Stable per-feature tiebreaker for symbolSortKey.
              //
              // Without it the sort key is the priority term alone, and this
              // venue's data sets priority to 0 on every marker — so every
              // feature in a layer ties on the exact same key. MapLibre then
              // places tied symbols in tile-arrival order, which is not stable
              // across the tile regeneration a zoom causes, so a collision never
              // resolves as "this marker loses": the whole tied layer is one
              // undifferentiated block and its outcome flips together. That is
              // the markers vanishing and reappearing as a group.
              //
              // Normalised by the feature count so the bias stays under 0.5 at
              // any venue size. That bound is load-bearing: the dot layer sorts
              // at `collisionBase + 0.6`, so keeping every bias below 0.6 means
              // each full marker still sorts ahead of every dot and the
              // marker → dot cascade is untouched.
              //
              // Index order is arbitrary but STABLE, which is the property that
              // matters here. To make the winner meaningful rather than merely
              // deterministic, set real `priority` values in the venue data —
              // the priority term already outranks this bias.
              'sortBias': index / biasDenominator * 0.5,
              // Per-feature base of the full marker's symbolSortKey. The dot layer
              // reuses this (+ a fractional offset) so each feature's dot is
              // placed right after its own full marker in the global collision
              // pass, yielding the marker → dot → hidden fallback cascade.
              'collisionBase': _collisionBase(
                // Must use the same predicate as the `icon` property above, or a
                // marker lands in the text layer while its collisionBase claims
                // it is an icon marker — the dot would then sort against a base
                // no layer is using and the marker → dot cascade breaks for it.
                hasIcon: _hasUsableIcon(marker),
                bearing: effectiveBearing,
                customRendering: marker.customRendering,
                sectionId: hasSectionId,
              ),
              // Image id for this marker's collision-fallback dot. Per-marker dots
              // are registered under their asset path; null falls back to the
              // shared default room dot.
              'dotIcon': marker.dotAssetPath ?? _kDotImageId,
              if(entryDirection != null)'bearing':entryDirection,
              // Bumped on every push, including retries that repeat otherwise
              // identical data (see the self-heal comment below) — without
              // this, a byte-identical resend risks being deduplicated by the
              // native GeoJsonSource before it ever reaches layout.
              '_rev': DateTime.now().microsecondsSinceEpoch,
            }
          };
        }).toList();
      }

      final features = buildFeatures(visible);


      await controller.setGeoJsonSource(
        sourceID,
        {
          "type": "FeatureCollection",
          "features": features,
        },
      );

      // Self-heal: a fresh setGeoJson call is what makes MapLibre 0.26.2
      // redo symbol layout/placement for a source — it's what tapping a
      // marker triggers today via selectLocation (it flips 'isSelected' on
      // one feature), and it's why that "fixes" markers that failed to draw
      // on their first push. A single re-push shortly after landed wasn't
      // enough on real devices doing heavy startup work (venue GeoJSON
      // parsing, furniture extrusion, pattern generation, marker-icon
      // compositing all run synchronously on the UI isolate and have been
      // observed dropping 200+ frames), which can delay when the native
      // side actually catches up to process queued addImage()/setGeoJson()
      // calls well past a few hundred milliseconds. Retry at several
      // increasing delays so at least one both lands after that backlog
      // clears and is guaranteed to force a real relayout.
      //
      // Rebuilt from scratch each tick (not a resend of the features pushed
      // above) rather than just bumping '_rev' on stale features:
      // animal markers push their paw-dot placeholder immediately and load
      // the real photo icon asynchronously afterwards (registration is a
      // network fetch + decode + addImage, which can itself outlast
      // addImage's own STYLE_NOT_READY retry budget under the same startup
      // load). A resend of the stale snapshot would just keep re-affirming
      // the placeholder forever. Re-attempting any still-unloaded animal
      // icon here, then rebuilding features from live marker/icon state,
      // means a slow or once-failed photo load still gets picked up and
      // rendered instead of being stuck on the placeholder permanently.
      if (scheduleSettleRepushes) {
        for (final timer in _settleTimers[sourceID] ?? const <Timer>[]) {
          timer.cancel();
        }
        _settleTimers[sourceID] = [
          for (final delay in const [
            Duration(milliseconds: 500),
            Duration(seconds: 2),
            Duration(seconds: 5),
          ])
            Timer(delay, () async {
              if (!_isClusteringEnabled) return;
              print(
                  "settle re-push firing for $sourceID after ${delay.inMilliseconds}ms");
              try {
                // Snapshot before the loop: `symbols` is usually the live
                // `_symbols` field, and this loop awaits per-marker icon
                // loads across several event-loop turns — if another
                // addMarkers()/removeMarker() call mutates `_symbols` while
                // this is in flight, iterating the live list throws
                // "Concurrent modification during iteration". A frozen copy
                // reflects the state at fire time and stays safe to iterate.
                final snapshot = List<GeoJsonMarker>.of(symbols);
                for (final marker in snapshot) {
                  if (_isAnimalMarker(marker) &&
                      !_registeredSmallIconIds.contains(
                          _animalSmallImageId(marker))) {
                    try {
                      // Load-path variant only (the label-less bake). The
                      // labelled composite is deferred to camera idle at label
                      // zoom via _ensureLabelledAnimalIcons.
                      await _loadAnimalSmallIcon(controller, marker);
                    } catch (e) {
                      print(
                          "settle re-push animal icon retry failed for ${marker.id}: $e");
                    }
                  }
                  // Labelled (Phase B) composite: only retry once the camera
                  // has actually reached label zoom at least once — baking it
                  // any earlier just spends network/CPU on a composite the
                  // layer won't reference yet (see _kLabelZoomThreshold).
                  // _ensureLabelledAnimalIcons itself only ever fires once
                  // per style (_labelledAnimalsStarted guard) and does not
                  // retry markers whose fetch/bake failed on that one pass —
                  // this is their only other chance to pick the photo up.
                  if (_isAnimalMarker(marker) &&
                      _labelledAnimalsStarted &&
                      !_loadedAnimalIcons.contains(_animalIconKey(marker))) {
                    try {
                      await _loadAnimalLabelledIcon(controller, marker);
                    } catch (e) {
                      print("settle re-push labelled animal icon retry "
                          "failed for ${marker.id}: $e");
                    }
                  }
                }
                // Re-filtered, not just rebuilt: the type filter may have
                // changed since this timer was armed, and a re-push must not
                // resurrect a marker the host has since hidden.
                final refreshed = sourceID == _clusterSourceId
                    ? snapshot
                        .where(_passesMarkerTypeFilter)
                        .toList(growable: false)
                    : snapshot;
                await controller.setGeoJsonSource(sourceID, {
                  "type": "FeatureCollection",
                  "features": buildFeatures(refreshed),
                });
              } catch (e) {
                print("settle re-push for $sourceID failed: $e");
              }
            }),
        ];
      }
    }
  }

  StreamSubscription<CompassEvent>? _compassSub;
  double? _currentHeading;

  /// Externally supplied heading that stands in for the device compass while
  /// set. See [setHeadingOverride].
  double? _headingOverride;

  @override
  Future<void> setHeadingOverride(dynamic controller, double? heading) async {
    _headingOverride = heading;
    // Written through to _currentHeading so the *position* repaint
    // (_updateUserLocation, which runs on every glide frame) carries the same
    // value the compass path would have written. Without this a move would push
    // a feature bearing the last live heading and undo the override.
    if (heading != null) _currentHeading = heading;
    if (controller is! MapLibreMapController) return;

    if (heading == null) {
      // Override cleared — drop any heading still queued from the override and
      // repaint once so control hands straight back to the live compass
      // without waiting for its next event.
      _compassThrottleTimer?.cancel();
      _compassThrottleTimer = null;
      _pendingCompassHeading = null;
      await _updateUserLocation(controller);
      return;
    }

    // The navigation SDK feeds a fused GPS/sensor heading here, typically on
    // every location fix (~1Hz) and faster mid-turn. Pushing the rotation
    // source synchronously on every call re-parses it and relayouts symbols on
    // the render thread while the follow-camera is also animating — that
    // contention is the lag/jitter seen only during guided navigation (this
    // app drives heading from the throttled compass listener instead, which is
    // why it doesn't show there). Route through the same coalescing throttle
    // the live compass uses: caps at ~10Hz, drops sub-2° changes, and stands
    // down entirely while a user-marker glide is repainting the source itself.
    _requestRotationPush(controller, _rotationSourceId, heading);
  }

  void _startCompassListening(
      MapLibreMapController controller, String sourceID) {
    if (_compassSub != null) return;
    _compassSub = HeadingSource.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      // Ignore the sensor rather than cancelling the subscription. There *is*
      // a restart path — removeMarker() cancels and nulls _compassSub when the
      // puck goes, and _startCompassListening re-subscribes when it comes back
      // — but it only runs on a marker remove/add cycle. Cancelling here would
      // leave the puck frozen from the moment the override is cleared until the
      // next floor change happens to rebuild the marker.
      if (_headingOverride != null) return;
      _currentHeading = heading;
      // A style reload wipes the rotation source; compass events keep arriving
      // during the rebuild, and pushing then NPEs natively on a null source.
      if (!_markerSourcesReady) return;
      // ANR guard: the compass fires 20–50Hz and each setGeoJsonSource makes
      // MapLibre re-parse the source + relayout on the render thread while
      // holding the native map lock. Pushing on every event backed the UI
      // thread up past the ANR threshold. Coalesce instead — see
      // [_requestRotationPush] / [_flushRotationPush].
      _requestRotationPush(controller, sourceID, heading);
    });
  }

  // ANR throttle for the compass-driven rotation source. Tunables: at most one
  // native push every 100ms (~10Hz ceiling), and ignore heading changes below
  // 2° so a stationary device sends nothing at all.
  static const int _kCompassMinPushMs = 100;
  static const double _kCompassMinHeadingDeg = 2.0;

  Timer? _compassThrottleTimer;
  double? _pendingCompassHeading;
  double? _lastPushedHeading;
  DateTime _lastCompassPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _compassPushInFlight = false;

  /// Smallest angular difference between two headings, in degrees (0..180),
  /// accounting for the 360°→0° wrap.
  double _headingDelta(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  /// Records the newest heading and arms a single coalescing timer. Runs on
  /// every compass event, so it stays cheap and allocation-free.
  void _requestRotationPush(
      MapLibreMapController controller, String sourceID, double heading) {
    _pendingCompassHeading = heading;
    // A user-marker glide is running. It already re-pushes this exact source
    // every frame with `_currentHeading` (updated above by the compass
    // listener) baked in, so a second writer here just doubles the native
    // relayout load — and the glide only runs during navigation, which is
    // exactly when the camera is also panning. Stand down; the glide's
    // finally-block flushes whatever heading is pending when it ends.
    if (_userMarkerAnimating) return;
    // A flush is already scheduled or running; it will pick up the value above.
    if (_compassThrottleTimer != null || _compassPushInFlight) return;
    _armCompassTimer(controller, sourceID);
  }

  void _armCompassTimer(MapLibreMapController controller, String sourceID) {
    final sinceLast =
        DateTime.now().difference(_lastCompassPush).inMilliseconds;
    final wait =
        sinceLast >= _kCompassMinPushMs ? 0 : _kCompassMinPushMs - sinceLast;
    _compassThrottleTimer = Timer(Duration(milliseconds: wait), () {
      _compassThrottleTimer = null;
      _flushRotationPush(controller, sourceID);
    });
  }

  /// Pushes the latest pending heading to the rotation source, at most one in
  /// flight at a time. Re-arms itself if newer events arrived mid-push so the
  /// final orientation is never dropped.
  Future<void> _flushRotationPush(
      MapLibreMapController controller, String sourceID) async {
    final heading = _pendingCompassHeading;
    if (heading == null) return;

    // A glide started after this flush was armed. Leave `_pendingCompassHeading`
    // set and bail: the glide is repainting the source itself, and its
    // finally-block re-arms this flush once it releases.
    if (_userMarkerAnimating) return;

    // The camera is mid-gesture / mid-follow-animation. A rotation-only source
    // rewrite (with its render-thread symbol placement pass) here competes with
    // the pan for frames. Hold the heading and retry after a fixed delay — the
    // puck's visible orientation doesn't meaningfully change over the hold, and
    // the fixed delay avoids a 0ms re-arm loop while the camera keeps moving.
    if (_cameraMovingNow) {
      _compassThrottleTimer?.cancel();
      _compassThrottleTimer = Timer(const Duration(milliseconds: 150), () {
        _compassThrottleTimer = null;
        _flushRotationPush(controller, sourceID);
      });
      return;
    }

    // Sub-threshold jitter: not worth a full source rewrite.
    final last = _lastPushedHeading;
    if (last != null && _headingDelta(heading, last) < _kCompassMinHeadingDeg) {
      _pendingCompassHeading = null;
      return;
    }
    // Same readiness guards the per-event path used to apply inline.
    if (!_markerSourcesReady || controller.cameraPosition == null) {
      _pendingCompassHeading = null;
      return;
    }

    _pendingCompassHeading = null;
    _compassPushInFlight = true;
    _lastCompassPush = DateTime.now();
    _lastPushedHeading = heading;

    final features = _rotatingSymbols
        .map((marker) => {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [
                  marker.position.longitude,
                  marker.position.latitude
                ],
              },
              'properties': {
                'title': '',
                'id': marker.id,
                if (marker.iconName != null || true) 'icon': marker.id,
                'isPriority': marker.priority ?? false,
                'intractable': marker.properties?["polyId"] != null,
                if (marker.compassBasedRotation) "bearing": heading,
              }
            })
        .toList();

    try {
      await controller.setGeoJsonSource(sourceID, {
        "type": "FeatureCollection",
        "features": features,
      });
    } catch (e) {
      // Lost the race with a style reload / map teardown: the next compass
      // event repaints once the source is back.
      print("compass setGeoJsonSource skipped: $e");
    } finally {
      _compassPushInFlight = false;
      if (_pendingCompassHeading != null) {
        _armCompassTimer(controller, sourceID);
      }
    }
  }

  /// Temporarily force icon/text overlap ON for the given marker ids so they
  /// are never hidden by collision. Reverse with [clearMarkersAllowOverlap] or
  /// [clearAllMarkersAllowOverlap].
  @override
  Future<void> setMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {
    if (controller is! MapLibreMapController) return;
    if (markerIds.isEmpty) return;
    _overlapOverrideIds.addAll(markerIds);
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  /// Turn the temporary overlap override back OFF for the given marker ids.
  @override
  Future<void> clearMarkersAllowOverlap(dynamic controller, List<String> markerIds) async {
    if (controller is! MapLibreMapController) return;
    if (markerIds.isEmpty) return;
    _overlapOverrideIds.removeAll(markerIds);
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  /// Turn the temporary overlap override OFF for every marker it was set on.
  @override
  Future<void> clearAllMarkersAllowOverlap(dynamic controller) async {
    if (controller is! MapLibreMapController) return;
    if (_overlapOverrideIds.isEmpty) return;
    _overlapOverrideIds.clear();
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  /// Whether venue content is drawn desaturated.
  ///
  /// Applied where colours are WRITTEN INTO THE SOURCE rather than as a layer
  /// paint property: MapLibre has no saturation control for fill/line layers
  /// (only raster ones), and every polygon here takes its colour from a
  /// per-feature `fillColor`, so the only place to intervene is the push.
  bool _greyscale = false;

  /// [color] as the current mode wants it drawn.
  Color _shade(Color color) =>
      _greyscale ? RenderingUtilities.toGreyscale(color) : color;

  /// [hex] as the current mode wants it drawn.
  ///
  /// Polylines carry their colour as a hex string straight from host data
  /// rather than as a parsed Color, so this parses, shades and re-encodes.
  /// Anything unparseable is passed through untouched — a bad colour should
  /// render as it always did, not vanish.
  String _shadeHex(String hex) {
    if (!_greyscale) return hex;
    try {
      final shaded = RenderingUtilities.toGreyscale(
          RenderingUtilities.hexToColor(hex));
      return '#${RenderingUtilities.colorToMapplsHex(shaded)}';
    } catch (_) {
      return hex;
    }
  }

  /// Whether markers and the venue boundary ramp their opacity across a zoom
  /// window, or simply draw at full strength wherever they draw at all.
  ///
  /// The ramps themselves are computed per venue from its fit zoom
  /// ([_refreshPatchAboveOpacity], [_refreshMarkerLayerMinZooms]); this only
  /// decides whether those interpolate expressions are emitted or collapsed to a
  /// flat value. Zoom RANGES are left alone — the venue label still stops
  /// drawing above its maxzoom, it just pops instead of fading.
  bool _fadeEnabled = true;

  /// [ramp] while the zoom fade is on; a flat, fully-opaque value when it is
  /// off.
  ///
  /// Takes a closure rather than a value so the ramp is not built when it is
  /// about to be discarded, and applies `op` itself on the off branch so both
  /// call-site shapes collapse to the same `op(1.0)`. Those shapes differ on
  /// purpose: where `op` sits INSIDE a ramp an opacity override lowers the
  /// ramp's peak, and where it wraps the whole expression an override replaces
  /// the ramp outright.
  Object? _fadeRamp(_OpacityResolver op, Object? Function() ramp) =>
      _fadeEnabled ? ramp() : op(1.0);

  /// Turn the zoom fade ramp on markers and the venue boundary on or off.
  ///
  /// Mirrors [setGreyscale]: a single global switch, applied by recomputing the
  /// curves rather than by storing a second set of them.
  @override
  Future<void> setFade(dynamic controller, bool enabled) async {
    if (controller is! MapLibreMapController) return;
    if (_fadeEnabled == enabled) return;
    _fadeEnabled = enabled;
    // Rebuilds the boundary/section curves AND, at its tail, the marker ones —
    // calling _refreshMarkerLayerMinZooms alone would leave the venue label and
    // section polygons still fading. Cheap to re-run: it no-ops until the marker
    // layers exist, and the venue's fit zoom is recomputed from cached polygons.
    await _refreshPatchAboveOpacity(controller, screenSize: _screenSize);
  }

  /// Draw the map in greyscale, or back in full colour.
  ///
  /// Covers the basemap (via raster-saturation), polygons and polylines. Marker
  /// icons are NOT covered: each is a PNG composited at load time and would
  /// have to be re-baked, which costs seconds for a large venue.
  @override
  Future<void> setGreyscale(dynamic controller, bool enabled) async {
    if (controller is! MapLibreMapController) return;
    if (_greyscale == enabled) return;
    _greyscale = enabled;

    // The basemap is a raster layer, which DOES have a saturation property —
    // the one place this can be done without rewriting data.
    try {
      await _pushLayerProperties(controller,
        _baseMapRasterLayerId,
        RasterLayerProperties(rasterSaturation: enabled ? -1.0 : 0.0),
      );
    } catch (e) {
      print('setGreyscale: basemap saturation failed: $e');
    }

    // Re-push whatever carries colour, so the new shade is written in.
    if (_polygons.isNotEmpty) await _updatePolygonSource(controller);
    if (_lines.isNotEmpty) await _updatePolylineSource(controller);
  }

  /// Whether [marker] survives the active [_markerTypeFilter].
  ///
  /// Source/destination pins are exempt: they are navigation endpoints, and a
  /// content filter must not be able to hide where the user is walking to.
  /// Everything else is a strict allowlist — a marker carrying no type at all is
  /// filtered out too, since it is by definition not one of the types asked for.
  /// Cache of whole-word matchers, one per filter value.
  ///
  /// Rebuilt rarely (only when a host changes the filter) but consulted once
  /// per marker per push, so the RegExp is worth keeping.
  final Map<String, RegExp> _wholeWordCache = {};

  RegExp _wholeWord(String wanted) => _wholeWordCache.putIfAbsent(
      wanted,
      () => RegExp('(?<![a-z0-9])${RegExp.escape(wanted)}(?![a-z0-9])'));

  bool _passesMarkerTypeFilter(GeoJsonMarker marker) {
    final filter = _markerTypeFilter;
    if (filter == null) return true;
    if (marker.priority == true) return true;
    final raw = RenderingUtilities.rawLandmarkType(marker.properties);
    if (raw == null) return false;
    final normalised = RenderingUtilities.normaliseLandmarkType(raw);
    // Contained as a WHOLE WORD, not a bare substring. Venues spell the same
    // concept differently ('Male Washroom' vs 'Accessible Washroom'), so
    // MarkerTypes exposes broad values like 'washroom' that a host can use
    // without knowing this venue's wording — and an exact spelling from
    // availableMarkerTypes still matches, since a string contains itself.
    //
    // The word boundaries are load-bearing. Plain `contains` makes
    // 'male washroom' match "FEmale washroom" and 'room' match "washROOM", so
    // filtering to male washrooms silently returned the female ones too.
    return filter.any((wanted) => _wholeWord(wanted).hasMatch(normalised));
  }

  /// Every landmark type present in the loaded venue, with counts.
  @override
  List<MarkerTypeInfo> availableMarkerTypes() {
    // Keyed by the normalised form so 'Male Washroom' and 'male washroom' are
    // one entry, while the first spelling seen is what the host displays.
    final byKey = <String, MarkerTypeInfo>{};
    for (final marker in _symbols) {
      final raw = RenderingUtilities.rawLandmarkType(marker.properties);
      if (raw == null || raw.trim().isEmpty) continue;
      final key = RenderingUtilities.normaliseLandmarkType(raw);
      final existing = byKey[key];
      byKey[key] = MarkerTypeInfo(
        rawType: existing?.rawType ?? raw,
        assetType: existing?.assetType ??
            RenderingUtilities.getAssetForLandmark(marker.properties),
        count: (existing?.count ?? 0) + 1,
      );
    }
    final types = byKey.values.toList();
    // Commonest first: a host rendering chips wants the useful ones up front.
    types.sort((a, b) => b.count != a.count
        ? b.count.compareTo(a.count)
        : a.rawType.toLowerCase().compareTo(b.rawType.toLowerCase()));
    return List.unmodifiable(types);
  }

  /// Draw only the markers whose raw landmark type is in [types]; null draws all.
  @override
  Future<void> setMarkerTypeFilter(
      dynamic controller, Set<String>? types) async {
    if (controller is! MapLibreMapController) return;
    // An empty set means "show nothing", which is a legitimate request and
    // deliberately not folded into null ("show everything").
    _markerTypeFilter = types == null
        ? null
        : types.map(RenderingUtilities.normaliseLandmarkType).toSet();
    await setGeoJsonSource(controller, _symbols, _clusterSourceId);
  }

  @override
  Future<void> removeMarker(dynamic controller, String markerId) async {
    if (controller is MapLibreMapController) {
      try {
        _symbols.removeWhere(
                (marker) => marker.id.toLowerCase().contains(markerId));
        _rotatingSymbols.forEach((symbol) {
          print("_rotatingSymbols ${symbol.id}");
        });
        if (_rotatingSymbols
            .where((m) => m.id.toLowerCase().contains(markerId))
            .isNotEmpty) {
          _compassSub?.cancel();
          _compassSub = null;
          _compassThrottleTimer?.cancel();
          _compassThrottleTimer = null;
          _pendingCompassHeading = null;
        }
        _rotatingSymbols.removeWhere(
                (marker) => marker.id.toLowerCase().contains(markerId));

        setGeoJsonSource(controller, _symbols, _clusterSourceId);
        setGeoJsonSource(controller, _rotatingSymbols, _rotationSourceId);
      } catch (e) {
        print('Error removing marker: $e');
      }
    }
  }

  @override
  Future<void> clearMarkers(dynamic controller) async {
    if (controller is MapLibreMapController) {
      try {
        _symbols.clear();
        // Per-marker state only. The content-keyed small icons stay: their ids
        // are still registered with the live style and their bytes are reusable
        // by the next render, which is the whole point of keying by content.
        _smallIconIds.clear();
        _bakedIconCache.clear();
        await setGeoJsonSource(controller, [], _clusterSourceId);
        await setGeoJsonSource(controller, [], _rotationSourceId);
      } catch (e) {
        print('Error clearing markers: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Polygons
  // ---------------------------------------------------------------------------

  @override
  Future<void> addPolygon(dynamic controller, GeoJsonPolygon polygon) async {
    if (controller is MapLibreMapController) {
      try {
        _polygons.add(polygon);
        await RenderingUtilities.registerLandmarkPattern(controller, polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygon: $e');
      }
    }
  }

  @override
  Future<void> addSection(controller, GeoJsonPolygon polygon) async {
    if (controller is MapLibreMapController) {
      try {
        _polygons.add(polygon);
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding section polygon: $e');
      }
    }
  }

  @override
  Future<void> addPolygons(
      dynamic controller, List<GeoJsonPolygon> polygons) async {
    if (controller is MapLibreMapController) {
      try {
        _polygons.addAll(polygons);
        await Future.wait(
          polygons.map((polygon) =>
              RenderingUtilities.registerLandmarkPattern(controller, polygon)
          ),
        );
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error adding polygons: $e');
      }
    }
  }

  Future<void> _updatePolygonSource(
      MapLibreMapController controller, {
        Set<String>? selectPolygonIds,
      }) async {
    if (!_isPolygonLayersEnabled) {
      return;
    }

    final features = _polygons.map((polygon) {
      final String? rawType =
          polygon.properties?["type"] ?? polygon.properties?["polygonType"];
      final String? type = rawType?.toLowerCase();

      final String? fillColorHex = polygon.properties?["fillColor"];
      final String? strokeColorHex = polygon.properties?["strokeColor"];
      final String? fillColorSecondaryHex=polygon.properties?["fillColorSecondary"];

      final Color fillColor = (fillColorHex != null &&
          fillColorHex != "undefined" &&
          fillColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColor"] ??
          Colors.white;

      final Color strokeColor = (strokeColorHex != null &&
          strokeColorHex != "undefined" &&
          strokeColorHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(strokeColorHex)
          : RenderingUtilities.polygonColorMap[type]?["strokeColor"] ??
          fillColor;


      final Color fillColorSecondary = (fillColorSecondaryHex != null &&
          fillColorSecondaryHex != "undefined" &&
          fillColorSecondaryHex.isNotEmpty)
          ? RenderingUtilities.hexToColor(fillColorSecondaryHex)
          : RenderingUtilities.polygonColorMap[type]?["fillColorSecondary"] ??
          const Color(0xffD3D3D3);

      final coordinates =
      polygon.points.map((p) => [p.longitude, p.latitude]).toList();

      double? baseHeight;
      double? height;
      bool pattern=false;

      if (polygon.properties?['baseHeight'] != null && polygon.properties?['baseHeight'].isNotEmpty && polygon.properties?['baseHeight'].toLowerCase() != "undefined") {
        baseHeight = double.tryParse(polygon.properties?['baseHeight']);
      }

      if (polygon.properties?['height'] != null && polygon.properties?['height'].isNotEmpty && polygon.properties?['height'].toLowerCase() != "undefined") {
        height = double.tryParse(polygon.properties?['height']);
        // If baseHeight exists, add it to height
        if (baseHeight != null && height != null) {
          height = height + baseHeight;
        }
      }

      if(polygon.properties?['pattern']!=null && polygon.properties?['pattern'].isNotEmpty && polygon.properties?['patternSize']!=null && polygon.properties?['patternSpacing']!=null && polygon.properties?['patternRotation']!=null){
        pattern=true;
      }

      return {
        'type': 'Feature',
        'id': polygon.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [coordinates],
        },
        'properties': {
          'id': polygon.id,
          'type': type ?? 'default',
          'fillColor':
          '#${RenderingUtilities.colorToMapplsHex(_shade(fillColor))}',
          'strokeColor':
          '#${RenderingUtilities.colorToMapplsHex(_shade(strokeColor))}',
          'fillColorSecondary':
          '#${RenderingUtilities.colorToMapplsHex(_shade(fillColorSecondary))}',
          'fillOpacity': fillColor.a,
          'isSelected': selectPolygonIds?.contains(polygon.id) ?? false,
          'boundary': polygon.properties?['type'] == "Boundary",
          'section': polygon.properties?['type'] == "Section",
          'subsection': polygon.properties?['type'] == "Sub Section",
          if (_config.immersive && baseHeight != null) 'base_height': baseHeight,
          if (_config.immersive && height != null) 'height': height,
          'hasPattern':pattern,
          'pattern':GeoJsonUtils.buildPatternKey(name:polygon.properties?['pattern'],size:polygon.properties?['patternSize'] ,gap: polygon.properties?['patternSpacing'],rotation:polygon.properties?['patternRotation'] ,color: polygon.properties?['patternColor']),
        }
      };
    }).toList();

    final patternKeys = features
        .where((f) => (f['properties'] as Map)['hasPattern'] == true)
        .map((f) => (f['properties'] as Map)['pattern'])
        .toList();

    await controller.setGeoJsonSource(
      _polygonSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );

    // The venue's fade thresholds are derived from these very polygons, so they
    // have to be recomputed whenever the polygon set changes.
    await _refreshPatchFadeIfStale(controller);
  }

  /// Recomputes the patch/section fade zooms when the polygons they are derived
  /// from have changed enough to move them.
  ///
  /// [_refreshPatchAboveOpacity] used to run from exactly one place —
  /// onStyleLoadedCallback — so the thresholds were computed ONCE, from
  /// whatever `_polygons` happened to hold at style-load time. When the venue
  /// data arrived after that (which is what happens as soon as anything on the
  /// load path gets faster), `_calculateFitZoom` fell back to its empty-list
  /// default of 13.0, every fade zoom was computed from that wrong value, and
  /// nothing ever recomputed them — the venue then never became visible and the
  /// map sat on the grey basemap forever, with no error.
  ///
  /// That is the "every speedup breaks rendering" race: removing the icon
  /// fetches' incidental latency, or baking smaller icons, both reordered the
  /// venue push past the style load and tripped it. Deriving the thresholds
  /// from the data whenever the data lands removes the ordering dependency
  /// instead of trying to preserve it.
  Future<void> _refreshPatchFadeIfStale(
      MapLibreMapController controller) async {
    if (!_isPolygonLayersEnabled) return;
    // The marker layers have to exist first. This runs off a polygon push,
    // which lands between enablePolygonLayers() (sets _isPolygonLayersEnabled)
    // and enableMarkerLayers() (sets _isClusteringEnabled) — so on the polygon
    // flag alone it fires into a style that has no marker layers yet, and
    // _refreshPatchAboveOpacity below then *creates* _patchAboveMarkerLayerId
    // out of order. enableMarkerLayers hits "Layer patch-above-markers-layer
    // already exists", and because its whole body is one try/catch that throw
    // skips every remaining layer, _isClusteringEnabled, and the _symbols
    // re-push — i.e. the venue renders with no markers at all.
    // Nothing is lost by waiting: enableMarkerLayers calls back in when done.
    if (!_isClusteringEnabled) return;
    final boundaryPolygons = _polygons.where((p) =>
        p.properties?['type']?.toString().toLowerCase() == 'boundary').toList();
    final basis = boundaryPolygons.isNotEmpty ? boundaryPolygons : _polygons;
    // Nothing to derive from yet; the next push will call back in.
    if (basis.isEmpty) return;
    final fitZoom =
        _calculateFitZoom(basis, screenSize: _screenSize) - 2.0;
    // Unchanged (or first run) → only pay for the layer rebuild when it moves.
    if (_fadeOutZoom != null && (_fadeOutZoom! - fitZoom).abs() < 0.01) return;
    print('patch fade stale: recomputing (was $_fadeOutZoom, now $fitZoom)');
    await _refreshPatchAboveOpacity(controller, screenSize: _screenSize);
  }

  @override
  Future<void> removePolygon(dynamic controller, String polygonId,
      {String? exclude}) async {
    if (controller is! MapLibreMapController) return;

    _polygons.removeWhere((polygon) {
      final id = polygon.id;
      if (exclude != null && id.contains(exclude)) return false;
      return id.contains(polygonId);
    });

    await _updatePolygonSource(controller);
  }

  @override
  Future<void> clearPolygons(dynamic controller) async {
    if (controller is MapLibreMapController) {
      try {
        _polygons.clear();
        await _updatePolygonSource(controller);
      } catch (e) {
        print('Error clearing polygons: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Furniture / 3D objects (fill-extrusion)
  //
  // Point features whose properties carry a "3dRef" map get their
  // "3dRef.3d" part list (boxes/cylinders/spheres in local meters)
  // converted into per-part GeoJSON polygons anchored at the point's
  // real-world lng/lat and rendered as a fill-extrusion layer.
  // ---------------------------------------------------------------------------

  static const double _metersPerDegLat = 111320.0;

  /// Points used to approximate a cylinder/sphere footprint circle.
  static const int _circleSegments = 16;

  /// Parts of the same furniture item (seat/back/legs, top/legs...) are
  /// built as independent, unwelded extrusion polygons. Where two parts
  /// are only meant to *touch*, floating-point rounding and the circle
  /// approximation above leave a sub-millimetre gap at the seam; at an
  /// oblique pitch, fill-extrusion's per-feature edge anti-aliasing lets
  /// whatever is underneath (floor layer, basemap) show through exactly
  /// there, which reads as "transparent furniture". Outsetting every part
  /// by this much forces neighbouring parts to overlap instead of merely
  /// touch, closing the seam. It's well under furniture scale (chairs are
  /// tens of centimetres), so it isn't visible as size inflation.
  static const double _partSeamOverlap = 0.01;

  /// Parts meant to sit flush against each other (a cushion directly on a
  /// seat base, a tabletop layer on its frame) frequently share the exact
  /// same footprint in the source data. Padding every part by the same
  /// fixed amount (above) keeps those side walls perfectly coplanar —
  /// which is exactly the condition that makes a GPU depth buffer flicker
  /// between two features as the camera moves: it can't consistently
  /// decide which coincident surface is nearer, so the "loser" shows
  /// whatever is behind it (another part, or the floor), and the loser
  /// flips as the view/projection matrix changes with tilt/rotation. This
  /// is a property of any standard depth buffer (WebGL, GLES, Metal), not
  /// a misconfigured render flag — MapLibre's native renderer already runs
  /// depth test/write correctly for fill-extrusion. The fix has to be on
  /// our side: never hand the renderer two bit-identical surfaces. Varying
  /// the pad per part index guarantees no two parts of the same item can
  /// ever end up with identical padded geometry, without needing to know
  /// which part is meant to sit "inside" which.
  static const int _seamJitterSteps = 6;
  static const double _seamJitterStep = 0.0015;

  /// "3dRef" may arrive as a Map or as a JSON-encoded string depending on
  /// how the API serialized the property — accept both.
  Map<String, dynamic>? _furnitureRefOf(Map<String, dynamic> props) {
    final raw = props['3dRef'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      // 1. Try to match by ID in the fetched furniture data
      final furnitureData = VenueData.instance?.furnitureData;
      if (furnitureData != null) {
        try {
          final model = furnitureData.firstWhere((m) => m.id == raw);
          return model.toJson();
        } catch (_) {}
      }

      // 2. Fall back to parsing as JSON string (original behavior)
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> addFurniture(
      dynamic controller, List<Map<String, dynamic>> items) async {
    if (controller is! MapLibreMapController) return;
    try {
      final furnitureItems = items.where((item) {
        final props = item['properties'] as Map<String, dynamic>? ?? {};
        return _furnitureRefOf(props) != null;
      }).toList();
      if (furnitureItems.isEmpty) return;

      // Upsert by id: the same building's furniture can be pushed more than
      // once — a floor switch, or the deferred furniture-model load re-rendering
      // the current floors — and a blind addAll would stack duplicate extruded
      // parts that removeFurniture(buildingId) then only partly clears.
      final incomingIds = furnitureItems
          .map((it) => it['id'])
          .where((id) => id != null)
          .toSet();
      if (incomingIds.isNotEmpty) {
        _furnitureItems.removeWhere((it) => incomingIds.contains(it['id']));
      }
      _furnitureItems.addAll(furnitureItems);
      await _enableFurnitureLayer(controller);
      await _updateFurnitureSource(controller);
    } catch (e) {
      print('Error adding furniture: $e');
    }
  }

  @override
  Future<void> removeFurniture(dynamic controller, String buildingId) async {
    if (controller is! MapLibreMapController) return;
    try {
      _furnitureItems.removeWhere((item) => item['buildingId'] == buildingId);
      if (_isFurnitureLayerEnabled) {
        await _updateFurnitureSource(controller);
      }
    } catch (e) {
      print('Error removing furniture: $e');
    }
  }

  @override
  Future<void> clearFurniture(dynamic controller) async {
    if (controller is! MapLibreMapController) return;
    try {
      _furnitureItems.clear();
      if (_isFurnitureLayerEnabled) {
        await _updateFurnitureSource(controller);
      }
    } catch (e) {
      print('Error clearing furniture: $e');
    }
  }

  /// Setup currently in progress, so concurrent callers await it instead of
  /// each starting their own.
  ///
  /// `_isFurnitureLayerEnabled` alone cannot do this: it is set at the END of
  /// [_enableFurnitureLayerOnce], several awaits after the guard reads it, so
  /// two callers both pass the guard and both add the source and layers. There
  /// ARE two — [addFurniture] and onStyleLoadedCallback — and the loser threw
  /// `CannotAddLayerException: Layer furniture-fill-layer already exists`
  /// UNHANDLED (neither call site catches), taking the app down on any venue
  /// that actually has furniture. The zoo has none, which is why this only
  /// surfaced on a hospital.
  Future<void>? _furnitureLayerSetup;

  Future<void> _enableFurnitureLayer(MapLibreMapController controller) {
    if (_isFurnitureLayerEnabled) return Future<void>.value();
    return _furnitureLayerSetup ??= _enableFurnitureLayerOnce(controller)
        .whenComplete(() => _furnitureLayerSetup = null);
  }

  Future<void> _enableFurnitureLayerOnce(
      MapLibreMapController controller) async {
    if (_isFurnitureLayerEnabled) return;

    await controller.addSource(
      _furnitureSourceId,
      GeojsonSourceProperties(
        data: {'type': 'FeatureCollection', 'features': <dynamic>[]},
        // Furniture parts are centimetre-scale, which puts them right on the
        // edge of what a tiled GeoJSON source can represent. Two separate
        // mechanisms erase them, and both have to stay disabled.
        //
        // 1. tolerance MUST stay 0. It is not just Douglas-Peucker: for any
        //    tile below maxzoom, geojson-vt drops a polygon ring outright when
        //    its area is under (tolerance / (2^z * extent))^2. At z18 that
        //    threshold is a ~1.4cm square, at z17 a ~2.8cm square — so thin
        //    parts silently disappear, and reappear once you zoom to maxzoom
        //    where the tolerance is forced to 0. That is exactly the
        //    "random parts missing" symptom. Simplification would save nothing
        //    here anyway: these rings are 4-16 points each.
        //
        // 2. maxzoom controls the quantisation grid of the deepest tile, since
        //    coordinates are rounded to `extent` steps. At the default 18 a
        //    step is ~3.7cm and a 5cm post collapses to zero area. At 22 a step
        //    is ~2.3mm, fine enough for anything in these models, while still
        //    stopping the source from building real tiles for two more zoom
        //    levels on every pan the way 24 did.
        maxzoom: 22,
        tolerance: 0,
        // Default. Furniture parts are sub-metre, so the doubled 256 buffer
        // was only duplicating geometry into neighbouring tiles. Buffer only
        // controls how much neighbouring geometry a tile carries, so lowering
        // it cannot drop a part — a clipped fill is re-closed at the seam.
        buffer: 256,
      ),
    );

    // Drop any survivor before adding. `_isFurnitureLayerEnabled` is reset in
    // onStyleLoadedCallback on the assumption the style was replaced and took
    // every layer with it — but that callback can fire again WITHOUT a style
    // swap, leaving the flag saying "no layers" while the layers are still
    // there. The add then threw CannotAddLayerException, unhandled, because the
    // onStyleLoaded call site has no catch. removeLayer no-ops when the layer is
    // absent, so this is free in the normal case.
    //
    // addSource above needs no equivalent: the plugin already logs
    // "source with id 'furniture-source' already exists, skipping" and carries
    // on rather than throwing.
    try {
      await controller.removeLayer(_furnitureFillLayerId);
    } catch (_) {}

    // Flat footprint — visible only in 2D mode. Uses the same per-part
    // "color" so the object reads as a top-down floor-plan silhouette.
    await controller.addFillLayer(
      _furnitureSourceId,
      _furnitureFillLayerId,
      _layerProps(_furnitureFillLayerId, (op) => FillLayerProperties(
        fillColor: ['get', 'color'],
        fillOutlineColor: ['get', 'color'],
        // The flat footprint is the 2D counterpart of the extrusion, so the
        // renderer hides it in 3D. A policy can hide it further, not force it on.
        visibility: _visibility(_furnitureFillLayerId,
            internalVisible: !_config.immersive),
        // Named so a furniture opacity override has somewhere to land; op(null)
        // serialises exactly as before when no override is set.
        fillOpacity: op(null),
      )),
      minzoom: _furnitureMinZoom,
    );

    _isFurnitureLayerEnabled = true;
    await _applyLayerPolicy(controller, only: [_furnitureFillLayerId]);

    // The 3D extrusion layer only exists in immersive mode — in 2D there is
    // no extrusion layer at all, just the flat fill above.
    if (_config.immersive) {
      await _addFurnitureExtrusionLayer(controller);
    }
  }

  /// Adds the furniture fill-extrusion layer (3D). No-op if already present
  /// or if the base furniture source/fill layer hasn't been created yet.
  Future<void> _addFurnitureExtrusionLayer(
      MapLibreMapController controller) async {
    if (!_isFurnitureLayerEnabled || _isFurnitureExtrusionAdded) return;
    // Same stale-flag hazard as the flat fill layer: _isFurnitureExtrusionAdded
    // is reset in onStyleLoadedCallback, which can fire without the style
    // actually being replaced. See the note there.
    try {
      await controller.removeLayer(_furnitureLayerId);
    } catch (_) {}
    await controller.addFillExtrusionLayer(
      _furnitureSourceId,
      _furnitureLayerId,
      _layerProps(_furnitureLayerId, (op) => FillExtrusionLayerProperties(
        visibility: _visibility(_furnitureLayerId),
        fillExtrusionColor: ['get', 'color'],
        fillExtrusionBase: ['get', 'base'],
        fillExtrusionHeight: ['get', 'height'],
        // Every other extrusion layer in this file pins this explicitly;
        // leaving it unset here was the one inconsistency letting the
        // renderer fall back to an implicit default instead of a
        // guaranteed-opaque layer.
        fillExtrusionOpacity: op(1.0),
      )),
      minzoom: _furnitureMinZoom,
    );
    _isFurnitureExtrusionAdded = true;
    // Same plugin gap as the polygon extrusions: setLayerProperties rejects
    // fill-extrusion layers, so policy changes have to rebuild this one.
    _layerReAdders[_furnitureLayerId] = () async {
      await controller.removeLayer(_furnitureLayerId);
      await controller.addFillExtrusionLayer(
        _furnitureSourceId,
        _furnitureLayerId,
        _layerProps(_furnitureLayerId, (op) => FillExtrusionLayerProperties(
              visibility: _visibility(_furnitureLayerId),
              fillExtrusionColor: ['get', 'color'],
              fillExtrusionBase: ['get', 'base'],
              fillExtrusionHeight: ['get', 'height'],
              fillExtrusionOpacity: op(1.0),
            )),
        minzoom: _furnitureMinZoom,
      );
    };
    await _applyLayerPolicy(controller, only: [_furnitureLayerId]);
  }

  /// Removes the furniture fill-extrusion layer entirely (used when switching
  /// to 2D). The source and flat fill layer stay in place.
  Future<void> _removeFurnitureExtrusionLayer(
      MapLibreMapController controller) async {
    if (!_isFurnitureExtrusionAdded) return;
    // Removing the re-adder matters: _applyLayerPolicy would otherwise rebuild
    // the extrusion we are deliberately taking away for 2D.
    _layerReAdders.remove(_furnitureLayerId);
    try {
      await controller.removeLayer(_furnitureLayerId);
    } catch (_) {}
    // Drop the builder too: the layer is gone until 3D is re-entered, and
    // _applyLayerPolicy would otherwise keep trying to write to it.
    _propBuilders.remove(_furnitureLayerId);
    _everApplied.remove(_furnitureLayerId);
    _isFurnitureExtrusionAdded = false;
  }

  Future<void> _updateFurnitureSource(MapLibreMapController controller) async {
    final features = <Map<String, dynamic>>[
      for (final item in _furnitureItems)
        ..._buildFurniturePartFeatures(item),
    ];
    print('furniture: ${_furnitureItems.length} items -> '
        '${features.length} extrusion features');

    await controller.setGeoJsonSource(
      _furnitureSourceId,
      {'type': 'FeatureCollection', 'features': features},
    );
  }

  /// Turns one furniture item's "3dRef.3d" part list into GeoJSON
  /// Polygon features with per-part base/height/color, anchored at the
  /// item's own real-world lng/lat (geometry.coordinates), ready for a
  /// fill-extrusion layer.
  List<Map<String, dynamic>> _buildFurniturePartFeatures(
      Map<String, dynamic> item) {
    final geometry = item['geometry'] as Map<String, dynamic>?;
    final props = item['properties'] as Map<String, dynamic>? ?? {};
    final ref = _furnitureRefOf(props);
    if (geometry == null || ref == null) return const [];

    final coords = geometry['coordinates'] as List?;
    if (coords == null || coords.length < 2) return const [];
    final anchorLng = double.tryParse('${coords[0]}');
    final anchorLat = double.tryParse('${coords[1]}');
    if (anchorLng == null || anchorLat == null) return const [];

    // Placement rotation comes from "3dModelAngle" (sits alongside
    // "3dRef" in properties) rather than "3dRef.rotation_y", which is
    // just the 3d object's own default/reference orientation.
    // "3dModelAngle" is defined 180deg opposite to the rotation
    // convention used below (every object was showing back-to-front),
    // so the offset corrects for that.
    final rotationDeg =
        (double.tryParse('${props['3dModelAngle'] ?? 0}') ?? 0.0) + 180.0;
    final rotationRad = rotationDeg * pi / 180.0;
    final cosT = cos(rotationRad);
    final sinT = sin(rotationRad);

    final anchorLatRad = anchorLat * pi / 180.0;
    final metersPerDegLng = _metersPerDegLat * cos(anchorLatRad);

    final parts = (ref['3d'] as List?) ?? const [];
    final result = <Map<String, dynamic>>[];

    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      final raw = parts[partIndex];
      if (raw is! Map) continue;
      final p = Map<String, dynamic>.from(raw);
      final shape = p['shape'] as String? ?? 'box';
      // Spheres describe size via "r" (radius) instead of "h" — treat
      // their vertical extent as the full diameter, centered on oy.
      final h = shape == 'sphere'
          ? (double.tryParse('${p['r'] ?? 0}') ?? 0.0) * 2
          : (double.tryParse('${p['h'] ?? 0}') ?? 0.0);
      final oy = double.tryParse('${p['oy'] ?? 0}') ?? 0.0;

      final eps = _partSeamOverlap +
          (partIndex % _seamJitterSteps) * _seamJitterStep;

      final localCorners = _footprintFor(p, eps);
      if (localCorners.isEmpty) continue;

      final ring = localCorners.map((c) {
        final x = c[0];
        final z = c[1];
        // Rotate around the item's own anchor point (matches how
        // rotation_y rotates the whole part group in a three.js-style
        // scene graph).
        final rx = x * cosT - z * sinT;
        final rz = x * sinT + z * cosT;
        final lng = anchorLng + rx / metersPerDegLng;
        final lat = anchorLat + rz / _metersPerDegLat;
        return [lng, lat];
      }).toList();
      ring.add(ring.first); // close the ring

      result.add({
        'type': 'Feature',
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
        'properties': {
          'color': p['color'] ?? '#888888',
          'base': oy - h / 2 - eps,
          'height': oy + h / 2 + eps,
        },
      });
    }

    return result;
  }

  /// Returns the local (pre-rotation) footprint corner points for one
  /// 3d part, in meters. "box" -> 4 rectangle corners. "cylinder" /
  /// "sphere" -> N points around a circle of radius r.
  ///
  /// Note: fill-extrusion can only produce flat-topped vertical
  /// columns, so a "sphere" renders as a cylinder of the same radius
  /// spanning its full diameter — not a true dome. That's a hard
  /// limit of this technique, not a bug.
  List<List<double>> _footprintFor(Map<String, dynamic> p, double eps) {
    final shape = p['shape'] as String? ?? 'box';
    final ox = double.tryParse('${p['ox'] ?? 0}') ?? 0.0;
    final oz = double.tryParse('${p['oz'] ?? 0}') ?? 0.0;

    // "polygon" -> an explicit footprint given as a "points" list of [x, z]
    // corners in local metres, relative to the part centre. Used for shells
    // whose outline is not a simple rectangle (e.g. an MRI housing body).
    if (shape == 'polygon') {
      final pts = p['points'] as List?;
      if (pts == null || pts.isEmpty) return const [];
      return pts
          .whereType<List>()
          .map<List<double>>((pt) => [
                ox + (double.tryParse('${pt[0]}') ?? 0.0),
                oz + (double.tryParse('${pt.length > 1 ? pt[1] : 0}') ?? 0.0),
              ])
          .toList();
    }

    if (shape == 'cylinder' || shape == 'sphere') {
      final r = (double.tryParse('${p['r'] ?? 0}') ?? 0.0) + eps;
      return List.generate(_circleSegments, (i) {
        final angle = 2 * pi * i / _circleSegments;
        return [ox + r * cos(angle), oz + r * sin(angle)];
      });
    }

    // default: box — w/d taken exactly as given in the JSON, no
    // unit scaling or minimum-size flooring. The footprint is the
    // horizontal w x d rectangle only; h feeds base/height later.
    // Half-extents grow by eps on every side so this part overlaps its
    // neighbours instead of merely touching (or exactly coinciding
    // with) them.
    final halfW = (double.tryParse('${p['w'] ?? 0}') ?? 0.0) / 2 + eps;
    final halfD = (double.tryParse('${p['d'] ?? 0}') ?? 0.0) / 2 + eps;

    // Optional per-part "ry": the part's own yaw around its center
    // (e.g. wall niches at ry 90/270, amalaka lobes at ry 30/60...),
    // applied before the whole-item 3dModelAngle rotation.
    final ryDeg = double.tryParse('${p['ry'] ?? 0}') ?? 0.0;
    if (ryDeg == 0) {
      return [
        [ox - halfW, oz - halfD],
        [ox + halfW, oz - halfD],
        [ox + halfW, oz + halfD],
        [ox - halfW, oz + halfD],
      ];
    }
    final ryRad = ryDeg * pi / 180.0;
    final cosR = cos(ryRad);
    final sinR = sin(ryRad);
    return [
      [-halfW, -halfD],
      [halfW, -halfD],
      [halfW, halfD],
      [-halfW, halfD],
    ].map((c) {
      final x = c[0];
      final z = c[1];
      return [ox + x * cosR - z * sinR, oz + x * sinR + z * cosR];
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Polylines
  // ---------------------------------------------------------------------------

  @override
  Future<void> addPolyline(dynamic controller, GeoJsonPolyline polyline) async {
    if (controller is MapLibreMapController) {
      bool isWaypoint = false;
      if (polyline.properties?["lineCategory"] != null) {
        isWaypoint =
            polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
      }
      if (polyline.properties?["polygonType"] != null) {
        isWaypoint =
            polyline.properties!["polygonType"].toLowerCase() == "waypoints";
      }
      if (isWaypoint) return;
      try {
        _lines.removeWhere((line) => line.id == polyline.id);
        _lines.add(polyline);
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error adding polyline: $e');
      }
    }
  }

  @override
  Future<void> addPolylines(
      controller, List<GeoJsonPolyline> polylines) async {
    if (controller is MapLibreMapController) {
      for (var polyline in polylines) {
        bool isWaypoint = false;
        if (polyline.properties?["lineCategory"] != null) {
          isWaypoint =
              polyline.properties!["lineCategory"].toLowerCase() == "waypoint";
        }
        if (polyline.properties?["polygonType"] != null) {
          isWaypoint = polyline.properties!["polygonType"].toLowerCase() ==
              "waypoints";
        }
        if (isWaypoint) continue;
        try {
          _lines.add(polyline);
        } catch (e) {
          print('Error adding polyline: $e');
        }
      }
      try {
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error updating polyline source: $e');
      }
    }
  }

  Future<void> _updatePolylineSource(MapLibreMapController controller) async {
    if (!_isPolylineLayersEnabled) {
      print("Polyline layers not enabled yet");
      return;
    }

    print("poyline going to add");

    final features = _lines.map((line) {
      return {
        'type': 'Feature',
        'id': line.id,
        'geometry': {
          'type': 'LineString',
          'coordinates': line.points
              .map((point) => [point.longitude, point.latitude])
              .toList(),
        },
        'properties': {
          'id': line.id,
          'type': 'default',
          'isSelected': false,
          'lineColor': _shadeHex(line.properties?['fillColor'] ?? '#000000'),
          'lineOpacity': line.properties?['fillOpacity'] ?? 1.0,
          'lineWidth': line.properties?['width']?.toDouble() ?? 4.0,
          'path': line.properties?['path'] ??
              line.id.toLowerCase().contains("path"),
          'style':line.properties?['style'],
          'isGreyOverlay': line.properties?['isGreyOverlay'] ?? false,
        }
      };
    }).toList();
    await controller.setGeoJsonSource(
      _polylineSourceId,
      {
        "type": "FeatureCollection",
        "features": features,
      },
    );

    // The corner pass below only reads solid, non-grey path lines. Build a
    // cheap signature of exactly those and skip the whole pass (segment walk +
    // per-bend image bakes) when it hasn't changed since the last build — e.g.
    // every time navigation adds/removes the grey traversed overlay, which
    // never touches the route geometry.
    final routeSignature = _lines
        .where((line) {
          final isPath = line.properties?['path'] ??
              line.id.toLowerCase().contains("path");
          return isPath &&
              line.properties?['style'] == "solid" &&
              !(line.properties?['isGreyOverlay'] ?? false);
        })
        .map((line) => "${line.id}:${line.points.length}")
        .join("|");

    if (routeSignature == _cornerFeaturesSignature) {
      await _refreshCornerVisibility(controller);
      return;
    }

    final cornerFeatures = <Map<String, dynamic>>[];
    for (var line in _lines) {
      final bool isPath = line.properties?['path'] ?? line.id.toLowerCase().contains("path");
      final String? style = line.properties?['style'];
      final bool isGreyOverlay = line.properties?['isGreyOverlay'] ?? false;

      if (isPath && style == "solid" && !isGreyOverlay && line.points.length >= 3) {
        // Detect significant corners (bends)
        for (int i = 1; i < line.points.length - 1; i++) {
          final b1 = _calculateBearing(line.points[i - 1], line.points[i]);
          final b2 = _calculateBearing(line.points[i], line.points[i + 1]);

          double diff = b2 - b1;
          if (diff > 180) diff -= 360;
          if (diff < -180) diff += 360;

          // Threshold for a "bend"
          if (diff.abs() > 20) {
            // Exact-angle icon (rounded to 5° purely to cap distinct
            // textures) instead of the old 6-way bucket — the baked bend now
            // matches the real geometry of the turn instead of snapping to
            // the nearest of [-135, -90, -45, 45, 90, 135].
            final String iconId = await _ensureCornerArrowImage(controller, diff);
            final String turnLabel = _turnLabel(diff);
            final String bubbleIconId = await _ensureTurnBubbleImage(controller, turnLabel);

            // Shorter of the two path segments meeting at this bend. Used by
            // _refreshCornerVisibility to drop the arrow when that segment is
            // too short on screen for the fixed-size sprite to sit on.
            final double segIn = _haversineMeters(line.points[i - 1], line.points[i]);
            final double segOut = _haversineMeters(line.points[i], line.points[i + 1]);

            cornerFeatures.add({
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [line.points[i].longitude, line.points[i].latitude],
              },
              'properties': {
                'path': true,
                'style': 'solid',
                'isGreyOverlay': false,
                'bearing': b1, // Rotate icon by incoming bearing so tail aligns
                'icon': iconId,
                'turnBubbleIcon': bubbleIconId,
                'turnSharpness': diff.abs(),
                'minSegMeters': segIn < segOut ? segIn : segOut,
              }
            });
          }
        }
      }
    }

    _allCornerFeatures = cornerFeatures;
    _cornerFeaturesSignature = routeSignature;
    await _refreshCornerVisibility(controller);
  }

  String _turnLabel(double diffDeg) {
    final d = diffDeg.abs();
    if (d < 20) return "Continue straight";
    if (d < 45) return diffDeg > 0 ? "Turn Slight right" : "Turn Slight left";
    if (d < 150) return diffDeg > 0 ? "Turn right" : "Turn left";
    return "U-turn";
  }

  IconData _turnIcon(double diffDeg) {
    if (diffDeg.abs() < 20) return Icons.straight;
    return diffDeg > 0 ? Icons.turn_right : Icons.turn_left;
  }

  double _calculateBearing(MapLocation start, MapLocation end) {
    double lat1 = start.latitude * pi / 180;
    double lon1 = start.longitude * pi / 180;
    double lat2 = end.latitude * pi / 180;
    double lon2 = end.longitude * pi / 180;

    double dLon = lon2 - lon1;

    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double brng = atan2(y, x);

    return (brng * 180 / pi + 360) % 360;
  }

  double _haversineMeters(MapLocation a, MapLocation b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLng = (b.longitude - a.longitude) * pi / 180;
    final lat1 = a.latitude * pi / 180;
    final lat2 = b.latitude * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * R * atan2(sqrt(h), sqrt(1 - h));
  }

  MapLocation _pointAlongPath(List<MapLocation> points, double t) {
    if (points.length < 2) return points.first;
    double total = 0;
    final segLengths = <double>[];
    for (int i = 0; i < points.length - 1; i++) {
      final d = _haversineMeters(points[i], points[i + 1]);
      segLengths.add(d);
      total += d;
    }
    if (total == 0) return points.first;
    double target = t.clamp(0.0, 1.0) * total;
    double accum = 0;
    for (int i = 0; i < segLengths.length; i++) {
      if (accum + segLengths[i] >= target) {
        final segT = segLengths[i] == 0 ? 0.0 : (target - accum) / segLengths[i];
        final a = points[i];
        final b = points[i + 1];
        return MapLocation(
          latitude: a.latitude + (b.latitude - a.latitude) * segT,
          longitude: a.longitude + (b.longitude - a.longitude) * segT,
        );
      }
      accum += segLengths[i];
    }
    return points.last;
  }

  Future<void> _refreshCornerVisibility(MapLibreMapController controller) async {
    if (_allCornerFeatures.isEmpty) {
      await controller.setGeoJsonSource(_pathCornerSourceId, {
        "type": "FeatureCollection",
        "features": [],
      });
      return;
    }

    final cameraPos = controller.cameraPosition;
    final zoom = cameraPos?.zoom ?? 16.0;
    final lat = cameraPos?.target.latitude ?? 0.0;

    // Below this zoom, hide corner arrows/bubbles entirely — even the
    // sharpest turn shouldn't survive once the view is zoomed out this far.
    const double hardCutoffZoom = 19;
    if (zoom < hardCutoffZoom) {
      await controller.setGeoJsonSource(_pathCornerSourceId, {
        "type": "FeatureCollection",
        "features": [],
      });
      return;
    }

    final metersPerPixel = 156543.03392 * cos(lat * pi / 180) / pow(2, zoom);
    const double pixelThreshold = 80.0;
    final double meterThreshold = pixelThreshold * metersPerPixel;

    // The big corner arrow is a fixed ~48px sprite pivoted on the bend. When a
    // path segment meeting the bend is shorter than that on screen — a tight
    // route near the destination, or the view zoomed out — the arrow overruns
    // the turn and reads as floating free of the path. Flag those per corner so
    // the arrow layer can drop just the arrow (the turn bubble still shows).
    const double arrowFitMinSegPixels = 55.0;

    final sorted = [..._allCornerFeatures]
      ..sort((a, b) => (b['properties']['turnSharpness'] as double)
          .compareTo(a['properties']['turnSharpness'] as double));

    final kept = <Map<String, dynamic>>[];
    for (final feature in sorted) {
      final coords = feature['geometry']['coordinates'] as List;
      final point = MapLocation(latitude: coords[1], longitude: coords[0]);
      bool tooClose = false;
      for (final k in kept) {
        final kCoords = k['geometry']['coordinates'] as List;
        final kPoint = MapLocation(latitude: kCoords[1], longitude: kCoords[0]);
        if (_haversineMeters(point, kPoint) < meterThreshold) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;

      final segMeters =
          (feature['properties']['minSegMeters'] as num?)?.toDouble();
      feature['properties']['arrowFits'] = segMeters == null ||
          segMeters / metersPerPixel >= arrowFitMinSegPixels;
      kept.add(feature);
    }

    await controller.setGeoJsonSource(_pathCornerSourceId, {
      "type": "FeatureCollection",
      "features": kept,
    });
  }

  Future<Uint8List> _createShineIconBytes() async {
    const double size = 44;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withOpacity(0.0)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size / 2));
    canvas.drawCircle(center, size / 2, paint);
    final img = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _loadShineImage(MapLibreMapController controller) async {
    try {
      final bytes = await _createShineIconBytes();
      await _addImageSafe(controller, _kShineImageId, bytes);
    } catch (e) {
      print("_loadShineImage $e");
    }
  }

  static const int _pathShineCount = 1;

  /// Decorative "energy pulse" that travels along the drawn route. Each tick
  /// rewrites a GeoJSON source, which makes MapLibre repaint the whole map —
  /// so while it runs the map never goes idle. Measured on a moto g64: on its
  /// own it holds a static navigation screen at ~25fps instead of letting it
  /// rest. Kept ON (it's a wanted effect), but throttled: it runs at ~8fps and
  /// stands completely down while the camera is moving (pan / nav follow), so
  /// it never competes with the interaction that actually needs the frames.
  /// Set false to drop it entirely.
  bool pathShineEnabled = true;

  // ~8fps: a soft glow reads as smooth motion well below 60fps, and every
  // tick costs a full-map repaint, so this is as slow as it can look right.
  static const Duration _kPathShineTick = Duration(milliseconds: 125);

  void _ensurePathShineAnimation(MapLibreMapController controller) {
    if (!pathShineEnabled) return;
    if (_pathShineTimer != null) return;
    _pathShineProgress = 0.0;
    _pathShineTimer = Timer.periodic(_kPathShineTick, (timer) async {
      if (!_isPolylineLayersEnabled) return;

      // Purely cosmetic. While the camera is moving (guided-navigation follow,
      // or a gesture) skip the source rewrite entirely — a native GeoJSON
      // re-parse + relayout on the render thread every tick is exactly what
      // makes the pan stutter. It resumes the moment the camera settles.
      if (_cameraMovingNow) return;

      // Per-tick advance, sized so the pulse covers the route in ~1.25s at the
      // 125ms tick (0.1 * ~10 ticks/loop). Bump this to speed the pulse up.
      _pathShineProgress += 0.10;
      if (_pathShineProgress > 1.0) _pathShineProgress -= 1.0;

      final activeLines = _lines.where((line) {
        final isPath = line.properties?['path'] ?? line.id.toLowerCase().contains("path");
        final style = line.properties?['style'];
        final isGrey = line.properties?['isGreyOverlay'] ?? false;
        return isPath && style == "solid" && !isGrey && line.points.length >= 2;
      }).toList();

      if (activeLines.isEmpty) {
        timer.cancel();
        _pathShineTimer = null;
        return;
      }

      final features = <Map<String, dynamic>>[];
      for (final line in activeLines) {
        for (int i = 0; i < _pathShineCount; i++) {
          final t = (_pathShineProgress + i / _pathShineCount) % 1.0;
          final pos = _pointAlongPath(line.points, t);
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [pos.longitude, pos.latitude],
            },
            'properties': {},
          });
        }
      }

      try {
        await controller.setGeoJsonSource(_pathShineSourceId, {
          'type': 'FeatureCollection',
          'features': features,
        });
      } catch (e) {
        // Source may not exist yet mid style-reload; next tick retries.
      }
    });
  }

  void _stopPathShineAnimation() {
    _pathShineTimer?.cancel();
    _pathShineTimer = null;
  }

  @override
  Future<void> removePolyline(dynamic controller, String polylineId) async {
    if (controller is! MapLibreMapController) return;

    _lines.removeWhere((line) => line.id.contains(polylineId));
    await _updatePolylineSource(controller);
  }

  @override
  Future<void> clearPolylines(dynamic controller) async {
    if (controller is MapLibreMapController) {
      try {
        _lines.clear();
        await _updatePolylineSource(controller);
      } catch (e) {
        print('Error clearing polylines: $e');
      }
    }
  }

  /// Clear all map elements
  Future<void> clearAll(dynamic controller) async {
    await clearMarkers(controller);
    await clearPolygons(controller);
    await clearPolylines(controller);
  }

  // ---------------------------------------------------------------------------
  // Icon loading
  // ---------------------------------------------------------------------------

  final creator = UnifiedMarkerCreator();

  /// Dot image ids already registered with the current style (cleared on style
  /// reload, which wipes addImage()). Avoids re-decoding shared dot assets.
  final Set<String> _registeredDotImageIds = {};

  /// Corner-arrow angles (rounded to the nearest 5°) already registered with
  /// the current style. Cleared on style reload same as the dot images.
  final Set<int> _registeredCornerArrowAngles = {};

  String _cornerArrowImageId(int roundedAngle) =>
      '${_kPathBigArrowImageId}_exact_$roundedAngle';

  /// Registers (once, cached by 5°-rounded angle) a bent-arrow icon whose bend
  /// matches the real turn angle, and returns its image id. Rounding to 5° is
  /// purely to cap the number of distinct textures (~72 max) — it is NOT a
  /// visual bucket like the old 6-way [-135, -90, -45, 45, 90, 135] scheme;
  /// a 5° step is visually indistinguishable from the exact angle.
  Future<String> _ensureCornerArrowImage(
      MapLibreMapController controller, double diff) async {
    final int rounded = (diff / 5).round() * 5;
    final String id = _cornerArrowImageId(rounded);
    if (!_registeredCornerArrowAngles.contains(rounded)) {
      final bytes = await creator.createBentArrow(angle: rounded.toDouble());
      await _addImageSafe(controller, id, bytes);
      _registeredCornerArrowAngles.add(rounded);
    }
    return id;
  }

  final Map<String, String> _registeredTurnBubbleIds = {};

  Future<String> _ensureTurnBubbleImage(
      MapLibreMapController controller, String label) async {
    if (_registeredTurnBubbleIds.containsKey(label)) {
      return _registeredTurnBubbleIds[label]!;
    }
    final bytes = await _createTurnBubbleBytes(label);
    final id = 'turn_bubble_${label.hashCode}';
    await _addImageSafe(controller, id, bytes);
    _registeredTurnBubbleIds[label] = id;
    return id;
  }

  Future<Uint8List> _createTurnBubbleBytes(String label) async {
    const double ratio = 2.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 14 * ratio,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const paddingH = 16.0, paddingV = 10.0, tailH = 10.0;
    final w = textPainter.width + paddingH * 2 * ratio;
    final bubbleH = textPainter.height + paddingV * 2 * ratio;
    final h = bubbleH + tailH * ratio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bubbleRect = Rect.fromLTWH(0, 0, w, bubbleH);
    final rrect = RRect.fromRectAndRadius(bubbleRect, Radius.circular(10 * ratio));

    canvas.drawRRect(
      rrect.shift(Offset(0, 2 * ratio)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * ratio),
    );

    final bgPaint = Paint()..color = const Color(0xFF1A73E8);
    canvas.drawRRect(rrect, bgPaint);

    final tailPath = Path()
      ..moveTo(w / 2 - 6 * ratio, bubbleH - 1)
      ..lineTo(w / 2 + 6 * ratio, bubbleH - 1)
      ..lineTo(w / 2, h)
      ..close();
    canvas.drawPath(tailPath, bgPaint);

    textPainter.paint(canvas, Offset(paddingH * ratio, paddingV * ratio));

    final img = await recorder.endRecording().toImage(w.ceil(), h.ceil());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Longest-edge cap (px) an animal photo is downscaled to before its icon
  /// is registered with the map style, regardless of the source photo's
  /// native resolution.
  ///
  /// DO NOT make this smaller on web to shrink the animal markers. Tried
  /// 2026-08-27 (56px + an 11pt pill): it works visually, but a smaller bake
  /// completes faster, which lands the venue push before onStyleLoadedCallback
  /// has enabled the layers — and those pushes are silently dropped, leaving a
  /// permanent grey basemap. Verified by A/B against a clean HEAD that renders.
  /// Shrink at RENDER time via [_kAnimalWebIconScale] on the layer's icon-size
  /// instead: same appearance, zero effect on bake timing.
  static const int _animalMaxIconSize = 80;

  /// Render-time shrink for the custom-rendering composites (animal photo +
  /// its pill) on web, where a browser viewport shows much more of the venue at
  /// a given zoom than a native phone map and the baked-at-80dp icons crowd
  /// each other. Applied to the layer's icon-size stops, so it costs nothing
  /// and cannot perturb load ordering. Museum POI pins are excluded — they have
  /// their own `hasSelectedIcon` curve.
  static final double _kAnimalWebIconScale = kIsWeb ? 0.55 : 1.0;

  /// Composited animal-icon bytes, keyed by [_animalIconKey] (photo URL +
  /// baked title). An enclosure of animals that share a photo and species
  /// name (e.g. every lion in one enclosure) bakes the composite once, no
  /// matter how many separate markers point at it.
  final Map<String, Uint8List> _animalIconCache = {};

  /// Content keys from [_animalIconCache] that have actually been registered
  /// with the current style via addImage(). Cleared on style reload (which
  /// wipes addImage()), independently of the byte cache above. Markers whose
  /// key is already in here reuse the shared image id instead of triggering
  /// another decode/addImage round trip.
  final Set<String> _loadedAnimalIcons = {};

  /// Marker ids whose icon has already been fetched/composited/registered via
  /// addImage() in the current style session (mirrors [_loadedAnimalIcons] for
  /// non-animal markers). A floor switch removes a marker from `_symbols`/the
  /// GeoJSON source but never un-registers its native image — so without this,
  /// switching away from a floor and back re-fetched the source asset/network
  /// image and re-ran the Canvas compositing for every one of its markers
  /// every single time, even though the exact same image was already sitting
  /// in the native style. This is what made floor switching visibly slower
  /// the more floors/markers a venue had and the more a user bounced between
  /// them. Cleared on style reload (which wipes addImage()) alongside
  /// _loadedAnimalIcons.
  final Set<String> _registeredMarkerIconIds = {};

  /// Anchor computed by compositing, for a marker id already covered by
  /// [_registeredMarkerIconIds]. A floor revisit gets a freshly-parsed
  /// [GeoJsonMarker] instance (same id, new object) that never itself ran
  /// through compositing, so the anchor has to be restored from here rather
  /// than recomputed.
  final Map<String, Offset> _markerIconAnchorCache = {};

  /// Shared "no label" icon ids already registered with the current style.
  ///
  /// The zoomed-out variant of a custom-rendering marker is the same photo
  /// baked with `text: ""`, so its bytes depend only on the photo and the pill
  /// geometry — never on the marker. Registering it under a per-marker
  /// `<id>-small` id therefore uploaded ~190 byte-identical images, each one a
  /// Blob → <img> decode → canvas readback → GPU upload. Keying by content
  /// collapses that to one upload per distinct photo+size. Cleared on style
  /// reload, which wipes addImage().
  final Set<String> _registeredSmallIconIds = {};

  /// Image id each marker's features should use for the zoomed-out (label-less)
  /// variant, emitted as the `smallIcon` feature property. Markers absent from
  /// here fall back to the old `<icon>-small` expression, which is what animal
  /// markers still use (their ids are already content-keyed).
  final Map<String, String> _smallIconIds = {};

  /// Bytes behind each id in [_registeredSmallIconIds], kept across style
  /// reloads so the shared label-less icons can be re-uploaded without being
  /// re-baked. Every registered id always has an entry here, because an id only
  /// enters the registry through an upload made from this map.
  final Map<String, Uint8List> _smallIconBytes = {};

  /// Baked icon bytes per marker, so re-registering after a style reload is
  /// upload-only — no source re-fetch and no re-entry into the bake path.
  /// Keyed on the inputs that change what gets drawn, not just the id.
  final Map<String, _BakedMarkerIcon> _bakedIconCache = {};

  String _bakedIconKey(GeoJsonMarker marker) =>
      '${marker.id}|${marker.textVisibility}|${marker.title ?? ""}';

  bool _isAnimalMarker(GeoJsonMarker marker) =>
      marker.customRendering && marker.properties?['animalRef'] != null;

  /// Content key an animal marker's baked icon depends on: its photo plus
  /// whatever title gets baked into the pill (empty when hidden). Two
  /// markers with the same key produce byte-identical composites.
  String _animalIconKey(GeoJsonMarker marker) =>
      '${marker.assetPath}|${marker.textVisibility ? (marker.title ?? '') : ''}';

  /// Registered image id shared by every animal marker with the same
  /// [_animalIconKey] — one GPU texture per unique photo+title instead of
  /// one per marker. Only used at or above [_kLabelZoomThreshold].
  String _animalImageId(GeoJsonMarker marker) =>
      'animal-${_animalIconKey(marker).hashCode}';

  /// Content key of the label-less animal variant: the photo, and nothing
  /// else. Titles are unique per animal, so keying the label-less bake by
  /// photo+title (as [_animalIconKey] does) made ~112 byte-identical images
  /// where a handful would do.
  String _animalPhotoKey(GeoJsonMarker marker) => marker.assetPath ?? '';

  /// Shared image id for the label-less variant, one per distinct photo.
  String _animalSmallImageId(GeoJsonMarker marker) =>
      'animal-small-${_animalPhotoKey(marker).hashCode}';

  /// Fetched-and-downscaled source photos, keyed by [_animalPhotoKey]. Shared
  /// between both bake phases so phase B never re-fetches or re-resizes.
  final Map<String, Uint8List> _animalSourceCache = {};

  /// Zoom at or above which the custom-rendering layer swaps from the
  /// label-less icon to the labelled composite. Must match the `step` stop in
  /// [_customRenderingLayerProps] — the deferred phase-B bake is scheduled off
  /// this, so if they drift the labels stop appearing.
  static const double _kLabelZoomThreshold = 16;

  /// True once the labelled animal composites have been requested, so camera
  /// idles after the first one don't re-enter the batch.
  bool _labelledAnimalsStarted = false;

  /// Image id an animal marker's feature should reference right now: the
  /// shared composite once it has finished loading, otherwise the paw dot
  /// so the marker isn't blank while the real photo streams in.
  String _animalDisplayIconId(GeoJsonMarker marker) {
    if (_loadedAnimalIcons.contains(_animalIconKey(marker))) {
      return _animalImageId(marker);
    }
    // Labelled composite not baked yet (it is deferred past
    // _kLabelZoomThreshold). Show the real photo without its label rather than
    // the paw — the paw is for "no image at all yet".
    final String smallId = _animalSmallImageId(marker);
    if (_registeredSmallIconIds.contains(smallId)) return smallId;
    return marker.dotAssetPath ?? _kDotImageId;
  }

  /// Downscales [bytes] so its longest edge is at most [maxSize] px, encoding
  /// the result back to PNG. Returns the original bytes unchanged if they're
  /// already small enough — avoids pushing whatever resolution the source
  /// photo happens to be up to the GPU.
  Future<Uint8List> _resizeImageBytes(Uint8List bytes, int maxSize) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final int width = frame.image.width;
    final int height = frame.image.height;
    if (width <= maxSize && height <= maxSize) return bytes;
    final double scale = maxSize / (width > height ? width : height);
    final int targetWidth = (width * scale).round().clamp(1, maxSize);
    final int targetHeight = (height * scale).round().clamp(1, maxSize);
    final resizedCodec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final resizedFrame = await resizedCodec.getNextFrame();
    final byteData =
        await resizedFrame.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List() ?? bytes;
  }

  /// Source photo for an animal marker, fetched once per *photo* and already
  /// downscaled to [_animalMaxIconSize].
  ///
  /// Previously keyed by photo+title, so N animals sharing a species photo each
  /// re-fetched and re-decoded it. Keying by photo alone collapses that to one
  /// fetch + one resize no matter how many titles reuse the image.
  Future<Uint8List?> _animalSourceBytes(GeoJsonMarker marker) async {
    final String key = _animalPhotoKey(marker);
    final Uint8List? cached = _animalSourceCache[key];
    if (cached != null) return cached;
    Uint8List? rawBytes;
    if (marker.assetPath!.startsWith('http')) {
      rawBytes = await CacheController().fetchWithCache(marker.assetPath!);
    } else {
      final bd = await rootBundle.load(marker.assetPath!);
      rawBytes = bd.buffer.asUint8List();
    }
    if (rawBytes == null) {
      print('_animalSourceBytes: no bytes for ${marker.assetPath} '
          '(icon stays a paw placeholder)');
      return null;
    }
    // NOT pre-resized. _resizeImageBytes cost a full decode plus a PNG
    // re-encode per photo, purely to hand smaller bytes to createUnifiedMarker
    // — which instantiates its codec at the final ~80px target anyway, and now
    // reads the source dimensions from the header instead of decoding. The
    // downscale therefore happens exactly once, inside the bake, and the
    // encode/decode pair this used to add is gone.
    _animalSourceCache[key] = rawBytes;
    return rawBytes;
  }

  /// Bake parameters shared by both animal variants, so the label-less and
  /// labelled composites differ only in their text.
  Future<MarkerIconWithAnchor> _bakeAnimalIcon(
      GeoJsonMarker marker, Uint8List source, String text) {
    final double fontSize = marker.properties?["fontSize"] ?? 14.5;
    final Offset customAnchor =
        marker.renderAnchor ?? marker.anchor ?? const Offset(0.5, 0.5);
    final Size iconSize =
        Size(_animalMaxIconSize.toDouble(), _animalMaxIconSize.toDouble());
    return creator.createUnifiedMarker(
      imageSize: iconSize,
      fontSize: fontSize,
      text: text,
      imageSource: marker.assetPath,
      imageBytes: source,
      layout: MarkerLayout.vertical,
      textFormat: TextFormat.smartWrap,
      textColor: const Color(0xff000000),
      customAnchor: customAnchor,
      expandCanvasForRotation:
          (customAnchor.dx == 0.5 && customAnchor.dy == 0.5) ? false : true,
    );
  }

  /// PHASE A — the label-less animal icon, which is all the map actually draws
  /// below [_kLabelZoomThreshold] (where every venue starts).
  ///
  /// Its pixels depend only on the photo, never the title, so it is keyed and
  /// registered per photo. That is the whole point: an enclosure of 30 animals
  /// with 30 distinct names shares ONE bake and ONE upload here, where the
  /// labelled variant below would need 30 of each.
  Future<bool> _loadAnimalSmallIcon(
      MapLibreMapController controller, GeoJsonMarker marker) async {
    await _loadMarkerDotIcon(controller, marker);
    if (marker.assetPath == null) return false;
    final String smallId = _animalSmallImageId(marker);
    marker.anchor ??= const Offset(0.5, 0.5);
    // Point this marker's feature at the shared image even if another marker
    // already registered it — the property is per marker, the image is not.
    _smallIconIds[marker.id] = smallId;
    if (_registeredSmallIconIds.contains(smallId)) return false;
    try {
      Uint8List? bytes = _smallIconBytes[smallId];
      if (bytes == null) {
        final Uint8List? source = await _animalSourceBytes(marker);
        if (source == null) return false;
        final baked = await _bakeAnimalIcon(marker, source, "");
        bytes = baked.icon;
        marker.anchor = baked.anchor;
        _smallIconBytes[smallId] = bytes;
      }
      await _addImageSafe(controller, _dbgReg(smallId), bytes);
      _registeredSmallIconIds.add(smallId);
      return true;
    } catch (e) {
      print("_loadAnimalSmallIcon $e");
      return false;
    }
  }

  /// PHASE B — the labelled composite, one per photo+title.
  ///
  /// This is the expensive half (a TextPainter pass and a PNG encode per
  /// distinct name) and it is only ever drawn at or above
  /// [_kLabelZoomThreshold], so it is deferred off the load path and run when
  /// the camera actually settles at that zoom. Deferring it is what takes the
  /// animal pass off the critical path; nothing about the rendered result
  /// changes, since the labelled image was invisible at load zoom anyway.
  Future<bool> _loadAnimalLabelledIcon(
      MapLibreMapController controller, GeoJsonMarker marker) async {
    if (marker.assetPath == null) return false;
    final String contentKey = _animalIconKey(marker);
    final String imageId = _animalImageId(marker);
    if (_loadedAnimalIcons.contains(contentKey)) return false;
    try {
      Uint8List? composite = _animalIconCache[contentKey];
      if (composite == null) {
        final Uint8List? source = await _animalSourceBytes(marker);
        if (source == null) return false;
        final baked = await _bakeAnimalIcon(marker, source,
            marker.textVisibility ? (marker.title ?? "") : "");
        composite = baked.icon;
        marker.anchor = baked.anchor;
        _animalIconCache[contentKey] = composite;
      }
      await _addImageSafe(controller, _dbgReg(imageId), composite);
      _loadedAnimalIcons.add(contentKey);
      return true;
    } catch (e) {
      print("_loadAnimalLabelledIcon $e");
      return false;
    }
  }

  /// Loads every animal marker's icon in parallel (instead of one at a time)
  /// so a whole enclosure's worth of photos decode concurrently. Markers show
  /// the paw placeholder (already pushed by the caller) until this resolves.
  /// Markers are grouped by content key first so 30 lions sharing one photo
  /// dispatch a single _loadAnimalIcon call instead of 30 concurrent, mutually
  /// unaware ones that would all miss the cache and redo the same work. The
  /// source is only re-pushed if at least one icon was newly registered,
  /// guarding against a no-op re-render/flicker when every marker's icon was
  /// already loaded from a previous call.
  Future<void> _batchLoadAnimalIcons(
      MapLibreMapController controller, List<GeoJsonMarker> animalMarkers) async {
    // Grouped by PHOTO, not photo+title: this pass bakes only the label-less
    // variant, whose pixels don't depend on the name. An enclosure of 30
    // differently-named animals sharing one photo is a single group here.
    final Map<String, List<GeoJsonMarker>> groups = {};
    for (final marker in animalMarkers) {
      groups.putIfAbsent(_animalPhotoKey(marker), () => []).add(marker);
    }

    bool anyChanged = false;
    await Future.wait(groups.values.map((group) async {
      try {
        final changed = await _loadAnimalSmallIcon(controller, group.first);
        // The whole group shares one image; propagate the anchor the leader
        // resolved, and point every follower's feature at the same id (the
        // leader's _loadAnimalSmallIcon only set its own).
        for (final marker in group.skip(1)) {
          marker.anchor = group.first.anchor;
          _smallIconIds[marker.id] = _animalSmallImageId(marker);
        }
        if (changed) {
          anyChanged = true;
          // Reveal icons as they finish instead of waiting for the whole
          // batch — throttled so 20 photos landing within the same tick
          // don't each trigger their own setGeoJsonSource round trip.
          _scheduleAnimalIconRefresh(controller);
        }
      } catch (e) {
        print("_batchLoadAnimalIcons $e");
      }
    }));
    if (anyChanged) {
      // Every icon in this batch has now resolved — flush right away rather
      // than waiting out the throttle window for the last stragglers.
      _pushAnimalIconRefresh(controller);
    }
  }

  /// Bakes the labelled animal composites (phase B), one per photo+title.
  ///
  /// Deferred until the camera settles at or above [_kLabelZoomThreshold],
  /// because that is the only zoom at which the layer draws them. Runs at most
  /// once per style; a second camera idle is a no-op.
  Future<void> _ensureLabelledAnimalIcons(
      MapLibreMapController controller) async {
    if (_labelledAnimalsStarted) return;
    final animals = _symbols.where(_isAnimalMarker).toList();
    if (animals.isEmpty) return;
    _labelledAnimalsStarted = true;

    final Map<String, List<GeoJsonMarker>> groups = {};
    for (final marker in animals) {
      groups.putIfAbsent(_animalIconKey(marker), () => []).add(marker);
    }
    bool anyChanged = false;
    await PerfTrace.timeAsync(
        'deferred: labelled bake of ${groups.length} animal icons', () async {
      await Future.wait(groups.values.map((group) async {
        try {
          final changed =
              await _loadAnimalLabelledIcon(controller, group.first);
          for (final marker in group.skip(1)) {
            marker.anchor = group.first.anchor;
          }
          if (changed) {
            anyChanged = true;
            _scheduleAnimalIconRefresh(controller);
          }
        } catch (e) {
          print("_ensureLabelledAnimalIcons $e");
        }
      }));
    });
    if (anyChanged) _pushAnimalIconRefresh(controller);
  }

  /// Debounce state for progressive animal-icon reveal. setGeoJsonSource
  /// doesn't do an incremental update — it re-serializes and re-pushes
  /// *every* marker on the map (not just animals) and makes the native side
  /// re-layout the whole symbol layer, so it's expensive. Pushing once per
  /// icon (or even throttled to ~150ms) still fired that full rebuild many
  /// times over the course of a batch and visibly janked the map. Instead,
  /// completions are batched with a trailing debounce: a push only fires
  /// [_animalIconRefreshQuiet] after completions stop arriving, so a burst
  /// of icons finishing close together (the common case, since they're all
  /// fetched in parallel) collapses into a single push.
  /// [_animalIconRefreshMaxWait] caps how long a slow trickle of completions
  /// can go without any visual feedback at all.
  Timer? _animalIconRefreshTimer;
  DateTime? _animalIconRefreshWindowStart;
  static const Duration _animalIconRefreshQuiet = Duration(milliseconds: 500);
  static const Duration _animalIconRefreshMaxWait = Duration(milliseconds: 1500);

  void _scheduleAnimalIconRefresh(MapLibreMapController controller) {
    _animalIconRefreshWindowStart ??= DateTime.now();
    _animalIconRefreshTimer?.cancel();
    if (DateTime.now().difference(_animalIconRefreshWindowStart!) >=
        _animalIconRefreshMaxWait) {
      _pushAnimalIconRefresh(controller);
      return;
    }
    _animalIconRefreshTimer =
        Timer(_animalIconRefreshQuiet, () => _pushAnimalIconRefresh(controller));
  }

  void _pushAnimalIconRefresh(MapLibreMapController controller) {
    _animalIconRefreshTimer?.cancel();
    _animalIconRefreshTimer = null;
    _animalIconRefreshWindowStart = null;
    try {
      setGeoJsonSource(controller, _symbols, _clusterSourceId);
    } catch (e) {
      print("error refreshing animal markers $e");
    }
  }

  /// Registers the default collision-fallback dot image. A style reload wipes
  /// addImage() calls, so this is invoked again from [enableMarkerLayers].
  Future<void> _loadDotImage(MapLibreMapController controller) async {
    try {
      final bd = await rootBundle.load(_kDotAssetPath);
      await controller.addImage(_dbgReg(_kDotImageId), bd.buffer.asUint8List());
      _registeredDotImageIds.add(_kDotImageId);
    } catch (e) {
      print("_loadDotImage $e");
    }
  }

  /// Registers the path direction arrow images.
  Future<void> _loadPathArrowImage(MapLibreMapController controller) async {
    try {
      final bytes = await creator.createDirectionArrow();
      await _addImageSafe(controller, _kPathArrowImageId, bytes);

      final bigBytes = await creator.createBigCornerArrow();
      await _addImageSafe(controller, _kPathBigArrowImageId, bigBytes);
    } catch (e) {
      print("_loadPathArrowImage $e");
    }
  }

  /// Registers a marker's custom dot image (under its asset path as the image
  /// id) so the dot layer can reference it via the feature's `dotIcon` property.
  Future<void> _loadMarkerDotIcon(
      MapLibreMapController controller, GeoJsonMarker marker) async {
    final path = marker.dotAssetPath;
    if (path == null || _registeredDotImageIds.contains(path)) return;
    try {
      Uint8List? bytes;
      if (path.startsWith('http')) {
        bytes = await CacheController().fetchWithCache(path);
      } else {
        final bd = await rootBundle.load(path);
        bytes = bd.buffer.asUint8List();
      }
      if (bytes != null) {
        await controller.addImage(_dbgReg(path), bytes);
        _registeredDotImageIds.add(path);
      }
    } catch (e) {
      print("_loadMarkerDotIcon $e");
    }
  }

  /// Wraps [MapLibreMapController.addImage] with a retry against the native
  /// "STYLE_NOT_READY" race (see [RenderingUtilities.retryOnStyleNotReady]).
  Future<void> _addImageSafe(
    MapLibreMapController controller,
    String name,
    Uint8List bytes, [
    bool sdf = false,
  ]) {
    return RenderingUtilities.retryOnStyleNotReady(
        () => controller.addImage(name, bytes, sdf));
  }

  /// Wraps [MapLibreMapController.addSymbolLayer] with the same retry.
  Future<void> _addSymbolLayerSafe(
    MapLibreMapController controller,
    String sourceId,
    String layerId,
    SymbolLayerProperties properties, {
    String? belowLayerId,
    String? sourceLayer,
    double? minzoom,
    double? maxzoom,
    dynamic filter,
    bool enableInteraction = true,
  }) {
    return RenderingUtilities.retryOnStyleNotReady(() => controller.addSymbolLayer(
          sourceId,
          layerId,
          properties,
          belowLayerId: belowLayerId,
          sourceLayer: sourceLayer,
          minzoom: minzoom,
          maxzoom: maxzoom,
          filter: filter,
          enableInteraction: enableInteraction,
        ));
  }

  /// Uploads a baked marker's images to the current style and records what it
  /// registered, so a later style reload can repeat this without re-baking.
  ///
  /// The label-less variant is uploaded at most once per distinct
  /// [_BakedMarkerIcon.smallIconId]; markers that share a photo and pill
  /// geometry all point at that one image.
  Future<void> _registerBakedIcon(
    MapLibreMapController controller,
    GeoJsonMarker marker,
    _BakedMarkerIcon baked,
  ) async {
    if (baked.small != null) {
      _smallIconBytes[baked.smallIconId] = baked.small!;
    }
    final Uint8List? smallBytes = baked.smallIconId == marker.id
        ? null // aliases the main image; nothing separate to upload
        : (_registeredSmallIconIds.contains(baked.smallIconId)
            ? null
            : _smallIconBytes[baked.smallIconId]);
    await Future.wait([
      _addImageSafe(controller, _dbgReg(marker.id), baked.main),
      if (smallBytes != null)
        _addImageSafe(controller, _dbgReg(baked.smallIconId), smallBytes),
      if (baked.selected != null)
        _addImageSafe(
            controller, _dbgReg("${marker.id}-selected"), baked.selected!),
    ]);
    if (smallBytes != null) _registeredSmallIconIds.add(baked.smallIconId);
    _smallIconIds[marker.id] = baked.smallIconId;
    _bakedIconCache[_bakedIconKey(marker)] = baked;
    marker.anchor = baked.anchor;
  }

  Future<bool> _loadMarkerIcon(MapLibreMapController controller, GeoJsonMarker marker) async {
    if (_isAnimalMarker(marker)) {
      // Only the label-less variant. The labelled composite is deferred to
      // _ensureLabelledAnimalIcons, which runs on camera idle at label zoom.
      return _loadAnimalSmallIcon(controller, marker);
    }
    await _loadMarkerDotIcon(controller, marker);
    if (marker.assetPath == null) return false;
    // Already baked once this session — a style reload wiped the addImage()
    // registrations but not the bytes, so re-register straight from the cache
    // instead of re-fetching the photo and re-entering the bake path.
    final _BakedMarkerIcon? cachedIcon = _bakedIconCache[_bakedIconKey(marker)];
    if (cachedIcon != null) {
      try {
        await _registerBakedIcon(controller, marker, cachedIcon);
        return true;
      } catch (e) {
        print("_loadMarkerIcon (cached) $e");
      }
    }
    // Marker types that don't populate _bakedIconCache (pathStop, plain
    // icon+text markers) track their registration here instead. Cleared on
    // style reload alongside _loadedAnimalIcons.
    if (_registeredMarkerIconIds.contains(marker.id)) {
      final cachedAnchor = _markerIconAnchorCache[marker.id];
      if (cachedAnchor != null) marker.anchor = cachedAnchor;
      return true;
    }
    try {
      if (marker.customRendering) {
        // Museum POI marker: photo card + tail + dot + title, baked into one PNG.
        // Anchor is (0.5, 0.5) so the "center" keyword anchor lands the dot on
        // the coordinate. Same image is used for the zoomed-out "-small" variant
        // so the anchor stays consistent across the custom-render layer's zoom
        // icon swap.
        if(RenderingTheme.current.isMuseum && marker.properties?['poiRef'] != null){
          // Fetch the source photo once and share it between the normal and
          // selected bakes below (each used to independently fetch the same
          // URL/asset).
          Uint8List? sourceBytes;
          if (marker.assetPath!.startsWith('http')) {
            sourceBytes = await CacheController().fetchWithCache(marker.assetPath!);
          } else {
            final bd = await rootBundle.load(marker.assetPath!);
            sourceBytes = bd.buffer.asUint8List();
          }
          final poiResults = await Future.wait([
            creator.createMuseumPoiMarker(
              text: marker.textVisibility ? marker.title ?? "" : "",
              imageSource: marker.assetPath,
              imageBytes: sourceBytes,
            ),
            // Highlighted (#CD084A) variant used by the selected-marker layer
            // when this POI is tapped.
            creator.createMuseumPoiMarker(
              text: marker.textVisibility ? marker.title ?? "" : "",
              imageSource: marker.assetPath,
              imageBytes: sourceBytes,
              selected: true,
            ),
          ]);
          final poiMarker = poiResults[0];
          final poiSelected = poiResults[1];
          // The zoomed-out variant is the *same bytes* as the full one here, so
          // it is aliased to the marker id rather than uploaded a second time.
          await _registerBakedIcon(
            controller,
            marker,
            _BakedMarkerIcon(
              main: poiMarker.icon,
              smallIconId: marker.id,
              selected: poiSelected.icon,
              anchor: poiMarker.anchor,
            ),
          );
          return true;
        }
        if(marker.properties?['pathStop']??false){
          final Uint8List iconBytes = await creator.createStopMarkerIcon(
            marker.title??"",
            museum: RenderingTheme.current.isMuseum,
            stopName: marker.properties?['stopName'] ?? "",
          );
          await _addImageSafe(controller, _dbgReg(marker.id), iconBytes);
          _registeredMarkerIconIds.add(marker.id);
          return true;
        }else{
          double fontSize = marker.properties?["fontSize"]??14.5;
          Offset customAnchor = marker.renderAnchor ?? marker.anchor ?? const Offset(0.5, 0.5);
          // Gallery landmarks use a bold, shadowed, border-less translucent card
          // on a slightly smaller icon.
          final bool isGallery =
              marker.assetPath?.contains('Gallery.png') ?? false;
          final FontWeight pillWeight =
              isGallery ? FontWeight.w700 : FontWeight.w500;
          final double pillFontSize = isGallery ? 14.0 : fontSize;
          final Size markerImageSize = isGallery
              ? const Size(62, 62)
              : (marker.imageSize ?? const Size(85, 85));
          final Color pillColor =
              isGallery ? Colors.white.withOpacity(0.82) : Colors.white;
          // Fetch the source photo once and share it between the with-text
          // and without-text bakes below (each used to independently fetch
          // the same URL/asset, doubling network+disk work per marker).
          Uint8List? sourceBytes;
          if (marker.assetPath!.startsWith('http')) {
            sourceBytes = await CacheController().fetchWithCache(marker.assetPath!);
          } else {
            final bd = await rootBundle.load(marker.assetPath!);
            sourceBytes = bd.buffer.asUint8List();
          }
          // Id the label-less bake is registered under. Its bytes depend only
          // on the photo and the pill geometry, never on the marker, so every
          // marker sharing those reuses one upload.
          final String smallIconId = marker.textVisibility
              ? 'small|${marker.assetPath}|${markerImageSize.width}x${markerImageSize.height}'
                  '|$pillFontSize|$isGallery|${customAnchor.dx},${customAnchor.dy}'
              // Label hidden → the "with text" bake has text "" too, so the two
              // are byte-identical and the small variant just aliases the main.
              : marker.id;
          // The two bakes are independent — run them concurrently instead of
          // back to back. The second is skipped entirely when it would only
          // reproduce the first (no label) or bytes already registered.
          final bool needsSmallBake = marker.textVisibility &&
              !_smallIconBytes.containsKey(smallIconId);
          final iconResults = await Future.wait([
            creator.createUnifiedMarker(
              imageSize: markerImageSize,
              fontSize: pillFontSize,
              text: marker.textVisibility? marker.title??"":"",
              imageSource: marker.assetPath,
              imageBytes: sourceBytes,
              layout: MarkerLayout.vertical,
              textFormat: TextFormat.smartWrap,
              textColor: const Color(0xff000000),
              customAnchor: customAnchor,
              fontWeight: pillWeight,
              showPillBorder: !isGallery,
              pillShadow: isGallery,
              pillColor: pillColor,
              pillCornerRadius: isGallery ? 10.0 : null,
              expandCanvasForRotation: (customAnchor.dx == 0.5 && customAnchor.dy == 0.5)?false:true,
            ),
            if (needsSmallBake)
              creator.createUnifiedMarker(
                imageSize: markerImageSize,
                fontSize: pillFontSize,
                text: "",
                imageSource: marker.assetPath,
                imageBytes: sourceBytes,
                layout: MarkerLayout.vertical,
                textFormat: TextFormat.smartWrap,
                textColor: const Color(0xff000000),
                customAnchor: customAnchor,
                fontWeight: pillWeight,
                showPillBorder: !isGallery,
                pillShadow: isGallery,
                pillColor: pillColor,
                pillCornerRadius: isGallery ? 10.0 : null,
              ),
          ]);
          final markerIconWithAnchorWithText = iconResults[0];
          await _registerBakedIcon(
            controller,
            marker,
            _BakedMarkerIcon(
              main: markerIconWithAnchorWithText.icon,
              smallIconId: smallIconId,
              small: needsSmallBake ? iconResults[1].icon : null,
              anchor: markerIconWithAnchorWithText.anchor,
            ),
          );
          return true;
        }
      } else {
        Uint8List? iconBytes;
        if (marker.assetPath!.startsWith('http')) {
          final response = await CacheController().fetchWithCache(marker.assetPath!);
          iconBytes = response;
        } else {
          final bd = await rootBundle.load(marker.assetPath!);
          iconBytes = bd.buffer.asUint8List();
        }
        // A server upload that is missing or truncated must not cost the marker
        // its icon. `imageFile` wins the assetPath slot outright during parsing
        // (`assetPath ??= asset.assetPath`), so the bundled artwork the landmark
        // type already matched — cafeteria, waiting area, counter … — is carried
        // on the marker as fallbackAssetPath purely for this moment.
        if ((iconBytes == null || iconBytes.isEmpty) &&
            marker.fallbackAssetPath != null &&
            marker.fallbackAssetPath != marker.assetPath) {
          try {
            final bd = await rootBundle.load(marker.fallbackAssetPath!);
            iconBytes = bd.buffer.asUint8List();
            print('icon fallback: "${marker.title}" -> '
                '${marker.fallbackAssetPath} (remote asset unavailable)');
          } catch (e) {
            print('icon fallback failed for "${marker.title}": $e');
          }
        }
        if (iconBytes != null && iconBytes.isNotEmpty) {
          await _addImageSafe(controller, _dbgReg(marker.id), iconBytes);
          _registeredMarkerIconIds.add(marker.id);
          return true;
        }
      }
      return false;
    } catch (e) {
      print("_loadMarkerIcon $e");
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Layer initialisation
  // ---------------------------------------------------------------------------

  Future<void> enableCircleLayers(MapLibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_circleSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addCircleLayer(
        _circleSourceId,
        _normalCircleLayerId,
        _layerProps(
          _normalCircleLayerId,
          (op) => CircleLayerProperties(
            visibility: _visibility(_normalCircleLayerId),
            circleRadius: 10.0,
            circleColor: '#448AFF',
            circleOpacity: op(0.3),
            circleStrokeWidth: 2.0,
            circleStrokeColor: '#4CAF50',
            // Overridden alongside the fill: dimming the puck but leaving the
            // ring at 0.8 reads as a rendering fault, not a dimmed marker.
            circleStrokeOpacity: op(0.8),
          ),
        ),
        enableInteraction: false,
        belowLayerId: await _webSafeBelowLayerId(controller, _rotationMarkerLayerId),
      );

      _isCircleLayersEnabled = true;
      await _applyLayerPolicy(controller, only: [_normalCircleLayerId]);
    } catch (e) {
      print('Error enabling circle layers: $e');
    }
  }

  /// Multiplier applied to every marker layer's `icon-size`.
  ///
  /// Web halves them: many landmarks collapse to collision dots at once there
  /// and the icons read far too heavy against the floor plan. **Native keeps
  /// 1.0 — the sizes mobile has always shipped.** Every call site below writes
  /// its original value times this, so the native number stays readable in the
  /// source instead of being pre-multiplied away.
  ///
  /// Not applied to the custom-rendering layer (layer 3, the animal/POI
  /// composites): its ramp was never rescaled and both platforms share it.
  /// Global multiplier on every marker `iconSize`: 0.5 on web, full size on
  /// native.
  ///
  /// Native is deliberately back at 1.0 — the sizes shipped before the web work
  /// and the ones this venue is tuned for. Dropping it to 0.5 does make the
  /// collision fights milder, but that is a side effect, not the fix: dots are
  /// cleared by the marker→dot cascade in [_refreshMarkerLayerMinZooms], which
  /// works at any size. Do not shrink icons to solve a collision problem.
  ///
  /// Call sites stay written as `<value> * _kIconScale` so the native number in
  /// the source is the real one.
  static final double _kIconScale = kIsWeb ? 0.5 : 1.0;

  /// Default zoom fade used when the layers are first created; replaced at
  /// runtime by [_refreshMarkerLayerMinZooms] once the real fade zoom is known.
  static const List<dynamic> _kDefaultMarkerOpacity = [
    "interpolate", ["linear"], ["zoom"],
    12.0, 0.0,
    14.0, 1.0,
  ];

  /// Full property set for the text-only marker layer.
  ///
  /// Shared by [enableMarkerLayers] and the **web** branch of
  /// [_refreshMarkerLayerMinZooms]. `setLayerProperties` REPLACES rather than
  /// merges — it serialises with `toJson(skipNulls: false)`, so every unset
  /// field is sent as an explicit null and resets that property to its default.
  /// A partial set therefore drops `text-field`, `text-size` and the rest, and
  /// also overwrites `symbol-sort-key` with a base-less expression — and that
  /// per-layer base is what keeps each full marker sorted immediately before its
  /// own collision dot. See the comment in [_refreshMarkerLayerMinZooms] for the
  /// cascade and for why native deliberately keeps the flattened sort key.
  SymbolLayerProperties _normalTextLayerProps(dynamic textOpacity,
          {String visibility = "visible", dynamic sortKey}) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: sortKey ?? ["+", 0, _kSortKeyExpression],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: "center",
        textAllowOverlap: false,
        textOpacity: textOpacity,
      );

  /// Full property set for the icon marker layers. The with/without-sectionId
  /// variants differ only in their sort base, so they share this builder.
  SymbolLayerProperties _normalIconLayerProps({
    required int sortBase,
    required dynamic opacity,
    String visibility = "visible",
    dynamic sortKey,
  }) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: sortKey ?? ["+", sortBase, _kSortKeyExpression],
        iconImage: ["get", "icon"],
        // Covers the ordinary landmark icons — lift, entry, washroom and the
        // rest — for both the with/without-sectionId layers.
        iconSize: 0.8 * _kIconScale,
        iconAnchor: ["get", "iconAnchor"],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: "top",
        textOffset: [
          "case",
          ["==", ["get", "iconAnchor"], "bottom"],
          ["literal", [0, 0.0]],
          ["==", ["get", "iconAnchor"], "center"],
          ["literal", [0, 1.2]],
          ["literal", [0, 1.2]]
        ],
        textAllowOverlap: false,
        iconAllowOverlap: false,
        // Icon-led placement. Both of these default to false, and that default
        // is what produced the reported bug: an icon that loses its quad — an
        // image not in the style at that moment, or a placement the icon loses
        // while the label wins — leaves the LABEL drawn on its own. The
        // landmark then reads as a bare floating word, and it flips back as you
        // zoom because placement is recomputed on every pass.
        //
        //   icon-optional: false  -> no icon, no symbol. Never a naked label.
        //   text-optional: true   -> a label that cannot fit is dropped while
        //                            the icon stays.
        //
        // So the marker has exactly one behaviour: it draws its icon (with the
        // label when there is room), or it is not drawn at all and its dot
        // takes over through the cascade. That is what reads as stable when you
        // zoom, and it is why a marker never half-renders.
        iconOptional: false,
        textOptional: true,
        iconOpacity: opacity,
        textOpacity: opacity,
      );

  /// Full property set for the section polygon layer.
  ///
  /// Shared by the creation call and the later fade-zoom update for the same
  /// reason as the marker builders: `setLayerProperties` replaces a layer's
  /// properties rather than merging them, so an update passing only
  /// `fillOpacity` drops `fill-color`/`fill-outline-color` and the sections
  /// render in MapLibre's default fill, black, instead of the colour carried on
  /// each feature.
  FillLayerProperties _sectionPolygonProps(dynamic fillOpacity,
          {String visibility = "visible"}) =>
      FillLayerProperties(
        visibility: visibility,
        fillColor: ["get", "fillColor"],
        fillOpacity: fillOpacity,
        fillOutlineColor: ["get", "strokeColor"],
      );

  /// Full property set for the boundary / venue-name marker layer.
  ///
  /// Shared by [enableMarkerLayers] and by [_refreshPatchAboveOpacity], which
  /// removes and re-adds this layer rather than setting properties on it —
  /// `maxzoom` is an addLayer argument and cannot be changed any other way.
  ///
  /// [allowOverlap] differs between those two callers and is passed explicitly
  /// rather than defaulted: the creation call has always used `false` and the
  /// refresh `true`. Since the refresh runs on every venue render, `true` is
  /// what is actually on screen for all but the first moments. Preserved as-is
  /// rather than unified, so extracting this builder changes no behaviour.
  SymbolLayerProperties _patchAboveMarkerProps({
    required dynamic opacity,
    required bool allowOverlap,
    String visibility = "visible",
  }) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: ["+", 10000, _kSortKeyExpression],
        iconImage: ["get", "icon"],
        iconAnchor: [
          "case",
          ["all", ["has", "title"], ["!=", ["get", "title"], ""]],
          "bottom",
          "center"
        ],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: ["case", ["has", "icon"], "top", "center"],
        textOffset: [
          "case",
          ["has", "icon"],
          ["literal", [0, 0.2]],
          ["literal", [0, 0]]
        ],
        textAllowOverlap: allowOverlap,
        iconAllowOverlap: allowOverlap,
        iconOpacity: opacity,
        textOpacity: opacity,
      );

  /// Full property set for the section label layer. Shared by
  /// [enableMarkerLayers] and [_refreshPatchAboveOpacity] for the same
  /// remove-and-re-add reason as [_patchAboveMarkerProps].
  SymbolLayerProperties _sectionMarkerProps({
    required dynamic opacity,
    String visibility = "visible",
  }) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: ["+", 7000, _kSortKeyExpression],
        iconImage: ["get", "icon"],
        iconSize: 0.8 * _kIconScale,
        iconAnchor: ["get", "iconAnchor"],
        textField: ["get", "title"],
        textSize: 14,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 1.5,
        textAnchor: ["case", ["has", "icon"], "top", "center"],
        textOffset: [
          "case",
          ["has", "icon"],
          ["literal", [0, 0.2]],
          ["literal", [0, 0]]
        ],
        textAllowOverlap: false,
        iconAllowOverlap: false,
        iconOpacity: opacity,
        textOpacity: opacity,
      );

  /// Full property set for the custom-rendering marker layer — the zoo animal
  /// composites, museum POI pins, and anything else baked by
  /// [UnifiedMarkerCreator] rather than referenced as a plain icon.
  ///
  /// Used at creation on every platform, and by the **web** branch of
  /// [_refreshMarkerLayerMinZooms]. `icon-image` here is not what was broken —
  /// setLayerProperties merges, so it was never dropped. The load-bearing line
  /// is `symbolSortKey`'s 1500 base (see [_collisionBase] for why it sits
  /// ahead of the plain icon layers), which the refresh's partial call used to
  /// overwrite: without it every full marker flattens to ~0, they collide with
  /// each other as one block under `iconAllowOverlap: false`, and each loser
  /// falls back to the layer-0 dot — for an animal, the paw. That is the "every
  /// animal is a paw at every zoom" defect, and it is a collision-ordering bug,
  /// not an icon-loading one: the composites were registered fine throughout.
  SymbolLayerProperties _customRenderingLayerProps(dynamic iconOpacity,
          {String visibility = "visible", dynamic sortKey}) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: sortKey ?? ["+", 1500, _kSortKeyExpression],
        // The zoom step is a LABEL toggle, not a placeholder→photo swap:
        // `icon` is the composite with the title baked in, the low-zoom id the
        // same photo with text: "". Custom-rendering markers carry that id in
        // `smallIcon` (content-keyed, so one image serves many markers);
        // animals have no `smallIcon` and keep the '<icon>-small' convention
        // that _loadAnimalIcon registers, since their ids are already
        // content-keyed.
        iconImage: [
          "step",
          ["zoom"],
          [
            "coalesce",
            ["get", "smallIcon"],
            ["concat", ["get", "icon"], "-small"],
          ],
          _kLabelZoomThreshold,
          ["get", "icon"],
        ],
        // Museum POI markers (hasSelectedIcon) use a dedicated zoom curve:
        // 0.3 at z18 growing linearly to 1.0 at z22 (clamped below/above).
        // All other custom-rendering markers keep the original 14→0.2,
        // 18.3→1.0 curve. Per the iOS rule above, the zoom `interpolate`
        // stays at the top level and the per-feature branch lives in the
        // stop outputs (nesting zoom inside a `case` throws on iOS).
        iconSize: [
          "interpolate",
          ["linear"],
          ["zoom"],
          // The non-hasSelectedIcon stops carry _kAnimalWebIconScale, which is
          // 1.0 off web — so native sizing is byte-identical and only the
          // browser gets the smaller composites.
          14.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3, 0.2 * _kAnimalWebIconScale],
          18.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3, 0.9442 * _kAnimalWebIconScale],
          18.3,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 0.3525, 1.0 * _kAnimalWebIconScale],
          22.0,  ["case", ["to-boolean", ["get", "hasSelectedIcon"]], 1.0, 1.0 * _kAnimalWebIconScale],
        ],
        iconAnchor: ["get", "iconAnchor"],
        iconAllowOverlap: false,
        iconOpacity: iconOpacity,
      );

  /// Full property set for the fixed/rotated marker layer (features carrying a
  /// bearing — entry pins and the like). Shared for the same replace-not-merge
  /// reason; the refresh path only ever wanted to retune `text-opacity`, but
  /// passing that alone dropped `icon-image`, `icon-rotate` and `text-field`.
  ///
  /// [textOpacity] is null at creation time (the layer ships without an
  /// explicit text-opacity) and carries the venue-fit fade once
  /// [_refreshMarkerLayerMinZooms] knows it.
  SymbolLayerProperties _fixedMarkerLayerProps({
    required dynamic iconOpacity,
    dynamic textOpacity,
    String visibility = "visible",
    dynamic sortKey,
  }) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: sortKey ?? ["+", 1000, _kSortKeyExpression],
        textRotate: ["get", "bearing"],
        textRotationAlignment: "map",
        textField: ["get", "title"],
        textSize: 12,
        textColor: "#000000",
        textHaloColor: "#f8f9fa",
        textHaloWidth: 2,
        textAnchor: "center",
        textAllowOverlap: false,
        textOpacity: textOpacity,
        iconImage: ["get", "icon"],
        // Fixed markers, which include the main entry pin. The 0.0 floor is a
        // fade-in, so only the top of the ramp scales.
        iconSize: [
          "interpolate",
          ["linear"],
          ["zoom"],
          18, 0.0,
          22.0, 1.0 * _kIconScale,
        ],
        iconAnchor: ["get", "iconAnchor"],
        iconOpacity: iconOpacity,
        iconRotate: ["get", "bearing"],
        iconRotationAlignment: "map",
        iconAllowOverlap: false,
      );

  Future<void> enableMarkerLayers(dynamic controller) async  {
    if (controller is! MapLibreMapController) return;

    try {
      // addGeoJsonSource() cannot set maxzoom and silently defaults to 18 —
      // geojson-vt then only tiles marker data up to z18, and every marker
      // vanishes once the camera zooms past that (over-zoomed tiles for a
      // point source lose their symbols instead of just looking coarser).
      // Furniture already learned this lesson (see its own maxzoom: 22
      // comment); apply the same fix here via the richer addSource() API.
      // Wrapped per-call because, unlike addGeoJsonSource(), addSource()
      // has no "already exists" guard on the native side and throws on a
      // style-reload re-add — which would otherwise abort every layer setup
      // after it in this function.
      try {
        await controller.addSource(
          _clusterSourceId,
          const GeojsonSourceProperties(
            data: {'type': 'FeatureCollection', 'features': []},
            maxzoom: 22,
          ),
        );
      } catch (_) {
        // Source already exists on the native side — fine, carry on.
      }
      try {
        await controller.addSource(
          _rotationSourceId,
          const GeojsonSourceProperties(
            data: {'type': 'FeatureCollection', 'features': []},
            maxzoom: 22,
          ),
        );
      } catch (_) {
        // Source already exists on the native side — fine, carry on.
      }
      // Both sources exist again — async pushes (compass, animation) may resume.
      _markerSourcesReady = true;

      // Register the collision-fallback dot image (style reload wipes images).
      await _loadDotImage(controller);

      // Layer 0: Collision-fallback dots.
      // One dot per collision-participating marker, drawn beneath the full
      // markers. Its symbolSortKey places each dot immediately after its own
      // full marker in MapLibre's single global collision pass:
      //   full = collisionBase + (-priority);  dot = collisionBase + 0.6 + (-priority)
      // Resulting cascade (all via native iconAllowOverlap:false placement):
      //   • 2 markers collide → winner shows full; loser's full is hidden and
      //     its small dot places in the gap (marker → dot).
      //   • marker vs existing dot → the marker's full collides with the dot and
      //     is hidden, so the marker also falls back to its dot.
      //   • 2 dots collide → the lower-priority dot is hidden.
      // The winner never shows a dot: its own dot collides with its own full.
      await controller.addSymbolLayer(
        _clusterSourceId,
        _dotMarkerLayerId,
        _layerProps(_dotMarkerLayerId, (op) => SymbolLayerProperties(
          visibility: _visibility(_dotMarkerLayerId),
          symbolSortKey: ["+", ["get", "collisionBase"], 0.6, _kSortKeyExpression],
          iconImage: ["get", "dotIcon"],
          // The dot is a bundled PNG registered via addImage, so its on-screen
          // size is image pixels × iconSize. Full size on native; web halves it
          // because many landmarks collapse to dots there at once.
          iconSize: 1.0 * _kIconScale,
          iconAnchor: "center",
          iconAllowOverlap: false,
          textAllowOverlap: false,
          // Mirror the per-type zoom visibility of the full markers: text (base
          // 0) and icon-with-sectionId (base 3000) only appear from zoom 18;
          // everything else fades in 12→14 like the normal icon markers.
          // MapLibre only allows a `zoom` expression at the very top level, so
          // we cannot nest `step`/`interpolate` over zoom inside a `case` (doing
          // so makes NSExpression(mglJSONObject:) throw an uncaught NSException
          // on iOS and aborts the app). Instead keep `interpolate` over zoom at
          // the top and move the per-feature branch into the stop outputs:
          //   • collisionBase 0/3000 → stays 0 until ~z18, then jumps to 1
          //     (near-instant step, matching the previous `step` behaviour).
          //   • everything else → fades in linearly 12→14, matching the
          //     previous `interpolate`.
          iconOpacity: op([
            "interpolate",
            ["linear"],
            ["zoom"],
            12.0,
            ["case", _kDotStepGroupExpression, 0.0, 0.0],
            14.0,
            ["case", _kDotStepGroupExpression, 0.0, 1.0],
            17.999,
            ["case", _kDotStepGroupExpression, 0.0, 1.0],
            18.0,
            ["case", _kDotStepGroupExpression, 1.0, 1.0],
          ]),
        )),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          // A selected feature is never a dot. Its full marker is now forced
          // visible by the selected layer regardless of collision, so the dot
          // is no longer a fallback for it — it would just sit behind the
          // highlighted icon.
          ["!", ["to-boolean", ["get", "isSelected"]]],
        ],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 1: Normal text markers (no icon, no bearing)
      await controller.addSymbolLayer(
          _clusterSourceId,
          _normalTextMarkerLayerId,
          _layerProps(
              _normalTextMarkerLayerId,
              (op) => _normalTextLayerProps(op(_kDefaultMarkerOpacity),
                  visibility: _visibility(_normalTextMarkerLayerId))),
          filter: [
            "all",
            ["!", ["to-boolean", ["get", "overlapOverride"]]],
            ["!", ["to-boolean", ["get", "isPriority"]]],
            ["!", ["to-boolean", ["get", "section"]]],
            ["!", ["to-boolean", ["get", "subSection"]]],
            ["!", ["to-boolean", ["get", "boundary"]]],
            ["!", ["to-boolean", ["get", "bearing"]]],
            ["!", ["to-boolean", ["get", "icon"]]],
            // The selected marker's label is drawn (enlarged) by Layer 10 —
            // don't also draw it here at rest size underneath.
            ["!", ["to-boolean", ["get", "isSelected"]]],
          ],
          enableInteraction: true,
          belowLayerId: null,
          minzoom: 18.0
      );

      // Layer 2: Normal icon markers (has icon, no bearing) — with sectionId
      await controller.addSymbolLayer(
        _clusterSourceId,
        "$_normalIconMarkerLayerId-withSectionId",
        _layerProps(
            "$_normalIconMarkerLayerId-withSectionId",
            (op) => _normalIconLayerProps(
                sortBase: 3000,
                opacity: op(_kDefaultMarkerOpacity),
                visibility:
                    _visibility("$_normalIconMarkerLayerId-withSectionId"))),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          // A selected marker is drawn by the selected layer instead. Without
          // this, the SAME feature is rendered twice — here at base 3000 and
          // again at 8000 — and because both layers have iconAllowOverlap
          // false, the two copies collide with each other. Which one wins is
          // re-decided on every placement pass, so the icon flickers between
          // its plain and highlighted form. Layer 3 has carried this exclusion
          // all along; these two layers were missed.
          ["!", ["to-boolean", ["get", "isSelected"]]],
          ["to-boolean", ["get", "sectionId"]],
          ["!", ["to-boolean", ["get", "customRendering"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalTextMarkerLayerId),
        // No minzoom. This layer used to be gated at z18, so an icon+label
        // landmark drew nothing below 18 and popped in at 18 — the swap that
        // reads as the marker "refreshing" on a zoom in/out. The gate is not
        // needed to keep the map uncluttered: these markers participate in the
        // same collision pass as every other icon layer, so a crowded plan
        // thins itself out and each loser falls back to its own dot via the
        // cascade in [_refreshMarkerLayerMinZooms].
        //
        // Paired with dropping base 3000 from [_kDotStepGroupExpression] — the
        // dot ramp has to stop special-casing these or the dot stays hidden
        // below 18 and the fallback has nothing to draw.
      );

      // Layer 2b: Normal icon markers — without sectionId
      await controller.addSymbolLayer(
        _clusterSourceId,
        "$_normalIconMarkerLayerId-withoutSectionId",
        _layerProps(
            "$_normalIconMarkerLayerId-withoutSectionId",
            (op) => _normalIconLayerProps(
                sortBase: 2000,
                opacity: op(_kDefaultMarkerOpacity),
                visibility: _visibility(
                    "$_normalIconMarkerLayerId-withoutSectionId"))),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          // Same double-draw exclusion as the withSectionId layer above.
          ["!", ["to-boolean", ["get", "isSelected"]]],
          ["!", ["to-boolean", ["get", "sectionId"]]],
          ["!", ["to-boolean", ["get", "customRendering"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalTextMarkerLayerId),
      );

      // Layer 3: Custom rendering markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _customRenderingMarkerLayerId,
        _layerProps(
            _customRenderingMarkerLayerId,
            (op) => _customRenderingLayerProps(op(_kDefaultMarkerOpacity),
                visibility: _visibility(_customRenderingMarkerLayerId))),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "bearing"]]],
          // When selected, the marker is drawn (and highlighted) by the selected
          // layer instead; excluding it here avoids the base image colliding with
          // or peeking out from behind the highlighted one.
          ["!", ["to-boolean", ["get", "isSelected"]]],
          ["to-boolean", ["get", "customRendering"]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
      );

      // Layer 4: Normal fixed/rotated markers (has bearing)
      await controller.addSymbolLayer(
        _clusterSourceId,
        _fixedMarkerLayerId,
        _layerProps(
            _fixedMarkerLayerId,
            (op) => _fixedMarkerLayerProps(
                  iconOpacity: op(_kDefaultMarkerOpacity),
                  // Entry pins are hidden by the renderer in 3D; a policy can
                  // hide them further but cannot force them back on.
                  visibility: _visibility(_fixedMarkerLayerId,
                      internalVisible: !_config.immersive),
                )),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "overlapOverride"]]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["to-boolean", ["get", "bearing"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalIconMarkerLayerId),
      );

      // Layer 5: Boundary / patch-above markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _patchAboveMarkerLayerId,
        _layerProps(
            _patchAboveMarkerLayerId,
            (op) => _patchAboveMarkerProps(
                  opacity: op(const [
                    "interpolate", ["linear"], ["zoom"],
                    12, 1.0,
                    14, 0.0,
                  ]),
                  allowOverlap: false,
                  visibility: _visibility(_patchAboveMarkerLayerId),
                )),
        filter: ["to-boolean", ["get", "boundary"]],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _fixedMarkerLayerId),
      );

      // Layer 6: Section markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _sectionMarkerLayerId,
        _layerProps(
            _sectionMarkerLayerId,
            (op) => _sectionMarkerProps(
                  opacity: op(const [
                    "interpolate", ["linear"], ["zoom"],
                    17, 1.0,
                    18, 0.0,
                  ]),
                  visibility: _visibility(_sectionMarkerLayerId),
                )),
        filter: ["to-boolean", ["get", "section"]],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _fixedMarkerLayerId),
      );

      // Layer 7: SubSection markers
      await controller.addSymbolLayer(
          _clusterSourceId,
          _subSectionMarkerLayerId,
          _layerProps(_subSectionMarkerLayerId, (op) => SymbolLayerProperties(
            visibility: _visibility(_subSectionMarkerLayerId),
            symbolSortKey: ["+", 6000, _kSortKeyExpression],
            iconImage: ["get", "icon"],
            iconSize: 1.5 * _kIconScale, // subSection markers
            textField: ["get", "title"],
            textSize: 12,
            textColor: "#000000",
            textHaloColor: "#f8f9fa",
            textHaloWidth: 2,
            textAnchor: "center",
            iconAllowOverlap: false,
            textAllowOverlap: false,
            iconOpacity: op(const [
              "interpolate",
              ["linear"],
              ["zoom"],
              12.0, 0.0,
              14.0, 1.0
            ]),
            textOpacity: op(const [
              "interpolate",
              ["linear"],
              ["zoom"],
              12.0, 0.0,
              14.0, 1.0
            ]),
          )),
          filter: ["to-boolean", ["get", "subSection"]],
          enableInteraction: true,
          belowLayerId: await _webSafeBelowLayerId(controller, _fixedMarkerLayerId),
          maxzoom: 18.0,
          minzoom: 17.0
      );

      // Layer 8: Rotation markers (separate source)
      await controller.addSymbolLayer(
        _rotationSourceId,
        _rotationMarkerLayerId,
        _layerProps(_rotationMarkerLayerId, (op) => SymbolLayerProperties(
          visibility: _visibility(_rotationMarkerLayerId),
          symbolSortKey: ["+", 9000, _kSortKeyExpression],
          // The layer shipped without an explicit icon-opacity; naming it here
          // is what lets a userLocation override reach it. op(null) resolves to
          // null when no override is set, which serialises the same as before.
          iconOpacity: op(null),
          iconImage: ["get", "icon"],
          // Web only: scale with zoom like every other marker layer, rather
          // than holding one size while the floor plan grows and shrinks under
          // it. Same 14 → 18.3 ramp the other custom-rendering markers use,
          // scaled so the top of the curve is the 0.75 tuned above instead of
          // 1.0 — the arrow keeps its established weight zoomed in and stops
          // swamping the plan zoomed out. Native deliberately keeps the plain
          // scalar: this was asked for on web, and a bare number cannot trip
          // the iOS zoom-expression hazard documented on Layer 0.
          iconSize: kIsWeb
              ? [
                  "interpolate",
                  ["linear"],
                  ["zoom"],
                  14.0, 0.15,
                  18.0, 0.7082,
                  18.3, 0.75,
                  22.0, 0.75,
                ]
              // The one call site 6f387c5 left as a bare number. Written with
              // the multiplier like every other layer so it tracks _kIconScale
              // instead of silently staying at double the reference size.
              : 1.5 * _kIconScale,
          iconRotate: ["get", "bearing"],
          iconRotationAlignment: "map",
          iconAllowOverlap: true,
          // Keep the puck OUT of the collision index. During guided navigation
          // its source is re-pushed many times a second (the glide in
          // _animateMarkerToPosition); if the puck is a collision obstacle,
          // every one of those pushes forces MapLibre to re-run symbol
          // placement for every nearby venue marker/label — the "location
          // update makes the whole map lag/jitter" symptom. With
          // ignore-placement it moves freely and perturbs nothing.
          iconIgnorePlacement: true,
          textAllowOverlap: true,
          textIgnorePlacement: true,
        )),
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _sectionMarkerLayerId),
      );

      // Layer 9: isPriority markers
      await controller.addSymbolLayer(
        _clusterSourceId,
        _priorityMarkerLayerId,
        _layerProps(_priorityMarkerLayerId, (op) => SymbolLayerProperties(
          visibility: _visibility(_priorityMarkerLayerId),
          symbolSortKey: ["+", 5000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          // Same standalone-pin class as the user and selected markers, so it
          // keeps the same visual weight as those.
          iconSize: 1.5 * _kIconScale,
          iconAllowOverlap: true,
          textAllowOverlap: false,
          iconOpacity: op(null),
          textOpacity: op(null),
        )),
        filter: ["to-boolean", ["get", "isPriority"]],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 9b: Temporary allow-overlap override markers.
      // Mirrors the normal icon-marker styling but with icon/text overlap forced
      // on, so toggled markers stay visible regardless of collision. Excludes
      // priority/structural markers (they are handled by their own layers).
      await controller.addSymbolLayer(
        _clusterSourceId,
        _overlapOverrideMarkerLayerId,
        _layerProps(_overlapOverrideMarkerLayerId, (op) => SymbolLayerProperties(
          visibility: _visibility(_overlapOverrideMarkerLayerId),
          symbolSortKey: ["+", 15000, _kSortKeyExpression],
          iconImage: ["get", "icon"],
          iconSize: 0.8 * _kIconScale, // overlap-override markers
          iconAnchor: ["get", "iconAnchor"],
          textField: ["get", "title"],
          textSize: 14,
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: [
            "case",
            ["==", ["get", "iconAnchor"], "bottom"],
            ["literal", [0, 0.0]],
            ["==", ["get", "iconAnchor"], "center"],
            ["literal", [0, 1.2]],
            ["literal", [0, 1.2]]
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
          iconOpacity: op(null),
          textOpacity: op(null),
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "overlapOverride"]],
          ["!", ["to-boolean", ["get", "isPriority"]]],
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subSection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
        ],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 10: Selected marker
      await controller.addSymbolLayer(
        _clusterSourceId,
        _selectedMarkerLayerId,
        _layerProps(_selectedMarkerLayerId, (op) => SymbolLayerProperties(
          visibility: _visibility(_selectedMarkerLayerId,
              internalVisible: _anyMarkerGroupVisible),
          // Placed first in MapLibre's single global collision pass (lowest
          // sort key) so the selected marker's label wins against every
          // neighbour. Paired with textIgnorePlacement:false below, a
          // neighbouring label that would overlap the selected label yields
          // and hides instead of drawing through it.
          symbolSortKey: ["+", -100000, _kSortKeyExpression],
          iconImage: [
            "case",
            // Text-only marker (a selected room/polygon label): no icon image.
            ["!", ["to-boolean", ["get", "icon"]]],
            "",
            ["to-boolean", ["get", "hasSelectedIcon"]],
            ["concat", ["get", "icon"], "-selected"],
            ["get", "icon"],
          ],
          // Flat (no zoom ramp): the selected marker should read the same size
          // at every zoom, so the size ONLY comes from the per-feature
          // `iconScaleFactor` (1.0 normally, _kSelectedMarkerRestScale while
          // selected, or the tap-animation curve when a style is set). A
          // per-type base keeps a selected animal photo / POI at its full
          // on-map size and a plain landmark icon just above its 0.8 resting
          // size, before that multiplier is applied.
          iconSize: [
            "*",
            [
              "case",
              ["to-boolean", ["get", "customRendering"]],
              1.0 * _kAnimalWebIconScale,
              0.9 * _kIconScale,
            ],
            ["get", "iconScaleFactor"],
          ],
          iconRotate: ["get", "iconShake"],
          iconRotationAlignment: "viewport",
          // Custom-rendering markers (animal photos, museum POIs) bake their
          // name straight into the icon image — see _customRenderingLayerProps,
          // which has no textField. Drawing ["get","title"] here too gave the
          // selected animal marker a second, raw label that the unselected
          // marker never shows (e.g. the Sangai deer's parenthetical species
          // name wrapping into stray "(" / ")" lines). Suppress the duplicate.
          textField: [
            "case",
            ["to-boolean", ["get", "customRendering"]],
            "",
            ["get", "title"],
          ],
          textSize: ["*", 14, 1.3], // keep this number equal to peakLabelScale above
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          // With an icon the label sits below it; a text-only marker keeps the
          // centred, unoffset placement its resting (Layer 1) version uses so
          // the label doesn't jump position on selection.
          textAnchor: ["case", ["to-boolean", ["get", "icon"]], "top", "center"],
          textOffset: [
            "case",
            ["to-boolean", ["get", "icon"]],
            ["literal", [0, 1.2]],
            ["literal", [0, 0]],
          ],
          iconAllowOverlap: true,
          textAllowOverlap: true,
          // Both the (enlarged) selected icon and its label are added to the
          // collision index, and this layer is placed first (lowest sort key
          // above), so a neighbouring marker's icon or label that would overlap
          // the selected pin gives way and hides instead of drawing across it.
          // The selected marker itself is still always shown via
          // icon/textAllowOverlap.
          iconIgnorePlacement: false,
          textIgnorePlacement: false,
          iconOpacity: op(null),
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "isSelected"]],
          ["!", ["to-boolean", ["get", "isAnimating"]]],
          // Render the selected marker if it has an icon OR just a label — a
          // room/polygon whose marker is text-only (shown as the green
          // collision dot at rest) still gets its label enlarged on tap.
          ["any", ["to-boolean", ["get", "icon"]], ["to-boolean", ["get", "title"]]],
        ],
        enableInteraction: true,
        belowLayerId: null,
      );

      // Layer 11: Animated marker — a separate, tiny source that only ever
      // holds the single marker currently being tap-animated. Updating this
      // every tick is cheap; updating the whole clusterSource every tick is not.
      await controller.addGeoJsonSource(_animatedMarkerSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });
      await _addSymbolLayerSafe(controller,
        _animatedMarkerSourceId,
        _animatedMarkerLayerId,
        SymbolLayerProperties(
          iconImage: ["get", "icon"],
          iconSize: ["*", 0.8, ["get", "iconScaleFactor"]],
          iconRotate: ["get", "iconShake"],
          iconRotationAlignment: "viewport",
          iconAnchor: "center",
          textField: ["get", "title"],
          textSize: ["*", 14, ["get", "labelScale"]],
          textColor: "#000000",
          textHaloColor: "#f8f9fa",
          textHaloWidth: 1.5,
          textAnchor: "top",
          textOffset: ["literal", [0, 1.2]],
          iconAllowOverlap: true,
          textAllowOverlap: true,
          iconIgnorePlacement: true,
          textIgnorePlacement: true,
        ),
        enableInteraction: false,
        belowLayerId: null,
      );

      _isClusteringEnabled = true;
      await _applyLayerPolicy(controller);

      if (_symbols.isNotEmpty) {
        final symbols = [..._symbols];
        setGeoJsonSource(controller, symbols, _clusterSourceId);
      }

      // The marker layers are up now, so any fade recompute that was skipped
      // by the guard in _refreshPatchFadeIfStale can safely run. No-ops when
      // the polygons have not landed yet — that push calls back in itself.
      await _refreshPatchFadeIfStale(controller);
    } catch (e, stack) {
      print('Error enabling marker layers: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> enablePolygonLayers(MapLibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polygonSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      /// 1️⃣ SECTION (TOP-MOST among polygon layers)
      await controller.addFillLayer(
        _polygonSourceId,
        _sectionPolygonLayerId,
        _layerProps(
            _sectionPolygonLayerId,
            (op) => _sectionPolygonProps(
                  // `op` sits on the ramp's PEAK stop, not around the whole
                  // expression. Wrapping the expression let a host override
                  // replace the ramp with a constant, so a dimmed venue drew
                  // section fills at every zoom instead of only across their
                  // fade window. Here the override sets how strong the peak is
                  // and the 0.0 stops stay 0.0.
                  [
                    "interpolate", ["linear"], ["zoom"],
                    16, 0.0,
                    17, op(1.0),
                    17.5, 0.0
                  ],
                  visibility: _visibility(_sectionPolygonLayerId),
                )),
        filter: [
          "all",
          ["to-boolean", ["get", "section"]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        belowLayerId: await _webSafeBelowLayerId(controller, _polylineLayerId),
      );

      /// 2️⃣ SUBSECTION
      await controller.addFillLayer(
        _polygonSourceId,
        _subSectionPolygonLayerId,
        _layerProps(_subSectionPolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_subSectionPolygonLayerId),
          fillColor: ["get", "fillColor"],
          fillOpacity: op(const ["get", "fillOpacity"]),
          fillOutlineColor: ["get", "strokeColor"],
        )),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["to-boolean", ["get", "subsection"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        minzoom: 17.0,
        maxzoom: 18.0,
        belowLayerId: await _webSafeBelowLayerId(controller, _sectionPolygonLayerId),
      );

      /// 3️⃣ SELECTED
      await controller.addFillLayer(
        _polygonSourceId,
        _selectedPlainPolygonLayerId,
        _layerProps(_selectedPlainPolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_selectedPlainPolygonLayerId),
          fillColor: "#4CAF50",
          fillOpacity: op(0.6),
          fillOutlineColor: "#2E7D32",
        )),
        filter: [
          "all",
          ["!", ["has", "height"]],
          ["to-boolean", ["get", "isSelected"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _subSectionPolygonLayerId),
      );

      // Stroke for the flat selected polygon. The height filter keeps it to the
      // 2D rendering only; in 3D the selection is drawn by the extrusion layer.
      await controller.addLineLayer(
        _polygonSourceId,
        _selectedPlainPolygonStrokeLayerId,
        _layerProps(_selectedPlainPolygonStrokeLayerId,
            (op) => LineLayerProperties(
          visibility: _visibility(_selectedPlainPolygonStrokeLayerId),
          lineColor: "#1B5E20",
          lineWidth: 2.5,
          lineOpacity: op(1.0),
          lineJoin: "round",
          lineCap: "round",
        )),
        filter: [
          "all",
          ["!", ["has", "height"]],
          ["to-boolean", ["get", "isSelected"]],
        ],
        enableInteraction: false,
        belowLayerId: await _webSafeBelowLayerId(controller, _subSectionPolygonLayerId),
      );

      await controller.addFillExtrusionLayer(
        _polygonSourceId,
        _selectedExtrudedPolygonLayerId,
        _layerProps(_selectedExtrudedPolygonLayerId,
            (op) => FillExtrusionLayerProperties(
          visibility: _visibility(_selectedExtrudedPolygonLayerId),
          fillExtrusionColor: "#4CAF50",
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          // Zeroed in 2D by the renderer to suppress residual shading. That is
          // an internal off, so it wins over a host override — otherwise
          // dimming this group would resurrect extrusions in 2D.
          fillExtrusionOpacity: _config.immersive ? op(1.0) : 0.0,
        )),
        filter: [
          "all",
          ['has', 'height'],
          ["to-boolean", ["get", "isSelected"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _subSectionPolygonLayerId),
      );
      _layerReAdders[_selectedExtrudedPolygonLayerId] = () async {
        await controller.removeLayer(_selectedExtrudedPolygonLayerId);
        await controller.addFillExtrusionLayer(
          _polygonSourceId,
          _selectedExtrudedPolygonLayerId,
          _layerProps(_selectedExtrudedPolygonLayerId,
              (op) => FillExtrusionLayerProperties(
                    visibility: _visibility(_selectedExtrudedPolygonLayerId),
                    fillExtrusionColor: "#4CAF50",
                    fillExtrusionHeight: ["get", "height"],
                    fillExtrusionBase: ["get", "base_height"],
                    fillExtrusionOpacity:
                        _config.immersive ? op(1.0) : 0.0,
                  )),
          filter: [
            "all",
            ['has', 'height'],
            ["to-boolean", ["get", "isSelected"]],
          ],
          enableInteraction: true,
          belowLayerId: await _webSafeBelowLayerId(
              controller, _subSectionPolygonLayerId),
        );
      };

      /// 4️⃣ EXTRUDED
      await controller.addFillExtrusionLayer(
        _polygonSourceId,
        _extrudedPolygonLayerId,
        _layerProps(_extrudedPolygonLayerId,
            (op) => FillExtrusionLayerProperties(
          visibility: _visibility(_extrudedPolygonLayerId),
          fillExtrusionColor: ["get", "fillColor"],
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: _config.immersive ? op(1.0) : 0.0,
        )),
        filter: [
          "all",
          ['has', 'height'],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        belowLayerId: await _webSafeBelowLayerId(controller, _selectedPlainPolygonLayerId),
      );
      _layerReAdders[_extrudedPolygonLayerId] = () async {
        await controller.removeLayer(_extrudedPolygonLayerId);
        await controller.addFillExtrusionLayer(
          _polygonSourceId,
          _extrudedPolygonLayerId,
          _layerProps(_extrudedPolygonLayerId,
              (op) => FillExtrusionLayerProperties(
                    visibility: _visibility(_extrudedPolygonLayerId),
                    fillExtrusionColor: ["get", "fillColor"],
                    fillExtrusionHeight: ["get", "height"],
                    fillExtrusionBase: ["get", "base_height"],
                    fillExtrusionOpacity:
                        _config.immersive ? op(1.0) : 0.0,
                  )),
          filter: [
            "all",
            ['has', 'height'],
            ["!", ["to-boolean", ["get", "hasPattern"]]],
          ],
          belowLayerId: await _webSafeBelowLayerId(
              controller, _selectedPlainPolygonLayerId),
        );
      };

      /// 5️⃣ NORMAL
      await controller.addFillLayer(
        _polygonSourceId,
        _normalPolygonLayerId,
        _layerProps(_normalPolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_normalPolygonLayerId),
          fillColor: ["get", "fillColor"],
          fillOpacity: op(const ["get", "fillOpacity"]),
          fillOutlineColor: ["get", "strokeColor"],
        )),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
          ["!", ["has", "height"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _extrudedPolygonLayerId),
      );

      /// 6️⃣ NORMAL with texture
      await controller.addFillLayer(
        _polygonSourceId,
        _patternPolygonLayerId,
        _layerProps(_patternPolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_patternPolygonLayerId),
          fillColor: ["get", "fillColor"],
          fillOpacity: op(const ["get", "fillOpacity"]),
          fillOutlineColor: ["get", "strokeColor"],
          fillPattern: ["get", "pattern"],
        )),
        filter: [
          "all",
          ["!", ["to-boolean", ["get", "section"]]],
          ["!", ["to-boolean", ["get", "subsection"]]],
          ["!", ["to-boolean", ["get", "boundary"]]],
          ["to-boolean", ["get", "hasPattern"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _extrudedPolygonLayerId),
      );

      /// 7️⃣ PATCH BELOW (zoom >= 14 → bottom-most)
      await controller.addFillLayer(
        _polygonSourceId,
        _patchBelowPolygonLayerId,
        _layerProps(_patchBelowPolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_patchBelowPolygonLayerId),
          fillColor: ["get", "fillColor"],
          fillOpacity: op(const ["get", "fillOpacity"]),
          fillOutlineColor: ["get", "strokeColor"],
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "boundary"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        minzoom: 13.5,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalPolygonLayerId),
      );

      /// 8️⃣ PATCH ABOVE (zoom < 14 → top-most)
      await controller.addFillLayer(
        _polygonSourceId,
        _patchAbovePolygonLayerId,
        _layerProps(_patchAbovePolygonLayerId, (op) => FillLayerProperties(
          visibility: _visibility(_patchAbovePolygonLayerId),
          fillColor: ["get", "fillColorSecondary"],
          // Override on the peak stop only — see the section layer above.
          fillOpacity: [
            "interpolate",
            ["linear"],
            ["zoom"],
            13, op(1.0),
            14, 0.0
          ],
          fillOutlineColor: ["get", "strokeColor"],
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "boundary"]],
          ["!", ["has", "height"]],
          ["!", ["to-boolean", ["get", "hasPattern"]]],
        ],
        enableInteraction: false,
        belowLayerId: await _webSafeBelowLayerId(controller, _polylineLayerId),
      );

      _isPolygonLayersEnabled = true;
      await _applyLayerPolicy(controller);

      if (_polygons.isNotEmpty) {
        await _updatePolygonSource(controller);
      }
    } catch (e, stack) {
      print('Error enabling polygon layers: $e');
      print('Stack trace: $stack');
    }
  }

  Future<void> _refreshPatchAboveOpacity(
      MapLibreMapController controller, {
        Size? screenSize,
      }) async {
    // Steps 2-4 below remove/re-add the patch-above and section MARKER layers
    // and then set properties on the rest of them, so none of it can run before
    // [enableMarkerLayers] has created them.
    //
    // It could: enablePolygonLayers runs first in onStyleLoadedCallback and
    // ends by pushing its source, which reaches here via _updatePolygonSource →
    // _refreshPatchFadeIfStale. That path used to re-add
    // patch-above-markers-layer while marker layers did not exist yet, and the
    // damage was silent and total — removeLayer no-ops on a missing layer, so
    // the re-add SUCCEEDED and left the layer sitting there. enableMarkerLayers
    // then threw CannotAddLayerException("Layer patch-above-markers-layer
    // already exists") partway through, aborting before `_isClusteringEnabled =
    // true` and before it pushed `_symbols` to the source, so the map rendered
    // with no markers at all and only a caught print to show for it.
    //
    // Nothing is lost by skipping: onStyleLoadedCallback calls this again after
    // every enable*Layers has run, which is where the real fade thresholds get
    // applied.
    if (!_isClusteringEnabled) return;

    final boundaryPolygons = _polygons.where((p) =>
    p.properties?['type']?.toString().toLowerCase() == 'boundary'
    ).toList();

    final fitZoom = _calculateFitZoom(
      boundaryPolygons.isNotEmpty ? boundaryPolygons : _polygons,
      screenSize: screenSize,
    ) - 2.0;

    final fadeOutZoom = fitZoom;
    final fadeInZoom  = fitZoom - 0.5;

    _fadeOutZoom = fadeOutZoom;

    // 1. Boundary polygon fade layer
    // Full property set. This used to send only fillColor + fillOpacity, which
    // — setLayerProperties replacing rather than merging — reset
    // fill-outline-color to its default on every venue render.
    await controller.setLayerProperties(
      _patchAbovePolygonLayerId,
      _layerProps(_patchAbovePolygonLayerId, (op) => FillLayerProperties(
        visibility: _visibility(_patchAbovePolygonLayerId),
        fillColor: ["get", "fillColorSecondary"],
        fillOpacity: _fadeRamp(op, () => [
          "interpolate", ["linear"], ["zoom"],
          fadeInZoom, op(1.0),
          fadeOutZoom, 0.0,
        ]),
        fillOutlineColor: ["get", "strokeColor"],
      )),
    );

    // 2. Boundary marker fade layer — remove and re-add to update maxzoom
    await controller.removeLayer(_patchAboveMarkerLayerId);
    await controller.addSymbolLayer(
      _clusterSourceId,
      _patchAboveMarkerLayerId,
      _layerProps(
          _patchAboveMarkerLayerId,
          (op) => _patchAboveMarkerProps(
                opacity: _fadeRamp(op, () => op([
                  "interpolate", ["linear"], ["zoom"],
                  fadeInZoom, 1.0,
                  fadeOutZoom, 0.0,
                ])),
                allowOverlap: true,
                visibility: _visibility(_patchAboveMarkerLayerId),
              )),
      filter: ["to-boolean", ["get", "boundary"]],
      enableInteraction: true,
      belowLayerId: await _webSafeBelowLayerId(controller, _fixedMarkerLayerId),
      maxzoom: fadeOutZoom,
    );

    print("fadeOutZoom $fadeOutZoom");

    // Full property set — passing only fillOpacity here is what dropped
    // fill-color and left the sections rendering black.
    await controller.setLayerProperties(
      _sectionPolygonLayerId,
      _layerProps(
          _sectionPolygonLayerId,
          (op) => _sectionPolygonProps(
                _fadeRamp(op, () => [
                  "interpolate", ["linear"], ["zoom"],
                  fadeOutZoom + 1.5, op(1.0),
                  fadeOutZoom + 2.0, 0.0,
                ]),
                visibility: _visibility(_sectionPolygonLayerId),
              )),
    );
    await controller.removeLayer(_sectionMarkerLayerId);
    await controller.addSymbolLayer(
      _clusterSourceId,
      _sectionMarkerLayerId,
      _layerProps(
          _sectionMarkerLayerId,
          (op) => _sectionMarkerProps(
                opacity: _fadeRamp(op, () => op([
                  "interpolate", ["linear"], ["zoom"],
                  fadeOutZoom + 1.5, 1.0,
                  fadeOutZoom + 2.0, 0.0,
                ])),
                visibility: _visibility(_sectionMarkerLayerId),
              )),
      filter: ["to-boolean", ["get", "section"]],
      enableInteraction: true,
      belowLayerId: await _webSafeBelowLayerId(controller, _fixedMarkerLayerId),
    );

    await _refreshMarkerLayerMinZooms(controller, fadeOutZoom);

    // The two label layers above were torn down and re-added, so re-arm the
    // policy on them — a re-added layer is born from the builder, but a host
    // that hid them before this ran needs the state pushed again.
    await _applyLayerPolicy(controller,
        only: [_patchAboveMarkerLayerId, _sectionMarkerLayerId]);

    // The venue is now genuinely on screen: polygons pushed, patch and section
    // fade curves applied, marker layers retuned. This is the point hosts need
    // in order to aim the camera at something — the style-loaded and
    // map-created callbacks both fire many seconds earlier, at which point a
    // camera move lands on tiles that have not drawn.
    // Release anything waiting on the venue being drawn (deferred marker work,
    // and the host's deep-link camera focus) before invoking the host callback,
    // so a throwing host handler cannot strand those waiters forever.
    if (!_venueRenderedCompleter.isCompleted) {
      _venueRenderedCompleter.complete();
    }
    try {
      _onVenueRenderedCb?.call();
    } catch (e) {
      print('onVenueRendered handler threw: $e');
    }
  }

  Future<void> _refreshMarkerLayerMinZooms(
      MapLibreMapController controller,
      double fadeOutZoom,
      ) async {
    final fadeInEnd = fadeOutZoom;
    fadeOutZoom --;

    // Collapsed rather than routed through [_fadeRamp]: every use below is
    // `op(opacityExpression)` — the resolver always wraps the whole value here —
    // so flattening the shared expression once gives the same `op(1.0)` at all
    // eleven call sites without threading a closure through each.
    final Object opacityExpression = _fadeEnabled
        ? [
            "interpolate", ["linear"], ["zoom"],
            fadeOutZoom, 0.0,
            fadeInEnd,   1.0,
          ]
        : 1.0;

    // ── BOTH PLATFORMS ──────────────────────────────────────────────────────
    //
    // Pushes each layer's FULL property set rather than the two opacity/sort
    // keys. The load-bearing line is `symbol-sort-key`: a partial call that
    // names it OVERWRITES it, and the bare `_kSortKeyExpression` discards the
    // per-layer base from [_collisionBase] (text 0, fixed 1000, icon 2000/3000,
    // customRendering 1500).
    //
    // That base is the whole marker→dot cascade. A feature's dot sorts at
    // `collisionBase + 0.6` — immediately behind ITS OWN full marker — so the
    // marker places first, wins, and suppresses its own dot. Flatten every full
    // marker to ~0 and that pairing is gone: markers all tie while dots keep
    // their per-feature bases, so a dot is no longer suppressed by the marker it
    // belongs to and lingers beside it as you zoom in.
    //
    // Zoo fix (2026-09-11): customRendering used to re-sort to 4000, i.e. after
    // every other layer including the plain amenity icons, so animal photo
    // composites routinely lost collisions and fell back to paws — even
    // against unrelated icons nowhere near as important as the photo itself.
    // [_collisionBase] now gives customRendering its own base (1500), ahead of
    // the icon layers, so it only loses to text/fixed wayfinding furniture.
    //
    // Was web-only; native ran the partial branch below, as ea627c6 does. So
    // this is the one place the reference build is NOT the behaviour we want —
    // its flattened key is why the collision dots never clear. Restoring the
    // bases on native is a deliberate divergence from ea627c6.
    await controller.setLayerProperties(
      _normalTextMarkerLayerId,
      _layerProps(
          _normalTextMarkerLayerId,
          (op) => _normalTextLayerProps(op(opacityExpression),
              visibility: _visibility(_normalTextMarkerLayerId))),
    );

    await controller.setLayerProperties(
      "$_normalIconMarkerLayerId-withSectionId",
      _layerProps(
          "$_normalIconMarkerLayerId-withSectionId",
          (op) => _normalIconLayerProps(
              sortBase: 3000,
              opacity: op(opacityExpression),
              visibility:
                  _visibility("$_normalIconMarkerLayerId-withSectionId"))),
    );

    await controller.setLayerProperties(
      "$_normalIconMarkerLayerId-withoutSectionId",
      _layerProps(
          "$_normalIconMarkerLayerId-withoutSectionId",
          (op) => _normalIconLayerProps(
              sortBase: 2000,
              opacity: op(opacityExpression),
              visibility: _visibility(
                  "$_normalIconMarkerLayerId-withoutSectionId"))),
    );

    await controller.setLayerProperties(
      _customRenderingMarkerLayerId,
      _layerProps(
          _customRenderingMarkerLayerId,
          (op) => _customRenderingLayerProps(op(opacityExpression),
              visibility: _visibility(_customRenderingMarkerLayerId))),
    );

    // icon-opacity keeps the layer's own creation ramp: the partial call this
    // stands in for only ever retuned text-opacity for the fixed markers.
    // Both are wrapped, so a host override collapses them to the same value.
    await controller.setLayerProperties(
      _fixedMarkerLayerId,
      _layerProps(
          _fixedMarkerLayerId,
          (op) => _fixedMarkerLayerProps(
                iconOpacity: op(_kDefaultMarkerOpacity),
                textOpacity: op(opacityExpression),
                visibility: _visibility(_fixedMarkerLayerId,
                    internalVisible: !_config.immersive),
              )),
    );
  }

  double _calculateFitZoom(List<GeoJsonPolygon> polygons, {Size? screenSize}) {
    if (polygons.isEmpty) return 13.0;

    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;

    for (final polygon in polygons) {
      for (final point in polygon.points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude < minLng) minLng = point.longitude;
        if (point.longitude > maxLng) maxLng = point.longitude;
      }
    }

    const double tileSize = 256.0;

    final double mapWidthPx  = screenSize?.width  ?? 400.0;
    final double mapHeightPx = screenSize?.height ?? 800.0;

    double _latToMercatorFraction(double latDeg) {
      final sinLat = sin(latDeg * pi / 180.0);
      return (0.5 - log((1 + sinLat) / (1 - sinLat)) / (4 * pi));
    }

    final double lngFraction = (maxLng - minLng) / 360.0;
    final double latFraction = (_latToMercatorFraction(minLat) - _latToMercatorFraction(maxLat)).abs();

    double zoomForLng = double.infinity;
    double zoomForLat = double.infinity;

    if (lngFraction > 0) {
      zoomForLng = log(mapWidthPx  / tileSize / lngFraction) / ln2;
    }
    if (latFraction > 0) {
      zoomForLat = log(mapHeightPx / tileSize / latFraction) / ln2;
    }

    final double fitZoom = min(zoomForLng, zoomForLat);
    return fitZoom.clamp(1.0, 22.0);
  }

  Future<void> enablePolylineLayers(MapLibreMapController controller) async {
    try {
      await controller.addGeoJsonSource(_polylineSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addGeoJsonSource(_pathCornerSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addGeoJsonSource(_pathShineSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });
      await _loadShineImage(controller);

      // Normal polylines (NOT path) — bottom-most
      await controller.addLineLayer(
        _polylineSourceId,
        _polylineLayerId,
        _layerProps(_polylineLayerId, (op) => LineLayerProperties(
          visibility: _visibility(_polylineLayerId),
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: op(const ["get", "lineOpacity"]),
        )),
        filter: ["!", ["to-boolean", ["get", "path"]]],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalIconMarkerLayerId),
      );

      await controller.addLineLayer(
        _polylineSourceId,
        _pathOutlineLayerId,          // new layer id, e.g. 'path-solid-outline'
        _layerProps(_pathOutlineLayerId, (op) => LineLayerProperties(
          visibility: _visibility(_pathOutlineLayerId),
          lineColor: "#FFFFFF",        // white outline
          lineWidth: 14,  // will be wider via lineGapWidth trick
          lineOpacity: op(const ["get", "lineOpacity"]),
          // lineGapWidth: ["get", "lineWidth"], // ← key: pushes the outline outward
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
        enableInteraction: false,       // outline doesn't need to be tappable
        belowLayerId: await _webSafeBelowLayerId(controller, _pathSolidLayerId), // render BELOW the solid line
      );

      // Solid path lines
      await controller.addLineLayer(
        _polylineSourceId,
        _pathSolidLayerId,
        _layerProps(_pathSolidLayerId, (op) => LineLayerProperties(
          visibility: _visibility(_pathSolidLayerId),
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: op(const ["get", "lineOpacity"]),
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalIconMarkerLayerId),
      );

      // Repetitive small arrows
      await _addSymbolLayerSafe(controller,
        _polylineSourceId,
        _pathArrowLayerId,
        const SymbolLayerProperties(
          iconImage: _kPathArrowImageId,
          symbolPlacement: 'line',
          symbolSpacing: [
            "interpolate", ["linear"], ["zoom"],
            0, 2.0,   // Ultra-dense spacing for world-level view
            10, 10.0,  // Very dense for city-level view
            14, 40.0,
            19, 100.0
          ],
          iconSize: [
            "interpolate", ["linear"], ["zoom"],
            0, 0.4,   // Scale down at extreme distance but keep visible
            10, 0.6,
            18, 0.8
          ],
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconPadding: 0,
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
      );

      // Big corner arrows
      await _addSymbolLayerSafe(controller,
        _pathCornerSourceId,
        _pathBigArrowLayerId,
        const SymbolLayerProperties(
          symbolSortKey: -999999,
          iconImage: ["coalesce", ["get", "icon"], _kPathBigArrowImageId],
          iconSize: 1.2,
          iconRotationAlignment: 'map',
          iconRotate: ["get", "bearing"],
          iconAnchor: 'center', // Pivot at the bend
          iconAllowOverlap: true,
          iconIgnorePlacement: false,
          iconPadding: 0,
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
          // Set per corner by _refreshCornerVisibility: false when the bend's
          // path segments are too short on screen for the fixed-size arrow, so
          // it doesn't float free of the route. (The turn bubble has no such
          // filter and still shows.)
          ["to-boolean", ["get", "arrowFits"]],
        ],
        // Only once the route is clearly zoomed in — below this the fixed-size
        // arrow dwarfs the thinned path and stops reading as "on" it.
        minzoom: 20.0,
      );

      // Moving shine that travels along the active path.
      await _addSymbolLayerSafe(controller,
        _pathShineSourceId,
        _pathShineLayerId,
        const SymbolLayerProperties(
          iconImage: _kShineImageId,
          iconSize: 2.5,
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      // Turn bubble (floating callout with the turn label), anchored to the
      // corner point. minzoom hides it when zoomed out too far.
      await _addSymbolLayerSafe(controller,
        _pathCornerSourceId,
        _turnBubbleLayerId,
        const SymbolLayerProperties(
          symbolSortKey: ["*", ["get", "turnSharpness"], -1],
          iconImage: ["get", "turnBubbleIcon"],
          iconAnchor: "bottom",
          iconOffset: [0, -24],
          iconAllowOverlap: false,
          iconIgnorePlacement: false,
          iconPadding: 8,
        ),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "solid"],
          ["!", ["to-boolean", ["get", "isGreyOverlay"]]],
        ],
        minzoom: 19.0,
      );

      // Dashed path lines
      await controller.addLineLayer(
        _polylineSourceId,
        _pathDashedLayerId,
        _layerProps(_pathDashedLayerId, (op) => LineLayerProperties(
          visibility: _visibility(_pathDashedLayerId),
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: op(const ["get", "lineOpacity"]),
          // `Platform` is dart:io and throws on web, so short-circuit first.
          lineDasharray: (!kIsWeb && Platform.isAndroid)
              ? ["literal", [0.1, 2.0]]
              : null,
          lineCap: "round",
        )),
        filter: [
          "all",
          ["to-boolean", ["get", "path"]],
          ["==", ["get", "style"], "dashed"],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalIconMarkerLayerId),
      );

      // Grey overlay — above all path layers, below user marker
      await controller.addLineLayer(
        _polylineSourceId,
        _greyOverlayLayerId,
        _layerProps(_greyOverlayLayerId, (op) => LineLayerProperties(
          visibility: _visibility(_greyOverlayLayerId),
          lineColor: ["get", "lineColor"],
          lineWidth: ["get", "lineWidth"],
          lineOpacity: op(const ["get", "lineOpacity"]),
          lineCap: "round",
          lineJoin: "round",
        )),
        filter: ["to-boolean", ["get", "isGreyOverlay"]],
        enableInteraction: false,
        belowLayerId: await _webSafeBelowLayerId(controller, _rotationMarkerLayerId),
      );

      _isPolylineLayersEnabled = true;
      await _applyLayerPolicy(controller);

      if (_lines.isNotEmpty) {
        await _updatePolylineSource(controller);
      }
    } catch (e, stack) {
      print('Error enabling polyline layers: $e');
      print('Stack trace: $stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Selection helpers
  // ---------------------------------------------------------------------------

  /// The leaf group a tapped marker feature belongs to.
  ///
  /// Ordered to mirror the layer filters in [enableMarkerLayers]: a feature is
  /// drawn by the first layer whose filter it satisfies, and this must agree.
  /// Web's `queryRenderedFeatures` does not report which layer a feature came
  /// from, so the classification has to come from the properties.
  MapLayer _markerGroupFor(Map<dynamic, dynamic>? props) {
    if (props == null) return MapLayer.landmarkMarkers;
    if (props['isSelected'] == true) return MapLayer.selection;
    if (props['boundary'] == true) return MapLayer.venueLabel;
    if (props['section'] == true) return MapLayer.sectionLabels;
    if (props['subSection'] == true) return MapLayer.subSectionLabels;
    if (props['isPriority'] == true) return MapLayer.priorityMarkers;
    final bearing = props['bearing'];
    if (bearing is num && bearing != 0) return MapLayer.entryMarkers;
    return MapLayer.landmarkMarkers;
  }

  /// The leaf group a tapped polygon belongs to.
  ///
  /// The height check mirrors [_updatePolygonSource], which only attaches
  /// `height` while immersive — so a polygon is drawn by the extrusion layer
  /// exactly when both are true, and this agrees with what is on screen.
  MapLayer _polygonGroupFor(GeoJsonPolygon polygon) {
    final type = polygon.properties?['type']?.toString().toLowerCase();
    if (type == 'boundary') return MapLayer.venueBoundary;
    if (type == 'section') return MapLayer.sections;
    if (type == 'sub section') return MapLayer.subSections;
    final height = polygon.properties?['height'];
    final hasHeight = height != null &&
        height.toString().isNotEmpty &&
        height.toString().toLowerCase() != 'undefined';
    return (_config.immersive && hasHeight)
        ? MapLayer.extrusions
        : MapLayer.rooms;
  }

  bool _tapAllowedForGroup(MapLayer group) =>
      _policy.resolve(group).tappable != false;

  /// Selection triggered by a tap.
  ///
  /// [selectLocation] itself is deliberately left ungated so that programmatic
  /// selection — search results, deep links, tour stops, all of which go through
  /// `UnifiedMapController.selectLocation` — keeps working with taps switched
  /// off entirely.
  Future<void> _selectFromTap(
      MapLibreMapController controller, String id, MapLayer group) async {
    if (!_tapAllowedForGroup(group)) return;
    await selectLocation(controller, id);
  }

  /// Every polygon drawn as part of the currently selected thing, or null when
  /// nothing is selected. Recomputed rather than cached so it cannot drift from
  /// [selectedLocation] across a style reload or a 2D/3D rebuild.
  Set<String>? get _currentSelectionGroup {
    final polygon = selectedLocation?.polygon;
    return polygon == null ? null : _selectionGroupFor(polygon);
  }

  /// The composite ids to mark `isSelected` for a selection of [primary].
  ///
  /// A room is not one polygon: the venue draws its walls and beams as separate
  /// features (`point-7ypw8j7` plus `point-7ypw8j7wall0..2`), and the feature
  /// data links them explicitly — the room lists its walls in
  /// `associatedPolygons` and each wall lists the room back.
  ///
  /// Walked as an undirected graph rather than one hop, so a tap on a wall
  /// selects the whole room — room, its other walls and its beams — exactly as
  /// a tap on the room does. Over this venue that yields 421 groups of at most
  /// 6, and no group ever contains two rooms, so the walk cannot bleed from one
  /// room into the next.
  ///
  /// The link is read from the data, deliberately not from the id spelling: the
  /// `<roomId>wall<n>` naming is this venue's convention, and a prefix match
  /// would silently group unrelated polygons on a venue that names things
  /// differently. A polygon with no links selects alone, as before.
  Set<String> _selectionGroupFor(GeoJsonPolygon primary) {
    final byOwnId = <String, List<GeoJsonPolygon>>{};
    final listedBy = <String, List<GeoJsonPolygon>>{};
    for (final p in _polygons) {
      final ownId = _extractPolygonIdFromTap(p.id);
      if (ownId != null) (byOwnId[ownId] ??= <GeoJsonPolygon>[]).add(p);
      for (final rel in p.associatedPolygonIds) {
        (listedBy[rel] ??= <GeoJsonPolygon>[]).add(p);
      }
    }

    // Visited by identity, not by id: the composite key is not guaranteed
    // unique, and skipping a polygon that merely shares a key would drop a real
    // member of the group.
    final visited = <GeoJsonPolygon>{};
    final ids = <String>{};
    final queue = <GeoJsonPolygon>[primary];
    while (queue.isNotEmpty) {
      final p = queue.removeLast();
      if (!visited.add(p)) continue;
      ids.add(p.id);
      for (final rel in p.associatedPolygonIds) {
        queue.addAll(byOwnId[rel] ?? const <GeoJsonPolygon>[]);
      }
      final ownId = _extractPolygonIdFromTap(p.id);
      if (ownId != null) {
        queue.addAll(listedBy[ownId] ?? const <GeoJsonPolygon>[]);
      }
    }
    return ids;
  }

  /// Resolves the polygon a selection id refers to.
  ///
  /// Matches the polygon's OWN id component first, and that exactness is the
  /// whole point: this venue names a room's walls after the room, with no
  /// separator. `point-7ypw8j7` is a room; `point-7ypw8j7wall0`,
  /// `...wall1` and `...wall2` are its walls and beams. A `contains` test over
  /// the composite key matches all four, so the `firstWhere` this replaces
  /// returned whichever came first in the venue data — the room for
  /// `point-frc9ipa`, but `point-7ypw8j7wall0` for `point-7ypw8j7`, whose
  /// walls are serialised ahead of it. Tapping that room's marker selected and
  /// highlighted its wall, while the identical tap one room over was correct.
  /// 173 of this venue's 900 polygon ids are a substring of another's, so the
  /// source ordering decided it silently, per room.
  ///
  /// The substring pass is kept as a fallback, for callers handing over a whole
  /// composite key rather than a bare feature id.
  GeoJsonPolygon? _findPolygonById(String polyID, String markerPolyID) {
    for (final p in _polygons) {
      final ownId = _extractPolygonIdFromTap(p.id);
      if (ownId == polyID || ownId == markerPolyID) return p;
    }
    for (final p in _polygons) {
      if (p.id.contains(polyID) || p.id.contains(markerPolyID)) return p;
    }
    return null;
  }

  String? _extractPolygonIdFromTap(String key) {
    var keyMap = GeoJsonUtils.extractKeyValueMap(key);
    if (keyMap["polyId"] != null) return keyMap["polyId"];
    if (keyMap["id"] != null) return keyMap["id"];
    return null;
  }

  bool _pointInPolygon(double lat, double lng, List<MapLocation> points) {
    if (points.length < 3) return false;
    bool inside = false;
    int j = points.length - 1;
    for (int i = 0; i < points.length; i++) {
      final xi = points[i].longitude, yi = points[i].latitude;
      final xj = points[j].longitude, yj = points[j].latitude;
      final intersects =
          ((yi > lat) != (yj > lat)) &&
              (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  /// Ray-casts the in-memory polygons, which is independent of what is actually
  /// rendered — so [allow] is how a policy keeps hidden or untappable polygons
  /// from being "tapped".
  GeoJsonPolygon? _hitTestPolygons(double lat, double lng,
      {bool Function(GeoJsonPolygon)? allow}) {
    final hits = _polygons.where((p) {
      // `properties` or `type` being absent used to throw NoSuchMethodError
      // here, which the caller's catch swallowed — silently killing the whole
      // polygon tap path for that tap.
      final type = p.properties?['type']?.toString().toLowerCase() ?? '';
      if (p.id.toLowerCase().contains("boundary")) return false;
      if (type.contains("boundary") || type.contains("section")) return false;
      if (allow != null && !allow(p)) return false;
      return _pointInPolygon(lat, lng, p.points);
    }).toList();

    if (hits.isEmpty) return null;

    final flat = hits.where((p) {
      final h = p.properties?['height'];
      return h == null || h.toString().isEmpty || h.toString().toLowerCase() == 'undefined';
    }).toList();

    return flat.isNotEmpty ? flat.first : hits.first;
  }

  CameraBound? calculateBounds(
      controller, List<MapLocation> allPoints) {
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (var point in allPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    try {
      final latPadding = (maxLat - minLat) * 0.5;
      final lngPadding = (maxLng - minLng) * 0.5;
      return CameraBound(
        southwest: MapLocation(
            latitude: minLat - latPadding, longitude: minLng - lngPadding),
        northeast: MapLocation(
            latitude: maxLat + latPadding, longitude: maxLng + lngPadding),
      );
    } catch (e) {
      print("calculateBounds error $e");
    }
    return null;
  }

  @override
  Future<void> selectLocation(controller, String polyID) async {
    final currentMarker = selectedLocation?.marker as GeoJsonMarker?;
    if (selectedLocation?.polyID == polyID || (currentMarker != null && currentMarker.id.contains(polyID))) return;
    if (controller is! MapLibreMapController) {
      print('Error: Invalid controller type');
      return;
    }
    if (polyID.isEmpty) {
      print('Error: polyID cannot be empty');
      return;
    }

    try {
      // We don't call deSelectLocation here to avoid redundant GeoJSON pushes.
      // The new selection will naturally overwrite the old one in the sources below.

      GeoJsonPolygon? polygon;
      GeoJsonMarker? marker;

      try {
        if (_symbols.isNotEmpty) {
          marker = _symbols.firstWhere(
                (m) => m.id.contains(polyID),
            orElse: () => throw Exception('Marker not found'),
          );
        }
      } catch (e) {
        print('No marker found for polyID: $polyID - $e');
        return;
      }

      String polyIDInsideMarker = polyID;
      if (marker?.id != null) {
        polyIDInsideMarker = _extractPolygonIdFromTap(marker!.id) ?? polyID;
      }
      print("polyIDInsideMarker $polyIDInsideMarker");

      try {
        if (_polygons.isNotEmpty) {
          polygon = _findPolygonById(polyID, polyIDInsideMarker);
          if (polygon == null) throw Exception('Polygon not found');
          if (polygon.points.length < 3) {
            print('Warning: Polygon has fewer than 3 points: ${polygon.id}');
            polygon = null;
          }
        }
      } catch (e) {
        print('No polygon found for polyID: $polyID - $e');
      }

      if (polygon == null && marker == null) {
        print('Error: Neither polygon nor marker found for polyID: $polyID');
        return;
      }

      selectedLocation = SelectedLocation(
        polyID: polyIDInsideMarker,
        polygon: polygon,
        marker: marker,
      );

      // 1. Kick off visual updates immediately for tap feedback.
      // We don't await these to let the camera start ASAP.
      if (polygon != null) {
        _updatePolygonSource(controller, selectPolygonIds: _selectionGroupFor(polygon));
      }
      if (marker != null) {
        // Clear any leftover frozen animation from the previous selection
        // BEFORE handling this new one. Needed because the animated layer
        // now freezes in place instead of resetting itself — if this new
        // marker has no icon, animateMarkerSelection never runs to
        // overwrite it, so without this it would just sit there forever.
        if (_animatingMarkerId != null && _animatingMarkerId != marker.id) {
          _iconAnimationTimer?.cancel();
          _markerIconScale.remove(_animatingMarkerId);
          _markerIconShakeDeg.remove(_animatingMarkerId);
          _animatingMarkerId = null;
          await controller.setGeoJsonSource(_animatedMarkerSourceId, {
            'type': 'FeatureCollection',
            'features': [],
          });
        }

        // Make the tapped marker sit a little larger than its resting size.
        // The animated selection styles drive `iconScaleFactor` themselves, so
        // only apply the static bump when no animation style is set.
        if (markerSelectionAnimationStyle == MarkerSelectionAnimationStyle.none) {
          if (_restScaledMarkerId != null && _restScaledMarkerId != marker.id) {
            _markerIconScale.remove(_restScaledMarkerId);
          }
          _markerIconScale[marker.id] = _kSelectedMarkerRestScale;
          _restScaledMarkerId = marker.id;
        }

        // Selection push: one rebuild to flip `isSelected`, no settle
        // re-pushes (see setGeoJsonSource) — every marker is already drawn, so
        // the extra 500ms/2s/5s full rebuilds only jank the map and make the
        // tap feel unresponsive.
        setGeoJsonSource(
          controller,
          _symbols,
          _clusterSourceId,
          selectedMarkerId: marker.id,
          scheduleSettleRepushes: false,
        );
      }

      if (marker != null &&
          marker.assetPath != null &&
          markerSelectionAnimationStyle != MarkerSelectionAnimationStyle.none) {
        animateMarkerSelection(controller, marker.id,
            style: markerSelectionAnimationStyle);
      }

      // 2. Notify listeners before the camera moves so panels open on tap
      // rather than after the animation settles.
      if (polygon != null) {
        _config.onPolygonTap?.call(
          coordinates: polygon.points,
          polygonId: polyID,
        );
      } else if (marker != null) {
        _config.onMarkerTap?.call(
          coordinates: marker.position,
          markerId: polyID,
        );
      }

      MapLocation? center;
      double? targetZoom;
      CameraBound? bounds;

      // Calculate target camera position
      if (polygon != null && polygon.points.isNotEmpty) {
        double minLat = polygon.points.first.latitude;
        double maxLat = polygon.points.first.latitude;
        double minLng = polygon.points.first.longitude;
        double maxLng = polygon.points.first.longitude;

        for (final point in polygon.points) {
          if (point.latitude < -90 || point.latitude > 90) continue;
          if (point.longitude < -180 || point.longitude > 180) continue;
          minLat = min(minLat, point.latitude);
          maxLat = max(maxLat, point.latitude);
          minLng = min(minLng, point.longitude);
          maxLng = max(maxLng, point.longitude);
        }

        final centerLat = (minLat + maxLat) / 2;
        final centerLng = (minLng + maxLng) / 2;

        if (!centerLat.isNaN && !centerLng.isNaN &&
            !centerLat.isInfinite && !centerLng.isInfinite) {
          center = MapLocation(latitude: centerLat, longitude: centerLng);
          final maxSpan = max(maxLat - minLat, maxLng - minLng);
          targetZoom = maxSpan > 1.0 ? 8.0
              : maxSpan > 0.1 ? 12.0
              : maxSpan > 0.01 ? 15.0
              : 20.0;
          bounds = calculateBounds(controller, polygon.points);
        }
      } else if (marker != null) {
        center = marker.position;
        targetZoom = 19;
      }

      // 3. Start camera animation
      try {
        // For an animal icon that also has an enclosure polygon, sequence the
        // camera: first zoom in on the tapped animal icon, then fit its polygon.
        final bool sequentialAnimalFit =
            marker != null && _isAnimalMarker(marker) && bounds != null;

        if (sequentialAnimalFit) {
          // Phase 1: glide in on the tapped animal icon with an explicit,
          // eased duration so it reads as a deliberate focus rather than a snap.
          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(marker!.position.latitude, marker.position.longitude),
              18,
            ),
            duration: const Duration(milliseconds: 900),
          );
          // Brief hold so the eye settles on the animal before we pull back.
          await Future.delayed(const Duration(milliseconds: 450));
          // Phase 2: slow, eased pull-back that fits the whole enclosure.
          await fitCameraToBounds(controller, bounds!);
        } else if (marker != null && !zoomToMarkerOnSelect) {
          // Plain marker tap: select + enlarge in place, no camera move.
        } else if (bounds != null) {
          await fitCameraToBounds(controller, bounds);
        } else if (center != null && targetZoom != null) {
          await animateCamera(controller, center, targetZoom);
        }
      } catch (e) {
        print('Warning: Failed to animate camera: $e');
      }
    } catch (e, stackTrace) {
      print('Error selecting location: $e\n$stackTrace');
      selectedLocation = null;
    }
  }

  Future<void> _updatePolygonSelectionState(
      MapLibreMapController controller,
      String selectPolygonId,
      bool isSelected,
      ) async {
    _updatePolygonSource(controller,
        selectPolygonIds: isSelected ? {selectPolygonId} : null);
  }

  @override
  Future<void> deSelectLocation(dynamic controller) async {
    if (controller is! MapLibreMapController) {
      print('Error: Invalid controller type in deSelectLocation');
      return;
    }

    if (selectedLocation == null) return;

    final polyID = selectedLocation!.polyID;
    if (polyID.isEmpty) {
      selectedLocation = null;
      return;
    }

    try {
      await _updatePolygonSource(controller, selectPolygonIds: null);

      // Undo whatever the animation left behind before the normal layers
      // take back over showing this marker at rest.
      _iconAnimationTimer?.cancel();
      if (_animatingMarkerId != null) {
        _markerIconScale.remove(_animatingMarkerId);
        _markerIconShakeDeg.remove(_animatingMarkerId);
        _animatingMarkerId = null;
      }
      // Drop the static selected-size bump so the marker returns to rest.
      if (_restScaledMarkerId != null) {
        _markerIconScale.remove(_restScaledMarkerId);
        _restScaledMarkerId = null;
      }
      await controller.setGeoJsonSource(_animatedMarkerSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      // Deselection push: same as selection — one rebuild to clear
      // `isSelected`, no settle re-pushes (see setGeoJsonSource).
      await setGeoJsonSource(
        controller,
        _symbols,
        _clusterSourceId,
        selectedMarkerId: null,
        scheduleSettleRepushes: false,
      );

      selectedLocation = null;
    } catch (e, stackTrace) {
      print('Error deselecting location: $e\n$stackTrace');
      selectedLocation = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Zoom helpers
  // ---------------------------------------------------------------------------

  @override
  Future<void> zoom(dynamic controller, {double zoom = 0.0}) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat =
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng =
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
      final cameraPos = _controller!.cameraPosition;

      await animateCamera(
        controller,
        MapLocation(latitude: centerLat, longitude: centerLng),
        (cameraPos?.zoom ?? 0.0) + zoom,
      );
    } catch (e) {
      print("Error zoom: $e");
    }
  }

  @override
  Future<void> zoomTo(controller, double zoom) async {
    try {
      final bounds = await _controller!.getVisibleRegion();
      final centerLat =
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng =
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      await animateCamera(
        controller,
        MapLocation(latitude: centerLat, longitude: centerLng),
        zoom,
      );
    } catch (e) {
      print("Error zoomTo: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Camera bounds
  // ---------------------------------------------------------------------------

  @override
  Future<void> fitCameraToLine(controller, GeoJsonPolyline polyline) async {
    if (polyline.points.isEmpty) return;

    double minLat = polyline.points.first.latitude;
    double maxLat = polyline.points.first.latitude;
    double minLng = polyline.points.first.longitude;
    double maxLng = polyline.points.first.longitude;

    for (final point in polyline.points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,
        top: 50,
        right: 50,
        bottom: 50,
      ),
    );
  }

  @override
  Future<void> fitCameraToBounds(controller, CameraBound bound) async {
    final bounds = LatLngBounds(
      southwest:
      LatLng(bound.southwest.latitude, bound.southwest.longitude),
      northeast:
      LatLng(bound.northeast.latitude, bound.northeast.longitude),
    );

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 50,
        top: 50,
        right: 50,
        bottom: 50,
      ),
      duration: const Duration(milliseconds: 2000),
    );
  }

  Future<void> addMapFade(controller) async {
    await controller.setLayerProperties(
      _patchAbovePolygonLayerId,
      _layerProps(_patchAbovePolygonLayerId, (op) => FillLayerProperties(
        visibility: _visibility(_patchAbovePolygonLayerId),
        fillOpacity: op(0.5),
        fillColor: "#FFFFFF",
        fillOutlineColor: ["get", "strokeColor"],
      )),
    );
  }

  Future<void> removeMapFade(controller) async {
    print("removeMapFade");
    await _refreshPatchAboveOpacity(controller, screenSize: _screenSize);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _markerSourcesReady = false;
    _isCircleLayersEnabled = false;
    _compassSub?.cancel();
    _compassSub = null;
    _compassThrottleTimer?.cancel();
    _compassThrottleTimer = null;
    _pendingCompassHeading = null;
    _circleAnimationTimer?.cancel();
    _circleAnimationTimer = null;
  }

  static const String osmRasterStyle = '''
{
  "version": 8,
  "name": "Esri Dark Gray Canvas",
  "glyphs": "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
  "sources": {
    "osm-tiles": {
      "type": "raster",
      "tiles": [
        "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
      ],
      "tileSize": 256,
      "attribution": "© Esri, HERE, Garmin, © OpenStreetMap contributors",
      "maxzoom": 16
    },
    "empty": {
      "type": "geojson",
      "data": { "type": "FeatureCollection", "features": [] }
    }
  },
  "layers": [
    {
      "id": "osm-tiles-layer",
      "type": "raster",
      "source": "osm-tiles",
      "minzoom": 0,
      "maxzoom": 23,
      "paint": {
        "raster-brightness-min": 0.18,
        "raster-brightness-max": 1.0
      }
    },
    {
      "id": "font-anchor",
      "type": "symbol",
      "source": "empty",
      "layout": {
        "text-field": "",
        "text-font": ["Open Sans Regular", "Arial Unicode MS Regular"]
      }
    }
  ]
}
''';
}
