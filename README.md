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
Add a constructor with named parameters.

```
import 'package:box/box.dart';

part 'employee.g.dart';

@entity
class Employee {
  @key
  final String id;
  final String name;

  Employee({this.id, this.name});
}
```

You can customize serialization by adding a `fromJson` constructor and a `toJson` method. 

```
Employee.fromJson(Map<String, dynamic> json) : this(
    id: json['id'],
    name: json['name'],
);

Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
};

```

Whenever you make a change to an annotated class, execute:
```
pub run build_runner build
```

Now you can any Box implementation as follows:
```
var registry = Registry()..register(Employee$BoxSupport()));
var box = MemoryBox(registry);
```
