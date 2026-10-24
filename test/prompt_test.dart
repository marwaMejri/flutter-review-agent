import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  final List<DiffFile> files = parseDiff(sampleDiff);
  final List<Rule> rules = <Rule>[Rule(id: 'P1', title: 't', text: '## P1. t')];

  test('adds the full changed files with line numbers', () {
    final String prompt = buildUserPrompt(
      rules: rules,
      files: files,
      sources: <String, String>{'lib/a.dart': 'class A {\n  final int x;\n}'},
    );

    expect(prompt, contains('# Full files'));
    expect(prompt, contains('    2 |   final int x;'));
    expect(prompt.indexOf('# Full files'), lessThan(prompt.indexOf('# Diff')));
  });

  test('does not send a file twice when the diff shows all of it', () {
    final List<DiffFile> newFile = parseDiff('''
diff --git a/lib/b.dart b/lib/b.dart
new file mode 100644
--- /dev/null
+++ b/lib/b.dart
@@ -0,0 +1,2 @@
+class B {}
+
''');

    expect(diffShowsWholeFile(newFile.single, 'class B {}\n\n'), isTrue);
    expect(diffShowsWholeFile(files.single, 'a\n' * 20), isFalse);
  });

  test('leaves the source and the level of a rule out', () {
    const String text = '''
## X1. Title

- **Why:** because.
- **Source:** a link that goes on
  on two lines
- **Level:** issue''';

    expect(ruleForModel(text), contains('- **Why:** because.'));
    expect(ruleForModel(text), isNot(contains('Source')));
    expect(ruleForModel(text), isNot(contains('on two lines')));
    expect(ruleForModel(text), isNot(contains('Level')));
  });
}
