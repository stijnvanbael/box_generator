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

Annotate the class you want to generate Box bindings for and add the generated file as a part.
Add constructor `fromJson` and method `toJson`.

```
import 'package:box/box.dart';

part 'employee.g.dart';

@entity
class Employee {
  @key
  final String id;
  final String name;

  Employee(this.id, this.name);

  Employee.fromJson(Map<String, dynamic> json) 
    : this(json['id'], json['name']);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  }
}
```

Whenever you make a change to an annotated class, execute:
```
pub run build_runner build
```
