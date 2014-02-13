library angular_transformers.expression_generator;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular/tools/source_crawler.dart';
import 'package:angular/tools/html_extractor.dart';
import 'package:angular/tools/source_metadata_extractor.dart';
import 'package:angular/core/module.dart';
import 'package:angular/core/parser/parser.dart';
import 'package:angular/tools/parser_generator/generator.dart';
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
        ..type(FilterMap, implementedBy: NullFilterMap)
        ..type(Parser, implementedBy: DynamicParser)
        ..type(ParserBackend, implementedBy: DynamicParserBackend)
        ..value(SourcePrinter, new _StreamPrinter(outputBuffer));
      var injector =
          new DynamicInjector(modules: [module], allowImplicitInjection: true);

      injector.get(ParserGenerator).generateParser(htmlExtractor.expressions);

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
import 'package:angular/core/parser/parser.dart';
import 'package:angular/core/parser/utils.dart';

Module get expressionModule => new Module()
    ..type(Parser, implementedBy: StaticParser)
    ..type(StaticParserFunctions,
        implementedBy: GeneratedStaticParserFunctions)
    ..value(DynamicParser, new _UnsupportedDynamicParser());

class _UnsupportedDynamicParser implements DynamicParser {
  Expression call(String input) =>
      throw new StateError(
          'Should not be evaluating \$input with the dynamic parser');
}

typedef Function FilterLookup(String filterName);

@NgInjectableService()
class GeneratedStaticParserFunctions extends StaticParserFunctions {
  GeneratedStaticParserFunctions() :
      super(buildEval(), buildAssign());
}
''');
}

class _StreamPrinter implements SourcePrinter {
  final StringSink _sink;

  _StreamPrinter(this._sink);

  printSrc(src) {
    _sink.write('$src\n');
  }
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
