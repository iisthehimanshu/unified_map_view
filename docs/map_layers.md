# MapLibre map layers — inventory & config reference

Source: `lib/src/providers/mapLibre_map_provider.dart`

Everything drawn on the map is a MapLibre *style layer*. Those layers are
addressable two ways, and both live in one `MapLayerPolicy`:

* by **semantic group** (`MapLayer`) — a small, stable taxonomy of families and
  members, for "dim every polygon" or "no marker responds to taps";
* by **style-layer id** (`MapStyleLayers`) — the exact layer, for settings a
  whole group should not get, and for *any* MapLibre paint or layout property,
  not just the three semantic fields.

Settings resolve most-specific-last:

```
default  ->  family  ->  member  ->  style layer id
```

Each link overrides only the fields it names, so a config that says
`fill-color: red` for one layer changes that one property and inherits
everything else — the family's opacity, the member's tappability, and the
renderer's own value for the other nineteen properties.

Below is a decision guide, the full inventory of what is rendered, the config
file format (`map_config.example.yaml`), and worked recipes for the common jobs.

---

## 0. Which call do I use?

Start here. Everything below is one of these five.

| I want to… | Use | Where |
|---|---|---|
| Ship a file the app reads at startup | `MapStyleConfig.fromAsset` → `UnifiedMapController(styleConfig:)` | `main()`, before `runApp` |
| Change **one exact layer** at runtime | `controller.setStyleLayer(id, …)` | anywhere after the map exists |
| Change **a whole category** at runtime | `controller.setLayer(group, …)` | same |
| Swap the whole configuration at once | `controller.applyStyleConfig(config)` | same |
| Put everything back | `controller.resetLayers()` | same |

Plus three global switches that are not per-layer:
`controller.setGreyscale(bool)`, `controller.setFade(bool)`,
`controller.showMarkerTypes({…})` / `clearMarkerTypeFilter()`.

### The two ways to name a layer

Every call above takes either a **group** or a **style-layer id**:

```dart
// GROUP — a category. Broad, semantic, stable.
controller.setLayer(MapLayer.rooms, opacity: 0.5);

// STYLE LAYER ID — one exact layer. Precise, and the only way to set
// arbitrary MapLibre properties.
controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  properties: {'fill-color': 'red'},
);
```

`MapStyleLayers.normalPolygons` is just a typo-safe constant for the string
`'normal-polygons-layer'` — the same name you would write in the YAML. §1 lists
every id and which group it belongs to.

### What each accepts

|  | `visible` | `opacity` | `tappable` | `properties` |
|---|:---:|:---:|:---:|:---:|
| `setLayer(group, …)` | ✅ | ✅ | ✅ | ❌ *(see note)* |
| `setStyleLayer(id, …)` | ✅ | ✅ | ✅ | ✅ |
| YAML, group key | ✅ | ✅ | ✅ | ✅ |
| YAML, layer-id key | ✅ | ✅ | ✅ | ✅ |

> **Note.** `setLayer` is the pre-existing group API and still takes only the
> three semantic fields. To set raw properties on a whole group *from Dart*, go
> through `updateLayers` with a policy (recipe 6). The config file has no such
> gap.

### Calls merge; they do not reset

Every call above merges into the live policy. Setting `fill-color` and later
`fill-outline-color` on the same layer leaves both set. To undo, pass the
explicit clears — `clearOpacity: true`, `clearProperties: true` — or
`resetLayers()` for the lot. `opacity: null` cannot mean "remove", because null
already means "leave unchanged".

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

`MapLayerState` carries three semantic fields plus an open-ended property map.
All four are settable on a group *or* on a single style-layer id.

| Field | Meaning |
|---|---|
| `visible` | `false` hides the layers outright. Not the same as `opacity: 0` — a hidden layer takes no part in collision and returns nothing from hit-testing. |
| `opacity` | Absolute `0.0–1.0` override. Semantic and cross-cutting: it resolves into *every* opacity a layer has (a symbol layer's icon and text alike) and replaces any zoom fade ramp. `null`/unset keeps the renderer's own value. |
| `tappable` | `false` makes the layers fully inert to taps (no highlight, no camera move, no `onMarkerTap`/`onPolygonTap`). Programmatic `selectLocation` still works. |
| `properties` | Any MapLibre paint/layout property, written over what the renderer built: `fill-color`, `text-size`, `line-width`, `raster-opacity`, … Values may be literals or full style expressions. |

### `properties` — the open-ended half

Where `opacity` is semantic, `properties` is a literal key/value overwrite of the
renderer's own property set. Keys not named keep the renderer's value; that is
what lets a config name one property and inherit the rest.

```dart
controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  properties: {'fill-color': 'red', 'fill-outline-color': '#990000'},
);
```

- Keys may be kebab-case (`fill-color`) or camelCase (`fillColor`) — the two are
  interchangeable.
- A property must match the layer's **type**: `fill-color` on a symbol layer does
  nothing. §1's tables say what each layer draws; `fill-*` for polygon/furniture
  fills, `fill-extrusion-*` for the 3D ones, `line-*` for routes and polylines,
  `text-*`/`icon-*` for markers and labels, `circle-*` for the accuracy circle,
  `raster-*` for the basemap.
- `visibility` is **not** honoured as a raw property — `visible` owns it, so one
  field answers "is this layer drawn".
- Applied both when a layer is first created and on every later re-push, so a
  config seeded at construction never flashes the un-styled version first.

Notes:
- `userLocation` and `selection` are intentionally left visible by presets like
  `polygonsOnly`, so the puck and tap-highlight survive.
- `entryMarkers` and (in 3D) `rooms`/`furniture` can be hidden by the renderer
  for coherence; a policy can subtract visibility but cannot force those back on.
- `extrusions` opacity **and properties** are applied by rebuilding the layer
  (fill-extrusion layers reject property pushes on Android) — a visible flicker,
  so avoid animating them.
- `osm-tiles-layer` is outside the group taxonomy; its id is the only way to
  reach it.

---

## 3. Config file → API mapping

The example config (`map_config.example.yaml`) is a plain data file, and the
package parses it — `MapStyleConfig`, exported from `unified_map_view.dart`.
YAML or JSON; the same loader reads both.

```dart
final style = await MapStyleConfig.fromAsset('assets/map_config.yaml');

UnifiedMapController(
  // ...,
  styleConfig: style,
);
```

That single argument does everything: `layers` seed `MapConfig.initialLayerPolicy`
so the map is created in the right state rather than flashing the default first,
and the global modes are pushed as soon as there is a controller. To swap
configs later, `await controller.applyStyleConfig(style)` — everything except
`immersive`, which is fixed when the map is built.

| Config key | Maps to |
|---|---|
| `layers.<group>.{visible,opacity,tappable}` | `MapLayerState` → `MapLayerPolicy.states` |
| `layers.<group>.<style-property>` | `MapLayerState.properties` |
| `layers.<style-layer-id>.…` | `MapLayerPolicy.layers` — same fields, applied to one layer |
| `greyscale` | `controller.setGreyscale(bool)` |
| `fade` | `controller.setFade(bool)` |
| `symbols.mode: all` | `controller.clearMarkerTypeFilter()` |
| `symbols.mode: only` + `symbols.types` | `controller.showMarkerTypes({…})` |
| `immersive` | `MapConfig.immersive` (creation-time) |

`<group>` is any of: `markers`, `landmarkMarkers`, `entryMarkers`,
`priorityMarkers`, `sectionLabels`, `subSectionLabels`, `venueLabel`,
`polygons`, `rooms`, `sections`, `subSections`, `venueBoundary`, `extrusions`,
`route`, `routeLine`, `routeTraveled`, `polylines`, `furniture`, `userLocation`,
`selection`.

`<style-layer-id>` is any id from §1, and the constants for them are on
`MapStyleLayers`.

### Omitted vs. specified

Every key is optional, and an omitted key is **not applied at all** — the
renderer's default stands. Two places where that distinction is load-bearing:

- Omitting `symbols:` entirely leaves the current filter alone. `symbols: {mode:
  all}` actively *clears* it.
- Omitting `opacity` on a layer keeps the renderer's own expression, zoom fade
  ramp included. `opacity: 1.0` replaces that expression with a flat 1.0.

### Errors

`MapStyleConfig.parse` throws `FormatException` only when the document itself is
unparseable. A key it does not recognise, or a value of the wrong type, is
collected into `config.warnings` (and `debugPrint`ed in debug builds) and skipped
— one typo must not cost the host its whole configuration at startup. An
unrecognised *layer id* is applied anyway, since it may name a layer the host
pushed onto the style itself; it is still reported.

Hosts that prefer to fail loudly can `assert(config.warnings.isEmpty)`.

### Building a config without a file

`MapStyleConfig.fromMap` takes an already-decoded map (a `json.decode` result, a
remote config payload), and `MapLayerPolicy` is public and constructible by
hand:

```dart
const policy = MapLayerPolicy({
  MapLayer.polygons: MapLayerState(opacity: 0.5),
}, {
  MapStyleLayers.normalPolygons: MapLayerState(
    properties: {'fill-color': 'red'},
  ),
});
```

At runtime, `controller.setLayer(group, …)` changes one group and
`controller.setStyleLayer(layerId, …)` one layer; both merge into the live
policy rather than replacing it.

---

## 4. Recipes

Each recipe shows the same job done from the config file and from Dart. Pick
whichever fits — they drive the identical machinery.

### 1. Repaint one layer, keep everything else it draws

The headline case: change a colour without inheriting responsibility for the
layer's other twenty properties.

```yaml
layers:
  normal-polygons-layer:
    fill-color: "#ffe8cc"
    fill-outline-color: "#d9a441"
```

```dart
controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  properties: {
    'fill-color': '#ffe8cc',
    'fill-outline-color': '#d9a441',
  },
);
```

`pattern-polygons-layer` — the other half of the `rooms` member — is untouched,
because it was never named.

### 2. Dim a whole category

```yaml
layers:
  polygons:
    opacity: 0.5
```

```dart
controller.setLayer(MapLayer.polygons, opacity: 0.5);
```

`opacity` is semantic and cross-cutting: on a symbol layer it lands on the icon
*and* the text, and it replaces any zoom fade ramp. That is the difference
between it and writing `fill-opacity` yourself.

### 3. Category-wide, with one exception

```yaml
layers:
  polygons:                # everything at half strength …
    opacity: 0.5
  normal-polygons-layer:   # … except this one
    opacity: 0.7
    fill-color: red
  extrusions:              # … and no 3D volumes at all
    visible: false
```

```dart
await controller.setLayer(MapLayer.polygons, opacity: 0.5);
await controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  opacity: 0.7,
  properties: {'fill-color': 'red'},
);
await controller.setLayer(MapLayer.extrusions, visible: false);
```

`pattern-polygons-layer` is not named, so it resolves through `rooms` (nothing
set) to `polygons` and draws at 0.5 with the renderer's own colour.

### 4. Hide something, or make it ignore taps

```yaml
layers:
  furniture:      { visible: false }
  polygons:       { tappable: false }
```

```dart
await controller.setLayer(MapLayer.furniture, visible: false);
await controller.setLayer(MapLayer.polygons, tappable: false);
```

`visible: false` and `opacity: 0` are **not** the same. A hidden marker takes no
part in collision and returns nothing from hit-testing; a zero-opacity one still
suppresses its neighbours and is still hit-tested.

`tappable: false` is fully inert — no highlight, no camera move, no
`onMarkerTap` / `onPolygonTap` — but `selectLocation` still works, so search
results and deep links keep functioning.

### 5. Restyle text, lines, circles, the basemap

The property prefix must match the layer's type (§2). Some worked ones:

```yaml
layers:
  section-markers-layer:        # symbol layer -> text-* / icon-*
    text-size: 15
    text-color: "#333333"
    text-halo-color: "#ffffff"
    text-halo-width: 1.5

  path-solid-polyline-layer:    # line layer -> line-*
    line-width: 8
    line-color: "#0066ff"

  normal-circle-layer:          # circle layer -> circle-*
    circle-color: "#2196F3"
    circle-stroke-width: 3

  osm-tiles-layer:              # raster layer -> raster-*
    raster-opacity: 0.85
```

```dart
controller.setStyleLayer(
  MapStyleLayers.sectionMarkers,
  properties: {'text-size': 15, 'text-halo-width': 1.5},
);
controller.setStyleLayer(
  MapStyleLayers.baseMapRaster,
  properties: {'raster-opacity': 0.85},
);
```

`osm-tiles-layer` is outside the group taxonomy, so its id is the only way to
reach it.

### 6. Raw properties on a whole group, from Dart

`setLayer` does not take `properties`, so build a policy and merge it:

```dart
await controller.updateLayers(const MapLayerPolicy({
  MapLayer.polygons: MapLayerState(
    properties: {'fill-outline-color': '#333333'},
  ),
}));
```

`updateLayers` merges field-wise; `setLayers` replaces the whole policy.

### 7. Values can be expressions, not just literals

Anything the MapLibre style spec accepts:

```yaml
layers:
  normal-polygons-layer:
    fill-color: ["get", "fillColor"]        # read it off the feature
    fill-translate: [2, 4]
```

```dart
controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  properties: {'fill-color': ['get', 'fillColor']},
);
```

### 8. Undo

```dart
// Drop one override, hand the layer back to the renderer.
await controller.setStyleLayer(
  MapStyleLayers.normalPolygons,
  clearProperties: true,
  clearOpacity: true,
);

// Drop everything, everywhere.
await controller.resetLayers();
```

### 9. Load the file at startup (the whole point)

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var style = MapStyleConfig.none;              // "change nothing"
  try {
    style = await MapStyleConfig.fromAsset('assets/map_config.yaml');
  } catch (e) {
    debugPrint('map config failed to load: $e');  // map still works
  }

  runApp(MyApp(styleConfig: style));
}

// … then, wherever the controller is built:
UnifiedMapController(
  // ... existing arguments unchanged ...
  styleConfig: style,
);
```

Load it in `main()`, not `initState`: `initState` is synchronous and cannot
await an asset, and passing the config at *construction* is what seeds
`MapConfig.initialLayerPolicy` — so layers are created already styled instead of
drawing plain and being repainted a frame later.

`example/lib/main.dart` does exactly this, with
`example/assets/map_config.yaml` as the file.

### 10. Re-apply a config while the app is running

```dart
rootBundle.evict('assets/map_config.yaml');   // else you get the cached copy
final config = await MapStyleConfig.fromAsset('assets/map_config.yaml');
await controller.applyStyleConfig(config);
```

`applyStyleConfig` **merges** over the live policy rather than replacing it, so
anything set by earlier calls survives unless the file names the same field.
Call `resetLayers()` first for a clean slate.

`immersive` is the one key this cannot change — 3D is fixed when the map is
built, so it only takes effect through the constructor.

### 11. No config at all

Pass nothing. Every layer resolves to `MapLayerState.defaults`, the property
merge is skipped outright, and no global mode is pushed — the map renders
exactly as it did before any of this existed. Pinned by
`test/no_config_defaults_test.dart`.

---

## 5. The fade toggle

`controller.setFade(bool)` turns off the zoom fade ramp on markers and the venue
boundary — the per-venue curves computed in `_refreshPatchAboveOpacity` and
`_refreshMarkerLayerMinZooms`. With it off, those interpolate expressions
collapse to a flat, fully-opaque value and the labels pop in and out instead of
dissolving.

Zoom **ranges** are deliberately left alone: the venue name still stops drawing
above its `maxzoom`, so nothing that was hidden becomes visible. Only the
dissolve goes.

Config key: `fade`. Provider hook: `BaseMapProvider.setFade`, implemented by the
MapLibre provider and a no-op elsewhere.
