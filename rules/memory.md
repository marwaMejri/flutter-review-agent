# Memory rules

The memory guide separates two problems: a **leak** (memory keeps growing
until the app crashes) and **bloat** (the app uses more memory than it needs).
These rules target leaks.

## B2. A resource created in `build()`

- **Check:** `build()` methods.
- **Flag when:** `build()` creates an object that holds a resource or needs to
  be disposed: a `TextEditingController`, `ScrollController`,
  `AnimationController`, `FocusNode`, `StreamController`, or a subscription.
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

## MEM1. An object with `dispose()` that is never disposed

- **Check:** fields of a `State` (or of any class that owns them) whose type
  has a `dispose()` method.
- **Flag when:** the object is created by this class, and the class has no
  `dispose()` call for it: no `dispose()` override, or an override that
  forgets this field.
- **Do not flag when:** the object was passed in from outside (its owner
  disposes it), or it is a `StreamSubscription` or a `Sink`: the lints
  `cancel_subscriptions` and `close_sinks` cover those.
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
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory) ("any object with a `dispose()` method should be disposed") and [StatefulWidget, Performance considerations](https://api.flutter.dev/flutter/widgets/StatefulWidget-class.html#performance-considerations)
- **Level:** issue

## MEM2. A `BuildContext` stored in a field

- **Check:** fields of a `State`, or of any object that lives longer than a
  widget.
- **Flag when:** a field has the type `BuildContext` or `BuildContext?`, or
  stores a context for later.
- **Do not flag when:** the context is only a parameter or a local variable,
  used during the call.
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
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory) ("never store the build context in the state's fields")
- **Level:** issue

## MEM3. A long-lived closure that captures `context`

- **Check:** closures that use `context` and are passed to something that
  lives longer than the widget: a stream listener, a service, a global
  callback, a `Timer`.
- **Flag when:** the closure reads `context` (for example `Theme.of(context)`)
  and is registered on such an object.
- **Do not flag when:** the closure only lives as long as the widget, for
  example an `onPressed` callback inside `build()`.
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
- **Source:** [DevTools, Memory view](https://docs.flutter.dev/tools/devtools/memory)
- **Level:** issue
