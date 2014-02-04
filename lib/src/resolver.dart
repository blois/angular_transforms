library angular_transformer.resolver;

import 'dart:async';
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart'
    show AnalysisEngine, ChangeSet;
import 'package:analyzer/src/generated/error.dart' show AnalysisErrorListener;
import 'package:analyzer/src/generated/java_core.dart' show CharSequence;
import 'package:analyzer/src/generated/java_io.dart' show JavaSystemIO;
import 'package:analyzer/src/generated/parser.dart' show Parser;
import 'package:analyzer/src/generated/scanner.dart'
    show CharSequenceReader, Scanner;
import 'package:analyzer/src/generated/sdk_io.dart' show DirectoryBasedDartSdk;
import 'package:analyzer/src/generated/source.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/span.dart' show SourceFile, Span;

class Resolver {
  /// Cache of all asset sources currently referenced.
  final Map<AssetId, AssetBasedSource> sources = {};
  /// The entryPoint for resolving all files.
  final AssetId entryPoint;

  AnalysisContext _context;
  Transform _currentTransform;
  LibraryElement _entryLibrary;

  Resolver(this.entryPoint, String sdkDir) {
    JavaSystemIO.setProperty("com.google.dart.sdk", sdkDir);

    _context = AnalysisEngine.instance.createAnalysisContext();
    _context.sourceFactory = new SourceFactory.con2([
        new DartUriResolver(DirectoryBasedDartSdk.defaultSdk),
        new AssetUriResolver(this)]);
  }

  /// Gets the resolved Dart library for the entry asset, or null if
  /// this has not been resolved.
  LibraryElement get entryLibrary => _entryLibrary;

  /// Update the status of all the sources referenced by the entryPoint and
  /// update the resolved library.
  Future updateSources(Transform transform) {
    if (_currentTransform != null) {
      throw new StateError('Cannot be accessed by concurrent transforms');
    }
    _currentTransform = transform;
    // Clear this out and update once all asset changes have been processed.
    _entryLibrary = null;

    var visited = new Set<AssetId>();
    var toVisit = new Set<AssetId>();
    var changedSources = [];
    var addedSources = [];
    var removedSources = [];
    toVisit.add(entryPoint);

    Future visitNext() {
      if (toVisit.length == 0) {
        return null;
      }
      var assetId = toVisit.first;
      toVisit.remove(assetId);
      visited.add(assetId);

      return transform.readInputAsString(assetId).then((contents) {
        var source = sources[assetId];
        if (source == null) {
          source = new AssetBasedSource(assetId, this);
          sources[assetId] = source;
          addedSources.add(source);
        }
        var changed = source.updateContents(contents);
        if (changed) {
          changedSources.add(source);
        }

        for (var id in source.dependentAssets) {
          if (!visited.contains(id) && !toVisit.contains(id)) {
            toVisit.add(id);
          }
        }

        return visitNext();
      }, onError: (e) {
        removedSources.add(sources[assetId]);
        sources.remove(assetId);
        return visitNext();
      });
    }

    return new Future(visitNext).then((_) {
      ChangeSet changeSet = new ChangeSet();
      var unreachableAssets = new Set.from(sources.keys).difference(visited);
      for (var unreachable in unreachableAssets) {
        changeSet.removed(sources[unreachable]);
        sources.remove(unreachable);
      }

      for (var added in addedSources) {
        changeSet.added(added);
      }
      for (var changed in changedSources) {
        changeSet.changed(changed);
      }
      for (var removed in removedSources) {
        changeSet.removed(removed);
      }
      _context.applyChanges(changeSet);
      _entryLibrary = _context.computeLibraryElement(sources[entryPoint]);

      _currentTransform = null;
    });
  }
}

/// Implementation of Analyzer's Source for Barback based assets.
class AssetBasedSource extends Source {
  final AssetId assetId;
  final Resolver _resolver;
  /// Cache of dependent asset IDs, to avoid re-parsing the AST.
  Iterable<AssetId> _dependentAssets;
  /// The current revision of the file, incremented each time this file changes.
  int _revision = 0;
  String _contents;

  AssetBasedSource(this.assetId, this._resolver);

  /// Returns true if the contents of this asset have changed.
  bool updateContents(String contents) {
    if (contents != _contents) {
      _contents = contents;
      ++_revision;
      // Invalidate the imports so we only parse the AST when needed.
      _dependentAssets = null;
      return true;
    }
    return false;
  }

  String get contents => _contents;

  TransformLogger get logger => _resolver._currentTransform.logger;

  /// Gets all imports/parts/exports which resolve to assets (non-Dart files).
  Iterable<AssetId> get dependentAssets {
    /// Use the cached imports if we have them.
    if (_dependentAssets != null) return _dependentAssets;

    var errorListener = new _ErrorCollector();
    var reader = new CharSequenceReader(new CharSequence(contents));
    var scanner = new Scanner(null, reader, errorListener);
    var token = scanner.tokenize();
    var parser = new Parser(null, errorListener);

    var compilationUnit = parser.parseCompilationUnit(token);

    _dependentAssets = compilationUnit.directives
        .where((d) => (d is ImportDirective || d is PartDirective ||
            d is ExportDirective))
        .map((d) => _resolve(assetId, d.uri.stringValue,
            logger, _getSpan(d)))
        .where((id) => id != null);

    return _dependentAssets;
  }

  bool exists() => true;

  bool operator ==(Object other) =>
      other is AssetBasedSource && assetId == other.assetId;

  int get hashCode => assetId.hashCode;

  void getContents(Source_ContentReceiver receiver) {
    receiver.accept2(contents, modificationStamp);
  }

  String get encoding =>
      "${uriKind.encoding}${assetId.package}/${assetId.path}";

  String get fullName => assetId.toString();

  int get modificationStamp => _revision;

  String get shortName => path.basename(assetId.path);

  UriKind get uriKind {
    if (assetId.path.startsWith('lib/')) return UriKind.PACKAGE_URI;
    return UriKind.FILE_URI;
  }

  bool get isInSystemLibrary => false;

  Source resolveRelative(Uri relativeUri) {
    var id = _resolve(assetId, relativeUri.toString(), logger, null);
    if (id != null) {
      var source = _resolver.sources[id];
      if (source == null) {
        logger.error('Could not load asset $id');
      }
      return source;
    }
    return null;
  }

  Span _getSpan(ASTNode node) => _sourceFile.span(node.offset, node.end);
  SourceFile get _sourceFile => new SourceFile.text(assetId.path, contents);
}

/// Implementation of Analyzer's UriResolver for Barback based assets.
class AssetUriResolver implements UriResolver {
  final Resolver _resolver;
  AssetUriResolver(this._resolver) {
  }

  Source fromEncoding(ContentCache contentCache, UriKind kind, Uri uri) {
    throw new UnsupportedError('fromEncoding is not supported');
  }

  Source resolveAbsolute(ContentCache contentCache, Uri uri) {
    var assetId = _resolve(null, uri.toString(), logger, null);
    var source = _resolver.sources[assetId];
    if (source == null) {
      logger.error('Unable to find asset for "$uri"');
    }
    return source;
  }

  Uri restoreAbsolute(Source source) {
    throw new UnsupportedError('restoreAbsolute is not supported');
  }

  TransformLogger get logger => _resolver._currentTransform.logger;
}


class _ErrorCollector extends AnalysisErrorListener {
  final errors = <AnalysisError>[];
  onError(error) => errors.add(error);
}


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
