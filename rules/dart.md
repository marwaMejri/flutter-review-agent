# Dart rules

Most of Effective Dart is checked by `dart format` and the lints. These two
rules need a reviewer.

## B4. A `late` variable checked for initialization

- **Check:** `late` fields and variables.
- **Flag when:** the code tracks whether a `late` variable was set, with a
  flag such as `_isInitialized`, or catches `LateInitializationError`.
- **Do not flag when:** the variable is always set before it is read, for
  example in `initState`.
- **Bad:**

  ```dart
  late User _user;
  bool _hasUser = false;

  void load(User user) {
    _user = user;
    _hasUser = true;
  }

  String get name => _hasUser ? _user.name : 'Guest';
  ```

- **Good:**

  ```dart
  User? _user;

  void load(User user) => _user = user;

  String get name => _user?.name ?? 'Guest';
  ```

- **Why:** Dart cannot test whether a `late` variable is initialized. A
  nullable type says the same thing, and the compiler checks it.
- **Source:** [Effective Dart, Usage: AVOID late variables if you need to check whether they are initialized](https://dart.dev/effective-dart/usage)
- **Level:** issue

## B5. A nullable `Future`, `Stream` or collection returned

- **Check:** return types of functions, methods and getters.
- **Flag when:** the return type is `Future<T>?`, `Stream<T>?`, `List<T>?`,
  `Set<T>?`, `Map<K, V>?`, or a `Future` of a nullable collection, such as
  `Future<List<T>?>`.
- **Do not flag when:** `null` has a meaning that is different from empty,
  and this meaning is documented on the member.
- **Bad:**

  ```dart
  Future<List<Release>?> fetchReleases() async { /* ... */ }
  ```

- **Good:**

  ```dart
  Future<List<Release>> fetchReleases() async { /* returns [] when empty */ }
  ```

- **Why:** every caller must handle both `null` and an empty collection. An
  empty collection is enough.
- **Source:** [Effective Dart, Design: AVOID returning nullable Future, Stream, and collection types](https://dart.dev/effective-dart/design)
- **Level:** suggestion
