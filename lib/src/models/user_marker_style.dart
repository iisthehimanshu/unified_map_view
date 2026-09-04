import 'dart:ui';

/// Runtime appearance override for the user-location puck.
///
/// The map ships a default puck ([LandmarkAssetType.user]); a host that needs a
/// visually distinct one — e.g. to mark a simulated or replayed position as not
/// a real fix — hands one of these to
/// [UnifiedMapController.setUserMarkerStyle]. Passing null there restores the
/// default.
///
/// Every field is optional and falls back to the default when null, so a caller
/// can change only the artwork and keep the stock size and rotation behaviour.
class UserMarkerStyle {
  /// Asset key for the puck image, resolved against the app's root bundle.
  /// An asset shipped by another package is addressed as
  /// `packages/<package_name>/<path>`.
  final String? assetPath;

  /// Rendered size in logical pixels. Defaults to 35x35.
  final Size? imageSize;

  /// Whether the puck rotates to the device heading. Defaults to true.
  ///
  /// Leave this alone unless the replacement artwork is directional. A
  /// rotationally symmetric image gains nothing from disabling it, and the
  /// compass update path only writes the `bearing` feature property while this
  /// is true — turning it off makes the compass tick and the source rebuild
  /// disagree about which properties a feature carries.
  final bool? compassBasedRotation;

  const UserMarkerStyle({
    this.assetPath,
    this.imageSize,
    this.compassBasedRotation,
  });

  @override
  String toString() => 'UserMarkerStyle(assetPath: $assetPath, '
      'imageSize: $imageSize, compassBasedRotation: $compassBasedRotation)';
}