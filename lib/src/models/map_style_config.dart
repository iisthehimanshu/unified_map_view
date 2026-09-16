import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import 'map_layer.dart';

/// A whole map's render configuration, parsed from a file the developer
/// maintains and hands over rather than compiled into the app.
///
/// Two kinds of setting live here:
///
/// * **global render modes** — [immersive], [greyscale], [fade], [symbolTypes]
///   — one switch each, applying to the map as a whole;
/// * **per-layer settings** — [layers] — visibility, tappability and *any*
///   MapLibre style property, keyed either by [MapLayer] group name or by exact
///   style-layer id (see [MapStyleLayers]).
///
/// Every field is nullable and every key optional. Anything the file leaves out
/// is not applied at all, so the renderer's own default stands — a config that
/// says only `fill-color: red` for one layer changes that one property and
/// nothing else on the map.
///
/// ```dart
/// final style = await MapStyleConfig.fromAsset('assets/map_config.yaml');
///
/// UnifiedMapController(
///   // ... ,
///   styleConfig: style,   // seeds layers at creation, then applies the
///                         // global modes once the venue is drawn
/// );
/// ```
///
/// The file format is documented, with every key, in
/// `docs/map_config.example.yaml`.
@immutable
class MapStyleConfig {
  /// Per-layer visibility / opacity / tappability / style properties.
  ///
  /// Never null — an absent `layers:` block parses to [MapLayerPolicy.all],
  /// which changes nothing.
  final MapLayerPolicy layers;

  /// 3D on/off, or null when the file does not say.
  ///
  /// Unlike the others this is a *creation-time* setting: it reaches
  /// `MapConfig.immersive` and cannot be changed by re-applying a config.
  final bool? immersive;

  /// Desaturate basemap, polygons and polylines, or null when unspecified.
  final bool? greyscale;

  /// Zoom fade ramp on markers and the venue boundary, or null when
  /// unspecified.
  final bool? fade;

  /// Which landmark symbol types to draw.
  ///
  /// Three distinct states, which is why this is not a plain set:
  /// * [symbolsSpecified] false — the file said nothing; leave the filter alone.
  /// * specified with null here (`mode: all`) — draw every type.
  /// * specified with a set (`mode: only`) — draw only these.
  final Set<String>? symbolTypes;

  /// Whether the file had a `symbols:` block at all. See [symbolTypes].
  final bool symbolsSpecified;

  /// Keys the parser did not recognise, in `section.key` form.
  ///
  /// Collected rather than thrown: a typo in one layer id must not cost the host
  /// its whole configuration at startup. Logged in debug mode by [parse]; hosts
  /// that would rather fail loudly can assert this is empty.
  final List<String> warnings;

  const MapStyleConfig({
    this.layers = MapLayerPolicy.all,
    this.immersive,
    this.greyscale,
    this.fade,
    this.symbolTypes,
    this.symbolsSpecified = false,
    this.warnings = const [],
  });

  /// A config that changes nothing.
  static const MapStyleConfig none = MapStyleConfig();

  bool get isEmpty =>
      layers.isEmpty &&
      immersive == null &&
      greyscale == null &&
      fade == null &&
      !symbolsSpecified;

  /// Parse a YAML (or JSON — YAML is a superset) config document.
  ///
  /// Throws [FormatException] only when the document itself is unparseable;
  /// unknown keys land in [warnings] instead.
  static MapStyleConfig parse(String source) {
    final Object? doc;
    try {
      doc = loadYaml(source);
    } on YamlException catch (e) {
      throw FormatException('map config is not valid YAML/JSON: $e');
    }
    if (doc == null) return none;
    if (doc is! Map) {
      throw const FormatException(
          'map config must be a mapping of keys at the top level');
    }
    return MapStyleConfig.fromMap(_plain(doc) as Map<String, Object?>);
  }

  /// Load and parse the config bundled as a Flutter asset.
  ///
  /// The asset must be declared in the host app's `pubspec.yaml`.
  static Future<MapStyleConfig> fromAsset(String assetPath) async {
    return parse(await rootBundle.loadString(assetPath));
  }

  /// Build from an already-decoded map — a `json.decode` result, a remote
  /// config payload, or a literal written in Dart.
  factory MapStyleConfig.fromMap(Map<String, Object?> map) {
    final warnings = <String>[];

    bool? readBool(String key) {
      final value = map[key];
      if (value == null) return null;
      if (value is bool) return value;
      warnings.add('$key: expected true/false, got "$value"');
      return null;
    }

    // ---- symbols -----------------------------------------------------------
    Set<String>? symbolTypes;
    var symbolsSpecified = false;
    final symbols = map['symbols'];
    if (symbols is Map) {
      symbolsSpecified = true;
      final mode = symbols['mode']?.toString() ?? 'all';
      if (mode == 'only') {
        final types = symbols['types'];
        symbolTypes = types is Iterable
            ? types.map((e) => e.toString()).toSet()
            : <String>{};
        if (types != null && types is! Iterable) {
          warnings.add('symbols.types: expected a list, got "$types"');
        }
      } else if (mode != 'all') {
        warnings.add('symbols.mode: expected "all" or "only", got "$mode"');
        symbolsSpecified = false;
      }
    } else if (symbols != null) {
      warnings.add('symbols: expected a mapping, got "$symbols"');
    }

    // ---- layers ------------------------------------------------------------
    var policy = MapLayerPolicy.all;
    final layers = map['layers'];
    if (layers is Map) {
      // Groups are applied before layer ids only for tidiness — resolution
      // order is fixed by MapLayerPolicy.resolveLayer, not by insertion order.
      layers.forEach((rawKey, rawValue) {
        final key = rawKey.toString();
        if (rawValue == null) return; // `rooms:` with an empty body
        if (rawValue is! Map) {
          warnings.add('layers.$key: expected a mapping, got "$rawValue"');
          return;
        }
        final state = _stateFromMap(
          rawValue.cast<Object?, Object?>(),
          path: 'layers.$key',
          warnings: warnings,
        );
        final group = MapLayer.byName(key);
        if (group != null) {
          policy = policy.withGroup(group, state);
          return;
        }
        if (!MapStyleLayers.known.contains(key)) {
          // Not fatal: the id may belong to a layer a future version adds, or
          // to one the host pushed onto the style itself.
          warnings.add(
              'layers.$key: not a known group name or style layer id — applied anyway');
        }
        policy = policy.withLayer(key, state);
      });
    } else if (layers != null) {
      warnings.add('layers: expected a mapping, got "$layers"');
    }

    for (final key in map.keys) {
      if (!_knownTopLevelKeys.contains(key)) {
        warnings.add('$key: unknown top-level key — ignored');
      }
    }

    final config = MapStyleConfig(
      layers: policy,
      immersive: readBool('immersive'),
      greyscale: readBool('greyscale'),
      fade: readBool('fade'),
      symbolTypes: symbolTypes,
      symbolsSpecified: symbolsSpecified,
      warnings: List.unmodifiable(warnings),
    );
    if (kDebugMode) {
      for (final warning in warnings) {
        debugPrint('[MapStyleConfig] $warning');
      }
    }
    return config;
  }

  static const Set<String> _knownTopLevelKeys = {
    'immersive',
    'greyscale',
    'fade',
    'symbols',
    'layers',
  };

  /// The three semantic fields plus every remaining key as a raw style
  /// property.
  ///
  /// Anything not named `visible` / `opacity` / `tappable` is passed straight
  /// through to MapLibre. That is what makes the format open-ended: a property
  /// this package has never heard of still reaches the layer, and a value can be
  /// a literal or a full style expression.
  static MapLayerState _stateFromMap(
    Map<Object?, Object?> map, {
    required String path,
    required List<String> warnings,
  }) {
    bool? visible;
    double? opacity;
    bool? tappable;
    final properties = <String, Object?>{};

    map.forEach((rawKey, rawValue) {
      final key = rawKey.toString();
      final value = _plain(rawValue);
      switch (key) {
        case 'visible':
          if (value is bool) {
            visible = value;
          } else {
            warnings.add('$path.visible: expected true/false, got "$value"');
          }
        case 'opacity':
          if (value is num) {
            opacity = value.toDouble().clamp(0.0, 1.0);
          } else {
            warnings.add('$path.opacity: expected a number 0.0-1.0, '
                'got "$value"');
          }
        case 'tappable':
          if (value is bool) {
            tappable = value;
          } else {
            warnings.add('$path.tappable: expected true/false, got "$value"');
          }
        case 'visibility':
          // `visible` owns this, so honouring both would let one config say two
          // contradictory things about the same layer.
          warnings.add('$path.visibility: use `visible: true/false` instead — '
              'ignored');
        default:
          properties[MapLayerState.normalizeKey(key)] = value;
      }
    });

    return MapLayerState(
      visible: visible,
      opacity: opacity,
      tappable: tappable,
      properties: properties,
    );
  }

  /// A YamlMap/YamlList tree as plain Dart maps, lists and scalars.
  ///
  /// Necessary rather than cosmetic: YamlMap and YamlList are unmodifiable views
  /// that do not survive the platform-channel encoding a style property goes
  /// through, and a YamlMap's runtime key type is `dynamic`, which breaks the
  /// `Map<String, Object?>` casts downstream.
  static Object? _plain(Object? node) {
    if (node is YamlMap || node is Map) {
      return <String, Object?>{
        for (final entry in (node as Map).entries)
          entry.key.toString(): _plain(entry.value),
      };
    }
    if (node is YamlList || node is List) {
      return [for (final item in node as List) _plain(item)];
    }
    return node;
  }

  MapStyleConfig copyWith({
    MapLayerPolicy? layers,
    bool? immersive,
    bool? greyscale,
    bool? fade,
    Set<String>? symbolTypes,
    bool? symbolsSpecified,
  }) {
    return MapStyleConfig(
      layers: layers ?? this.layers,
      immersive: immersive ?? this.immersive,
      greyscale: greyscale ?? this.greyscale,
      fade: fade ?? this.fade,
      symbolTypes: symbolTypes ?? this.symbolTypes,
      symbolsSpecified: symbolsSpecified ?? this.symbolsSpecified,
      warnings: warnings,
    );
  }

  @override
  String toString() => 'MapStyleConfig(immersive: $immersive, '
      'greyscale: $greyscale, fade: $fade, '
      'symbols: ${symbolsSpecified ? (symbolTypes ?? 'all') : 'unspecified'}, '
      'layers: $layers)';
}
