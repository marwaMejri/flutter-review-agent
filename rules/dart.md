# Dart rules

Most of Effective Dart is checked by `dart format` and the lints. These two
rules need a reviewer.

## B4. A `late` variable checked for initialization

- **Check:** `late` fields and variables.
- **Flag when:** the code tracks whether a `late` variable was set, with a
  flag such as `_isInitialized`, or catches `LateInitializationError`.
- **Do not flag when:**
  - the code never checks whether the variable is set: it is assigned in its
    declaration (lazy initialization), in the constructor or in `initState`,
    before any read.
- **Decide:**
  1. Is there a `late` variable? If yes, go to step 2. If no, do not flag.
  2. Does the code use a flag (such as `_isInitialized`) to know whether it is
     set, or catch `LateInitializationError`? If yes, flag. If no, do not flag.
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
- **Triggers:** `late `

## B5. A nullable `Future`, `Stream` or collection returned

- **Check:** return types of functions, methods and getters.
- **Flag when:** the return type is `Future<T>?`, `Stream<T>?`, `List<T>?`,
  `Set<T>?`, `Map<K, V>?` or `Iterable<T>?`.
- **Do not flag when:**
  - `null` has a meaning that is different from empty, and a `///` comment
    on the member says what `null` means. A comment that says `null` means
    "none", "no result" or "empty" does not count: that is what an empty
    collection means;
  - the `Future` itself is not nullable and only its value is, such as
    `Future<User?>`: the guide recommends this form;
  - only the elements are nullable, for example `List<String?>` or
    `Map<String, Object?>`;
  - it is a parameter, a field or a local variable: this rule is about return
    types only.
- **Decide:**
  1. Look at the return type of each function, method or getter. Does it end
     with `>?`, as in `List<Release>?`, `Map<String, int>?` or `Future<int>?`? A
     type that ends with `?>`, as in `Future<Release?>` or `List<String?>`,
     answers no. Parameters, fields and variables answer no. If yes, go to step
     2. If no, do not flag.
  2. Read the `///` comment on the member. If there is no comment, flag. If it
     says that `null` means "none", "no result" or "empty" (for example "null
     when there is none"), flag: an empty collection says the same. If it gives
     `null` another meaning, such as "not loaded yet", do not flag.
- **Bad:**

  ```dart
  List<Release>? betaReleases() { /* returns null when there is none */ }
  ```

- **Good:**

  ```dart
  List<Release> betaReleases() { /* returns [] when there is none */ }
  ```

- **Why:** every caller must handle both `null` and an empty collection. An
  empty collection is enough.
- **Source:** [Effective Dart, Design: AVOID returning nullable Future, Stream, and collection types](https://dart.dev/effective-dart/design) ("Users generally assume and prefer that you use an empty container to indicate "no data".")
- **Level:** suggestion
- **Triggers:** `?>`, `>?`
