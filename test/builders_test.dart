import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  group('the list widget that P5 is about', () {
    // Pull request #5: the known issues in a `Column`, inside the `Column` of
    // a `SingleChildScrollView`.
    const String code = '''
SingleChildScrollView(
  child: Column(
    children: <Widget>[
      MarkdownBody(data: release.notes),
      if (release.knownIssues.isNotEmpty)
        Column(
          children: release.knownIssues.map(Text.new).toList(),
        ),
    ],
  ),
)
''';

    test('is the list built with the .map, not a widget around it', () {
      expect(listPlace(code, 1), 6);
      expect(listPlace(code, 2), 6);
    });

    test('keeps a remark that is already on that list', () {
      expect(listPlace(code, 6), isNull);
      expect(listPlace(code, 7), isNull);
    });

    test('finds the lines in no list widget', () {
      // bloc #4566: a `for` in the children of a `Stack`.
      const String stack = '''
SizedBox(
  child: Stack(
    children: <Widget>[
      for (final Task task in tasks) Bar(task: task),
    ],
  ),
)
''';
      expect(inListWidget(stack, 4), isFalse);
      expect(inListWidget(code, 7), isTrue);
      expect(inListWidget(code, 1), isTrue);
    });

    test('keeps a remark on a list with no loop and no .map', () {
      // Challenge `limits/grid-children`: the `const` list of the `ListView`.
      const String grid = '''
Column(
  children: <Widget>[
    ListView(children: const <Widget>[Chip(label: Text('Stable'))]),
    GridView.count(
      crossAxisCount: 2,
      children: <Widget>[
        for (final Release release in releases) Text(release.version),
      ],
    ),
  ],
)
''';
      expect(listPlace(grid, 3), isNull);
      expect(listPlace(grid, 1), 4);
    });
  });

  test('finds the lines of a function given to a callback', () {
    // localsend #3591: the logs are joined when the button is tapped.
    const String code = r'''
IconButton(
  onPressed: logs.isEmpty
      ? null
      : () async {
          await Clipboard.setData(
            ClipboardData(text: logs.map((log) => log.text).join('\n')),
          );
        },
  icon: const Icon(Icons.copy),
),
Text(logs.map((log) => log.text).join(', ')),
TextField(onChanged: viewModel.search),
''';
    final Set<int> lines = callbackLines(code);

    expect(lines, containsAll(<int>[2, 6, 8]));
    expect(lines, isNot(contains(11)));
    expect(lines, isNot(contains(12)));
  });

  group('the lines with a condition or an action in a widget', () {
    test('are inside a widget or a State class only', () {
      const String code = r'''
String label(int count) => count == 1 ? 'one' : 'many';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (_count > 0) Text('$_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: Text(widget.title ?? 'Add'),
        ),
      ],
    );
  }
}
''';
      expect(widgetConditionLines(code), <int>{17, 19, 20});
    });

    test('leave out the comments, the strings and the nullable types', () {
      const String code = r'''
class Hint extends StatelessWidget {
  const Hint({this.text, super.key});

  // if (text == null) it shows nothing
  final String? text;

  @override
  Widget build(BuildContext context, [Widget? child]) =>
      Text('Is it new ? Yes');
}
''';
      expect(widgetConditionLines(code), isEmpty);
    });
  });
}
