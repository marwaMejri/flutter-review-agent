import 'package:material_ui_packages_migration/core/data/releases.dart';

/// The release the user opened last.
class Selection {
  late Release _release;
  bool _hasRelease = false;

  void select(Release release) {
    _release = release;
    _hasRelease = true;
  }

  String get title => _hasRelease ? _release.version : 'No release';
}
