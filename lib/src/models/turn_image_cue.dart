enum TurnDirection {
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
}

class TurnImageCue {
  final TurnDirection direction;
  final String imagePath;
  final double distanceToTurnMeters;

  const TurnImageCue({
    required this.direction,
    required this.imagePath,
    required this.distanceToTurnMeters,
  });
}
