import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:box/box.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

class BoxRegistryBuilder extends GeneratorForAnnotation<Entity> {
  final List<String> types = [];

  @override
  FutureOr<String> generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (element.kind != ElementKind.CLASS) {
      throw 'ERROR: @Entity can only be used on a class, found on $element';
    }
    var inspector = EntityInspector();
    element.visitChildren(inspector);
    var typeName = element.name;
    var deserializer = '${typeName}.fromJson(map)';
    if (inspector.deserializer == null) {
      deserializer = _generateDeserializer(inspector, typeName);
    }
    var serializer = 'entity.toJson()';
    if (inspector.serializer == null) {
      serializer = _generateSerializer(inspector);
    }
    return '''
    class ${typeName}\$BoxSupport extends EntitySupport<${typeName}> {
      ${typeName}\$BoxSupport() : super(
        name: '${typeName}',
        keyAccessor: ${_buildKeyAccessor(inspector)},
        fieldAccessors: ${_buildFieldAccessors(inspector)},
        keyFields: [${inspector.keys.map((key) => "'${key.name}'").join(',')}],
        fieldTypes: {${_buildFieldTypes(inspector)}}
      );
      
      @override
      ${typeName} deserialize(Map<String, dynamic> map) => $deserializer;
      
      @override
      Map<String, dynamic> serialize(${typeName} entity) => $serializer;
    }
    ''';
  }

  String _buildFieldTypes(EntityInspector inspector) => inspector.fields
      .where(_fieldFilter)
      .map((field) => "'${field.name}': ${field.type.element.name}")
      .join(', ');

  String _buildFieldAccessors(EntityInspector inspector) =>
      '{' +
      inspector.fields
          .where(_fieldFilter)
          .map((field) => "'${field.name}': (entity) => entity.${field.name}")
          .join(', ') +
      '}';

  bool _fieldFilter(FieldElement field) => !field.isStatic;

  String _buildKeyAccessor(EntityInspector inspector) => inspector.keys.isEmpty
      ? '(entity) => null'
      : inspector.keys.length == 1
          ? '(entity) => entity.${inspector.keys.first.name}'
          : '(entity) => Composite({${inspector.keys.map((field) => "'${field.name}': entity.${field.name}").join(', ')}})';

  String _generateDeserializer(EntityInspector inspector, String typeName) =>
      'map != null '
      '? $typeName(${inspector.fields.map((field) => '${field.name}: ${_deserializeType(field.type, "map['${field.name}']")}').join(', ')})'
      ': null';

  String _generateSerializer(EntityInspector inspector) => 'entity != null '
      '? {${inspector.fields.map((field) => "'${field.name}': ${_serializeType(field.type, 'entity.${field.name}')}").join(', ')}}'
      ': null';

  String _serializeType(DartType type, String input) {
    if (_isPrimitive(type)) {
      return input;
    } else if (type.isDartCoreList) {
      return _serializeList(
          (type as ParameterizedType).typeArguments.first, input);
    } else if (type.isDartCoreSet) {
      return _serializeSet(
          (type as ParameterizedType).typeArguments.first, input);
    } else if (_isType(type, 'dart.core', 'DateTime')) {
      return '$input?.toIso8601String()';
    } else if (_isEnum(type.element)) {
      return 'serializeEnum($input)';
    } else if (_isEntity(type.element)) {
      return 'serializeEntity($input)';
    } else {
      return '$input?.toJson()';
    }
  }

  String _deserializeType(DartType type, String input) {
    if (_isPrimitive(type)) {
      return input;
    } else if (type.isDartCoreList) {
      return _deserializeList(
          (type as ParameterizedType).typeArguments.first, input);
    } else if (type.isDartCoreSet) {
      return _deserializeSet(
          (type as ParameterizedType).typeArguments.first, input);
    } else if (_isType(type, 'dart.core', 'DateTime')) {
      return 'deserializeDateTime($input)';
    } else if (_isEnum(type.element)) {
      return 'deserializeEnum($input, ${type.element.name}.values)';
    } else if (_isEntity(type.element)) {
      return 'deserializeEntity<${type.element.name}>($input)';
    } else {
      return '$input != null ? ${type.element.name}.fromJson($input) : null';
    }
  }

  bool _isPrimitive(DartType type) {
    return type.isDartCoreBool ||
        type.isDartCoreString ||
        type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreNum;
  }

  bool _isType(DartType type, String library, String typeName) =>
      type.element.library.name == library && type.element.name == typeName;

  bool _isEntity(Element element) => element.metadata.any((metadata) =>
      _isType(metadata.computeConstantValue().type, 'box.core', 'Entity'));

  String _deserializeList(DartType type, String input) => '$input != null '
      '? List<${type.element.name}>.from($input.map((element) => ${_deserializeType(type, 'element')})) '
      ': null';

  String _deserializeSet(DartType type, String input) => '$input != null '
      '? Set<${type.element.name}>.from($input.map((element) => ${_deserializeType(type, 'element')})) '
      ': null';

  String _serializeList(DartType type, String input) => '$input != null '
      '? $input.map((element) => ${_serializeType(type, 'element')}).toList() '
      ': null';

  String _serializeSet(DartType type, String input) => '$input != null '
      '? $input.map((element) => ${_serializeType(type, 'element')}).toSet() '
      ': null';

  bool _isEnum(Element element) => element is ClassElement && element.isEnum;
}

class EntityInspector extends SimpleElementVisitor<void> {
  final List<FieldElement> keys = [];
  final List<FieldElement> fields = [];
  MethodElement serializer;
  ConstructorElement deserializer;

  @override
  void visitFieldElement(FieldElement element) {
    if (!element.isSynthetic) {
      fields.add(element);
      if (element.metadata.any(_isKey)) {
        keys.add(element);
      }
    }
  }

  bool _isKey(ElementAnnotation element) {
    var value = element.computeConstantValue();
    return value.type.element.library.name == 'box.core' &&
        value.type.element.name == 'Key';
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
