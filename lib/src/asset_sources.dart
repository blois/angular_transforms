library angular_transformer.asset_sources;

import 'dart:async';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/error.dart';
import 'package:analyzer/src/generated/java_core.dart' show CharSequence;
import 'package:analyzer/src/generated/parser.dart';
import 'package:analyzer/src/generated/scanner.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/span.dart' show SourceFile, Span;

/**
 * Simple wrapper for a parsed Dart source file.
 */
class DartSource {
  final Transform _transform;
  final CompilationUnit compilationUnit;
  final AssetId assetId;
  final String text;
  final Map<AssetId, CompilationUnit> parts = <AssetId, CompilationUnit>{};

  DartSource(this._transform, this.compilationUnit, this.assetId, this.text);

  Span getSpan(ASTNode node) => sourceFile.span(node.offset, node.end);
  SourceFile get sourceFile => new SourceFile.text(assetId.path, text);
  TransformLogger get logger => _transform.logger;

  bool get isComplete => !parts.values.any((c) => c == null);

  Iterable<CompilationUnit> get compilationUnits {
    return [compilationUnit]
        ..addAll(parts.values);
  }
}

/**
 * Crawls all of the Dart sources referenced by the provided asset.
 * This excludes all dart: files.
 */
Stream<DartSource> crawlSources(Transform transform, Asset entryPoint) {
  List<AssetId> visited = <AssetId>[];
  List<AssetId> toVisit = <AssetId>[entryPoint.id];
  // List of all libraries which have outstanding parts.
  Map<AssetId, List<DartSource>> incomplete = {};

  var controller = new StreamController<DartSource>.broadcast();

  Future visitNext() {
    if (toVisit.length == 0) {
      return null;
    }
    var id = toVisit.removeAt(0);
    visited.add(id);

    return transform.readInputAsString(id).then((contents) {
      var cu = _parseCompilationUnit(contents);
      if (incomplete.containsKey(id)) {
        for (var source in incomplete[id]) {
          source.parts[id] = cu;
          if (source.isComplete) {
            controller.add(source);
          }
        }
        incomplete.remove(id);
      } else {
        var source = new DartSource(transform, cu, id, contents);
        _processImports(source, visited, toVisit, incomplete);

        if (source.isComplete) {
          controller.add(source);
        }
      }

      return visitNext();
    }).catchError(controller.addError);
  }

  new Future(visitNext).then((_) {
    if (!incomplete.isEmpty) {
      throw new StateError(
          'Expected all incomplete compilation units to be completed.');
    }
    controller.close();
  });

  return controller.stream;
}

/** Parse [code] using analyzer. */
CompilationUnit _parseCompilationUnit(String code) {
  var errorListener = new _ErrorCollector();
  var reader = new CharSequenceReader(new CharSequence(code));
  var scanner = new Scanner(null, reader, errorListener);
  var token = scanner.tokenize();
  var parser = new Parser(null, errorListener);
  return parser.parseCompilationUnit(token);
}

/** Find all imports and parts which are referenced and add those to the
 * list to be visited.
 */
void _processImports(DartSource source, List<AssetId> visited,
    List<AssetId> toVisit, Map<AssetId, DartSource> incomplete) {
  source.compilationUnit.directives.forEach((Directive directive) {
    if (directive is ImportDirective ||
        directive is PartDirective ||
        directive is ExportDirective) {
      UriBasedDirective import = directive;
      var span = source.getSpan(directive);
      var assetId = _resolve(source.assetId,
          import.uri.stringValue, source.logger, span);
      if (assetId == null) return;
      if (!visited.contains(assetId) && !toVisit.contains(assetId)) {
        toVisit.add(assetId);
      }

      if (directive is PartDirective) {
        source.parts[assetId] = null;
        var libs = incomplete[assetId];
        if (libs == null) {
          incomplete[assetId] = [source];
        } else {
          libs.add(source);
        }
      }
    }
  });
}

class _ErrorCollector extends AnalysisErrorListener {
  final errors = <AnalysisError>[];
  onError(error) => errors.add(error);
}


/**
 * Create an [AssetId] for a [url] seen in the [source] asset.
 * The url is assumed to be using dart import syntax.
 */
AssetId _resolve(AssetId source, String url, TransformLogger logger,
    Span span) {
  if (url == null || url == '') return null;
  var urlBuilder = path.url;
  var uri = Uri.parse(url);

  if (uri.scheme == 'package') {
    var segments = new List.from(uri.pathSegments);
    var package = segments[0];
    segments[0] = 'lib';
    return new AssetId(package, segments.join(urlBuilder.separator));
  }
  if (uri.scheme == 'dart') {
    return null;
  }

  if (uri.host != '' || uri.scheme != '' || urlBuilder.isAbsolute(url)) {
    logger.error('absolute paths not allowed: "$url"', span: span);
    return null;
  }

  var targetPath = urlBuilder.normalize(
      urlBuilder.join(urlBuilder.dirname(source.path), url));
  return new AssetId(source.package, targetPath);
}
