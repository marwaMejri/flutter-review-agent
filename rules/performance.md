# Performance rules

## P1. Expensive work in `build()`

- **Check:** code inside a `build()` method, or in a method that `build()`
  calls.
- **Flag when:**
  - the code sorts, filters or groups a collection that comes from data (a
    field, a parameter, an API result);
  - it loops over a collection to compute a value (a sum, a count, a search);
  - it decodes JSON, compiles a `RegExp`, reads a file, or parses each item of
    a collection (dates, numbers, text);
  - `build()` creates the `Future` of a `FutureBuilder` (for example
    `FutureBuilder(future: api.fetchReleases())`): the request starts again on
    every rebuild. This applies whatever the function does, even when it
    looks cheap: the documentation asks for a `Future` obtained earlier, for
    example in `initState`.
- **Do not flag when:**
  - `future:` reads a `Future` stored in a field, such as `future: _unread`,
    and the field is set in `initState`;
  - the code works on one value, with no loop: formatting one date,
    `items[index]`, a string interpolation;
  - the result is computed outside `build()` (in `initState`,
    `didUpdateWidget` or a field), and `build()` only reads it;
  - the code only builds the widget tree, for example a `for` loop or a `.map`
    that creates the child widgets;
  - the code only reads values: `Theme.of(context)`, `MediaQuery.of(context)`,
    fields of the widget or of the state;
  - while the tree is built, each item gets one simple operation: a
    comparison, `contains`, `toLowerCase`, a string interpolation. Parsing
    each item (a `RegExp`, `DateTime.parse`, `jsonDecode`) is flagged.
- **Decide:**
  1. Does code in `build()`, or in a method it calls, create the `Future` given
     to a `FutureBuilder`, such as `future: load()` or `future: api.fetch()`?
     `future: _unread`, which reads a field, answers no. If yes, flag, whatever
     the function does. If no, go to step 2.
  2. Does code in `build()`, or in a method it calls, sort, filter or group a
     collection, loop over a collection to compute a value (a sum, a count, a
     search), decode JSON, compile a `RegExp`, read a file, or parse each item
     of a collection? A `for` or a `.map` that only creates one widget for each
     item answers no: that is rule P5. If yes, go to step 3. If no, do not flag.
  3. Is that result computed outside `build()` (in `initState`,
     `didUpdateWidget` or a field) and only read in `build()`? Or is it one
     simple operation, such as `contains`, a comparison or `toLowerCase`?
     Calling, for each item, a function that compiles a `RegExp` or parses the
     item is not simple. If yes, do not flag. If no, flag.
- **Bad:**

  ```dart
  @override
  Widget build(BuildContext context) {
    final List<Release> sorted = List.of(widget.releases)
      ..sort((a, b) => b.date.compareTo(a.date));
    return ReleaseList(releases: sorted);
  }
  ```

- **Good:** sort once, when the data changes.

  ```dart
  late List<Release> _sorted = _sort(widget.releases);

  @override
  void didUpdateWidget(covariant ReleasesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.releases != widget.releases) {
      _sorted = _sort(widget.releases);
    }
  }

  @override
  Widget build(BuildContext context) => ReleaseList(releases: _sorted);
  ```

- **Why:** `build()` can run every time an ancestor rebuilds. Repeated work
  there costs time on every frame.
- **Source:** [Performance best practices, Control build() cost](https://docs.flutter.dev/perf/best-practices#control-build-cost) and [FutureBuilder](https://api.flutter.dev/flutter/widgets/FutureBuilder-class.html) (obtain the future in `initState`, not in `build()`)
- **Level:** issue

## P2. `setState` higher in the tree than needed

- **Check:** a `State` that calls `setState`, and whose `build()` returns
  several widgets, such as a `Scaffold` with an app bar and a body, or a
  `Column` with several sections.
- **Flag when:** the field changed by `setState` is read by one part of
  `build()` only (one widget and its children), and the other widgets of
  `build()` do not read it. For example a counter, a timer or a toggle shown in
  one place.
- **Do not flag when:**
  - the field chooses what `build()` returns, or what the `body:` of the
    `Scaffold` shows, for example `if (_loading) return const Spinner();` or
    `body: _loading ? const Spinner() : const Content()`. The whole screen
    changes, so this is not a small part, even if the app bar does not read
    the field. A field that changes only one widget (a `Text` that shows its
    value, one `Icon`) does not choose what the screen shows;
  - `build()` returns only widgets that read the field, or that wrap one that
    does (a `Padding`, a `Center`): there is nothing to move out.
- **Decide:**
  1. Does this `State` call `setState`, and does its `build()` return a
     `Scaffold`, or a `Column` or a `ListView` with several sections? If yes, go
     to step 2. If no (it returns one widget, or a `Padding` or a `Center`
     around one widget), do not flag.
  2. Does the field changed by `setState` change only one part of `build()`: one
     widget and its children, such as a `Text` that shows its value or one
     `Icon`, while the other widgets do not read it? If yes, flag. If no (the
     field chooses what `build()` returns, or what the `body:` shows, with an
     `if`, a `? :` or a `switch`, as in `body: _loading ? const Spinner() :
     const Content()`), do not flag.
- **Bad:** a whole screen rebuilds every second for a clock.

  ```dart
  class _DashboardState extends State<Dashboard> {
    DateTime _now = DateTime.now();
    // A Timer calls setState(() => _now = DateTime.now()) every second.

    @override
    Widget build(BuildContext context) {
      return Column(
        children: <Widget>[
          Text('$_now'),
          const StatsPanel(),
          const ActivityFeed(),
        ],
      );
    }
  }
  ```

- **Good:** move the changing state into its own widget.

  ```dart
  class Dashboard extends StatelessWidget {
    const Dashboard({super.key});

    @override
    Widget build(BuildContext context) {
      return const Column(
        children: <Widget>[Clock(), StatsPanel(), ActivityFeed()],
      );
    }
  }
  ```

- **Why:** `setState` rebuilds every descendant of the `State`. Keeping the
  state low keeps each rebuild small.
- **Source:** [Performance best practices, Control build() cost](https://docs.flutter.dev/perf/best-practices#control-build-cost) and [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations)
- **Level:** suggestion
- **Triggers:** `setState`

## P3. A method that returns a widget tree instead of a widget

- **Check:** methods in a widget or `State` class that return a `Widget`, such
  as `Widget _buildHeader()`.
- **Flag when:** the method returns a widget that contains other widgets (it
  has a `child` or `children`), or the method is called from two places or
  more. This applies even when the method needs values from `build()` (the
  `context`, the theme, the item of a loop): they can be passed to the
  constructor of the new widget.
- **Do not flag when:**
  - the method returns one widget with no child widget, such as
    `Text(title)`, an `Icon` or `const SizedBox()`;
  - it is `build()` itself, or a method that overrides a framework method
    (marked `@override`);
  - it is a function written directly as the argument of a builder, such as
    `itemBuilder: (context, index) => ...`. A method called from inside that
    function is not a callback: apply the rule to it.
- **Decide:**
  1. Is it a method that returns a `Widget`? Answer no for `build()`, for a
     method marked `@override`, and for a function written directly as the
     argument of a builder (`itemBuilder: (context, index) => ...`). A method
     called from inside that function answers yes. If yes, go to step 2. If no,
     do not flag.
  2. Does the returned widget have a `child:` or `children:` argument, or is the
     method called from two places or more? If yes, flag, even when the method
     uses values from `build()`: they can be passed to the constructor of a new
     widget. If no (one `Text`, `Icon` or `SizedBox`, called once), do not flag.
- **Bad:**

  ```dart
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: <Widget>[const Icon(Icons.info), Text(title)]),
    );
  }
  ```

- **Good:**

  ```dart
  class Header extends StatelessWidget {
    const Header({super.key, required this.title});

    final String title;

    @override
    Widget build(BuildContext context) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: <Widget>[const Icon(Icons.info), Text(title)]),
      );
    }
  }
  ```

- **Why:** the tree returned by a helper method is rebuilt every time its
  parent rebuilds. A separate widget lets Flutter update only the parts that
  changed, and a `const` widget lets Flutter skip most of the rebuild work.
  This is a structure suggestion: the gain depends on how often the parent
  rebuilds.
- **Source:** [Performance best practices](https://docs.flutter.dev/perf/best-practices#control-build-cost), [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations) and the video [Widgets vs helper methods](https://www.youtube.com/watch?v=IOyq-eTRhvo) (official Flutter channel)
- **Level:** suggestion
- **Triggers:** `Widget _`, `Widget build`

## P5. A long list built without a builder

- **Check:** `ListView(children: ...)`, `GridView(children: ...)`,
  `SliverChildListDelegate(...)`, or a `Column` (or a `Row`) inside a
  `SingleChildScrollView`, whose children come from data.
- **Flag when:** the children are built from a collection whose size is
  known only when the app runs: a field, a parameter, an API result, a
  database or a provider. For example `items.map(...)`, or a `for` loop over
  such a collection. A `final` list computed from data (with a loop, `map`,
  `where` or `split`) is data too, even at the top level of a file.
- **Do not flag when:**
  - the children are written one by one in the code, with no loop and no
    `.map`;
  - the collection is a literal whose items are written one by one in the
    code (`const [...]`), or the values of an enum;
  - the loop over the collection was already there before the pull request
    (shown as unchanged lines), and the pull request only changes an item
    inside it.
- **Decide:**
  1. Is it `ListView(children: ...)`, `GridView(children: ...)`,
     `SliverChildListDelegate(...)`, or a `Column` or `Row` inside a
     `SingleChildScrollView`? If yes, go to step 2. If no, do not flag.
  2. Are the children made by a `for` loop or a `.map` over a collection? If
     yes, go to step 3. If no (the children are written one by one), do not
     flag.
  3. Is the collection a `const` literal with its items written one by one, or
     the values of an enum? Or was the loop already there before the pull
     request (unchanged lines)? If yes, do not flag. If no (a field, a
     parameter, data from an API, a database or a provider, or a list computed
     from data), flag.
- **Bad:**

  ```dart
  ListView(
    children: <Widget>[
      for (final Release release in releases) ReleaseTile(release: release),
    ],
  )
  ```

- **Good:**

  ```dart
  ListView.builder(
    itemCount: releases.length,
    itemBuilder: (BuildContext context, int index) =>
        ReleaseTile(release: releases[index]),
  )
  ```

- **Why:** with a concrete list of children, Flutter does work for every
  child, even the ones off screen. A builder only builds the visible items.
  The code rarely shows how long the collection will be, so this is a
  suggestion: it matters when most children are off screen.
- **Source:** [Performance best practices, Be lazy!](https://docs.flutter.dev/perf/best-practices#be-lazy), [Pitfalls](https://docs.flutter.dev/perf/best-practices#pitfalls) ("if most of the children are not visible on screen"), [ListView](https://api.flutter.dev/flutter/widgets/ListView-class.html) (the default constructor "is appropriate for list views with a small number of children") and [SliverChildListDelegate](https://api.flutter.dev/flutter/widgets/SliverChildListDelegate-class.html)
- **Level:** suggestion
- **Triggers:** `ListView(`, `GridView(`, `Column(`, `SliverChildListDelegate(`, `SingleChildScrollView(`

## P9. A builder that rebuilds a subtree that does not change

- **Check:** the `builder` function of an `AnimatedBuilder`, a
  `ListenableBuilder` or a `ValueListenableBuilder`.
- **Flag when:** the `builder` contains a subtree that does not depend on the
  animation, the listenable or the `value` parameter, and that subtree is not
  `const`. It should be built once and passed through the `child` parameter.
  Look at each subtree on its own: in a `Row` that holds a `Transform` using
  the animation and a `Padding` with `Text(widget.version)`, the `Padding`
  does not depend on the animation, even if the `Row` must stay in the
  `builder`. This applies even when the subtree is small (a `Text`, a
  `Padding`). Reading the `context` parameter of the `builder` (for example
  `Theme.of(context)`) does not count as depending on the value.
- **Do not flag when:**
  - every subtree in the `builder` depends on the animation, the listenable
    or the value;
  - the subtrees that do not depend on them are `const`: Flutter reuses the
    same instance and skips rebuilding them;
  - the widget is given to the `child:` argument of the `AnimatedBuilder`,
    `ListenableBuilder` or `ValueListenableBuilder` itself: it is outside the
    `builder`, and built once. This is the fix the rule asks for.
- **Decide:**
  1. Does the pull request add or change the `builder` of an `AnimatedBuilder`,
     a `ListenableBuilder` or a `ValueListenableBuilder`? If yes, go to step 2.
     If no, do not flag.
  2. Look only inside the `builder` function. The widget given to the `child:`
     argument of the `AnimatedBuilder`, `ListenableBuilder` or
     `ValueListenableBuilder` itself is outside the `builder`: it is built once,
     so skip it. Do not judge the `builder` as a whole either: it always uses
     the animation somewhere. Search inside it for one widget whose arguments
     use only fields of the widget (`widget.version`), constants or `context`,
     and not the animation, the listenable or `value`. For example, in
     `Row(children: [Transform.rotate(angle: _controller.value, ...),
     Padding(child: Text(widget.version))])`, the `Padding` is such a widget,
     and so is `Text('Saved.', style: Theme.of(context).textTheme.bodySmall)`.
     If you found one, go to step 3. If not, do not flag.
  3. Is that widget marked `const`? If yes, do not flag. If no, flag it, even
     when it is small and even when it reads `context`: it can be built once,
     outside the `builder`, and passed through the `child` parameter.
- **Bad:**

  ```dart
  AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) {
      return Transform.rotate(
        angle: _controller.value * 2 * math.pi,
        child: Logo(color: widget.color),
      );
    },
  )
  ```

- **Good:**

  ```dart
  AnimatedBuilder(
    animation: _controller,
    child: Logo(color: widget.color),
    builder: (BuildContext context, Widget? child) {
      return Transform.rotate(
        angle: _controller.value * 2 * math.pi,
        child: child,
      );
    },
  )
  ```

- **Why:** the `builder` runs on every tick of the animation, or on every
  change of the value. A subtree passed as `child` is built once.
- **Source:** [Performance best practices, Control build() cost](https://docs.flutter.dev/perf/best-practices#control-build-cost) (the rebuild stops at "the same instance of the child widget"), [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations) ("If a subtree does not change, cache the widget that represents that subtree"), [Pitfalls](https://docs.flutter.dev/perf/best-practices#pitfalls), [AnimatedBuilder, Performance optimizations](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html#performance-optimizations), [ValueListenableBuilder](https://api.flutter.dev/flutter/widgets/ValueListenableBuilder-class.html) and [ListenableBuilder.child](https://api.flutter.dev/flutter/widgets/ListenableBuilder/child.html)
- **Level:** issue
- **Triggers:** `AnimatedBuilder`, `ListenableBuilder`, `ValueListenableBuilder`
