import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final List<DiffFile> files = parseDiff(sampleDiff);
  final List<Rule> rules = <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')];

  test('sends a changed file whole, with its added and removed lines', () {
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      sources: <String, String>{
        'lib/a.dart':
            '${'// line\n' * 9}'
            '  final int x;\n  final int z;\n  final int w;\n'
            '  void run() {}\n}\n',
      },
    );

    expect(prompt, contains('## File: lib/a.dart (whole file)'));
    expect(prompt, contains('    1 | // line'));
    expect(prompt, contains('      |-  final int y;\n   11 |+  final int z;'));
    expect(prompt, contains('   14 | }'));
    expect(prompt, isNot(contains('@@')));
  });

  test('asks to check the conventions as one more rule', () {
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      conventions: '- Screens never use `Navigator.push`.',
    );

    expect(prompt, contains('# Project conventions'));
    expect(prompt, contains('For each convention below, in order'));
    expect(prompt, contains('- [C1] Screens never use `Navigator.push`.'));
    expect(
      prompt,
      contains('add one entry "CONVENTION" for each convention that the'),
    );
    expect(systemPrompt, contains('report two findings, each on its own line'));
    expect(
      systemPrompt,
      contains('write the answer of each step you went through, then the end'),
    );
  });

  test('sends the deleted files, to show where moved code comes from', () {
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      deletedFiles: parseDeletedFiles(sampleDiff),
    );

    expect(prompt, contains('## File: lib/old.dart (deleted)'));
    expect(prompt, contains('      |-void old() {}'));
    expect(systemPrompt, contains('Code that the pull request only moves'));
  });

  test('says which test files the pull request changes', () {
    expect(
      buildUserPrompt(rules: rules, files: files),
      contains('Test files changed by this pull request: none.'),
    );
    expect(
      buildUserPrompt(
        rules: rules,
        files: files,
        testFiles: <String>['test/a_test.dart'],
      ),
      contains(
        'Test files changed by this pull request: test/a_test.dart. '
        'None of their added lines has a check (`expect`, `verify`)',
      ),
    );
    expect(
      buildUserPrompt(
        rules: rules,
        files: files,
        testFiles: <String>['test/a_test.dart'],
        testExpects: <String>['`test/a_test.dart:3` `expect(a.value, 1);`'],
      ),
      contains(
        'Test files changed by this pull request: test/a_test.dart. Their '
        'added checks (`expect`, `verify`), which show what each test '
        'checks:\n'
        '- `test/a_test.dart:3` `expect(a.value, 1);`\n',
      ),
    );
  });

  test('asks for one check for each section of the conventions', () {
    const String conventions = '''
# Conventions

## Folders
- A feature never imports another feature.

## Navigation
- Screens never use `Navigator.push`.
''';
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      conventions: conventions,
    );

    expect(conventionSections(conventions), <String>['Folders', 'Navigation']);
    expect(
      prompt,
      contains('Go through the sections below, in order: Folders, Navigation.'),
    );
    expect(prompt, contains('add one entry "CONVENTION" for each section'));
    expect(prompt, isNot(contains('For each convention below')));
  });

  test('gives an ID to each convention, and keeps its whole text', () {
    const String conventions = '''
## Folders
- A feature never imports another feature. Code that two features need moves
  to `lib/core/`.
- `lib/features/<feature>/`: one feature, in three layers:
  - `data/`: `data_sources/`, `models/`, `repositories/`;

## Navigation
- Screens never use `Navigator.push`.
''';

    expect(
      conventionsWithIds(conventions),
      contains('- [C1] A feature never imports another feature.'),
    );
    expect(conventionsWithIds(conventions), contains('  - [C3] `data/`'));
    expect(numberedConventions(conventions), <String, String>{
      'C1':
          'A feature never imports another feature. Code that two features '
          'need moves to `lib/core/`.',
      'C2': '`lib/features/<feature>/`: one feature, in three layers:',
      'C3': '`data/`: `data_sources/`, `models/`, `repositories/`;',
      'C4': 'Screens never use `Navigator.push`.',
    });
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      conventions: conventions,
    );
    expect(prompt, contains('- [C4] Screens never use `Navigator.push`.'));
    expect(prompt, contains('"convention": "C7"}'));
  });

  test('gives the added expect statements of the test files', () {
    // Pull request #11 only changes `const` to `final` in its test.
    final List<DiffFile> diff = parseDiff('''
diff --git a/test/a_test.dart b/test/a_test.dart
--- a/test/a_test.dart
+++ b/test/a_test.dart
@@ -1,1 +1,3 @@
-  const A a = A();
+  final A a = A();
+    expect(a.value, 1);
+    await expectLater(a.load(), completes);
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,1 +1,2 @@
 class A {
+  // expect(x) in a comment of lib/ does not count.
''');

    expect(addedExpects(diff), <String>[
      '`test/a_test.dart:2` `expect(a.value, 1);`',
      '`test/a_test.dart:3` `await expectLater(a.load(), completes);`',
    ]);

    // Pull request #5: an expect written on several lines.
    final List<DiffFile> multiLine = parseDiff('''
diff --git a/test/b_test.dart b/test/b_test.dart
--- a/test/b_test.dart
+++ b/test/b_test.dart
@@ -1,1 +1,5 @@
   test('refuses a known issue that is not a text', () {
+    expect(
+      () => ReleaseModel.fromJson(<String, Object?>{'known_issues': 42}),
+      throwsFormatException,
+    );
''');
    // A blocTest, with the expect: and verify: arguments and a verify( of
    // mocktail.
    final List<DiffFile> bloc = parseDiff('''
diff --git a/test/c_test.dart b/test/c_test.dart
new file mode 100644
--- /dev/null
+++ b/test/c_test.dart
@@ -0,0 +1,10 @@
+  blocTest<CounterCubit, int>('adds one',
+    build: () => CounterCubit(repo),
+    act: (CounterCubit cubit) => cubit.add(),
+    expect: () => <int>[
+      1,
+    ],
+    verify: (_) {
+      verify(() => repo.save(1)).called(1);
+    },
+  );
''');
    expect(addedExpects(bloc), <String>[
      '`test/c_test.dart:4` `expect: () => <int>[1],`',
      '`test/c_test.dart:7` `verify: (_) {verify(() => repo.save(1)).called(1);},`',
      '`test/c_test.dart:8` `verify(() => repo.save(1)).called(1);`',
    ]);

    expect(addedExpects(multiLine), <String>[
      '`test/b_test.dart:2` `expect(() => ReleaseModel.fromJson('
          "<String, Object?>{'known_issues': 42}), throwsFormatException);`",
    ]);
  });

  group('the imports between features', () {
    // Pull request #30: a screen of `settings` imports two files of
    // `releases`, written with `package:` and with a relative path.
    final List<DiffFile> diff = parseDiff('''
diff --git a/lib/features/settings/presentation/views/settings_view.dart b/lib/features/settings/presentation/views/settings_view.dart
--- a/lib/features/settings/presentation/views/settings_view.dart
+++ b/lib/features/settings/presentation/views/settings_view.dart
@@ -1,2 +1,7 @@
 import 'package:flutter/widgets.dart';
+import 'package:app/features/releases/domain/entities/release.dart';
+import '../../../releases/domain/repositories/release_repository.dart';
+import 'package:other/features/a/b/c.dart';
+import 'package:app/core/theme.dart';
+import '../../domain/entities/app_settings.dart';
 import '../view_models/settings_view_model.dart';
''');

    test('gives the feature and the layer of each side', () {
      expect(importFacts(diff, 'app'), <String>[
        '`lib/features/settings/presentation/views/settings_view.dart:2` '
            '(settings, presentation) imports '
            '`lib/features/releases/domain/entities/release.dart` '
            '(releases, domain): another feature',
        '`lib/features/settings/presentation/views/settings_view.dart:3` '
            '(settings, presentation) imports '
            '`lib/features/releases/domain/repositories/release_repository.dart` '
            '(releases, domain): another feature',
        '`lib/features/settings/presentation/views/settings_view.dart:6` '
            '(settings, presentation) imports '
            '`lib/features/settings/domain/entities/app_settings.dart` '
            '(settings, domain): same feature',
      ]);
    });

    test('reads only the relative imports with no package name', () {
      expect(importFacts(diff, null), hasLength(2));
    });

    test('are in the conventions part of the prompt only', () {
      expect(
        buildUserPrompt(
          rules: rules,
          files: diff,
          conventions: '- A feature never imports another feature.',
          packageName: 'app',
        ),
        contains('(settings, presentation) imports'),
      );
      expect(
        buildUserPrompt(rules: rules, files: diff, packageName: 'app'),
        isNot(contains('Imports added by this pull request')),
      );
    });

    test('reads the features under lib/src/ too', () {
      final List<DiffFile> src = parseDiff('''
diff --git a/lib/src/features/a/ui/a_view.dart b/lib/src/features/a/ui/a_view.dart
--- a/lib/src/features/a/ui/a_view.dart
+++ b/lib/src/features/a/ui/a_view.dart
@@ -1,1 +1,2 @@
 import 'package:flutter/widgets.dart';
+import 'package:app/src/features/b/data/b_repository.dart';
''');
      expect(importFacts(src, 'app'), <String>[
        '`lib/src/features/a/ui/a_view.dart:2` (a, ui) imports '
            '`lib/src/features/b/data/b_repository.dart` (b, data): '
            'another feature',
      ]);
    });

    test('reads the package name in the pubspec', () {
      expect(packageNameOf('name: app\nversion: 1.0.0\n'), 'app');
      expect(packageNameOf(null), isNull);
    });
  });

  group('the added lines inside a router call', () {
    // Pull request #14 adds a `name:` to each `GoRoute`. The parentheses in
    // the comment and in the string do not count.
    const String router = '''
final GoRouter router = GoRouter(
  // ) in a comment
  routes: <RouteBase>[
    GoRoute(path: ')', name: 'a'),
    GoRoute(
      path: '/b',
      builder: (BuildContext context, GoRouterState state) =>
          const ChangeNotifierProvider<int>(),
    ),
  ],
);
''';
    final List<DiffFile> diff = parseDiff('''
diff --git a/lib/app/router.dart b/lib/app/router.dart
--- a/lib/app/router.dart
+++ b/lib/app/router.dart
@@ -3,2 +3,4 @@
   routes: <RouteBase>[
+    GoRoute(path: ')', name: 'a'),
     GoRoute(
+      path: '/b',
''');

    test('gives the innermost router call of each added line', () {
      expect(
        routerLinesOf(diff, <String, String>{'lib/app/router.dart': router}),
        <String, Map<int, String>>{
          'lib/app/router.dart': <int, String>{4: 'routes:', 6: 'GoRoute('},
        },
      );
    });

    test('leaves out the tests and the files with no source', () {
      final List<DiffFile> test = parseDiff('''
diff --git a/test/a_test.dart b/test/a_test.dart
--- a/test/a_test.dart
+++ b/test/a_test.dart
@@ -1,1 +1,2 @@
 Widget app = MaterialApp(
+  home: const A(),
''');
      expect(
        routerLinesOf(test, <String, String>{
          'test/a_test.dart':
              'Widget app = MaterialApp(\n  home: const A(),\n);\n',
        }),
        isEmpty,
      );
      expect(routerLinesOf(diff, const <String, String>{}), isEmpty);
    });

    test('are a fact of the prompt, even with the changed parts only', () {
      final String prompt = buildUserPrompt(
        rules: rules,
        files: diff,
        routerLines: routerLinesOf(diff, <String, String>{
          'lib/app/router.dart': router,
        }),
      );
      expect(prompt, contains('(changed parts only)'));
      expect(
        prompt,
        contains(
          '`routes:` list: `lib/app/router.dart:4` (`routes:`), '
          '`lib/app/router.dart:6` (`GoRoute(`).',
        ),
      );
      expect(
        buildUserPrompt(rules: rules, files: diff),
        isNot(contains('inside a `GoRouter(`')),
      );
    });
  });

  test('sees a changed computation, not a changed constant', () {
    final List<DiffFile> changed = parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +1,2 @@
-int total(int a, int b) => a + b;
+int total(int a, int b) => a * b;
-const int limit = 5;
+const int limit = 6;
''');
    final List<DiffFile> constant = parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,1 +1,1 @@
-const int limit = 5;
+const int limit = 6;
''');

    expect(changesComputation(changed.single), isTrue);
    expect(changesComputation(constant.single), isFalse);
  });

  test('finds the method whose body holds a line', () {
    const String code = '''
class _ViewState extends State<View> {
  Future<void> load() async {
    if (ready) {
      sort();
    }
  }

  List<int> get sorted => items.toList()..sort();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[for (final int item in sorted) Text('\$item')],
    );
  }
}
''';
    final Map<int, List<String>> open = openCalls(code);

    expect(methodAt(open, 4), 'load');
    expect(methodAt(open, 8), isNull);
    expect(methodAt(open, 13), 'build');
    // The lines that open the bodies of load() and build().
    expect(methodAt(open, 2), 'load');
    expect(methodAt(open, 11), 'build');
  });

  test('gives the added exports of the SDK Material or Cupertino', () {
    // Challenge `limits/cupertino-export`.
    final List<DiffFile> export = parseDiff('''
diff --git a/lib/core/cupertino.dart b/lib/core/cupertino.dart
new file mode 100644
--- /dev/null
+++ b/lib/core/cupertino.dart
@@ -0,0 +1,4 @@
+/// The Cupertino widgets, for the pages that follow iOS.
+library;
+
+export 'package:flutter/cupertino.dart';
''');

    expect(
      buildUserPrompt(rules: rules, files: export),
      contains(
        'Added lines that export `package:flutter/material.dart` or '
        '`package:flutter/cupertino.dart`: `lib/core/cupertino.dart:4`.',
      ),
    );
    expect(
      buildUserPrompt(rules: rules, files: files),
      isNot(contains('Added lines that export')),
    );
  });

  group('the conditions of a widget that no test renders', () {
    // Pull request #5: a new `if` on a screen, and a test of the parsing
    // only.
    const String widget = '''
class Issues extends StatelessWidget {
  const Issues({required this.issues, super.key});

  final List<String> issues;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      if (issues.isNotEmpty) const Text('Known issues'),
    ],
  );
}
''';
    String diffOf(String test) =>
        '''
diff --git a/lib/issues.dart b/lib/issues.dart
new file mode 100644
--- /dev/null
+++ b/lib/issues.dart
@@ -0,0 +1,12 @@
${widget.trimRight().split('\n').map((String line) => '+$line').join('\n')}
diff --git a/test/a_test.dart b/test/a_test.dart
new file mode 100644
--- /dev/null
+++ b/test/a_test.dart
@@ -0,0 +1,3 @@
$test
''';
    const Map<String, String> sources = <String, String>{
      'lib/issues.dart': widget,
    };

    test('are given when no added test line renders a widget', () {
      final List<DiffFile> unit = parseDiff(
        diffOf("+test('reads', () {\n+  expect(read(), 1);\n+});"),
      );

      expect(untestedWidgetLines(unit, sources), <String>[
        '`lib/issues.dart:9`',
      ]);
      expect(
        buildUserPrompt(rules: rules, files: unit, sources: sources),
        contains(
          'Added lines under `lib/` with a condition or an action inside a '
          'widget or a `State` class: `lib/issues.dart:9`. No added test '
          'line renders a widget (`testWidgets`, `tester.`, `find.`): no '
          'test of this pull request checks them.',
        ),
      );
    });

    test('are not given when an added test line renders a widget', () {
      final List<DiffFile> rendered = parseDiff(
        diffOf(
          "+testWidgets('shows', (WidgetTester tester) async {\n"
          "+  expect(find.text('Known issues'), findsOneWidget);\n"
          '+});',
        ),
      );

      expect(untestedWidgetLines(rendered, sources), isEmpty);
      expect(
        buildUserPrompt(rules: rules, files: rendered, sources: sources),
        isNot(contains('with a condition or an action')),
      );
    });

    test('leave out a line moved from another file', () {
      final List<DiffFile> unit = parseDiff(
        diffOf("+test('reads', () {\n+  expect(read(), 1);\n+});"),
      );
      final List<DiffFile> deleted = parseDeletedFiles('''
diff --git a/lib/old.dart b/lib/old.dart
deleted file mode 100644
--- a/lib/old.dart
+++ /dev/null
@@ -1,1 +0,0 @@
-      if (issues.isNotEmpty) const Text('Known issues'),
''');

      expect(
        untestedWidgetLines(unit, sources, deletedFiles: deleted),
        isEmpty,
      );
    });
  });

  test('sends only the changed parts when the file is unknown', () {
    final String prompt = buildUserPrompt(rules: rules, files: files);

    expect(prompt, contains('## File: lib/a.dart (changed parts only)'));
    expect(prompt, contains('   11 |+  final int z;'));
  });

  test('leaves out the fields the model does not need', () {
    const String text = '''
## X1. Title

- **Check:** something.
- **Flag when:** a case
  on two lines.
- **Do not flag when:** another case.
- **Decide:** answer these questions in order.
  1. Is it so? If yes, flag.
- **Why:** because.
- **Source:** a link that goes on
  on two lines
- **Level:** issue
- **Remarks:** one per pull request
- **Remark line:** contains `>?`
- **Not on a line of:** B2''';

    expect(ruleForModel(text), contains('- **Why:** because.'));
    expect(ruleForModel(text), isNot(contains('Source')));
    expect(ruleForModel(text), isNot(contains('on two lines')));
    expect(ruleForModel(text), isNot(contains('Level')));
    expect(ruleForModel(text), isNot(contains('Remarks')));
    expect(ruleForModel(text), isNot(contains('Remark line')));
    expect(ruleForModel(text), isNot(contains('Not on a line of')));
    expect(ruleForModel(text), isNot(contains('Flag when')));
    expect(ruleForModel(text), isNot(contains('Check')));
    expect(ruleForModel(text), contains('  1. Is it so? If yes, flag.'));
  });

  test('points at the added lines next to a trigger around:', () {
    // Pull request #14: `name:` is added under a `GoRoute(` it does not
    // change.
    final List<DiffFile> router = parseDiff('''
diff --git a/lib/app/router.dart b/lib/app/router.dart
--- a/lib/app/router.dart
+++ b/lib/app/router.dart
@@ -40,2 +40,3 @@
           GoRoute(
             path: 'settings',
+            name: 'settings',
''');
    final Rule rule = Rule(
      id: 'T5',
      title: 't',
      text: 't',
      triggers: <String>['around:GoRoute'],
    );

    expect(triggerPlaces(rule, router), <String>['lib/app/router.dart:42']);
  });

  test('points at the added lines that contain a trigger of the rule', () {
    final Rule rule = Rule(
      id: 'X1',
      title: 't',
      text: 't',
      triggers: <String>['int w', 'file:lib/'],
    );

    expect(triggerPlaces(rule, files), <String>['lib/a.dart:12']);
    expect(
      buildUserPrompt(rules: <Rule>[rule], files: files),
      contains('Look first at:** lib/a.dart:12'),
    );
  });
}
