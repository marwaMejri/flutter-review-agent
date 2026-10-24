# Memory rules

The memory guide separates two problems: a **leak** (memory keeps growing
until the app crashes) and **bloat** (the app uses more memory than it needs).
These rules target leaks.

## B2. A resource created in `build()`

- **Check:** `build()` methods.
- **Flag when:** `build()` creates an object whose class has a `dispose()`,
  `close()` or `cancel()` method, such as a `TextEditingController`,
  `ScrollController`, `AnimationController`, `FocusNode` or
  `StreamController`, or starts a subscription with `stream.listen(...)`.
- **Do not flag when:** the object is created in `initState` (or a field
  initializer of the `State`) and only used in `build()`.
- **Bad:**

  ```dart
  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return TextField(controller: controller);
  }
  ```

- **Good:**

  ```dart
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _controller);
  ```

- **Why:** `build()` can run many times. A new controller each time loses the
  user's input and is never disposed.
- **Source:** [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations) (allocate resources in `initState`, release them in `dispose`)
- **Level:** issue
- **Triggers:** `Controller(`, `FocusNode(`, `Subscription`, `.listen(`

## MEM1. An object with `dispose()` that is never disposed

- **Check:** fields of a `State` (or of any class that owns them) whose type
  has a `dispose()` method.
- **Flag when:**
  - the object is created by this class, and the class has no `dispose()`
    call for it: no `dispose()` override, or an override that forgets this
    field;
  - a `Timer.periodic` is started and never cancelled in `dispose()`: its
    callback keeps the `State` alive.
- **Do not flag when:**
  - the object was passed in from outside: its owner disposes it;
  - it is a `StreamSubscription` or a `Sink`: they have no `dispose()`. The
    lints `cancel_subscriptions` and `close_sinks` cover them when they are
    turned on (they are not in the recommended lint sets);
  - a library creates and disposes it, for example `useAnimationController`
    from `flutter_hooks`, or `ChangeNotifierProvider(create: ...)` from
    `provider`.
- **Bad:**

  ```dart
  class _PlayerState extends State<Player> with SingleTickerProviderStateMixin {
    late final AnimationController _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    @override
    Widget build(BuildContext context) => FadeTransition(
          opacity: _controller,
          child: widget.child,
        );
  }
  ```

- **Good:** add

  ```dart
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  ```

- **Why:** an object that is not disposed keeps its listeners and resources.
  Repeated on every visit to the screen, this is a leak.
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory) ("To avoid memory leaks, invoke `dispose` when the object isn't needed anymore"), [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations), [flutter_hooks](https://pub.dev/packages/flutter_hooks) and [provider](https://pub.dev/packages/provider)
- **Level:** issue
- **Triggers:** `Controller`, `FocusNode`, `ChangeNotifier`, `dispose`, `Timer.periodic`

## MEM2. A `BuildContext` stored in a field

- **Check:** fields of a `State`, a controller, a service or a singleton, and
  global variables.
- **Flag when:** a field or a global variable has the type `BuildContext` or
  `BuildContext?`, or the code assigns `context` to a field, a global variable
  or a collection.
- **Do not flag when:**
  - the context is only a parameter or a local variable, used during the
    call;
  - it is kept by an object created in `build()`, and that object is never
    stored in a field.
- **Bad:**

  ```dart
  class _FormState extends State<SignUpForm> {
    BuildContext? _savedContext;

    @override
    Widget build(BuildContext context) {
      _savedContext = context;
      return const SizedBox();
    }
  }
  ```

- **Good:** use the `context` getter of `State`, which is always current, and
  check `mounted` after an `await`.
- **Why:** the `State` can outlive its widget, and a stored context keeps the
  old widget tree in memory.
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory) ("The build context, owned by the widget, should never be referenced from the state's fields")
- **Level:** issue
- **Triggers:** `BuildContext`

## MEM3. A long-lived closure that captures `context`

- **Check:** closures that use `context` and are given to a stream
  (`.listen(...)`), a `Timer`, a service, a singleton or a global object, for
  example through `addListener`, `onMessage` or `register`.
- **Flag when:** the closure reads `context` (for example `Theme.of(context)`)
  and is registered on such an object.
- **Do not flag when:**
  - the object is created and disposed by the same `State`: it does not
    outlive the widget;
  - the closure only lives as long as the widget: a callback given to a widget
    in `build()` (`onPressed:`, `onTap:`, `builder:`), or
    `WidgetsBinding.instance.addPostFrameCallback`, which runs once;
  - the problem is `context` used after an `await`: the lint
    `use_build_context_synchronously` covers that.
- **Bad:**

  ```dart
  notifications.onMessage(() => showBanner(Theme.of(context)));
  ```

- **Good:**

  ```dart
  final ThemeData theme = Theme.of(context);
  notifications.onMessage(() => showBanner(theme));
  ```

- **Why:** a closure keeps everything it captures alive. If it outlives the
  widget, it keeps the context, and the widget tree behind it, in memory.
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory) ("if the closure doesn't outlive the widget, it's ok to pass the context to the closure")
- **Level:** issue
- **Triggers:** `context`
