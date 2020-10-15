library box_generator;

import 'package:box_generator/src/box_registry_builder.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

export 'src/box_registry_builder.dart';

Builder registryBuilder(BuilderOptions options) => SharedPartBuilder([BoxRegistryBuilder()], 'box_generator');
