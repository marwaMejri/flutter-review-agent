import 'package:material_ui_packages_migration/core/data/releases.dart';

/// The releases, newest first. They are sorted the first time they are read.
class ReleaseIndex {
  late final List<Release> newestFirst = List<Release>.of(releases)
    ..sort((Release a, Release b) => b.id.compareTo(a.id));
}
