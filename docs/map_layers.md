# MapLibre map layers — inventory & config reference

Source: `lib/src/providers/mapLibre_map_provider.dart`

Everything drawn on the map is a MapLibre *style layer*. This provider never
exposes those raw layer ids to host code — they are grouped into a small,
stable, semantic taxonomy (`MapLayer`) that the host controls. Below is the
full inventory of what is rendered, followed by how the example config file
(`map_config.example.yaml`) maps onto the existing controller API.

---

## 1. Layer inventory

Every style layer this provider creates, grouped by its semantic `MapLayer`
group (from `_layerGroups` in the provider). Controlling a **family** affects
all its members; controlling a **member** overrides just that one.

### markers (family)
| Style layer id | Group (member) | What it draws |
|---|---|---|
| `collision-dot-markers-layer` | `landmarkMarkers` | Small dot a marker collapses to when it loses a collision |
| `normalText-markers-layer` | `landmarkMarkers` | Text-only landmark labels |
| `normalIcon-markers-layer-withSectionId` | `landmarkMarkers` | Icon markers that belong to a section |
| `normalIcon-markers-layer-withoutSectionId` | `landmarkMarkers` | Icon markers with no section |
| `customRendering-markers-layer` | `landmarkMarkers` | Custom-baked composite markers (photo pills etc.) |
| `overlap-override-markers-layer` | `landmarkMarkers` | Markers force-pinned to always show (allow-overlap) |
| `fixed-markers-layer` | `entryMarkers` | Bearing-carrying pins (building entries). Hidden by renderer in 3D |
| `priority-marker-layer` | `priorityMarkers` | Source & destination pins (never hidden by filters) |
| `section-markers-layer` | `sectionLabels` | Section name labels |
| `subSection-markers-layer` | `subSectionLabels` | Sub-section name labels |
| `patch-above-markers-layer` | `venueLabel` | Venue name label shown when zoomed out |

### polygons (family)
| Style layer id | Group (member) | What it draws |
|---|---|---|
| `normal-polygons-layer` | `rooms` | Room / unit fills |
| `pattern-polygons-layer` | `rooms` | Textured (pattern-filled) rooms |
| `extruded-polygon-layer` | `extrusions` | 3D extruded building volumes / walls |

> `sections`, `subSections`, `venueBoundary` polygon members exist in the
> taxonomy but their style layers are currently commented out in
> `_layerGroups`, so they render nothing today.

### route (family)
| Style layer id | Group (member) | What it draws |
|---|---|---|
| `path-solid-polyline-layer` | `routeLine` | Solid navigation route line |
| `path-solid-outline-polyline-layer` | `routeLine` | Route line outline / halo |
| `path-dashed-polyline-layer` | `routeLine` | Dashed route segments |
| `grey-overlay-polyline-layer` | `routeTraveled` | Grey overlay over already-travelled path |
| `normal-polyline-layer` | `polylines` | Generic host-drawn polylines |

### furniture (family, no members)
| Style layer id | Group | What it draws |
|---|---|---|
| `furniture-fill-layer` | `furniture` | Flat 2D furniture footprint |
| `furniture-layer` | `furniture` | 3D extruded furniture (immersive mode, zoom ≥ 17.5) |

### userLocation (family, no members)
| Style layer id | Group | What it draws |
|---|---|---|
| `rotation-marker-layer` | `userLocation` | User position puck (with bearing) |
| `normal-circle-layer` | `userLocation` | Accuracy circle |

### selection (family, no members)
| Style layer id | Group | What it draws |
|---|---|---|
| `selected-marker-layer` | `selection` | Highlight on the selected landmark marker |
| `selected-plain-polygon-layer` | `selection` | Selected room fill highlight |
| `selected-plain-polygon-stroke-layer` | `selection` | Selected room outline |
| `selected-extruded-polygon-layer` | `selection` | Selected room 3D highlight |

### Unmanaged (not in the taxonomy)
| Style layer id | Notes |
|---|---|
| `osm-tiles-layer` | Basemap raster. Not group-controllable; affected only by **greyscale** (raster-saturation) |

---

## 2. What each layer supports

Per group (`MapLayerState`) you can set three things:

| Field | Meaning |
|---|---|
| `visible` | `false` hides the group's layers outright. Not the same as `opacity: 0` — a hidden layer takes no part in collision and returns nothing from hit-testing. |
| `opacity` | Absolute `0.0–1.0` override. Replaces per-feature opacity and any zoom fade ramp. `null`/unset keeps the renderer's own value. |
| `tappable` | `false` makes the group fully inert to taps (no highlight, no camera move, no `onMarkerTap`/`onPolygonTap`). Programmatic `selectLocation` still works. |

Notes:
- `userLocation` and `selection` are intentionally left visible by presets like
  `polygonsOnly`, so the puck and tap-highlight survive.
- `entryMarkers` and (in 3D) `rooms`/`furniture` can be hidden by the renderer
  for coherence; a policy can subtract visibility but cannot force those back on.
- `extrusions` opacity is applied by **rebuilding** the layer (fill-extrusion
  layers reject property pushes on Android) — a visible flicker, so avoid
  animating it.

---

## 3. Config file → API mapping

The example config (`map_config.example.yaml`) is a plain data file. It maps
1:1 onto the existing public API on `UnifiedMapController` / `MapConfig`.
A tiny loader (section 4) parses it into a `MapLayerPolicy` + a few calls.

| Config key | Maps to |
|---|---|
| `layers.<group>.visible` | `MapLayerState(visible:)` → `MapLayerPolicy` → `MapConfig.initialLayerPolicy` / `controller.setLayers` |
| `layers.<group>.opacity` | `MapLayerState(opacity:)` |
| `layers.<group>.tappable` | `MapLayerState(tappable:)` |
| `greyscale` | `controller.setGreyscale(bool)` |
| `symbols.mode: all` | `controller.clearMarkerTypeFilter()` |
| `symbols.mode: only` + `symbols.types` | `controller.showMarkerTypes({...})` |
| `immersive` (3D on/off) | `MapConfig.immersive` |
| `fade` | **Proposed** — see section 5 (no public toggle exists yet) |

`<group>` is any of: `markers`, `landmarkMarkers`, `entryMarkers`,
`priorityMarkers`, `sectionLabels`, `subSectionLabels`, `venueLabel`,
`polygons`, `rooms`, `extrusions`, `route`, `routeLine`, `routeTraveled`,
`polylines`, `furniture`, `userLocation`, `selection`.

---

## 4. Loader example (Dart)

```dart
import 'package:yaml/yaml.dart';
import 'package:unified_map_view/unified_map_view.dart';

/// Parse the group table into a MapLayerPolicy.
MapLayerPolicy _policyFromYaml(YamlMap? layers) {
  if (layers == null) return MapLayerPolicy.all;
  const byName = <String, MapLayer>{
    'markers': MapLayer.markers,
    'landmarkMarkers': MapLayer.landmarkMarkers,
    'entryMarkers': MapLayer.entryMarkers,
    'priorityMarkers': MapLayer.priorityMarkers,
    'sectionLabels': MapLayer.sectionLabels,
    'subSectionLabels': MapLayer.subSectionLabels,
    'venueLabel': MapLayer.venueLabel,
    'polygons': MapLayer.polygons,
    'rooms': MapLayer.rooms,
    'extrusions': MapLayer.extrusions,
    'route': MapLayer.route,
    'routeLine': MapLayer.routeLine,
    'routeTraveled': MapLayer.routeTraveled,
    'polylines': MapLayer.polylines,
    'furniture': MapLayer.furniture,
    'userLocation': MapLayer.userLocation,
    'selection': MapLayer.selection,
  };

  final states = <MapLayer, MapLayerState>{};
  layers.forEach((key, value) {
    final group = byName[key as String];
    if (group == null || value is! YamlMap) return;
    states[group] = MapLayerState(
      visible: value['visible'] as bool?,
      opacity: (value['opacity'] as num?)?.toDouble(),
      tappable: value['tappable'] as bool?,
    );
  });
  return MapLayerPolicy(states);
}

Future<void> applyConfig(
    UnifiedMapController controller, YamlMap cfg) async {
  // 1. per-layer policy
  await controller.setLayers(_policyFromYaml(cfg['layers'] as YamlMap?));

  // 2. greyscale
  await controller.setGreyscale(cfg['greyscale'] == true);

  // 3. symbol types
  final symbols = cfg['symbols'] as YamlMap?;
  if (symbols == null || symbols['mode'] == 'all') {
    await controller.clearMarkerTypeFilter();
  } else if (symbols['mode'] == 'only') {
    final types = (symbols['types'] as YamlList?)
            ?.map((e) => e.toString())
            .toSet() ??
        <String>{};
    await controller.showMarkerTypes(types);
  }
}
```

Seed the map at creation time (so nothing wrong flashes on screen) via
`MapConfig(initialLayerPolicy: _policyFromYaml(...), immersive: cfg['immersive'])`,
then apply greyscale / symbols in `onVenueRendered`.

---

## 5. The "fade" toggle (proposed — not yet in the API)

The renderer already computes a per-venue zoom fade (`_fadeOutZoom`,
`fadeInZoom`/`fadeOutZoom` in `_refreshMarkerLayerMinZooms` /
`_refreshPatchFadeIfStale`): markers and the venue boundary ramp their opacity
in/out across a zoom window. There is currently **no public switch** to turn
that ramp off.

To honour `fade: false` in the config you'd add a small flag to the provider,
e.g.:

```dart
bool _fadeEnabled = true;

Future<void> setFade(dynamic controller, bool enabled) async {
  if (controller is! MapLibreMapController || _fadeEnabled == enabled) return;
  _fadeEnabled = enabled;
  await _refreshMarkerLayerMinZooms(controller); // rebuild the ramps
}
```

and, inside the interpolate expressions that build the fade (the
`op(1.0)` / `0.0` stops), collapse the ramp to a flat `op(1.0)` when
`_fadeEnabled == false`. Expose it on `UnifiedMapController.setFade(bool)`,
mirroring `setGreyscale`. The config key is already reserved in the example
file so the wiring is a drop-in once the method exists.
