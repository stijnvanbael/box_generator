Dart Box Generator
==================

Generates Box bindings for `@entity` annotated classes.

Setup
-----
Add dev dependencies build_runner and box_generator to pubspec.yaml:
```
dev_dependencies:
    build_runner: <version>
    box_generator: <version>
```

Usage
-----

Whenever you make a change to an annotated class, execute:
```
pub run build_runner build
```
