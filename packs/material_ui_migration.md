# Pack: material_ui migration (optional)

Turn this pack on while a project moves from the Material and Cupertino
libraries of the Flutter SDK to the `material_ui` and `cupertino_ui` packages.
Turn it off when the migration is done. The rules below assume that the pack
is on only in such a project: the project uses `material_ui` or
`cupertino_ui`.

Official guide: [Material and Cupertino as packages](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)

## M1. An `export` of the SDK Material or Cupertino

- **Check:** `export` directives in `lib/`.
- **Flag when:** a file exports `package:flutter/material.dart` or
  `package:flutter/cupertino.dart`.
- **Do not flag when:** the export is of `package:material_ui/...` or
  `package:cupertino_ui/...`.
- **Bad:**

  ```dart
  // lib/core/ui.dart
  export 'package:flutter/material.dart';
  ```

- **Good:**

  ```dart
  export 'package:material_ui/material_ui.dart';
  ```

- **Why:** `dart fix` rewrites `import` lines but not `export` lines. Every
  file that imports this barrel still gets the SDK Material, and its widgets
  fall back to the default theme with no error.
- **Source:** measured in [Can you migrate to material_ui yet?](https://dev.to/marwamejri/can-you-migrate-to-materialui-yet-1aa1) and reported in [dart-lang/sdk#63968](https://github.com/dart-lang/sdk/issues/63968)
- **Level:** issue
- **Triggers:** `export '`, `export "`

## M2. A dependency that can bring in, or keep out, `material_ui`

- **Check:** changes to `pubspec.yaml`.
- **Flag when:**
  - `material_ui` or `cupertino_ui` has the constraint `any` (this is what
    `dart fix` writes), or
  - the pull request moves a package under `dependencies:` to a new major
    version: the first number changes (`18.1.0` to `19.0.0`), or the second
    one when the first is `0` (`0.1.2` to `0.2.0`). The new version may use
    `material_ui` differently: ask the author to check its changelog.
- **Do not flag when:**
  - the version changes inside the same major version (`18.1.0` to
    `18.2.0`);
  - a package is added: M3 covers new packages;
  - the change only touches `dev_dependencies`, or the `version:` of the
    app.
- **Bad:**

  ```yaml
  dependencies:
    material_ui: any
  ```

- **Good:**

  ```yaml
  dependencies:
    material_ui: ^1.7.0
  ```

- **Why:** `any` accepts every future version, including one that breaks the
  app. And in an app that has not migrated, `flutter pub add go_router` with
  no version installed 18.1.0, which already uses `material_ui`: the page
  transitions disappeared, with no error.
- **Source:** [Package dependencies, Caret syntax](https://dart.dev/tools/pub/dependencies) (`^0.1.2` is `'>=0.1.2 <0.2.0'`), measured in [Can you migrate to material_ui yet?](https://dev.to/marwamejri/can-you-migrate-to-materialui-yet-1aa1) (`any`) and in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration) (`go_router`)
- **Level:** issue
- **Triggers:** `file:pubspec.yaml`

## M3. A new UI package in a migrated app

- **Check:** packages added under `dependencies:` in `pubspec.yaml`.
- **Flag when:** the name of the package, or the pull request, shows that it
  provides widgets or reads the theme (a UI kit, a form, a Markdown renderer,
  a router).
- **Do not flag when:**
  - the package has no UI (HTTP, storage, logging), or nothing in its name or
    in the code of the pull request shows that it has UI.
- **Bad:** adding `flutter_markdown_plus: 1.0.12` to a migrated app, with no
  check.
- **Good:** the author checks that the package uses `material_ui`, for example
  with `tool/check_design_imports.dart` from the source below, and writes the
  result in the pull request.
- **Why:** a package that still reads the SDK `Theme` falls back to the
  default theme in a migrated app, with no error and no warning.
- **Source:** measured in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration)
- **Level:** suggestion
- **Triggers:** `file:pubspec.yaml`

## M4. `MaterialUiCompatibilityBridge` with no reason and no removal plan

- **Check:** uses of `MaterialUiCompatibilityBridge`.
- **Flag when:** the bridge is added without a comment that says which
  package needs it and when to remove it.
- **Do not flag when:** the comment is there.
- **Bad:**

  ```dart
  // ignore: deprecated_member_use
  return MaterialUiCompatibilityBridge(child: child!);
  ```

- **Good:**

  ```dart
  // Needed by dropdown_button2 3.1.0, which still uses the SDK Material.
  // Remove when a migrated version is published.
  // ignore: deprecated_member_use
  return MaterialUiCompatibilityBridge(child: child!);
  ```

- **Why:** the bridge is already deprecated, and it only copies part of the
  theme. Without a reason and a removal plan, it stays forever.
- **Source:** measured in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration)
- **Level:** issue
- **Triggers:** `MaterialUiCompatibilityBridge`
