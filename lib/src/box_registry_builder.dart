import 'dart:async';

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:box/box.dart';
import 'package:box_generator/src/util.dart';
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
    inspector.visitClassElement(element as ClassElement);
    var typeName = element.name;
    var deserializer = '$typeName.fromJson(map)';
    if (inspector.deserializer == null) {
      deserializer = _generateDeserializer(inspector, typeName);
    }
    var serializer = 'entity.toJson()';
    if (inspector.serializer == null) {
      serializer = _generateSerializer(inspector);
    }
    return '''
    class $typeName\$BoxSupport extends EntitySupport<$typeName> {
      $typeName\$BoxSupport() : super(
        name: '$typeName',
        keyAccessor: ${_buildKeyAccessor(inspector)},
        fieldAccessors: ${_buildFieldAccessors(inspector)},
        keyFields: [${inspector.keys.map((key) => "'${key.name}'").join(',')}],
        fieldTypes: {${_buildFieldTypes(inspector)}},
        indexes: [${_buildIndexes(inspector)}],
      );
      
      @override
      $typeName deserialize(Map<String, dynamic> map) => $deserializer;
      
      @override
      Map<String, dynamic> serialize($typeName entity) => $serializer;
    }
    ''';
  }

  String _buildIndexes(EntityInspector inspector) =>
      inspector.indexes.map(_buildIndex).join(', ');

  String _buildFieldTypes(EntityInspector inspector) => inspector.fields
      .where(_fieldFilter)
      .map((field) => "'${field.name}': ${field.type.element!.name}")
      .join(', ');

  String _buildFieldAccessors(EntityInspector inspector) =>
      '{' +
      inspector.fields
          .where(_fieldFilter)
          .map((field) => "'${field.name}': (entity) => entity.${field.name}")
          .join(', ') +
      '}';

  bool _fieldFilter(FieldElement field) => !field.isStatic;

  String _buildIndex(DartObject index) =>
      'Index([${index.getField('fields')!.toListValue()!.map(_buildIndexField).join(', ')}])';

  String _buildIndexField(DartObject field) =>
      "IndexField('${field.getField('name')!.toStringValue()}', ${_directionOf(field)})";

  String _directionOf(DartObject field) =>
      field.getField('direction')!.getField('index')!.toIntValue() == 0
          ? 'Direction.ascending'
          : 'Direction.descending';

  String _buildKeyAccessor(EntityInspector inspector) => inspector.keys.isEmpty
      ? '(entity) => null'
      : inspector.keys.length == 1
          ? '(entity) => entity.${inspector.keys.first.name}'
          : '(entity) => Composite({${inspector.keys.map((field) => "'${field.name}': entity.${field.name}").join(', ')}})';

  String _generateDeserializer(EntityInspector inspector, String typeName) =>
      '$typeName(${inspector.fields.map((field) => '${field.name}: ${_deserializeType(field.type, "map['${field.name}']")}').join(', ')})';

  String _generateSerializer(EntityInspector inspector) =>
      '{${inspector.fields.map((field) => "'${field.name}': ${_serializeType(field.type, 'entity.${field.name}')}").join(', ')}}';

  String _serializeType(DartType type, String input) {
    if (_isPrimitive(type)) {
      return input;
    } else if (type.isDartCoreList) {
      return _serializeList(type as ParameterizedType, input);
    } else if (type.isDartCoreSet) {
      return _serializeSet(type as ParameterizedType, input);
    } else if (type.isDartCoreMap) {
      return _serializeMap(type as ParameterizedType, input);
    } else if (_isType(type, 'dart.core', 'DateTime')) {
      return '$input${_nullable(type)}.toIso8601String()';
    } else if (_isEnum(type.element!)) {
      return 'serializeEnum($input)';
    } else if (_isEntity(type.element!)) {
      return 'serializeEntity($input)';
    } else {
      return 'serializeDynamic($input${_nullable(type)})';
    }
  }

  String _deserializeType(DartType type, String input) {
    if (_isPrimitive(type)) {
      return input;
    } else if (type.isDartCoreList) {
      return _wrapNullable(
          type,
          input,
          _deserializeList(
              (type as ParameterizedType).typeArguments.first, input));
    } else if (type.isDartCoreSet) {
      return _wrapNullable(
          type,
          input,
          _deserializeSet(
              (type as ParameterizedType).typeArguments.first, input));
    } else if (type.isDartCoreMap) {
      return _wrapNullable(
          type,
          input,
          _deserializeMap(
            (type as ParameterizedType).typeArguments[0],
            type.typeArguments[1],
            input,
          ));
    } else if (type.isDynamic) {
      return input;
    } else if (_isType(type, 'dart.core', 'DateTime')) {
      return _wrapNullable(type, input, 'deserializeDateTime($input)');
    } else if (_isEnum(type.element!)) {
      return _wrapNullable(
          type, input, 'deserializeEnum($input, ${type.element!.name}.values)');
    } else if (_isEntity(type.element!)) {
      return _wrapNullable(
          type, input, 'deserializeEntity<${type.element!.name}>($input)');
    } else {
      return _wrapNullable(
          type, input, '${type.element!.name}.fromJson($input)');
    }
  }

  String _wrapNullable(DartType type, String input, String output) =>
      type.nullabilitySuffix == NullabilitySuffix.question
          ? '$input != null ? $output : null'
          : output;

  bool _isPrimitive(DartType type) {
    return type.isDartCoreBool ||
        type.isDartCoreString ||
        type.isDartCoreInt ||
        type.isDartCoreDouble ||
        type.isDartCoreNum;
  }

  bool _isType(DartType type, String library, String typeName) =>
      type.element!.library!.name == library && type.element!.name == typeName;

  bool _isEntity(Element element) => element.metadata.any((metadata) =>
      _isType(metadata.computeConstantValue()!.type!, 'box.core', 'Entity'));

  String _deserializeList(DartType type, String input) => '$input != null '
      '? List<${type.element!.name}>.from($input!.map((element) => '
      '${_deserializeType(type, 'element')})) '
      ': <${type.element!.name}>[]';

  String _deserializeSet(DartType type, String input) => '$input != null '
      '? Set<${type.element!.name}>.from($input!.map((element) => '
      '${_deserializeType(type, 'element')})) '
      ': <${type.element!.name}>{}';

  String _deserializeMap(DartType keyType, DartType valueType, String input) =>
      '$input != null '
      '? $input!.map((key, value) => '
      'MapEntry(key, ${_deserializeType(keyType, 'value')})) '
      ': <${keyType.element!.name}, ${valueType.element!.name}>{}';

  String _serializeList(ParameterizedType type, String input) {
    return '$input${_nullable(type)}.map((element) => '
        '${_serializeType(type.typeArguments.first, 'element')})'
        '.toList()';
  }

  String _serializeSet(ParameterizedType type, String input) =>
      '$input${_nullable(type)}.map((element) => '
      '${_serializeType(type.typeArguments.first, 'element')})'
      '.toSet()';

  String _serializeMap(ParameterizedType type, String input) =>
      '$input${_nullable(type)}.map((key, value) => '
      'MapEntry(key, ${_serializeType(type.typeArguments.first, 'value')}))';

  bool _isEnum(Element element) =>
      element is ClassElement && element.isDartCoreEnum;

  String _nullable(DartType type) =>
      type.nullabilitySuffix == NullabilitySuffix.none ? '' : '?';
}

class EntityInspector extends SimpleElementVisitor<void> {
  final List<FieldElement> keys = [];
  final List<FieldElement> fields = [];
  final List<DartObject> indexes = [];
  MethodElement? serializer;
  ConstructorElement? deserializer;

  @override
  void visitFieldElement(FieldElement element) {
    if (!element.isSynthetic && !element.hasMeta(Transient)) {
      fields.add(element);
      if (element.metadata.any(_isKey)) {
        keys.add(element);
      }
    }
  }

  bool _isKey(ElementAnnotation element) {
    var value = element.computeConstantValue();
    return value!.type!.element!.library!.name == 'box.core' &&
        value.type!.element!.name == 'Key';
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

  @override
  void visitClassElement(ClassElement element) {
    element.metadata.forEach((metadata) {
      var value = metadata.computeConstantValue();
      if (value!.type!.element!.library!.name == 'box.core' &&
          value.type!.element!.name == 'Index') {
        indexes.add(value);
      }
    });
  }
}
