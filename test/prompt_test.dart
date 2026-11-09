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
        'None of their added lines has an `expect`',
      ),
    );
    expect(
      buildUserPrompt(
        rules: rules,
        files: files,
        testFiles: <String>['test/a_test.dart'],
        testExpects: 2,
      ),
      contains('test/a_test.dart (2 added lines with an `expect`).'),
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

  test('counts the added lines with an expect in the test files', () {
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

    expect(addedExpects(diff), 2);
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
