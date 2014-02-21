library angular_transformers.injector_generator;

import 'dart:async';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart';

import 'common.dart';
import 'resolver.dart';
import 'resolver_transformer.dart';

const String _generateInjector = 'generated_static_injector.dart';

class InjectorGenerator extends Transformer {
  final TransformOptions options;
  final ResolverTransformer resolvers;
  TransformLogger _logger;
  Resolver _resolver;
  List<TopLevelVariableElement> _injectableMetaConsts;
  List<ConstructorElement> _injectableMetaConstructors;
  List<FunctionElement> _invokableClosures;

  InjectorGenerator(this.options, this.resolvers);

  Future<bool> isPrimary(Asset input) =>
      new Future.value(options.isDartEntry(input.id));

  Future apply(Transform transform) {
    _logger = transform.logger;
    _resolver = this.resolvers.getResolver(transform.primaryInput.id);

    return _resolver.updateSources(transform).then((_) {
      _resolveInjectableMetadata();
      var constructors = _gatherConstructors();

      var closures = _gatherInjectedClosures();

      var injectLibContents = _generateInjectLibrary(constructors, closures);

      var outputId = new AssetId(transform.primaryInput.id.package,
          'lib/$_generateInjector');
      transform.addOutput(new Asset.fromString(outputId, injectLibContents));

      _transformAsset(transform);

      _logger = null;
      _resolver = null;
    });
  }

  /** Default list of injectable consts */
  static const List<String> _defaultInjectableMetaConsts = const [
    'inject.inject'
  ];

  /** Resolves the classes for the injectable annotations in the current AST. */
  void _resolveInjectableMetadata() {
    _injectableMetaConsts = <TopLevelVariableElement>[];
    _injectableMetaConstructors = <ConstructorElement>[];
    _invokableClosures = <FunctionElement>[];

    for (var constName in _defaultInjectableMetaConsts) {
      var variable = _resolver.getLibraryVariable(constName);
      if (variable != null) {
        _injectableMetaConsts.add(variable);
      }
    }

    for (var metaName in options.injectableAnnotations) {
      var variable = _resolver.getLibraryVariable(metaName);
      if (variable != null) {
        _injectableMetaConsts.add(variable);
        continue;
      }
      var cls = _resolver.getType(metaName);
      if (cls != null && cls.unnamedConstructor != null) {
        _injectableMetaConstructors.add(cls.unnamedConstructor);
        continue;
      }
      _logger.warning('Unable to resolve injectable annotation $metaName');
    }

    for (var name in options.invokableClosureMethods) {
      var fn = _resolver.getLibraryFunction(name);
      if (fn == null) {
        _logger.warning('Unable to resolve invokable closure method $name');
        continue;
      }
      if (fn.parameters.length != 1) {
        _logger.warning('Injectable closure must take a single parameter',
            asset: _resolver.getSourceAssetId(fn),
            span: _resolver.getSourceSpan(fn));
        continue;
      }
      _invokableClosures.add(fn);
    }
  }

  /** Finds all annotated constructors or annotated classes in the program. */
  Iterable<ConstructorElement> _gatherConstructors() {
    var constructors = _resolver.libraries
        .expand((lib) => lib.units)
        .expand((compilationUnit) => compilationUnit.types)
        .map(_findInjectedConstructor)
        .where((ctor) => ctor != null).toList();

    constructors.addAll(_gatherInjectablesContents());
    constructors.addAll(_gatherManuallyInjected());

    return constructors.toSet();
  }

  /**
   * Get the constructors for all elements in the library @Injectables
   * statements. These are used to mark types as injectable which would
   * otherwise not be injected.
   *
   * Syntax is:
   *
   *     @Injectables(const[ElementName])
   *     library my.library;
   */
  Iterable<ConstructorElement> _gatherInjectablesContents() {
    var injectablesClass = _resolver.getType('di.annotations.Injectables');
    if (injectablesClass == null) return const [];
    var injectablesCtor = injectablesClass.unnamedConstructor;

    var ctors = [];

    for (var lib in _resolver.libraries) {
      var annotationIdx = 0;
      for (var annotation in lib.metadata) {
        if (annotation.element == injectablesCtor) {
          var libDirective = lib.definingCompilationUnit.node.directives
              .where((d) => d is LibraryDirective).single;
          var annotationDirective = libDirective.metadata[annotationIdx];
          var listLiteral = annotationDirective.arguments.arguments.first;

          for (var expr in listLiteral.elements) {
            var element = (expr as SimpleIdentifier).bestElement;
            if (element == null || element is! ClassElement) {
              _logger.warning('Unable to resolve class $expr',
                  asset: _resolver.getSourceAssetId(element),
                  span: _resolver.getSourceSpan(element));
              continue;
            }
            var ctor = _findInjectedConstructor(element, true);
            if (ctor != null) {
              ctors.add(ctor);
            }
          }
        }
      }
    }
    return ctors;
  }

  Iterable<ConstructorElement> _gatherManuallyInjected() {
    var ctors = [];
    for (var injectedName in options.injectedTypes) {
      var injectedClass = _resolver.getType(injectedName);
      if (injectedClass == null) {
        _logger.warning('Unable to resolve injected type name $injectedName');
        continue;
      }
      var ctor = _findInjectedConstructor(injectedClass, true);
      if (ctor != null) {
        ctors.add(ctor);
      }
    }
    return ctors;
  }

  /**
   * Checks if the element is annotated with one of the known injectablee
   * annotations.
   */
  bool _isElementAnnotated(Element e) {
    for (var meta in e.metadata) {
      if (meta.element is PropertyAccessorElement &&
          _injectableMetaConsts.contains(meta.element.variable)) {
        return true;
      } else if (meta.element is ConstructorElement &&
          _injectableMetaConstructors.contains(meta.element)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Find an 'injected' constructor for the given class.
   * If [noAnnotation] is true then this will assume that the class is marked
   * for injection and will use the default constructor.
   */
  ConstructorElement _findInjectedConstructor(ClassElement cls,
      [bool noAnnotation = false]) {
    var classInjectedConstructors = [];
    if (_isElementAnnotated(cls) || noAnnotation) {
      var defaultConstructor = cls.unnamedConstructor;
      if (defaultConstructor == null) {
        _logger.warning('${cls.name} cannot be injected because '
            'it does not have a default constructor.',
            asset: _resolver.getSourceAssetId(cls),
            span: _resolver.getSourceSpan(cls));
      } else {
        classInjectedConstructors.add(defaultConstructor);
      }
    }

    classInjectedConstructors.addAll(
        cls.constructors.where(_isElementAnnotated));

    if (classInjectedConstructors.isEmpty) return null;
    if (classInjectedConstructors.length > 1) {
      _logger.warning('${cls.name} has more than one constructor annotated for '
          'injection.',
          asset: _resolver.getSourceAssetId(cls),
          span: _resolver.getSourceSpan(cls));
      return null;
    }

    var ctor = classInjectedConstructors.single;
    if (!_validateConstructor(ctor)) return null;

    return ctor;
  }

  /**
   * Validates that the constructor is injectable and emits warnings for any
   * errors.
   */
  bool _validateConstructor(ConstructorElement ctor) {
    var cls = ctor.enclosingElement;
    if (cls.isAbstract && !ctor.isFactory) {
      _logger.warning('${cls.name} cannot be injected because '
          'it is an abstract type with no factory constructor.',
          asset: _resolver.getSourceAssetId(cls),
          span: _resolver.getSourceSpan(cls));
      return false;
    }
    if (cls.isPrivate) {
      _logger.warning('${cls.name} cannot be injected because it is a private '
          'type.',
          asset: _resolver.getSourceAssetId(cls),
          span: _resolver.getSourceSpan(cls));
      return false;
    }
    if (_resolver.getImportUri(cls.library) == null) {
      _logger.warning('${cls.name} cannot be injected because '
          'the containing file cannot be imported.',
          asset: _resolver.getSourceAssetId(ctor),
          span: _resolver.getSourceSpan(ctor));
      return false;
    }
    if (!cls.typeParameters.isEmpty) {
      _logger.warning('${cls.name} is a parameterized type.',
          asset: _resolver.getSourceAssetId(ctor),
          span: _resolver.getSourceSpan(ctor));
      // Only warn.
    }
    if (ctor.name != '') {
      _logger.warning('Named constructors cannot be injected.',
          asset: _resolver.getSourceAssetId(ctor),
          span: _resolver.getSourceSpan(ctor));
      return false;
    }
    return _validateExecutableElement(ctor);
  }

  bool _validateExecutableElement(ExecutableElement e) {
    for (var param in e.parameters) {
      var type = param.type;
      if (type is InterfaceType &&
          type.typeArguments.any((t) => !t.isDynamic)) {
        _logger.warning('$e cannot be injected because '
            '${param.type} is a parameterized type.',
            asset: _resolver.getSourceAssetId(e),
            span: _resolver.getSourceSpan(e));
        return false;
      }
      if (type.isDynamic) {
        _logger.warning('$e cannot be injected because parameter type '
          '${param.name} cannot be resolved.',
            asset: _resolver.getSourceAssetId(e),
            span: _resolver.getSourceSpan(e));
        return false;
      }
    }
    return true;
  }

  /**
   * Creates a library file for the specified constructors.
   */
  String _generateInjectLibrary(Iterable<ConstructorElement> constructors,
      Iterable<_TypedefInfo> typedefs) {
    var outputBuffer = new StringBuffer();

    _writeStaticInjectorHeader(_resolver.entryPoint, outputBuffer);

    var prefixes = <LibraryElement, String>{};

    var ctorTypes = constructors.map((ctor) => ctor.enclosingElement).toSet();
    var paramTypes = constructors.expand((ctor) => ctor.parameters)
        .map((param) => param.type.element).toSet();
    var typedefTypes = typedefs.expand((t) => t.parameters).toSet();

    var libs = ctorTypes..addAll(paramTypes)..addAll(typedefTypes);
    libs = libs.map((type) => type.library).toSet();

    for (var lib in libs) {
      if (lib.isDartCore) {
        prefixes[lib] = '';
      } else {
        var prefix = 'import_${prefixes.length}';
        var uri = _resolver.getImportUri(lib);
        outputBuffer.write('import \'$uri\' as $prefix;\n');
        prefixes[lib] = '$prefix.';
      }
    }

    _writePreamble(outputBuffer);

    for (var ctor in constructors) {
      var type = ctor.enclosingElement;
      var typeName = '${prefixes[type.library]}${type.name}';
      outputBuffer.write('  $typeName: (f) => new $typeName(');
      var params = ctor.parameters.map((param) {
        var type = param.type.element;
        var typeName = '${prefixes[type.library]}${type.name}';
        return 'f($typeName)';
      });
      outputBuffer.write('${params.join(', ')}),\n');
    }

    _writeTypeFactoryFooter(outputBuffer);

    var index = 0;
    for (var td in typedefs) {
      outputBuffer.write('typedef td_${index++}(');
      var paramIdx = 0;
      var params = td.parameters.map((param) {
        var type = param.type.element;
        return '${prefixes[type.library]}${type.name} p${paramIdx++}';
      });
      outputBuffer.write('${params.join(', ')});\n');
    }

    _writeClosureInjectorHeader(outputBuffer);
    index = 0;
    for (var td in typedefs) {
      outputBuffer.write('  if (fn is td_${index++}) return (f) => fn(');
      var params = td.parameters.map((param) {
        var type = param.type.element;
        var typeName = '${prefixes[type.library]}${type.name}';
        return 'f($typeName)';
      });
      outputBuffer.write('${params.join(', ')});\n');
    }
    _writeClosureInjectorFooter(outputBuffer);

    return outputBuffer.toString();
  }

  /**
   * Modify the primary asset of the transform to import the generated source
   * and modify all references to defaultInjector to refer to the generated
   * static injector.
   */
  void _transformAsset(Transform transform) {
    var autoInjector = _resolver.getLibraryFunction(
        'angular_transformers.auto_modules.defaultInjector');

    if (autoInjector == null) {
      _logger.info('Unable to resolve defaultInjector, not transforming '
          'entry point.');
      transform.addOutput(transform.primaryInput);
      return;
    }

    var lib = _resolver.entryLibrary;
    var transaction = _resolver.createTextEditTransaction(lib);

    var unit = lib.definingCompilationUnit.node;
    transformMethodInvocations(transaction, unit, autoInjector,
        'generated_static_injector.createStaticInjector');

    if (transaction.hasEdits) {
      var id = transform.primaryInput.id;

      addImport(transaction, unit,
          'package:${id.package}/$_generateInjector',
          'generated_static_injector');

      var printer = transaction.commit();
      var url = id.path.startsWith('lib/')
          ? 'package:${id.package}/${id.path.substring(4)}' : id.path;
      printer.build(url);
      transform.addOutput(new Asset.fromString(id, printer.text));
    } else {
      transform.addOutput(transform.primaryInput);
    }
  }

  Iterable<_TypedefInfo> _gatherInjectedClosures() {
    var methods = [];
    var visitor = new _MethodInvocationVisitor((node) {
      var element = node.methodName.bestElement;
      if (_invokableClosures.contains(element)) {
        methods.add(node);
      }
    });
    for (var lib in _resolver.libraries) {
      lib.definingCompilationUnit.node.accept(visitor);
    }

    return methods.map(_extractTypedef)
        .where((t) => t != null)
        .toList();
  }

  _TypedefInfo _extractTypedef(MethodInvocation invocation) {
    var args = invocation.argumentList;
    if (args.arguments.length != 1) {
      _logger.warning('$invocation cannot be injected because '
          'it must have a single argument.',
          asset: _resolver.getNodeSourceAssetId(invocation),
          span: _resolver.getNodeSourceSpan(invocation));
      return null;
    }
    var closure = args.arguments.single;
    if (closure is! FunctionExpression) {
      _logger.warning('$closure cannot be injected because '
          'the argument must be a function literal.',
          asset: _resolver.getNodeSourceAssetId(closure),
          span: _resolver.getNodeSourceSpan(closure));
      return null;
    }
    var functionElement = closure.element;
    if (!_validateExecutableElement(functionElement)) return null;

    return new _TypedefInfo(functionElement);
  }
}

class _MethodInvocationVisitor extends GeneralizingASTVisitor {
  final Iterable<FunctionElement> invokableClosures;
  final List<MethodInvocation> methods = <MethodInvocation>[];

  final Function callback;

  _MethodInvocationVisitor(void callback(MethodInvocation node)) :
      callback = callback;

  visitMethodInvocation(MethodInvocation node) {
    callback(node);
    return super.visitMethodInvocation(node);
  }
}

class _TypedefInfo {
  final List<ClassElement> parameters;
  _TypedefInfo(FunctionElement e):
      parameters = e.parameters.map((param) => param.type.element).toList();

  bool operator == (var other) {
    if (other != _TypedefInfo) return false;

    if (other.parameters.length != parameters.length) return false;

    for (var i = 0; i < parameters.length; ++i) {
      if (parameters[i] != other.parameters[i]) return false;
    }
    return true;
  }

  int get hashCode => parameters.fold(
          parameters.length * 7, (hash, type) => hash ^ type.hashCode);
}

void _writeStaticInjectorHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  sink.write('''
library ${id.package}.$libPath.generated_static_injector;

import 'package:di/di.dart';
import 'package:di/static_injector.dart';

@MirrorsUsed(override: const [
    'di.dynamic_injector',
    'mirrors',
    'di.src.reflected_type'])
import 'dart:mirrors';
''');
}

void _writePreamble(StringSink sink) {
  sink.write('''
Injector createStaticInjector({List<Module> modules, String name,
    bool allowImplicitInjection: false}) =>
  new StaticInjector(modules: modules, name: name,
      allowImplicitInjection: allowImplicitInjection,
      typeFactories: factories,
      closureSource: closures);

Module get staticInjectorModule => new Module()
    ..value(Injector, createStaticInjector(name: 'Static Injector'));

final Map<Type, TypeFactory> factories = <Type, TypeFactory>{
''');
}

void _writeTypeFactoryFooter(StringSink sink) {
  sink.write('''
};
''');
}

void _writeClosureInjectorHeader(StringSink sink) {
  sink.write('''

ClosureInvoker closures(Function fn) {
''');
}

void _writeClosureInjectorFooter(StringSink sink) {
sink.write('''  return null;
}
''');
}
