/// The folders that only a package holds at its top: in a monorepo, the
/// package of `packages/core/lib/a.dart` is `packages/core/`.
const Set<String> _packageFolders = <String>{'lib', 'test', 'integration_test'};

/// The folder of the package of [path], with its last `/`, or an empty text
/// for the top of the repository: `packages/core/` for
/// `packages/core/lib/a.dart` and for `packages/core/pubspec.yaml`, and an
/// empty text for `lib/a.dart`. A package is the folder that holds `lib/`,
/// `test/`, `integration_test/` or `pubspec.yaml`, as Dart packages do.
String packageRoot(String path) {
  final List<String> parts = path.split('/');
  for (int i = 0; i < parts.length; i++) {
    final bool isLast = i == parts.length - 1;
    if (isLast
        ? parts[i] == 'pubspec.yaml'
        : _packageFolders.contains(parts[i])) {
      return parts.take(i).map((String part) => '$part/').join();
    }
  }
  return '';
}

/// The path of [path] inside its package (see [packageRoot]): `lib/a.dart`
/// for `packages/core/lib/a.dart`.
String inPackage(String path) => path.substring(packageRoot(path).length);
