library angular_transformers.metadata_extractor;

import 'package:analyzer/src/generated/ast.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'asset_libraries.dart';
import 'common.dart';

class LibraryInfo {
  final AssetId assetId;
  final List<AnnotatedClass> classes = <AnnotatedClass>[];
  final List<ImportDirective> imports = <ImportDirective>[];

  LibraryInfo(this.assetId);

  void writeImports(StringSink sink, String prefix) {
    var hasClassAnnotations = classes.any((c) => !c.annotations.isEmpty);
    if (hasClassAnnotations) {
      sink.write('import \'dart:core\' as $prefix;\n');
    }
    var baseUri =
        Uri.parse('package:${assetId.package}/${assetId.path.substring(4)}');
    sink.write('import \'$baseUri\' as $prefix;\n');

    if (!hasClassAnnotations) return;

    for (var imprt in imports) {
      var importPrefix =
          imprt.prefix == null ? prefix : '${prefix}_${imprt.prefix.name}';

      var uri = baseUri.resolve(imprt.uri.stringValue);
      sink.write('import \'$uri\' as $importPrefix;\n');
    }
  }

  void writeClassAnnotations(StringSink sink, String prefix) {
    for (var cls in classes) {
      cls.writeClassAnnotations(sink, prefix);
    }
  }

  void writeMemberAnnotations(StringSink sink, String prefix) {
    for (var cls in classes) {
      cls.writeMemberAnnotations(sink, prefix);
    }
  }
}

class AnnotatedClass {
  final ClassDeclaration cls;
  final Map<String, AnnotationInfo> members = {};
  final List<AnnotationInfo> annotations = [];

  AnnotatedClass(this.cls);

  void writeClassAnnotations(StringSink sink, String prefix) {
    if (annotations.isEmpty) return;

    sink.write('  $prefix.${cls.name}: [\n');
    for (var annotation in annotations) {
      var ann = annotation.toString().substring(1);
      if (annotation.arguments != null) {
        sink.write('    const $prefix.$ann,\n');
      } else {
        sink.write('    $prefix.$ann,\n');
      }
    }
    sink.write('  ],\n');
  }

  void writeMemberAnnotations(StringSink sink, String prefix) {
    if (members.isEmpty) return;

    sink.write('  $prefix.${cls.name}: {\n');
    for (var member in members.keys) {
      var ann = members[member].toString().substring(1);
      sink.write('    \'$member\': const $ann,\n');
    }
    sink.write('  },\n');
  }
}

LibraryInfo gatherAnnotatedLibraries(DartLibrary lib, TransformOptions options) {
  var visitor = new _ASTVisitor(new LibraryInfo(lib.assetId), lib,
      options);

  for (var compilationUnit in lib.compilationUnits) {
    compilationUnit.visitChildren(visitor);
  }

  if (!visitor.lib.classes.isEmpty) {
    if (!canImportAsset(lib.assetId)) {
      var cls = visitor.lib.classes.first.cls;
      lib.logger.warning('${visitor.lib.assetId} cannot contain annotated '
          'because it cannot be imported (must be in a lib folder).',
          asset: lib.assetId, span: lib.getSpan(cls));
      return null;
    }
    return visitor.lib;
  }
  return null;
}

class _ASTVisitor extends GeneralizingASTVisitor {
  final LibraryInfo lib;
  final DartLibrary source;
  final TransformOptions options;

  _ASTVisitor(this.lib, this.source, this.options);

  // Skip everything other than imports and classes.
  visitNode(ASTNode node) {}

  visitImportDirective(ImportDirective node) {
    lib.imports.add(node);
  }

  visitClassDeclaration(ClassDeclaration cls) {
    var annotatedClass = null;
    if (!cls.metadata.isEmpty) {
      annotatedClass = new AnnotatedClass(cls);
      lib.classes.add(annotatedClass);
      for (var annotation in cls.metadata) {
        annotatedClass.annotations.add(annotation);
      }
    }

    for (var member in cls.members) {
      for (var annotation in member.metadata) {
        if (isAngularMetadata(annotation)) {
          var added = false;
          if (annotatedClass == null) {
            annotatedClass = new AnnotatedClass(cls);
            lib.classes.add(annotatedClass);
          }
          var memberName;

          if (member is FieldDeclaration) {
            FieldDeclaration fieldDeclaration = member;
            var fields = fieldDeclaration.fields.variables;
            for (var field in fields) {
              var fieldName = field.name.name;
              if (fieldName != null) {
                memberName = fieldName;
                break;
              }
            }
          }
          else if (member is MethodDeclaration) {
            memberName = member.name.name;
          }

          if (memberName == null) {
            print('FAILED ${member.runtimeType} ${member} has ${annotation}');
          }

          if (annotatedClass.members.containsKey(memberName)) {
            source.logger.warning('$memberName can only have one annotation.',
                asset: lib.assetId, span: source.getSpan(member));
          }
          annotatedClass.members[memberName] = annotation;
        }
      }
    }
  }

  static Set<String> _ngAnnotations = new Set<String>.from([
    'NgAttr',
    'NgOneWay',
    'NgOneWayOneTime',
    'NgTwoWay',
    'NgCallback'
  ]);
  bool isAngularMetadata(Annotation annotation) =>
      _ngAnnotations.contains(annotation.name.name);
}