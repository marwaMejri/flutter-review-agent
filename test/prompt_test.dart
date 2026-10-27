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
- **Level:** issue''';

    expect(ruleForModel(text), contains('- **Why:** because.'));
    expect(ruleForModel(text), isNot(contains('Source')));
    expect(ruleForModel(text), isNot(contains('on two lines')));
    expect(ruleForModel(text), isNot(contains('Level')));
    expect(ruleForModel(text), isNot(contains('Flag when')));
    expect(ruleForModel(text), isNot(contains('Check')));
    expect(ruleForModel(text), contains('  1. Is it so? If yes, flag.'));
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
