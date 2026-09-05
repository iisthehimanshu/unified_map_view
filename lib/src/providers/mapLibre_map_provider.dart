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
import 'package:http/http.dart' as http;

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

  /// Marker ids for which icon/text overlap is temporarily forced on. These
  /// markers are routed into a dedicated always-visible layer (and excluded
  /// from the collision-subject normal layers) so they are never hidden by
  /// collision, until cleared.
  final Set<String> _overlapOverrideIds = {};

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
  final String _pathSolidLayerId = 'path-solid-polyline-layer';
  final String _pathOutlineLayerId = 'path-solid-outline-polyline-layer';
  final String _pathDashedLayerId = 'path-dashed-polyline-layer';
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
    _sectionPolygonLayerId: MapLayer.sections,
    _subSectionPolygonLayerId: MapLayer.subSections,
    _patchBelowPolygonLayerId: MapLayer.venueBoundary,
    _patchAbovePolygonLayerId: MapLayer.venueBoundary,
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

  /// Layers we have written a policy value to at least once.
  ///
  /// [_applyLayerPolicy] skips layers whose resolved state is the default, so a
  /// host that never touches this API sees no extra channel traffic at all.
  /// Without this set, that fast path would also skip the write that *restores*
  /// a layer after a host un-hides it or clears an opacity override.
  final Set<String> _everApplied = {};

  MapLayerState _stateForLayer(String layerId) {
    final group = _layerGroups[layerId];
    return group == null ? MapLayerState.defaults : _policy.resolve(group);
  }

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
    return build((base) => override ?? base);
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

  /// Re-push the full property set for [only], or every registered layer.
  ///
  /// Wrapped per layer: `furniture-layer`, `patch-above-markers-layer` and
  /// `section-markers-layer` are removed and re-added at runtime, so a write can
  /// legitimately land on a layer that does not exist right now.
  Future<void> _applyLayerPolicy(
    MapLibreMapController controller, {
    Iterable<String>? only,
    bool force = false,
  }) async {
    final ids = (only ?? _propBuilders.keys).toList(growable: false);
    for (final id in ids) {
      final build = _propBuilders[id];
      if (build == null) continue;
      final state = _stateForLayer(id);
      final isDefault = state.opacity == null && state.visible != false;
      if (!force && isDefault && !_everApplied.contains(id)) continue;
      if (!isDefault) _everApplied.add(id);
      try {
        await controller.setLayerProperties(
            id, build((base) => state.opacity ?? base));
      } catch (_) {
        // Layer not present right now (furniture in 2D, or mid re-add).
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
    "*",
    ["get", _kPriorityKey],
    -1,
  ];

  /// Markers whose full marker only appears from zoom 18 (text markers with
  /// collisionBase 0 and icon-with-sectionId markers with collisionBase 3000).
  /// Used to pick the dot's opacity ramp; see [enableMarkerLayers].
  static const List<dynamic> _kDotStepGroupExpression = [
    "any",
    ["==", ["get", "collisionBase"], 0],
    ["==", ["get", "collisionBase"], 3000],
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

            // Handle feature taps (polygons & markers)
            // MapLibre signature: (Point<double> point, LatLng coordinates, String id, String layerId, Annotation? annotation)
            controller.onFeatureTapped.add((Point<double> point, LatLng coordinates, String id, String layerId, Annotation? annotation) async {
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
              // Same for the shared label-less icons. The baked bytes in
              // _bakedIconCache stay valid — only the addImage() registration
              // is gone — so the rebake pass below is upload-only.
              _registeredSmallIconIds.clear();
              // Registered animal icons are wiped too (the composited bytes in
              // _animalIconCache are still valid and get reused, only the
              // addImage() registration needs to happen again).
              _loadedAnimalIcons.clear();
              // Re-arm the deferred labelled bake: its addImage() calls are
              // gone with the style, so the next camera idle at label zoom has
              // to re-register them. The bytes survive in _animalIconCache, so
              // that pass is upload-only.
              _labelledAnimalsStarted = false;
              _isCircleLayersEnabled = false;
              _isFurnitureLayerEnabled = false;
              _isFurnitureExtrusionAdded = false;
              // Every layer is about to be rebuilt, and each builder closes over
              // the fade zoom and 2D/3D mode of the style it was registered
              // under — so the stale ones must go. `_policy` deliberately does
              // NOT reset: it is the host's setting, not style state, and the
              // enableXxxLayers calls below read it to recreate the layers in
              // the state the host asked for.
              _propBuilders.clear();
              _everApplied.clear();

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
                  await Future.wait(iconMarkers.map((marker) async {
                    try {
                      await _loadMarkerIcon(_controller!, marker);
                    } catch (e) {
                      print('Warning: failed to reload icon for ${marker.id}: $e');
                    }
                  }));
                } else {
                  for (final marker in iconMarkers) {
                    try {
                      await _loadMarkerIcon(_controller!, marker);
                    } catch (e) {
                      print('Warning: failed to reload icon for ${marker.id}: $e');
                    }
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
                final cameraPos = _controller!.cameraPosition;
                if(cameraPos == null) return;
                final target = cameraPos.target;
                final bearing = cameraPos.bearing;
                final tilt = cameraPos.tilt;
                final zoom = cameraPos.zoom;
                print("tilt $tilt");
                print("zoom $zoom");
                print("bearing $bearing");
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
          myLocationEnabled: config.showUserLocation,
          myLocationTrackingMode: MyLocationTrackingMode.none,
          compassEnabled: false,
          rotateGesturesEnabled: config.rotateGesturesEnabled,
          scrollGesturesEnabled: config.scrollGesturesEnabled,
          tiltGesturesEnabled: config.tiltGesturesEnabled,
          zoomGesturesEnabled: config.zoomControlsEnabled,
          minMaxZoomPreference: const MinMaxZoomPreference(12.0, 23.0),
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
    if (controller is MapLibreMapController) {
      if (bearing != null && tilt != null) {
        await controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(location.latitude, location.longitude),
                zoom: zoom,
                bearing: bearing,
                tilt: tilt,
              ),
            ),
            duration: duration
        );
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(location.latitude, location.longitude),
            zoom,
          ),
        );
        if (bearing != null && tilt == null) {
          await controller.animateCamera(CameraUpdate.bearingTo(bearing));
        } else if (tilt != null && bearing == null) {
          await controller.animateCamera(CameraUpdate.tiltTo(tilt));
        }
      }
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
    try {
      await controller.setLayerProperties(
        _selectedExtrudedPolygonLayerId,
        _layerProps(_selectedExtrudedPolygonLayerId,
            (op) => FillExtrusionLayerProperties(
          visibility: _visibility(_selectedExtrudedPolygonLayerId),
          fillExtrusionColor: "#4CAF50",
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          // The 2D zero is an internal off and wins over a host override.
          fillExtrusionOpacity: isEnabled ? op(1.0) : 0.0,
        )),
      );
    } catch (_) {}
    try {
      await controller.setLayerProperties(
        _extrudedPolygonLayerId,
        _layerProps(_extrudedPolygonLayerId,
            (op) => FillExtrusionLayerProperties(
          visibility: _visibility(_extrudedPolygonLayerId),
          fillExtrusionColor: ["get", "fillColor"],
          fillExtrusionHeight: ["get", "height"],
          fillExtrusionBase: ["get", "base_height"],
          fillExtrusionOpacity: isEnabled ? op(1.0) : 0.0,
        )),
      );
    } catch (_) {}
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
      selectPolygonId: selectedLocation?.polygon?.id,
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

  Timer? _circleAnimationTimer;
  bool _circleExpanding = true;

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
      await _loadMarkerIcon(controller, marker);
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
      await Future.wait(otherMarkers.map((marker) async {
        try {
          await _loadMarkerIcon(controller, marker);
        } catch (e) {
          print("error in addMarkers $e");
        }
      }));
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

  Future<void> _animateMarkerToPosition(
      MapLibreMapController controller,
      String id,
      MapLocation targetLocation,
      Duration duration
      ) async {
    // Each step costs two `setGeoJsonSource` round trips, which alone overrun a
    // 60fps budget — the loop could never hold that rate. 30 is the honest
    // number and halves the traffic competing with map gestures.
    const fps = 30;
    final steps = (duration.inMilliseconds / (1000 / fps)).round();

    final markers =
    _rotatingSymbols.where((s) => s.id.toLowerCase().contains(id));
    final circles =
    _circles.where((c) => c.id.toLowerCase().contains(id));

    if (markers.isEmpty) return;

    final token = ++_markerAnimationToken;

    final marker = markers.first;
    GeoJsonCircle? circle;
    if (circles.isNotEmpty) circle = circles.first;

    final startLat = marker.position.latitude;
    final startLng = marker.position.longitude;
    final endLat = targetLocation.latitude;
    final endLng = targetLocation.longitude;

    if (startLat == endLat && startLng == endLng) return;

    for (int i = 1; i <= steps; i++) {
      if (token != _markerAnimationToken) return;
      final progress = i / steps;
      final currentLat = startLat + (endLat - startLat) * progress;
      final currentLng = startLng + (endLng - startLng) * progress;

      marker.position = MapLocation(latitude: currentLat, longitude: currentLng);
      if (circle != null) {
        circle.position =
            MapLocation(latitude: currentLat, longitude: currentLng);
      }
      await _updateUserLocation(controller);
      await _setGeoJsonCircle(controller);
      await Future.delayed(Duration(milliseconds: 1000 ~/ fps));
    }

    if (token != _markerAnimationToken) return;
    marker.position = targetLocation;
    if (circle != null) circle.position = targetLocation;
    await _updateUserLocation(controller);
    await _setGeoJsonCircle(controller);
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
  /// [enableMarkerLayers] (text=0, fixed/bearing=1000, icon-withoutSectionId=
  /// 2000, icon-withSectionId=3000, customRendering=4000). Used by the dot layer
  /// so a feature's dot sorts right after its own full marker.
  int _collisionBase({
    required bool hasIcon,
    required double bearing,
    required bool customRendering,
    required bool sectionId,
  }) {
    if (bearing != 0.0) return 1000; // Layer 4: fixed/bearing
    if (!hasIcon) return 0; // Layer 1: text-only
    if (customRendering) return 4000; // Layer 3: custom rendering
    return sectionId ? 3000 : 2000; // Layer 2 / 2b: icon markers
  }

  Future<void> setGeoJsonSource(
      dynamic controller,
      List<GeoJsonMarker> symbols,
      String sourceID,
      {String? selectedMarkerId}
      ) async {
    if (controller is MapLibreMapController) {
      if (!_isClusteringEnabled) {
        print("Clustering not enabled yet");
        return;
      }

      final features = symbols.map((marker) {
        final anchor = (marker.anchor?.dx == 0.5 && marker.anchor?.dy == 0.5)
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
            if (marker.assetPath != null)
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
            // Per-feature base of the full marker's symbolSortKey. The dot layer
            // reuses this (+ a fractional offset) so each feature's dot is
            // placed right after its own full marker in the global collision
            // pass, yielding the marker → dot → hidden fallback cascade.
            'collisionBase': _collisionBase(
              hasIcon: marker.assetPath != null,
              bearing: effectiveBearing,
              customRendering: marker.customRendering,
              sectionId: hasSectionId,
            ),
            // Image id for this marker's collision-fallback dot. Per-marker dots
            // are registered under their asset path; null falls back to the
            // shared default room dot.
            'dotIcon': marker.dotAssetPath ?? _kDotImageId,
            if(entryDirection != null)'bearing':entryDirection
          }
        };
      }).toList();


      await controller.setGeoJsonSource(
        sourceID,
        {
          "type": "FeatureCollection",
          "features": features,
        },
      );
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
    // (_updateUserLocation, which runs on every move) carries the same value
    // the compass path would have written. Without this a move would push a
    // feature bearing the last live heading and undo the override.
    if (heading != null) _currentHeading = heading;
    if (controller is! MapLibreMapController) return;
    await _updateUserLocation(controller);
  }

  void _startCompassListening(
      MapLibreMapController controller, String sourceID) {
    if (_compassSub != null) return;
    _compassSub = FlutterCompass.events?.listen((event) async {
      if (event.heading == null) return;
      // Ignore the sensor rather than cancelling the subscription. There *is*
      // a restart path — removeMarker() cancels and nulls _compassSub when the
      // puck goes, and _startCompassListening re-subscribes when it comes back
      // — but it only runs on a marker remove/add cycle. Cancelling here would
      // leave the puck frozen from the moment the override is cleared until the
      // next floor change happens to rebuild the marker.
      if (_headingOverride != null) return;
      _currentHeading = event.heading;
      // A style reload wipes the rotation source; compass events keep arriving
      // during the rebuild, and pushing then NPEs natively on a null source.
      if (!_markerSourcesReady) return;
      final cameraPos = controller.cameraPosition;
      if (cameraPos == null) return;

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
          if (marker.compassBasedRotation) "bearing": event.heading!,
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
      }
    });
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
        setGeoJsonSource(controller, [], _clusterSourceId);
        setGeoJsonSource(controller, [], _rotationSourceId);
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
        String? selectPolygonId,
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
          '#${RenderingUtilities.colorToMapplsHex(fillColor)}',
          'strokeColor':
          '#${RenderingUtilities.colorToMapplsHex(strokeColor)}',
          'fillColorSecondary':'#${RenderingUtilities.colorToMapplsHex(fillColorSecondary)}',
          'fillOpacity': fillColor.a,
          'isSelected': polygon.id == selectPolygonId,
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
      print('addFurniture: ${furnitureItems.length}/${items.length} items '
          'carry a usable 3dRef');
      if (furnitureItems.isEmpty) return;

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

  Future<void> _enableFurnitureLayer(MapLibreMapController controller) async {
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
    await controller.addFillExtrusionLayer(
      _furnitureSourceId,
      _furnitureLayerId,
      _layerProps(_furnitureLayerId, (op) => FillExtrusionLayerProperties(
        visibility: _visibility(_furnitureLayerId),
        fillExtrusionColor: ['get', 'color'],
        fillExtrusionBase: ['get', 'base'],
        fillExtrusionHeight: ['get', 'height'],
        fillExtrusionOpacity: op(null),
      )),
      minzoom: _furnitureMinZoom,
    );
    _isFurnitureExtrusionAdded = true;
    await _applyLayerPolicy(controller, only: [_furnitureLayerId]);
  }

  /// Removes the furniture fill-extrusion layer entirely (used when switching
  /// to 2D). The source and flat fill layer stay in place.
  Future<void> _removeFurnitureExtrusionLayer(
      MapLibreMapController controller) async {
    if (!_isFurnitureExtrusionAdded) return;
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

    for (final raw in parts) {
      if (raw is! Map) continue;
      final p = Map<String, dynamic>.from(raw);
      final shape = p['shape'] as String? ?? 'box';
      // Spheres describe size via "r" (radius) instead of "h" — treat
      // their vertical extent as the full diameter, centered on oy.
      final h = shape == 'sphere'
          ? (double.tryParse('${p['r'] ?? 0}') ?? 0.0) * 2
          : (double.tryParse('${p['h'] ?? 0}') ?? 0.0);
      final oy = double.tryParse('${p['oy'] ?? 0}') ?? 0.0;

      final localCorners = _footprintFor(p);
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
          'base': oy - h / 2,
          'height': oy + h / 2,
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
  List<List<double>> _footprintFor(Map<String, dynamic> p) {
    final shape = p['shape'] as String? ?? 'box';
    final ox = double.tryParse('${p['ox'] ?? 0}') ?? 0.0;
    final oz = double.tryParse('${p['oz'] ?? 0}') ?? 0.0;

    if (shape == 'cylinder' || shape == 'sphere') {
      final r = double.tryParse('${p['r'] ?? 0}') ?? 0.0;
      return List.generate(_circleSegments, (i) {
        final angle = 2 * pi * i / _circleSegments;
        return [ox + r * cos(angle), oz + r * sin(angle)];
      });
    }

    // default: box — w/d taken exactly as given in the JSON, no
    // unit scaling or minimum-size flooring. The footprint is the
    // horizontal w x d rectangle only; h feeds base/height later.
    final w = double.tryParse('${p['w'] ?? 0}') ?? 0.0;
    final d = double.tryParse('${p['d'] ?? 0}') ?? 0.0;

    // Optional per-part "ry": the part's own yaw around its center
    // (e.g. wall niches at ry 90/270, amalaka lobes at ry 30/60...),
    // applied before the whole-item 3dModelAngle rotation.
    final ryDeg = double.tryParse('${p['ry'] ?? 0}') ?? 0.0;
    if (ryDeg == 0) {
      return [
        [ox - w / 2, oz - d / 2],
        [ox + w / 2, oz - d / 2],
        [ox + w / 2, oz + d / 2],
        [ox - w / 2, oz + d / 2],
      ];
    }
    final ryRad = ryDeg * pi / 180.0;
    final cosR = cos(ryRad);
    final sinR = sin(ryRad);
    return [
      [-w / 2, -d / 2],
      [w / 2, -d / 2],
      [w / 2, d / 2],
      [-w / 2, d / 2],
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
          'lineColor': line.properties?['fillColor'] ?? '#000000',
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
      await controller.addImage(smallId, bytes);
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
      await controller.addImage(imageId, composite);
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
      await controller.addImage(_kDotImageId, bd.buffer.asUint8List());
      _registeredDotImageIds.add(_kDotImageId);
    } catch (e) {
      print("_loadDotImage $e");
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
        await controller.addImage(path, bytes);
        _registeredDotImageIds.add(path);
      }
    } catch (e) {
      print("_loadMarkerDotIcon $e");
    }
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
      controller.addImage(marker.id, baked.main),
      if (smallBytes != null) controller.addImage(baked.smallIconId, smallBytes),
      if (baked.selected != null)
        controller.addImage("${marker.id}-selected", baked.selected!),
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
          await controller.addImage(marker.id, iconBytes);
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
        if (iconBytes != null) {
          await controller.addImage(marker.id, iconBytes);
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
  /// [_refreshMarkerLayerMinZooms]. The load-bearing line is `symbolSortKey`'s
  /// 4000 base, which the refresh's partial call used to overwrite: without it every full marker flattens to ~0, they collide with
  /// each other as one block under `iconAllowOverlap: false`, and each loser
  /// falls back to the layer-0 dot — for an animal, the paw. That is the "every
  /// animal is a paw at every zoom" defect, and it is a collision-ordering bug,
  /// not an icon-loading one: the composites were registered fine throughout.
  SymbolLayerProperties _customRenderingLayerProps(dynamic iconOpacity,
          {String visibility = "visible", dynamic sortKey}) =>
      SymbolLayerProperties(
        visibility: visibility,
        symbolSortKey: sortKey ?? ["+", 4000, _kSortKeyExpression],
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
      await controller.addGeoJsonSource(_clusterSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

      await controller.addGeoJsonSource(_rotationSourceId, {
        'type': 'FeatureCollection',
        'features': [],
      });

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
          ["to-boolean", ["get", "sectionId"]],
          ["!", ["to-boolean", ["get", "customRendering"]]],
          ["to-boolean", ["get", "icon"]],
        ],
        enableInteraction: true,
        belowLayerId: await _webSafeBelowLayerId(controller, _normalTextMarkerLayerId),
        minzoom: 18.0,
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
          // Halved (was 1.5) to match the collision dots — the user arrow was
          // dominating the floor plan it is meant to sit on.
          //
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
              : 1.5,
          iconRotate: ["get", "bearing"],
          iconRotationAlignment: "map",
          iconAllowOverlap: true,
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
          visibility: _visibility(_selectedMarkerLayerId),
          symbolSortKey: ["+", 8000, _kSortKeyExpression],
          iconImage: [
            "case",
            ["to-boolean", ["get", "hasSelectedIcon"]],
            ["concat", ["get", "icon"], "-selected"],
            ["get", "icon"],
          ],
          // Both stops scale together so the destination pin keeps the shape
          // of its ramp at every zoom.
          iconSize: [
            "interpolate",
            ["linear"],
            ["zoom"],
            13,  0.2 * _kIconScale,
            18,  1.5 * _kIconScale,
          ],
          iconAllowOverlap: false,
          textAllowOverlap: false,
          iconOpacity: op(null),
        )),
        filter: ["to-boolean", ["get", "isSelected"]],
        enableInteraction: true,
        belowLayerId: null,
      );

      _isClusteringEnabled = true;
      await _applyLayerPolicy(controller);

      if (_symbols.isNotEmpty) {
        final symbols = [..._symbols];
        setGeoJsonSource(controller, symbols, _clusterSourceId);
      }
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
                  op(const [
                    "interpolate", ["linear"], ["zoom"],
                    16, 0.0,
                    17, 1.0,
                    17.5, 0.0
                  ]),
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
          fillOpacity: op(const [
            "interpolate",
            ["linear"],
            ["zoom"],
            13, 1.0,
            14, 0.0
          ]),
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
        fillOpacity: op([
          "interpolate", ["linear"], ["zoom"],
          fadeInZoom, 1.0,
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
                opacity: op([
                  "interpolate", ["linear"], ["zoom"],
                  fadeInZoom, 1.0,
                  fadeOutZoom, 0.0,
                ]),
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
                op([
                  "interpolate", ["linear"], ["zoom"],
                  fadeOutZoom + 1.5, 1.0,
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
                opacity: op([
                  "interpolate", ["linear"], ["zoom"],
                  fadeOutZoom + 1.5, 1.0,
                  fadeOutZoom + 2.0, 0.0,
                ]),
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

    final opacityExpression = [
      "interpolate", ["linear"], ["zoom"],
      fadeOutZoom, 0.0,
      fadeInEnd,   1.0,
    ];

    // ── WEB ONLY ────────────────────────────────────────────────────────────
    //
    // These calls push each layer's FULL property set instead of just the two
    // opacity/sort keys. The part that actually matters is `symbol-sort-key`:
    // `setLayerProperties` MERGES on both platforms (Android routes
    // `layer#setProperties` into `Layer.setProperties`, which applies only the
    // keys present; the web binding loops setPaintProperty/setLayoutProperty
    // per key), so nothing was ever dropped — but a partial call that names
    // `symbolSortKey` still OVERWRITES it, and the bare `_kSortKeyExpression`
    // discards the per-layer base from [_collisionBase] (text 0, fixed 1000,
    // icon 2000/3000, customRendering 4000).
    //
    // That base is the whole marker→dot cascade: a feature's dot sorts at
    // `collisionBase + 0.6`, i.e. immediately after its own full marker, so the
    // full marker wins and suppresses its own dot. Flatten every full marker to
    // ~0 and they instead all place first as one undifferentiated block, knock
    // each other out under `iconAllowOverlap: false`, and each loser's dot then
    // places into the gap. For an animal that dot is the paw — which is the
    // "paw at every zoom" defect this fixes on web.
    //
    // NOT applied on native. Restoring the bases re-sorts customRendering to
    // 4000, i.e. *after* text/fixed/icon markers, so the large labelled animal
    // composites start losing collisions to them as you zoom in and drop back
    // to paws. Mobile shipped for a long time with the flattened sort key and
    // that is the accepted look there, so native keeps the original partial
    // calls verbatim. Re-unify only with a deliberate mobile design pass.
    if (kIsWeb) {
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
      return;
    }

    // Native: unchanged from before the web work — partial sets that retune the
    // fade ramp and flatten symbol-sort-key. Deliberately kept as-is; the only
    // change here is that each opacity value passes through the layer's opacity
    // resolver, so a host override substitutes for it.
    //
    // Each layer also re-registers its full property set carrying THIS branch's
    // flattened sort key rather than the creation-time per-layer base, so that
    // if a policy is later applied the state it regenerates is the one native
    // actually wants. (Registering is not pushing: a host that never uses the
    // layer API triggers no extra write, and native behaviour is unchanged.)
    final textOp = _opFor(_normalTextMarkerLayerId);
    _registerLayerProps(
        _normalTextMarkerLayerId,
        (op) => _normalTextLayerProps(op(opacityExpression),
            visibility: _visibility(_normalTextMarkerLayerId),
            sortKey: _kSortKeyExpression));
    await controller.setLayerProperties(
      _normalTextMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        textOpacity: textOp(opacityExpression),
      ),
    );

    final withSecId = "$_normalIconMarkerLayerId-withSectionId";
    final withSecOp = _opFor(withSecId);
    _registerLayerProps(
        withSecId,
        (op) => _normalIconLayerProps(
            sortBase: 3000,
            opacity: op(opacityExpression),
            visibility: _visibility(withSecId),
            sortKey: _kSortKeyExpression));
    await controller.setLayerProperties(
      withSecId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: withSecOp(opacityExpression),
        textOpacity: withSecOp(opacityExpression),
      ),
    );

    final withoutSecId = "$_normalIconMarkerLayerId-withoutSectionId";
    final withoutSecOp = _opFor(withoutSecId);
    _registerLayerProps(
        withoutSecId,
        (op) => _normalIconLayerProps(
            sortBase: 2000,
            opacity: op(opacityExpression),
            visibility: _visibility(withoutSecId),
            sortKey: _kSortKeyExpression));
    await controller.setLayerProperties(
      withoutSecId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: withoutSecOp(opacityExpression),
        textOpacity: withoutSecOp(opacityExpression),
      ),
    );

    final customOp = _opFor(_customRenderingMarkerLayerId);
    _registerLayerProps(
        _customRenderingMarkerLayerId,
        (op) => _customRenderingLayerProps(op(opacityExpression),
            visibility: _visibility(_customRenderingMarkerLayerId),
            sortKey: _kSortKeyExpression));
    await controller.setLayerProperties(
      _customRenderingMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        iconOpacity: customOp(opacityExpression),
      ),
    );

    final fixedOp = _opFor(_fixedMarkerLayerId);
    _registerLayerProps(
        _fixedMarkerLayerId,
        (op) => _fixedMarkerLayerProps(
              iconOpacity: op(_kDefaultMarkerOpacity),
              textOpacity: op(opacityExpression),
              visibility: _visibility(_fixedMarkerLayerId,
                  internalVisible: !_config.immersive),
              sortKey: _kSortKeyExpression,
            ));
    await controller.setLayerProperties(
      _fixedMarkerLayerId,
      SymbolLayerProperties(
        symbolSortKey: _kSortKeyExpression,
        textOpacity: fixedOp(opacityExpression),
      ),
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
          polygon = _polygons.firstWhere(
                (p) => p.id.contains(polyID) || p.id.contains(polyIDInsideMarker),
            orElse: () => throw Exception('Polygon not found'),
          );
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
        _updatePolygonSource(controller, selectPolygonId: polygon.id);
      }
      if (marker != null) {
        setGeoJsonSource(
          controller,
          _symbols,
          _clusterSourceId,
          selectedMarkerId: marker.id,
        );
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
    _updatePolygonSource(controller, selectPolygonId: isSelected ? selectPolygonId : null);
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
      await _updatePolygonSource(controller, selectPolygonId: null);

      await setGeoJsonSource(
        controller,
        _symbols,
        _clusterSourceId,
        selectedMarkerId: null,
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