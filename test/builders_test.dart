import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

void main() {
  group('the widget of a builder that P9 is about', () {
    test('is the subtree under the widget that reads the animation', () {
      // Pull request #6.
      const String code = '''
return AnimatedBuilder(
  animation: _controller,
  builder: (BuildContext context, Widget? child) {
    return Opacity(
      opacity: _controller.value,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.primary),
        child: Text('NEW', style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  },
);
''';
      expect(builderPlaces(code), <BuilderPlace>[
        (first: 1, last: 12, line: 6),
      ]);
    });

    test('is none when every widget reads the value or is const', () {
      // Pull request #7: the value is read in a string interpolation.
      const String value = r'''
ValueListenableBuilder<int>(
  valueListenable: viewModel.matchCount,
  builder: (BuildContext context, int count, Widget? child) =>
      Text('$count matches'),
)
''';
      // Pull request #24: the child is already passed as `child`.
      const String child = '''
AnimatedBuilder(
  animation: _pulse,
  child: const Icon(Icons.star),
  builder: (BuildContext context, Widget? child) =>
      Opacity(opacity: _pulse.value, child: child),
)
''';
      // Pull request #21: the widgets of the builder are const.
      const String constant = '''
ValueListenableBuilder<UpdateChannel?>(
  valueListenable: viewModel.channel,
  builder: (BuildContext context, UpdateChannel? channel, Widget? child) =>
      channel == UpdateChannel.beta
      ? const Padding(padding: EdgeInsets.all(12), child: Text('Beta'))
      : const SizedBox.shrink(),
)
''';
      expect(builderPlaces(value).single.line, isNull);
      expect(builderPlaces(child).single.line, isNull);
      expect(builderPlaces(constant).single.line, isNull);
    });

    test('reads the end of the chain given to valueListenable', () {
      // Challenge `limits/value-builder`: `context` is not the value.
      const String code = r'''
ValueListenableBuilder<int>(
  valueListenable: context.read<ReleasesViewModel>().unread,
  builder: (BuildContext context, int count, Widget? child) => Row(
    children: <Widget>[
      Text(
        '$appName releases',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Badge(label: Text('$count')),
    ],
  ),
)
''';
      expect(builderPlaces(code).single.line, 5);
    });

    test('skips the calls that are not a child, and the child parameter', () {
      const String code = '''
AnimatedBuilder(
  animation: _c,
  child: const Icon(Icons.star),
  builder: (BuildContext context, Widget? child) => Container(
    decoration: BoxDecoration(color: Colors.red),
    width: _c.value,
    child: Row(children: <Widget>[child!, Text(widget.label)]),
  ),
)
''';
      expect(builderPlaces(code).single.line, 7);
    });

    test('reads the value parameter of a TweenAnimationBuilder', () {
      // Challenge `limits/tween-builder`.
      const String code = '''
TweenAnimationBuilder<double>(
  tween: Tween<double>(begin: 0, end: progress),
  duration: const Duration(milliseconds: 300),
  builder: (BuildContext context, double value, Widget? child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        LinearProgressIndicator(value: value),
      ],
    );
  },
)
''';
      expect(builderPlaces(code), <BuilderPlace>[
        (first: 1, last: 13, line: 8),
      ]);
    });
  });

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
