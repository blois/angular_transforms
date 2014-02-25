library angular_transformers.metadata_extractor;

import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';

class AnnotatedType {
  final ClassElement type;
  Iterable<Annotation> annotations;

  final Map<String, Annotation> members = <String, Annotation>{};

  AnnotatedType(this.type);

  /**
   * Finds all the libraries referenced by the annotations
   */
  Iterable<LibraryElement> get referencedLibraries {
    var libs = new Set();
    libs.add(type.library);

    var libCollector = new _LibraryCollector();
    for (var annotation in annotations) {
      annotation.accept(libCollector);
    }
    for (var annotation in members.values) {
      annotation.accept(libCollector);
    }
    libs.addAll(libCollector.libraries);

    return libs;
  }

  void writeClassAnnotations(StringBuffer sink, TransformLogger logger,
      Resolver resolver, Map<LibraryElement, String> prefixes) {
    sink.write('  ${prefixes[type.library]}${type.name}: [\n');
    var writer = new _AnnotationWriter(sink, prefixes);
    for (var annotation in annotations) {
      sink.write('    ');
      if (writer.writeAnnotation(annotation)) {
        sink.write(',\n');
      } else {
        sink.write('null,\n');
        logger.warning('Unable to serialize annotation $annotation.',
            asset: resolver.getSourceAssetId(annotation.parent.element),
            span: resolver.getSourceSpan(annotation.parent.element));
      }
    }
    sink.write('  ],\n');
  }

  void writeMemberAnnotations(StringBuffer sink, TransformLogger logger,
      Resolver resolver, Map<LibraryElement, String> prefixes) {
    if (members.isEmpty) return;

    sink.write('  ${prefixes[type.library]}${type.name}: {\n');

    var writer = new _AnnotationWriter(sink, prefixes);
    members.forEach((memberName, annotation) {
      sink.write('    \'$memberName\': ');
      if (writer.writeAnnotation(annotation)) {
        sink.write(',\n');
      } else {
        sink.write('null,\n');
        logger.warning('Unable to serialize annotation $annotation.',
            asset: resolver.getSourceAssetId(annotation.parent.element),
            span: resolver.getSourceSpan(annotation.parent.element));
      }
    });
    sink.write('  },\n');
  }
}

/**
 * Helper which finds all libraries referenced within the provided AST.
 */
class _LibraryCollector extends GeneralizingASTVisitor {
  final Set<LibraryElement> libraries = new Set<LibraryElement>();
  void visitSimpleIdentifier(SimpleIdentifier s) {
    var element = s.bestElement;
    if (element != null) {
      libraries.add(element.library);
    }
  }
}

/**
 * Helper class which writes annotations out to the buffer.
 * This does not support every syntax possible, but will return false when
 * the annotation cannot be serialized.
 */
class _AnnotationWriter {
  final StringBuffer sink;
  final Map<LibraryElement, String> prefixes;

  _AnnotationWriter(this.sink, this.prefixes);

  /**
   * Returns true if the annotation was successfully serialized.
   * If the annotation could not be written then the buffer is returned to its
   * original state.
   */
  bool writeAnnotation(Annotation annotation) {
    // Record the current location in the buffer and if writing fails then
    // back up the buffer to where we started.
    var len = sink.length;
    if (!_writeAnnotation(annotation)) {
      var str = sink.toString();
      sink.clear();
      sink.write(str.substring(0, len));
      return false;
    }
    return true;
  }

   bool _writeAnnotation(Annotation annotation) {
    var element = annotation.element;
    if (element is ConstructorElement) {
      sink.write('const ${prefixes[element.library]}'
          '${element.enclosingElement.name}');
      // Named constructors
      if (!element.name.isEmpty) {
        sink.write('.${element.name}');
      }
      sink.write('(');
      if (!_writeArguments(annotation)) return false;
      sink.write(')');
      return true;
    } else if (element is PropertyAccessorElement) {
      sink.write('${prefixes[element.library]}${element.name}');
      return true;
    }

    return false;
  }

  /** Writes the arguments for a type constructor. */
  bool _writeArguments(Annotation annotation) {
    var args = annotation.arguments;
    var index = 0;
    for (var arg in args.arguments) {
      if (arg is NamedExpression) {
        sink.write('${arg.name.label.name}: ');
        if (!_writeExpression(arg.expression)) return false;
      } else {
        if (!_writeExpression(arg)) return false;
      }
      if (++index < args.arguments.length) {
        sink.write(', ');
      }
    }
    return true;
  }

  /** Writes an expression. */
  bool _writeExpression(Expression expression) {
    if (expression is StringLiteral) {
      var str = expression.stringValue
          .replaceAll(r'\', r'\\')
          .replaceAll('\'', '\\\'');
      sink.write('\'$str\'');
      return true;
    }
    if (expression is ListLiteral) {
      sink.write('const [');
      for (var element in expression.elements) {
        if (!_writeExpression(element)) return false;
        sink.write(',');
      }
      sink.write(']');
      return true;
    }
    if (expression is MapLiteral) {
      sink.write('const {');
      var index = 0;
      for (var entry in expression.entries) {
        if (!_writeExpression(entry.key)) return false;
        sink.write(': ');
        if (!_writeExpression(entry.value)) return false;
        if (++index < expression.entries.length) {
          sink.write(', ');
        }
      }
      sink.write('}');
      return true;
    }
    if (expression is Identifier) {
      var element = expression.bestElement;
      if (element == null || !element.isPublic) return false;

      if (element is ClassElement) {
        sink.write('${prefixes[element.library]}${element.name}');
        return true;
      }
      if (element is PropertyAccessorElement) {
        var variable = element.variable;
        if (variable is FieldElement) {
          var cls = variable.enclosingElement;
          sink.write('${prefixes[cls.library]}${cls.name}.${variable.name}');
          return true;
        } else if (variable is TopLevelVariableElement) {
          sink.write('${prefixes[variable.library]}${variable.name}');
          return true;
        }
        print('variable ${variable.runtimeType} $variable');
      }
      print('element ${element.runtimeType} $element');
    }
    if (expression is BooleanLiteral ||
        expression is DoubleLiteral ||
        expression is IntegerLiteral) {
      sink.write(expression.value);
      return true;
    }
    if (expression is NullLiteral) {
      sink.write('null');
      return true;
    }
    print('expression ${expression.runtimeType} $expression');
    return false;
  }
}

class AnnotationExtractor {
  final TransformLogger logger;
  final Resolver resolver;

  static const List<String> _angularAnnotationNames = const [
    'angular.core.NgAttr',
    'angular.core.NgOneWay',
    'angular.core.NgOneWayOneTime',
    'angular.core.NgTwoWay',
    'angular.core.NgCallback'
  ];

  /// Resolved annotations that this will pick up for members.
  final List<Element> _annotationElements = <Element>[];

  AnnotationExtractor(this.logger, this.resolver) {
    for (var annotation in _angularAnnotationNames) {
      var type = resolver.getType(annotation);
      if (type == null) {
        logger.warning('Unable to resolve $annotation, skipping metadata.');
        continue;
      }
      _annotationElements.add(type.unnamedConstructor);
    }
  }

  AnnotatedType extractAnnotations(ClassElement cls) {
    if (resolver.getImportUri(cls.library) == null) {
      logger.warning('Dropping annotations for ${cls.name} because the '
          'containing file cannot be imported (must be in a lib folder).',
          asset: resolver.getSourceAssetId(cls),
          span: resolver.getSourceSpan(cls));
      return null;
    }

    var visitor = new _AnnotationVisitor(_annotationElements);
    cls.node.accept(visitor);

    if (!visitor.hasAnnotations) return null;

    var type = new AnnotatedType(cls)..annotations = visitor.classAnnotations
        .where((annotation) {
          var element = annotation.element;
          if (element != null && !element.isPublic) {
            logger.warning('Annotation $annotation is not public.',
                asset: resolver.getSourceAssetId(annotation.parent.element),
                span: resolver.getSourceSpan(annotation.parent.element));
            return false;
          }
          if (element is ConstructorElement &&
              !element.enclosingElement.isPublic) {
            logger.warning('Annotation $annotation is not public.',
                asset: resolver.getSourceAssetId(annotation.parent.element),
                span: resolver.getSourceSpan(annotation.parent.element));
            return false;
          }
          return true;
        }).toList();


    visitor.memberAnnotations.forEach((memberName, annotations) {
      if (annotations.length > 1) {
        logger.warning('$memberName can only have one annotation.',
            asset: resolver.getSourceAssetId(annotations[0].parent.element),
            span: resolver.getSourceSpan(annotations[0].parent.element));
        return;
      }

      type.members[memberName] = annotations[0];
    });

    if (type.annotations.isEmpty && type.members.isEmpty) return null;

    return type;
  }
}


/**
 * AST visitor which walks the current AST and finds all annotated
 * classes and members.
 */
class _AnnotationVisitor extends GeneralizingASTVisitor {
  final List<Element> allowedMemberAnnotations;
  final List<Annotation> classAnnotations = [];
  final Map<String, List<Annotation>> memberAnnotations = {};

  _AnnotationVisitor(this.allowedMemberAnnotations);

  void visitAnnotation(Annotation annotation) {
    var parent = annotation.parent;
    if (parent is! Declaration) return;

    if (parent.element is ClassElement) {
      classAnnotations.add(annotation);
    } else if (allowedMemberAnnotations.contains(annotation.element)) {
      if (parent is MethodDeclaration) {
        memberAnnotations.putIfAbsent(parent.name.name, () => [])
            .add(annotation);
      } else if (parent is FieldDeclaration) {
        var name = parent.fields.variables.first.name.name;
        memberAnnotations.putIfAbsent(name, () => []).add(annotation);
      }
    }
  }

  bool get hasAnnotations =>
      !classAnnotations.isEmpty || !memberAnnotations.isEmpty;
}
