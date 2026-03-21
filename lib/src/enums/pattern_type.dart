enum PatternType {
  dots,
  stripes,
  grid,
  hatch,
  bush,
  trees,
  water,
  sand,
  rocks,
  parking,
  restricted;
}

PatternType? getPatternType(String? patternName) {
  switch (patternName) {
    case 'dots':
      return PatternType.dots;
    case 'stripes':
      return PatternType.stripes;
    case 'grid':
      return PatternType.grid;
    case 'hatch':
      return PatternType.hatch;
    case 'bush':
      return PatternType.bush;
    case 'trees':
      return PatternType.trees;
    case 'water':
      return PatternType.water;
    case 'sand':
      return PatternType.sand;
    case 'rocks':
      return PatternType.rocks;
    case 'parking':
      return PatternType.parking;
    case 'restricted':
      return PatternType.restricted;
    default:
      return null;
  }}