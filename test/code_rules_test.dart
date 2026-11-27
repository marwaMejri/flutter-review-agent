import 'package:flutter_review/flutter_review.dart';
import 'package:test/test.dart';

/// The widgets of [code] that P9 is about, as `line widget`.
List<String> staticWidgets(String code) => <String>[
  for (final StaticWidget w in staticBuilderWidgets(code).widgets)
    '${w.line} ${w.widget}',
];

void main() {
  group('the widget of a builder that reads nothing that changes', () {
    test('is under the widget that reads the animation', () {
      // Pull request #6.
      const String code = '''
class _NewBadgeState extends State<NewBadge> {
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
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
  }
}
''';
      expect(staticWidgets(code), <String>['9 DecoratedBox']);
    });

    test('is none when every widget reads the value or is const', () {
      // Pull request #7: the value is read in a string interpolation.
      const String value = r'''
class A {
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: viewModel.matchCount,
    builder: (BuildContext context, int count, Widget? child) =>
        Text('$count matches'),
  );
}
''';
      // Pull request #24: the child is already given as `child`.
      const String child = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulse,
    child: const Icon(Icons.star),
    builder: (BuildContext context, Widget? child) =>
        Opacity(opacity: _pulse.value, child: child),
  );
}
''';
      // Pull request #21: the widgets of the builder are const.
      const String constant = '''
class A {
  Widget build(BuildContext context) => ValueListenableBuilder<UpdateChannel?>(
    valueListenable: viewModel.channel,
    builder: (BuildContext context, UpdateChannel? channel, Widget? child) =>
        channel == UpdateChannel.beta
        ? const Padding(padding: EdgeInsets.all(12), child: Text('Beta'))
        : const SizedBox.shrink(),
  );
}
''';
      expect(staticWidgets(value), isEmpty);
      expect(staticWidgets(child), isEmpty);
      expect(staticWidgets(constant), isEmpty);
    });

    test('takes the whole expression given to valueListenable', () {
      // Pull request #44: `context` is not what the builder listens to.
      const String code = r'''
class A {
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
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
  );
}
''';
      expect(staticWidgets(code), <String>['6 Text']);
    });

    test('skips the arguments that are not a child, and the child', () {
      const String code = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: const Icon(Icons.star),
    builder: (BuildContext context, Widget? child) => Container(
      decoration: BoxDecoration(color: Colors.red),
      width: _c.value,
      child: Row(children: <Widget>[child!, Text(widget.label)]),
    ),
  );
}
''';
      expect(staticWidgets(code), <String>['8 Text']);
    });

    test('reads the value parameter of a TweenAnimationBuilder', () {
      // Pull request #45.
      const String code = '''
class A {
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      builder: (BuildContext context, double value, Widget? child) {
        return Column(
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            LinearProgressIndicator(value: value),
          ],
        );
      },
    );
  }
}
''';
      expect(staticWidgets(code), <String>['9 Text']);
    });

    test('counts a variable of the builder computed from the value', () {
      // ente #14946: `wordmark` comes from `scroll`.
      const String code = '''
class A {
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: _scroll,
    builder: (context, scroll, _) {
      final wordmark = reel.pageAt(scroll).wordmark;
      return Stack(
        children: [
          Pages(scroll: scroll),
          if (wordmark != null) Positioned(child: Mark(color: wordmark)),
        ],
      );
    },
  );
}
''';
      expect(staticWidgets(code), isEmpty);
    });

    test('takes the expression of a variable given to animation', () {
      const String code = '''
class A {
  Widget build(BuildContext context) {
    final Animation<double> a = widget.controller;
    return AnimatedBuilder(
      animation: a,
      builder: (BuildContext context, Widget? child) => Column(
        children: <Widget>[
          Text('\${widget.controller.value}'),
          Text(widget.label),
        ],
      ),
    );
  }
}
''';
      expect(staticWidgets(code), <String>['9 Text']);
    });

    test('takes the objects of Listenable.merge and of an animation', () {
      const String code = '''
class A {
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_a, _b]),
        builder: (BuildContext context, Widget? child) =>
            Column(children: <Widget>[Text(_b.text), Text(_title)]),
      ),
      AnimatedBuilder(
        animation: CurvedAnimation(parent: _c, curve: Curves.ease),
        builder: (BuildContext context, Widget? child) =>
            Opacity(opacity: _c.value, child: Icon(_icon)),
      ),
    ],
  );
}
''';
      expect(staticWidgets(code), <String>['7 Text', '12 Icon']);
    });

    test('reads the methods of the class that the widgets call', () {
      const String code = '''
class A {
  double get _angle => _controller.value * 2;

  Widget _label() => Text(widget.label);

  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) => Column(
      children: <Widget>[
        Transform.rotate(angle: _angle, child: const Logo()),
        _label(),
        _Badge(color: widget.color),
      ],
    ),
  );
}
''';
      expect(staticWidgets(code), <String>['11 _label', '12 _Badge']);
    });

    test('counts a variable that the code changes while the builder lives', () {
      const String code = '''
class _A extends State<A> {
  double _drag = 0;
  int _count = 0;
  String _title = '';

  void _onDrag(double d) => _drag = d;

  void _rename(String t) => setState(() => _title = t);

  @override
  void initState() {
    super.initState();
    _count = 1;
  }

  Widget build(BuildContext context) {
    var label = widget.label;
    onLabel = (String l) => label = l;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) => Column(
        children: <Widget>[
          Text('\$_drag'),
          Text('\$label'),
          Text('\$_count'),
          Text(_title),
        ],
      ),
    );
  }
}
''';
      // `_drag` changes in a drag callback, and `label` in a function of
      // build(): the builder shows their new value. `_count` and `_title`
      // change before a build only.
      expect(staticWidgets(code), <String>['25 Text', '26 Text']);
    });

    test('does not run the functions given to a widget', () {
      const String code = '''
class _A extends State<A> {
  void _submit() => setState(() => _sent = true);

  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _fields,
    builder: (BuildContext context, Widget? child) => Column(
      children: <Widget>[
        Text(_fields.text),
        TextButton(onPressed: _submit, child: Text(widget.label)),
        TextButton(
          onPressed: () => showDialog(context: context, builder: _dialog),
          child: Text(widget.cancel),
        ),
      ],
    ),
  );
}
''';
      final ({
        List<StaticWidget> widgets,
        List<String> undecided,
        List<({int first, int last})> builders,
      })
      result = staticBuilderWidgets(code);

      expect(
        <String>[
          for (final StaticWidget w in result.widgets) '${w.line} ${w.widget}',
        ],
        <String>['9 TextButton', '10 TextButton'],
      );
      expect(result.undecided, isEmpty);
    });

    test('decides nothing on a method that is not in the file', () {
      const String code = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) =>
        Column(children: <Widget>[Text(textTheme().title)]),
  );
}

class B {
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _controller, builder: _build);
}
''';
      final ({
        List<StaticWidget> widgets,
        List<String> undecided,
        List<({int first, int last})> builders,
      })
      result = staticBuilderWidgets(code);

      expect(result.widgets, isEmpty);
      expect(result.undecided, <String>[
        'line 5: `Column`: `textTheme()` is not in the file',
        'line 11: the builder is `_build`, whose code is not here',
      ]);
    });
  });

  group('P9 decided by the code', () {
    const String source = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) => Opacity(
      opacity: _controller.value,
      child: Text(widget.label),
    ),
  );
}
''';

    test('flags a widget that the pull request writes', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -5,3 +5,3 @@
       opacity: _controller.value,
-      child: child,
+      child: Text(widget.label),
     ),
''';
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff(diff),
        <String, String>{'lib/a.dart': source},
      );

      expect(decision.applies, isTrue);
      expect(decision.findings.single.line, 6);
      expect(decision.findings.single.rule, 'P9');
      expect(decision.findings.single.evidence, 'child: Text(widget.label),');
      expect(decision.findings.single.message, contains('`Text`'));
    });

    test('does not flag a widget that the pull request does not write', () {
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -4,3 +4,3 @@
     builder: (BuildContext context, Widget? child) => Opacity(
-      opacity: 1,
+      opacity: _controller.value,
       child: Text(widget.label),
''';
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff(diff),
        <String, String>{'lib/a.dart': source},
      );

      expect(decision.applies, isTrue);
      expect(decision.findings, isEmpty);
      expect(decision.reason, contains('does not write its line'));
    });

    test('says how to build it once when the child is already used', () {
      const String taken = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (BuildContext context, Widget? child) => Row(
      children: <Widget>[Opacity(opacity: _controller.value), Text(widget.a)],
    ),
  );
}
''';
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
new file mode 100644
--- /dev/null
+++ b/lib/a.dart
@@ -0,0 +1,9 @@
${taken.trimRight().split('\n').map((String l) => '+$l').join('\n')}
'''),
        <String, String>{'lib/a.dart': taken},
      );

      expect(decision.findings.single.line, 6);
      expect(
        decision.findings.single.message,
        contains('keep it in a variable written before the `AnimatedBuilder`'),
      );
    });

    test('makes one remark for each builder, with the other widgets', () {
      const String two = '''
class A {
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _fields,
    builder: (BuildContext context, Widget? child) => Column(
      children: <Widget>[
        Text(_fields.text),
        Text(widget.title),
        Icon(widget.icon),
      ],
    ),
  );
}
''';
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
new file mode 100644
--- /dev/null
+++ b/lib/a.dart
@@ -0,0 +1,12 @@
${two.trimRight().split('\n').map((String l) => '+$l').join('\n')}
'''),
        <String, String>{'lib/a.dart': two},
      );

      expect(decision.findings, hasLength(1));
      expect(decision.findings.single.line, 7);
      expect(
        decision.findings.single.message,
        contains('`Text`, and the widget of line 8, read nothing'),
      );
      expect(
        decision.findings.single.message,
        contains('Only one widget can be the `child`'),
      );
      // A `Text` and an `Icon` have no widget inside them.
      expect(decision.findings.single.level, 'suggestion');
    });

    test('keeps the level of the rule for a subtree', () {
      // `source`: `Text(widget.label)` alone is a leaf.
      const String subtree = '''
class A {
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) => Opacity(
      opacity: _controller.value,
      child: Padding(padding: p, child: Text(widget.label)),
    ),
  );
}
''';
      CodeDecision decide(String code) => rebuiltSubtrees(
        parseDiff('''
diff --git a/lib/a.dart b/lib/a.dart
new file mode 100644
--- /dev/null
+++ b/lib/a.dart
@@ -0,0 +1,${code.trimRight().split('\n').length} @@
${code.trimRight().split('\n').map((String l) => '+$l').join('\n')}
'''),
        <String, String>{'lib/a.dart': code},
      );

      // `Navigator` has a widget inside its pages.
      const String pages = '''
class A {
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: _position,
    builder: (BuildContext context, int position, Widget? child) => Stack(
      children: <Widget>[
        Positioned(top: position.toDouble(), child: const Logo()),
        Navigator(pages: <Page<void>>[MaterialPage(child: CallPage(id))]),
      ],
    ),
  );
}
''';
      expect(decide(subtree).findings.single.level, isNull);
      expect(decide(pages).findings.single.line, 7);
      expect(decide(pages).findings.single.level, isNull);
      expect(decide(source).findings.single.level, 'suggestion');
    });

    test('does not check the tests', () {
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff('''
diff --git a/test/a_test.dart b/test/a_test.dart
new file mode 100644
--- /dev/null
+++ b/test/a_test.dart
@@ -0,0 +1,9 @@
${source.trimRight().split('\n').map((String l) => '+$l').join('\n')}
'''),
        <String, String>{'test/a_test.dart': source},
      );

      expect(decision.applies, isFalse);
    });

    test('applies only when a builder holds an added line', () {
      // immich #32771: the line of the builder is unchanged, the `Row` in
      // it is added. Here the change is outside the builder.
      const String diff = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +1,2 @@
-class B {
+class A {
   Widget build(BuildContext context) => AnimatedBuilder(
''';
      final CodeDecision decision = rebuiltSubtrees(
        parseDiff(diff),
        <String, String>{'lib/a.dart': source},
      );

      expect(decision.applies, isFalse);
      expect(decision.findings, isEmpty);
    });
  });
}
