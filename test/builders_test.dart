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
  });
}
