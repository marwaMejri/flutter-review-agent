# Performance rules

## P1. Expensive work in `build()`

- **Check:** code inside a `build()` method, or in a method that `build()`
  calls.
- **Flag when:** `build()` sorts or filters a large collection, decodes JSON,
  parses dates or text, compiles a `RegExp`, reads a file, or runs a loop over
  data that does not change between frames.
- **Do not flag when:** the work is small and fixed (formatting one value,
  picking one item), or the result is already cached outside `build()`.
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
- **Source:** [Performance best practices, Control build() cost](https://docs.flutter.dev/perf/best-practices#control-build-cost)
- **Level:** issue

## P2. `setState` higher in the tree than needed

- **Check:** a `State` that calls `setState` and builds a large subtree.
- **Flag when:** the field changed by `setState` is only used by a small part
  of the subtree, such as a counter, a timer or a toggle, while the rest of the
  screen does not depend on it.
- **Do not flag when:** most of the subtree uses the changed field, or the
  subtree is small.
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

## P3. A method that returns a widget tree instead of a widget

- **Check:** methods in a widget or `State` class that return a `Widget`, such
  as `Widget _buildHeader()`.
- **Flag when:** the method returns a subtree with several widgets, or it is
  used more than once.
- **Do not flag when:** the method returns a single small widget, or it needs
  values that only exist inside `build()` and the subtree is small.
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

- **Why:** a method runs again on every rebuild of its parent. A widget can be
  `const`, and Flutter can skip rebuilding it when nothing changed.
- **Source:** [Performance best practices](https://docs.flutter.dev/perf/best-practices#control-build-cost), [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations) and the video [Widgets vs helper methods](https://www.youtube.com/watch?v=IOyq-eTRhvo) (official Flutter channel)
- **Level:** suggestion

## P5. A long list built without a builder

- **Check:** `ListView(children: ...)`, `GridView(children: ...)`, or a
  `Column` inside a `SingleChildScrollView`, whose children come from data.
- **Flag when:** the children are built from a collection that can be long,
  for example `items.map(...)` or a `for` loop over data from an API or a
  database.
- **Do not flag when:** the list has a small, fixed number of children, such
  as a settings screen with five rows.
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

- **Why:** a list with a concrete `children` list builds every item, even the
  ones off screen. A builder only builds the visible items.
- **Source:** [Performance best practices, Be lazy!](https://docs.flutter.dev/perf/best-practices#be-lazy) and [Pitfalls](https://docs.flutter.dev/perf/best-practices#pitfalls)
- **Level:** issue

## P9. `AnimatedBuilder` that rebuilds a subtree that does not animate

- **Check:** the `builder` function of an `AnimatedBuilder`.
- **Flag when:** the `builder` builds widgets that do not use the animation
  value, instead of receiving them through the `child` parameter.
- **Do not flag when:** everything in the `builder` depends on the animation.
- **Bad:**

  ```dart
  AnimatedBuilder(
    animation: _controller,
    builder: (BuildContext context, Widget? child) {
      return Transform.rotate(
        angle: _controller.value * 2 * math.pi,
        child: const ExpensiveLogo(),
      );
    },
  )
  ```

- **Good:**

  ```dart
  AnimatedBuilder(
    animation: _controller,
    child: const ExpensiveLogo(),
    builder: (BuildContext context, Widget? child) {
      return Transform.rotate(
        angle: _controller.value * 2 * math.pi,
        child: child,
      );
    },
  )
  ```

- **Why:** the `builder` runs on every tick of the animation. A subtree passed
  as `child` is built once.
- **Source:** [Performance best practices, Pitfalls](https://docs.flutter.dev/perf/best-practices#pitfalls) and [AnimatedBuilder, Performance optimizations](https://api.flutter.dev/flutter/widgets/AnimatedBuilder-class.html#performance-optimizations)
- **Level:** issue
