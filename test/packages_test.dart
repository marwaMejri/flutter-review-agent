import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  test('finds the package of a path at the top of the repository', () {
    expect(packageRoot('lib/a.dart'), '');
    expect(packageRoot('test/a_test.dart'), '');
    expect(packageRoot('integration_test/app_test.dart'), '');
    expect(packageRoot('pubspec.yaml'), '');
    expect(packageRoot('lib/src/test/a.dart'), '');
    expect(inPackage('lib/a.dart'), 'lib/a.dart');
  });

  test('finds the package of a path in a monorepo', () {
    expect(packageRoot('packages/core/lib/a.dart'), 'packages/core/');
    expect(packageRoot('packages/core/test/a_test.dart'), 'packages/core/');
    expect(packageRoot('packages/core/pubspec.yaml'), 'packages/core/');
    expect(packageRoot('apps/mobile/lib/main.dart'), 'apps/mobile/');
    expect(inPackage('packages/core/lib/src/a.dart'), 'lib/src/a.dart');
  });

  test('gives no package to a file outside one', () {
    expect(packageRoot('README.md'), '');
    expect(packageRoot('tool/run.dart'), '');
    expect(inPackage('tool/run.dart'), 'tool/run.dart');
  });
}
