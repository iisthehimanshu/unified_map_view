part of '../maplibre_gl.dart';

/// Where one wall image stands: a rectangle running along the ground from
/// [start] to [end] and rising from [baseMeters] to
/// `baseMeters + heightMeters`. The image is stretched to fill it.
///
/// The front of the image is the side where [start] is on the viewer's left.
@immutable
class WallImagePlacement {
  const WallImagePlacement({
    required this.start,
    required this.end,
    required this.heightMeters,
    this.baseMeters = 0,
  });

  final LatLng start;
  final LatLng end;
  final double baseMeters;
  final double heightMeters;
}

/// Draws images standing upright on vertical walls (Android and iOS only).
///
/// A wall-image layer is one native MapLibre custom layer that draws any
/// number of textured rectangles sharing one image, in a single draw call.
///
/// It shares the depth buffer with fill-extrusion layers, so buildings hide
/// the images correctly and the images hide what is behind them. Add the
/// layer above (after) the extrusion layers it should be hidden by.
extension WallImageExtension on MapLibreMapController {
  MethodChannel get _wallImageChannel {
    final id = _platformViewId;
    if (id == null) {
      throw StateError('Wall images need a map that has finished creating.');
    }
    return MethodChannel('plugins.flutter.io/maplibre_gl_$id');
  }

  /// Adds one layer [id] that draws [imageBytes] (an encoded PNG or JPEG) at
  /// every placement in [walls].
  ///
  /// With [doubleSided] the back of each image shows it mirrored, as a real
  /// sheet would; without it the back is not drawn.
  ///
  /// [belowLayerId] inserts the layer below that layer; otherwise it goes on
  /// top of the style. Adding an [id] that already exists replaces it.
  Future<void> addWallImages({
    required String id,
    required List<WallImagePlacement> walls,
    required Uint8List imageBytes,
    double opacity = 1,
    bool doubleSided = true,
    String? belowLayerId,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Wall images are only supported on Android and iOS.');
    }
    if (walls.isEmpty) {
      await removeWallImage(id);
      return;
    }
    final values = Float64List(walls.length * 6);
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      values
        ..[i * 6] = w.start.latitude
        ..[i * 6 + 1] = w.start.longitude
        ..[i * 6 + 2] = w.end.latitude
        ..[i * 6 + 3] = w.end.longitude
        ..[i * 6 + 4] = w.baseMeters
        ..[i * 6 + 5] = w.heightMeters;
    }
    await _wallImageChannel.invokeMethod<void>('wallImage#add', {
      'id': id,
      'walls': values,
      'opacity': opacity,
      'doubleSided': doubleSided,
      'image': imageBytes,
      'belowLayerId': belowLayerId,
    });
  }

  /// Adds a layer [id] with a single wall image. See [addWallImages].
  Future<void> addWallImage({
    required String id,
    required LatLng start,
    required LatLng end,
    required Uint8List imageBytes,
    required double heightMeters,
    double baseMeters = 0,
    double opacity = 1,
    bool doubleSided = true,
    String? belowLayerId,
  }) {
    return addWallImages(
      id: id,
      walls: [
        WallImagePlacement(
          start: start,
          end: end,
          baseMeters: baseMeters,
          heightMeters: heightMeters,
        ),
      ],
      imageBytes: imageBytes,
      opacity: opacity,
      doubleSided: doubleSided,
      belowLayerId: belowLayerId,
    );
  }

  /// Removes the wall-image layer [id]. Does nothing if it doesn't exist.
  Future<void> removeWallImage(String id) async {
    if (kIsWeb) return;
    await _wallImageChannel.invokeMethod<void>('wallImage#remove', {'id': id});
  }
}
