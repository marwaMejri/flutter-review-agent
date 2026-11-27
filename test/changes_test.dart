import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  group('readDartFile', () {
    test('reads the classes, their role and their members', () {
      final DartFile file = readDartFile('''
/// A page.
class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  final ScrollController _controller = ScrollController();

  @override
  Widget build(BuildContext context) => const Text('a');
}
''');

      expect(file.error, isNull);
      expect(
        <String>[
          for (final DartDeclaration d in file.declarations)
            '${d.kind} ${d.fullName} ${d.startLine}-${d.endLine} ${d.role}',
        ],
        <String>[
          'class Page 2-7 widget',
          'constructor Page 3-3 null',
          'method Page.createState 6-6 null',
          'class _PageState 9-14 state',
          'field _PageState._controller 10-10 null',
          'method _PageState.build 13-13 null',
        ],
      );
      final DartDeclaration field = file.declarations[4];
      expect(field.type, 'ScrollController');
      expect(field.initializer, 'ScrollController()');
    });

    test('reads every kind of declaration, with its members', () {
      final DartFile file = readDartFile('''
enum Status {
  a,
  b;

  bool get isA => this == a;
}

extension Words on String {
  int get count => split(' ').length;
}

extension on int {
  int get twice => this * 2;
}

extension type Id(int value) {
  int get next => value + 1;
}

typedef Json = Map<String, Object?>;

class Tile = Base with Shape;

mixin Shape {
  void draw() {}
}
''');

      expect(file.error, isNull);
      expect(
        <String>[
          for (final DartDeclaration d in file.declarations)
            '${d.kind} ${d.fullName} ${d.startLine}-${d.endLine}',
        ],
        <String>[
          'enum Status 1-6',
          'getter Status.isA 5-5',
          'extension Words 8-10',
          'getter Words.count 9-9',
          'extension on int 12-14',
          'getter (extension on int).twice 13-13',
          'extension type Id 16-18',
          'getter Id.next 17-17',
          'typedef Json 20-20',
          'class Tile 22-22',
          'mixin Shape 24-26',
          'method Shape.draw 25-25',
        ],
      );
      // Every line with code is in a declaration.
      expect(
        file.outsideDeclarations(<int>[for (int i = 1; i <= 26; i++) i]),
        isEmpty,
      );
    });

    test('gives the added lines with code outside a declaration', () {
      final DartFile file = DartFile(
        declarations: const <DartDeclaration>[],
        directives: const <String>[],
        codeLines: <int>{1, 2, 3, 5},
        declaredLines: <int>{1, 2},
      );

      // Line 4 has no code, line 6 is not added.
      expect(file.outsideDeclarations(<int>[2, 3, 4, 5]), <int>[3, 5]);
    });

    test('gives the line of a syntax error, and no declaration', () {
      final DartFile file = readDartFile('class Page {\n  void a( {\n}\n');

      expect(file.error, startsWith('line '));
      expect(file.declarations, isEmpty);
    });
  });

  group('codeChanges', () {
    // Pull request #2: a filter added in build().
    const String filterDiff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -3,3 +3,5 @@ class _Body extends StatelessWidget {
   Widget build(BuildContext context) {
-    final List<int> items = model.items;
+    final List<int> items = model.items
+        .where((int item) => item > 2)
+        .toList();
     return Text(items.join());
''';
    const String filterAfter = '''
class _Body extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final List<int> items = model.items
        .where((int item) => item > 2)
        .toList();
    return Text(items.join());
  }
}
''';

    test('rebuilds the version before the pull request', () {
      expect(oldSource(filterAfter, parseDiff(filterDiff).single), '''
class _Body extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final List<int> items = model.items;
    return Text(items.join());
  }
}
''');
    });

    test('rebuilds it from the diff, not from the re-indented lines', () {
      // The added `  );` is taken as the removed `  );` re-indented, which
      // is in another place: the version before must not move it there.
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,6 +1,6 @@
 f() {
-  a(
-    1,
-  );
-  b(2);
+  a(1);
+  c(
+    b(2),
+  );
 }
''';
      final DiffFile file = parseDiff(diff).single;

      expect(file.addedLines, isNot(contains(5)));
      expect(
        oldSource('f() {\n  a(1);\n  c(\n    b(2),\n  );\n}\n', file),
        'f() {\n  a(\n    1,\n  );\n  b(2);\n}\n',
      );
    });

    test('finds a changed method, with its added lines', () {
      final ChangeReport report = codeChanges(
        files: parseDiff(filterDiff),
        sources: <String, String>{'lib/a.dart': filterAfter},
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  method _Body.build, lines 3-8, added lines 4-6',
      ]);
    });

    test('finds a widget made stateful, with a new field', () {
      // Pull request #8: a ScrollController in a new State.
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,6 +1,13 @@
-class Page extends StatelessWidget {
+class Page extends StatefulWidget {
   const Page({super.key});
 
+  @override
+  State<Page> createState() => _PageState();
+}
+
+class _PageState extends State<Page> {
+  final ScrollController _controller = ScrollController();
+
   @override
   Widget build(BuildContext context) => const Text('a');
 }
''';
      const String after = '''
class Page extends StatefulWidget {
  const Page({super.key});

  @override
  State<Page> createState() => _PageState();
}

class _PageState extends State<Page> {
  final ScrollController _controller = ScrollController();

  @override
  Widget build(BuildContext context) => const Text('a');
}
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{'lib/a.dart': after},
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  class Page extends StatefulWidget, lines 1-6, which '
            'extended StatelessWidget',
        '  added    method Page.createState, line 5',
        '  added    class _PageState extends State<Page>, lines 8-13',
        '  added    field _PageState._controller: ScrollController = '
            'ScrollController(), line 9',
        '  moved    method _PageState.build, line 12, from Page.build',
      ]);
    });

    test('finds a class moved from a deleted file', () {
      // Pull request #28: ReleaseTile moved next to the list that uses it.
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,1 +1,5 @@
 class Page {}
+
+class Tile {
+  int get size => 1;
+}
diff --git a/lib/b.dart b/lib/b.dart
deleted file mode 100644
--- a/lib/b.dart
+++ /dev/null
@@ -1,5 +0,0 @@
-import 'package:app/x.dart';
-
-class Tile {
-  int get size => 1;
-}
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart':
              'class Page {}\n\nclass Tile {\n  int get size => 1;\n}\n',
        },
        deletedFiles: parseDeletedFiles(diff),
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  moved    class Tile, lines 3-5, from lib/b.dart',
        'lib/b.dart',
        '  deleted  file',
      ]);
    });

    test('lists the added and removed imports', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,3 @@
-import 'package:app/old.dart';
+import 'package:app/new.dart';
 
 class Page {}
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart': "import 'package:app/new.dart';\n\nclass Page {}\n",
        },
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        "  added    import 'package:app/new.dart';",
        "  removed  import 'package:app/old.dart';",
      ]);
    });

    test('cuts a long value and leaves out library;', () {
      final String values =
          '<int>[${<int>[for (int i = 1; i <= 40; i++) i].join(', ')}]';
      final String diff = '''
diff --git a/lib/c.dart b/lib/c.dart
new file mode 100644
--- /dev/null
+++ b/lib/c.dart
@@ -0,0 +1,3 @@
+library;
+
+const List<int> values = $values;
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/c.dart': 'library;\n\nconst List<int> values = $values;\n',
        },
      );

      expect(describeChanges(report), <String>[
        'lib/c.dart',
        '  added    variable values: List<int> = '
            '${values.substring(0, 77)}..., line 3',
      ]);
    });

    test('finds a value added to an enum', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,4 +1,5 @@
 enum Status {
   a,
   b,
+  c,
 }
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart': 'enum Status {\n  a,\n  b,\n  c,\n}\n',
        },
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  enum Status, lines 1-5, added line 4',
      ]);
    });

    test('finds a changed member of an extension with no name', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,3 @@
 extension on int {
-  int get twice => this * 2;
+  int get twice => this * 3;
 }
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart': 'extension on int {\n  int get twice => this * 3;\n}\n',
        },
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  getter (extension on int).twice, line 2, added line 2',
      ]);
    });

    test('gives the added lines of the header of a type, not its body', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,4 +1,4 @@
-class Page implements A {
+class Page implements A, B {
   void show() {
-    print(1);
+    print(2);
   }
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart':
              'class Page implements A, B {\n'
              '  void show() {\n    print(2);\n  }\n}\n',
        },
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  class Page, lines 1-5, added line 1',
        '  changed  method Page.show, lines 2-4, added line 3',
      ]);
    });

    test('compares the header of a class, not its text up to a brace', () {
      // The `{` of a record type is not the start of the body.
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,3 +1,3 @@
-class Page extends Base<({int a})> {
+class Page extends Base<({int a, int b})> {
   void show() {}
 }
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{
          'lib/a.dart':
              'class Page extends Base<({int a, int b})> {\n'
              '  void show() {}\n}\n',
        },
      );

      expect(describeChanges(report), <String>[
        'lib/a.dart',
        '  changed  class Page extends Base<({int a, int b})>, lines 1-3, '
            'which extended Base<({int a})>',
      ]);
    });

    test('names a file that cannot be read, and keeps the others', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,1 +1,2 @@
 class Page {
+  void a( {
''';

      final ChangeReport report = codeChanges(
        files: parseDiff(diff),
        sources: <String, String>{'lib/a.dart': 'class Page {\n  void a( {\n'},
      );

      expect(report.changes, isEmpty);
      expect(report.unread['lib/a.dart'], startsWith('line '));
    });
  });
}
