import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Web-only load-phase tracing.
///
/// There was previously no way to tell which part of startup was slow: the only
/// `Stopwatch` in the package measured internet speed, and every other signal
/// was an unconditional `print` of state with no duration attached. Measuring
/// showed all network finishing in ~2s while the main thread stayed pinned for
/// tens of seconds afterwards, so the interesting numbers are all CPU phases —
/// which is what this records.
///
/// Gated on [kIsWeb] so native behaviour is bit-for-bit unchanged, and gated
/// again on [enabled] so it can be switched off without unpicking call sites.
/// `print` is NOT stripped from Flutter web release builds, so leaving this on
/// in production would itself cost something.
class PerfTrace {
  /// On web `Stopwatch` is backed by `performance.now()`, so this is monotonic
  /// and unaffected by clock changes. Starts at first touch of the class, which
  /// in practice is the first `mark` during initialize.
  static final Stopwatch _sw = Stopwatch()..start();

  static final List<_Mark> _marks = <_Mark>[];

  /// On in debug and profile, off in release.
  ///
  /// `print` is NOT stripped from Flutter web release builds, so leaving this
  /// on would put a per-phase log in production — the same cost that was just
  /// removed from the hot paths. Profile builds keep it, since that is what the
  /// device measurements are taken on.
  ///
  /// Set `PerfTrace.enabled = true` early in main() to trace a release build,
  /// or build with `--dart-define=PERF_TRACE=true`. The dart-define matters
  /// because the load-time problem only reproduces at realistic speed in a
  /// RELEASE build — a debug build's 2287-module bootstrap swamps everything
  /// being measured — so without it there is no phase breakdown to look at.
  static bool enabled = kIsWeb &&
      (!kReleaseMode || const bool.fromEnvironment('PERF_TRACE'));

  static void mark(String label) {
    if (!enabled) return;
    final int ms = _sw.elapsedMilliseconds;
    _marks.add(_Mark(label, ms));
    // ignore: avoid_print
    print('[perf] +${ms}ms  $label');
  }

  /// Times an async phase and records how long it took, not just when it ended.
  static Future<T> timeAsync<T>(String label, Future<T> Function() body) async {
    if (!enabled) return body();
    final int start = _sw.elapsedMilliseconds;
    try {
      return await body();
    } finally {
      final int end = _sw.elapsedMilliseconds;
      _marks.add(_Mark(label, end, durationMs: end - start));
      // ignore: avoid_print
      print('[perf] +${end}ms  $label  (took ${end - start}ms)');
    }
  }

  /// Times a synchronous phase. Worth using on the parse/serialise paths, since
  /// those are the ones that block the browser from painting at all.
  static T time<T>(String label, T Function() body) {
    if (!enabled) return body();
    final int start = _sw.elapsedMilliseconds;
    try {
      return body();
    } finally {
      final int end = _sw.elapsedMilliseconds;
      _marks.add(_Mark(label, end, durationMs: end - start));
      // ignore: avoid_print
      print('[perf] +${end}ms  $label  (took ${end - start}ms)');
    }
  }

  /// One-shot summary, sorted slowest-first. Call from the console via a hook,
  /// or after first paint, to see where the time actually went.
  static String report() {
    if (_marks.isEmpty) return '[perf] no marks recorded';
    final timed = _marks.where((m) => m.durationMs != null).toList()
      ..sort((a, b) => b.durationMs!.compareTo(a.durationMs!));
    final buf = StringBuffer('[perf] timeline (${_marks.length} marks)\n');
    for (final m in _marks) {
      buf.writeln('  +${m.atMs}ms  ${m.label}'
          '${m.durationMs != null ? '  (${m.durationMs}ms)' : ''}');
    }
    buf.writeln('[perf] slowest phases:');
    for (final m in timed.take(10)) {
      buf.writeln('  ${m.durationMs}ms  ${m.label}');
    }
    return buf.toString();
  }

  static void reset() {
    _marks.clear();
    _sw
      ..reset()
      ..start();
  }
}

class _Mark {
  final String label;
  final int atMs;
  final int? durationMs;

  _Mark(this.label, this.atMs, {this.durationMs});
}
