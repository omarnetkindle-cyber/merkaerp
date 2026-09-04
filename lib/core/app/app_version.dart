/// Single source of truth for the desktop/API version exposed at runtime.
/// Keep this value aligned with `pubspec.yaml`.
class AppVersion {
  const AppVersion._();

  static const String version = '1.3.0';
  static const int build = 8;
  static const String display = '$version+$build';
}
