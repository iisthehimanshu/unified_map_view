enum RenderingTheme {
  regular,
  zoo;
  // Read from --dart-define
  static RenderingTheme get current {
    const env = String.fromEnvironment('THEME', defaultValue: 'regular');
    return RenderingTheme.values.firstWhere(
          (e) => e.name == env,
      orElse: () => RenderingTheme.regular,
    );
  }

  bool get isRegular => this == RenderingTheme.regular;
  bool get isZoo => this == RenderingTheme.zoo;
}