library angular_transformers.expression_generator;

import 'dart:async';
import 'dart:math' as math;
import 'package:analyzer/src/generated/element.dart';
import 'package:angular/core/module.dart';
import 'package:angular/core/parser/parser.dart';
import 'package:angular/tools/html_extractor.dart';
import 'package:angular/tools/parser_getter_setter/generator.dart';
import 'package:angular/tools/source_crawler.dart';
import 'package:angular/tools/source_metadata_extractor.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';
import 'package:path/path.dart' as path;

import 'common.dart';
import 'resolver.dart';
import 'resolver_transformer.dart';

const String _generatedExpressionFilename = 'generated_static_expressions.dart';

/**
 * Transformer which gathers all expressions from the HTML source files and
 * Dart source files of an application and packages them for static evaluation.
 *
 * This will also modify the main Dart source file to import the generated
 * expressions and modify all references to NG_EXPRESSION_MODULE to refer to
 * the generated expressions.
 */
class ExpressionGenerator extends Transformer {
  final TransformOptions options;
  final ResolverTransformer resolvers;

  ExpressionGenerator(this.options, this.resolvers);

  Future<bool> isPrimary(Asset input) =>
      new Future.value(options.isDartEntry(input.id));

  Future apply(Transform transform) {
    var resolver = this.resolvers.getResolver(transform.primaryInput.id);
    return resolver.updateSources(transform).then((_) {
      return _generateExpressions(transform, resolver);
    });
  }

  Future<String> _generateExpressions(Transform transform, Resolver resolver) {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    _writeStaticExpressionHeader(asset.id, outputBuffer);

    var sourceMetadataExtractor = new SourceMetadataExtractor();
    var directives =
        sourceMetadataExtractor.gatherDirectiveInfo(null,
        new _LibrarySourceCrawler(resolver.libraries));

    var htmlExtractor = new HtmlExpressionExtractor(directives);
    return _getHtmlSources(transform)
        .forEach(htmlExtractor.parseHtml)
        .then((_) {
      var module = new Module()
        ..type(Parser, implementedBy: DynamicParser)
        ..type(ParserBackend, implementedBy: DartGetterSetterGen);
      var injector =
          new DynamicInjector(modules: [module], allowImplicitInjection: true);

      injector.get(_ParserGetterSetter).generateParser(
          htmlExtractor.expressions.toList(), outputBuffer);

      var outputId =
          new AssetId(asset.id.package, 'lib/$_generatedExpressionFilename');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));

      _transformAsset(transform, resolver);
    });
  }

  /**
   * Modify the asset of to import the generated source and modify all
   * references to angular_transformers.auto_modules.defaultExpressionModule to
   * refer to the generated expressions.
   */
  void _transformAsset(Transform transform, Resolver resolver) {
    transformIdentifiers(transform, resolver,
        identifier: 'angular_transformers.auto_modules.defaultExpressionModule',
        replacement: 'expressionModule',
        importPrefix: 'generated_static_expressions',
        generatedFilename: _generatedExpressionFilename);
  }

  /**
   * Gets a stream consisting of the contents of all HTML source files to be
   * scoured for expressions.
   */
  Stream<String> _getHtmlSources(Transform transform) {
    var controller = new StreamController<String>();
    if (options.htmlFiles == null) {
      controller.close();
      return controller.stream;
    }
    Future.wait(options.htmlFiles.map((path) {
      var htmlId = new AssetId(transform.primaryInput.id.package, path);
      return transform.readInputAsString(htmlId);
    }).map((future) {
      return future.then(controller.add).catchError(controller.addError);
    })).then((_) {
      controller.close();
    });
    return controller.stream;
  }
}

void _writeStaticExpressionHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  sink.write('''
library ${id.package}.$libPath.generated_expressions;

import 'package:angular/angular.dart';
import 'package:angular/core/parser/dynamic_parser.dart' show ClosureMap;

Module get expressionModule => new Module()
    ..value(ClosureMap, new StaticClosureMap());

''');
}

class _LibrarySourceCrawler implements SourceCrawler {
  final List<LibraryElement> libraries;
  _LibrarySourceCrawler(this.libraries);

  void crawl(String entryPoint, CompilationUnitVisitor visitor) {
    libraries.expand((lib) => lib.units)
        .map((compilationUnitElement) => compilationUnitElement.node)
        .forEach(visitor);
  }
}

class _ParserGetterSetter {
  final Parser parser;
  final ParserBackend backend;
  _ParserGetterSetter(this.parser, this.backend);

  generateParser(List<String> exprs, StringSink sink) {
    exprs.forEach((expr) {
      try {
        parser(expr);
      } catch (e) {
        // Ignore exceptions.
      }
    });

    DartGetterSetterGen backend = this.backend;
    sink.write(generateClosureMap(backend.properties, backend.calls));
  }

  String generateClosureMap(Set<String> properties,
      Map<String, Set<int>> calls) {
    return '''
class StaticClosureMap extends ClosureMap {
  Map<String, Getter> _getters = ${generateGetterMap(properties)};
  Map<String, Setter> _setters = ${generateSetterMap(properties)};
  List<Map<String, Function>> _functions = ${generateFunctionMap(calls)};

  Getter lookupGetter(String name)
      => _getters[name];
  Setter lookupSetter(String name)
      => _setters[name];
  lookupFunction(String name, int arity)
      => (arity < _functions.length) ? _functions[arity][name] : null;
}
''';
  }

  generateGetterMap(Iterable<String> keys) {
    var lines = keys.map((key) => 'r"${key}": (o) => o.$key');
    return '{\n   ${lines.join(",\n    ")}\n  }';
  }

  generateSetterMap(Iterable<String> keys) {
    var lines = keys.map((key) => 'r"${key}": (o, v) => o.$key = v');
    return '{\n   ${lines.join(",\n    ")}\n  }';
  }

  generateFunctionMap(Map<String, Set<int>> calls) {
    Map<int, Set<String>> arities = {};
    calls.forEach((name, callArities) {
      callArities.forEach((arity){
        arities.putIfAbsent(arity, () => new Set<String>()).add(name);
      });
    });

    var maxArity = arities.isEmpty ? 0 :
        arities.keys.reduce((x, y) => math.max(x, y));

    var maps = new Iterable.generate(maxArity, (arity) {
      var names = arities[arity];
      if (names == null) {
        return '{\n    }';
      } else {
        var args = new List.generate(arity, (e) => "a$e").join(',');
        var p = args.isEmpty ? '' : ', $args';
        var lines = names.map((name) => 'r"$name": (o$p) => o.$name($args)');
        return '{\n    ${lines.join(",\n    ")}\n  }';
      }
    });

    return '[${maps.join(",")}]';
  }
}

