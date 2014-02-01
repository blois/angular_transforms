library angular_transformers.expression_generator;

import 'dart:async';
import 'package:angular/core/parser/parser.dart';
import 'package:angular/tools/parser_generator/generator.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart';

import 'source_metadata_extractor.dart';
import 'asset_sources.dart';
import 'common.dart';

const String GENERATED_EXPRESSIONS = 'generated_static_expressions.dart';

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

  ExpressionGenerator(this.options);

  Future<bool> isPrimary(Asset input) => new Future.value(
      options.isDartEntry(input.id));

  Future apply(Transform transform) {
    return _generateStaticExpressions(transform).then((_) {
      // Workaround for dartbug.com/16120- do not send data across the isolate
      // boundaries.
      return null;
    });
  }

  Future<String> _generateStaticExpressions(Transform transform) {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    _writeStaticExpressionHeader(asset.id, outputBuffer);

    var module = new Module()
      ..type(Parser, implementedBy: DynamicParser)
      ..type(ParserBackend, implementedBy: DynamicParserBackend)
      ..value(SourcePrinter, new _StreamPrinter(outputBuffer));
    var injector =
        new DynamicInjector(modules: [module], allowImplicitInjection: true);

    var sources = crawlSources(transform, asset);
    // The first source file is always the entry file, update that to include
    // the generated expressions.
    sources.first.then((source) {
      _transformPrimarySource(transform, source);
    });

    var units = sources.expand((source) => source.compilationUnits);
    var html = _getHtmlSources(transform);

    return gatherExpressions(units, html).then((expressions) {
      injector.get(ParserGenerator).generateParser(expressions);

      var outputId =
          new AssetId(asset.id.package, 'lib/$GENERATED_EXPRESSIONS');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));
    });
  }

  /**
   * Modify the primary asset of the transform to import the generated source
   * and modify all references to NG_EXPRESSION_MODULE to refer to the generated
   * expression.
   */
  void _transformPrimarySource(Transform transform, DartSource source) {
    var transaction = new TextEditTransaction(source.text, source.sourceFile);

    transformIdentifiers(transaction, source.compilationUnit,
        'defaultExpressionModule',
        'generated_static_expressions.expressionModule');

    if (transaction.hasEdits) {
      addImport(transaction, source.compilationUnit,
          'package:${source.assetId.package}/$GENERATED_EXPRESSIONS',
          'generated_static_expressions');

      var id = source.assetId;
      var printer = transaction.commit();
      var url = id.path.startsWith('lib/')
          ? 'package:${id.package}/${id.path.substring(4)}' : id.path;
      printer.build(url);
      transform.addOutput(new Asset.fromString(id, printer.text));
    } else {
      // No modifications, so just pass the source through.
      transform.addOutput(transform.primaryInput);
    }
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
  GeneratedStaticParserFunctions(FilterMap filters) :
      super(buildEval(filters), buildAssign(filters));
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
