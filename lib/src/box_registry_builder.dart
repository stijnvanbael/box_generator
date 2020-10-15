import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:box/box.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

class BoxRegistryBuilder extends GeneratorForAnnotation<Entity> {
  final List<String> types = [];

  @override
  FutureOr<String> generateForAnnotatedElement(Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element.kind != ElementKind.CLASS) {
      throw 'ERROR: @Entity can only be used on a class, found on $element';
    }
    var inspector = EntityInspector();
    element.visitChildren(inspector);
    var typeName = element.name;
    if (inspector.deserializer == null) {
      throw 'ERROR: Missing deserializer constructor on $element, please add a constructor "${typeName}.fromJson(Map map)"';
    }
    if (inspector.serializer == null) {
      throw 'ERROR: Missing serializer method on $element, please add a method "Map ${typeName}.toJson()"';
    }
    types.add(typeName);
    return '''
    class ${typeName}\$BoxSupport extends EntitySupport<${typeName}> {
      ${typeName}\$BoxSupport() : super(
        '${typeName}',
        ${buildKeyAccessor(inspector)},
        (map) => ${typeName}.fromJson(map),
        ${buildFieldAccessors(inspector)},
        [${inspector.keys.map((key) => "'${key.name}'").join(',')}],
        {${buildFieldTypes(inspector)}}
      );
      
      static Registry appendToRegistry(Registry registry) {
        ${types.map((type) => 'registry.register(${type}\$BoxSupport());').join('\n')}
        return registry;
      }
    }
    ''';
  }

  String buildFieldTypes(EntityInspector inspector) =>
      inspector.fields.where(fieldFilter).map((field) => "'${field.name}': ${field.type.element.name}").join(', ');

  String buildFieldAccessors(EntityInspector inspector) =>
      '{' +
      inspector.fields
          .where(fieldFilter)
          .map((field) => "'${field.name}': (entity) => entity.${field.name}")
          .join(', ') +
      '}';

  bool fieldFilter(FieldElement field) => !field.isStatic;

  String buildKeyAccessor(EntityInspector inspector) => inspector.keys.isEmpty
      ? '(entity) => null'
      : inspector.keys.length == 1
          ? '(entity) => entity.${inspector.keys.first.name}'
          : '(entity) => Composite({${inspector.keys.map((field) => "'${field.name}': entity.${field.name}").join(', ')}})';
}

class EntityInspector extends SimpleElementVisitor<void> {
  final List<FieldElement> keys = [];
  final List<FieldElement> fields = [];
  MethodElement serializer;
  ConstructorElement deserializer;

  @override
  void visitFieldElement(FieldElement element) {
    if (element.name != 'hashCode') {
      fields.add(element);
      if (element.metadata.any(_isKey)) {
        keys.add(element);
      }
    }
  }

  bool _isKey(ElementAnnotation element) {
    var value = element.computeConstantValue();
    return value.type.element.library.name == 'box.core' && value.type.element.name == 'Key';
  }

  @override
  void visitConstructorElement(ConstructorElement element) {
    if (element.name == 'fromJson') {
      deserializer = element;
    }
  }

  @override
  void visitMethodElement(MethodElement element) {
    if (element.name == 'toJson') {
      serializer = element;
    }
  }
}
