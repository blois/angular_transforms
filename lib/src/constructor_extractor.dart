library angular_transformers.constructor_extractor;

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'asset_sources.dart';

class ConstructorsInfo {
  final AssetId id;
  final List<ImportDirective> imports = <ImportDirective>[];
  final List<Constructor> constructors = <Constructor>[];

  ConstructorsInfo(this.id);

  void writeImports(StringSink sink, String prefix) {
    // All non-library files should be filtered elsewhere.
    if (!id.path.startsWith('lib/')) {
      throw new StateError('Asset is not in a library.');
    }

    var baseUri = Uri.parse('package:${id.package}/${id.path.substring(4)}');

    sink.write('import \'dart:core\' as $prefix;\n');
    sink.write('import \'$baseUri\' as $prefix;\n');

    for (var imprt in imports) {
      var importPrefix =
          imprt.prefix == null ? prefix : '${prefix}_${imprt.prefix.name}';

      var uri = baseUri.resolve(imprt.uri.stringValue);
      sink.write('import \'$uri\' as $importPrefix;\n');
    }
  }

  void writeGenerators(StringSink sink, String prefix) {
    for (var constructor in constructors) {
      sink.write('  $prefix.${constructor.typeName}: (f) =>');
      sink.write(' new $prefix.${constructor.typeName}(');

      var params = [];
      for (var param in constructor.parameters) {
        var paramType = _resolveParameterType(constructor.clazz, param);
        var typeName;
        if (paramType.name is PrefixedIdentifier) {
          typeName = '${prefix}_${paramType.name.prefix.name}.'
              '${paramType.name.identifier.name}';
        } else {
          typeName = '${prefix}.${paramType.name}';
        }
        params.add('f($typeName)');
      }
      sink.write(params.join(', '));
      sink.write('),\n');
    }
  }
}

abstract class Constructor {
  List<FormalParameter> get parameters;
  String get typeName;
}

class _ASTConstructor implements Constructor {
  final ConstructorDeclaration constructor;
  _ASTConstructor(this.constructor);

  List<FormalParameter> get parameters => constructor.parameters.parameters;
  String get typeName => constructor.parent.name.name;
  ClassDeclaration get clazz => constructor.parent;
}

// Placeholder for implicit constructors since they are not in the AST.
class _ImplicitConstructor implements Constructor {
  final ClassDeclaration clazz;
  _ImplicitConstructor(this.clazz);

  String get typeName => clazz.name.name;

  List<FormalParameter> get parameters => [];
}

ConstructorsInfo gatherConstructors(DartSource source,
    TransformOptions options) {
  var visitor = new _ASTVisitor(new ConstructorsInfo(source.assetId), source,
      options);

  for (var compilationUnit in source.compilationUnits) {
    compilationUnit.visitChildren(visitor);
  }

  if (!visitor.info.constructors.isEmpty) {
    if (!_canImport(visitor.info.id)) {
      var cls = visitor.info.constructors.first.clazz;
      source.logger.warning('${cls.name.name} cannot be injected because '
          'the containing file cannot be imported.',
          asset: source.assetId, span: source.getSpan(cls));
      return null;
    }
    return visitor.info;
  }
  return null;
}

class _ASTVisitor extends GeneralizingASTVisitor {
  final ConstructorsInfo info;
  final DartSource source;
  final TransformOptions options;

  _ASTVisitor(this.info, this.source, this.options);

  // Skip everything other than imports and classes.
  visitNode(ASTNode node) {}

  visitImportDirective(ImportDirective node) {
    info.imports.add(node);
  }

  visitClassDeclaration(ClassDeclaration cls) {
    var constructors = cls.members.where(
        (m) => m is ConstructorDeclaration &&
        hasInjectAnnotation(m));

    if (constructors.length == 0) {
      // Only continue if inject annotation is on the class.
      if (!hasInjectAnnotation(cls) &&
          !options.isInjectableType(getFullName(cls))) {
        return;
      }
      // If the annotation is on the class then we use the default
      // constructor.
      var constructor = _getConstructor(cls, null);
      // If the class is abstract then it must have a factory constructor.
      if (cls.abstractKeyword != null &&
          (constructor == null || constructor.factoryKeyword == null)) {
        source.logger.warning('${cls.name.name} cannot be injected '
            'because it is an abstract type with no factory constructor.',
            asset: source.assetId, span: source.getSpan(cls));
        return;
      }
      if (constructor == null) {
        if (cls.members.where((m) => m is ConstructorDeclaration).length > 0) {
          source.logger.warning('${cls.name.name} does not have a default '
              'constructor',
              asset: source.assetId, span: source.getSpan(cls));
          return;
        }
        // Add a dummy implicit constructor.
        info.constructors.add(new _ImplicitConstructor(cls));
      } else {
        if (validateConstructor(cls, constructor)) {
          info.constructors.add(new _ASTConstructor(constructor));
        }
      }
      return;
    }
    if (constructors.length > 1) {
      source.logger.warning('${cls.name.name} can only have a single '
          'injected constructor.',
          asset: source.assetId, span: source.getSpan(cls));
      return;
    }
    var constructor = constructors.single;
    if (constructor.name != null) {
      source.logger.warning('Named constructors cannot be injected.',
          asset: source.assetId, span: source.getSpan(constructor));
      return;
    }
    if (!validateConstructor(cls, constructor)) {
      return;
    }
    info.constructors.add(new _ASTConstructor(constructor));
  }

  bool validateConstructor(ClassDeclaration cls,
      ConstructorDeclaration constructor) {
    if (isParameterized(cls)) {
      source.logger.warning('${cls.name} cannot be injected because it is a '
          'parameterized type.',
          asset: source.assetId, span: source.getSpan(cls));
      return false;
    }
    for (var param in constructor.parameters.parameters) {
      var type = _resolveParameterType(cls, param);
      if (type == null) {
        source.logger.warning('${cls.name} cannot be injected '
          'because parameter type $param cannot be resolved.',
          asset: source.assetId, span: source.getSpan(param));
        return false;
      }
      if (type.typeArguments != null) {
        source.logger.warning('${cls.name} cannot be injected '
          'because $param is a parameterized type.',
          asset: source.assetId, span: source.getSpan(param));
        return false;
      }
    }
    return true;
  }

  bool isParameterized(ClassDeclaration cls) => cls.typeParameters != null;

  bool hasInjectAnnotation(AnnotatedNode node) =>
    node.metadata.any(isInjectAnnotation);

  // This isn't correct if the annotation has been imported with a prefix, or
  // cases like that. We should technically be resolving, but that is expensive
  // in analyzer, so it isn't feasible yet.
  bool isInjectAnnotation(Annotation node) =>
      isAnnotationConstant(node, 'inject') ||
      options.injectableAnnotations.any((a) =>
          (isAnnotationConstant(node, a) || isAnnotationType(node, a)));

  bool isAnnotationConstant(Annotation m, String name) =>
      m.name.name == name && m.constructorName == null && m.arguments == null;

  bool isAnnotationType(Annotation m, String name) => m.name.name == name;

  String getFullName(ClassDeclaration cls) {
    var name = cls.name.name;
    var parent = cls.parent;

    var libs = parent.directives.where((c) => c is LibraryDirective);
    if (libs.isEmpty) {
      return name;
    }
    return '${libs.single.name.name}.$name';
  }
}

bool _canImport(AssetId id) => id.path.startsWith('lib/');

TypeName _resolveParameterType(ClassDeclaration cls,
    FormalParameter parameter) {
  if (parameter is FieldFormalParameter) {
    if (parameter.type != null) return parameter.type;

    var field = _getField(cls, parameter.identifier.name);
    if (field == null) {
      return null;
    }
    return field.parent.type;
  } else if (parameter is DefaultFormalParameter) {
    return _resolveParameterType(cls, parameter.parameter);
  }
  return parameter.type;
}

// TODO: replace with ClassDeclaration.getField once we can move to
// analyzer V 0.11+
VariableDeclaration _getField(ClassDeclaration cls, String name) {
  for (ClassMember classMember in cls.members) {
    if (classMember is FieldDeclaration) {
      FieldDeclaration fieldDeclaration = classMember;
      NodeList<VariableDeclaration> fields = fieldDeclaration.fields.variables;
      for (VariableDeclaration field in fields) {
        SimpleIdentifier fieldName = field.name;
        if (fieldName != null && name == fieldName.name) {
          return field;
        }
      }
    }
  }
  return null;
}

// TODO: replace with ClassDeclaration.getConstructor once we can move to
// analyzer V 0.11+
ConstructorDeclaration _getConstructor(ClassDeclaration cls, String name) {
  for (ClassMember classMember in cls.members) {
    if (classMember is ConstructorDeclaration) {
      ConstructorDeclaration constructor = classMember;
      SimpleIdentifier constructorName = constructor.name;
      if (name == null && constructorName == null) {
        return constructor;
      }
      if (constructorName != null && constructorName.name == name) {
        return constructor;
      }
    }
  }
  return null;
}
