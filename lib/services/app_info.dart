import 'package:package_info_plus/package_info_plus.dart';

/// Runtime read of the version baked into THIS build (pubspec.yaml's
/// `version:` line, bumped by tool/bump_version.py via scripts/build_web.sh).
class AppInfo {
  AppInfo._();

  static PackageInfo? _cached;

  /// Call once at startup.
  static Future<void> init() async {
    _cached = await PackageInfo.fromPlatform();
  }

  /// "1.0.1" — the part before '+'.
  static String get version => _cached?.version ?? '?';

  /// "20260926" — the part after '+' (today's date at build time).
  static String get buildNumber => _cached?.buildNumber ?? '?';

  /// Stamped by scripts/build_web.sh through --dart-define=BUILD_TIME.
  static String get buildTime {
    const stamped = String.fromEnvironment('BUILD_TIME');
    return stamped.isEmpty ? 'not stamped (dev run)' : stamped;
  }
}
