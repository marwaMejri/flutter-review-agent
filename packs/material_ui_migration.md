# Pack: material_ui migration (optional)

Turn this pack on while a project moves from the Material and Cupertino
libraries of the Flutter SDK to the `material_ui` and `cupertino_ui` packages.
Turn it off when the migration is done.

Official guide: [Material and Cupertino as packages](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)

## M1. An `export` of the SDK Material or Cupertino

- **Check:** `export` directives in `lib/`.
- **Flag when:** a file exports `package:flutter/material.dart` or
  `package:flutter/cupertino.dart` in a project that depends on `material_ui`
  or `cupertino_ui`.
- **Do not flag when:** the project does not use `material_ui` or
  `cupertino_ui` yet.
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

## M2. A dependency that can bring in, or keep out, `material_ui`

- **Check:** changes to `pubspec.yaml`.
- **Flag when:**
  - `material_ui` or `cupertino_ui` has the constraint `any` (this is what
    `dart fix` writes), or
  - the app has **not** migrated (it still imports
    `package:flutter/material.dart`) and the pull request adds a package or
    moves one to a new major version. The new version may already use
    `material_ui`: ask the author to check its changelog.
- **Do not flag when:** the constraint is a real range, and the package's
  changelog was checked (the pull request description says so).
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
- **Source:** measured in [Can you migrate to material_ui yet?](https://dev.to/marwamejri/can-you-migrate-to-materialui-yet-1aa1) (`any`) and in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration) (`go_router`)
- **Level:** issue

## M3. A new UI package in a migrated app

- **Check:** packages added to `pubspec.yaml` in an app that imports
  `material_ui`.
- **Flag when:** the new package provides widgets or reads the theme (a UI
  kit, a form, a Markdown renderer, a router).
- **Do not flag when:** the package has no UI (HTTP, storage, logging).
- **Bad:** adding `flutter_markdown_plus: 1.0.12` to a migrated app, with no
  check.
- **Good:** the author checks that the package uses `material_ui`, for example
  with `tool/check_design_imports.dart` from the source below, and writes the
  result in the pull request.
- **Why:** a package that still reads the SDK `Theme` falls back to the
  default theme in a migrated app, with no error and no warning.
- **Source:** measured in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration)
- **Level:** suggestion

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
