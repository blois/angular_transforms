library angular_transformer.resolver;

import 'dart:async';
import 'dart:collection';
import 'dart:mirrors' show reflect;
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/sdk.dart' show DartSdk;
import 'package:analyzer/src/generated/engine.dart'
    show AnalysisEngine, AnalysisContext, ChangeSet, AnalysisOptionsImpl;
import 'package:analyzer/src/generated/error.dart' show AnalysisErrorListener;
import 'package:analyzer/src/generated/java_core.dart' show CharSequence;
import 'package:analyzer/src/generated/java_io.dart' show JavaSystemIO, JavaFile;
import 'package:analyzer/src/generated/parser.dart' show Parser;
import 'package:analyzer/src/generated/scanner.dart'
    show CharSequenceReader, Scanner;
import 'package:analyzer/src/generated/sdk_io.dart' show DirectoryBasedDartSdk;
import 'package:analyzer/src/generated/source.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/span.dart' show SourceFile, Span;

/**
 * Resolves an AST based on Barback-based assets.
 * Also handles updating the AST based on incremental changes to the assets.
 */
class Resolver {
  /** Cache of all asset sources currently referenced. */
  final Map<AssetId, _AssetBasedSource> sources = {};
  /** The entryPoint for resolving all files. */
  final AssetId entryPoint;

  final AnalysisContext _context =
    AnalysisEngine.instance.createAnalysisContext();
  Transform _currentTransform;
  LibraryElement _entryLibrary;

  /**
   * [entryPoint] is the AssetID of the entry point where code resolution
   * should begin, this will then load all dependent assets from there.
   *
   * [sdkDir] is the root directory of the Dart SDK, for resolving dart:
   * imports.
   */
  Resolver(this.entryPoint, String sdkDir) {
    var options = new AnalysisOptionsImpl();
    options.cacheSize = 256;
    options.preserveComments = false;
    options.analyzeFunctionBodies = false;
    _context.analysisOptions = options;

    var dartSdk = new _DirectoryBasedDartSdkProxy(new JavaFile(sdkDir));
    dartSdk.context.analysisOptions = options;

    _context.sourceFactory = new SourceFactory.con2([
        new DartUriResolverProxy(dartSdk),
        new _AssetUriResolver(this)]);
  }

  /**
   * Gets the resolved Dart library for the entry asset, or null if
   * this has not been resolved.
   */
  LibraryElement get entryLibrary => _entryLibrary;

  /**
   * Update the status of all the sources referenced by the entryPoint and
   * update the resolved library.
   */
  Future updateSources(Transform transform) {
    if (_currentTransform != null) {
      throw new StateError('Cannot be accessed by concurrent transforms');
    }
    _currentTransform = transform;
    // Clear this out and update once all asset changes have been processed.
    _entryLibrary = null;

    // Basic approach is to start at the first file, update it's contents
    // and see if it changed, then walk all files accessed by it.
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
          source = new _AssetBasedSource(assetId, this);
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

    // Once we have all asset sources updated with the new contents then
    // resolve everything.
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

  /** Gets all libraries accessible from the entry point, recursively. */
  Iterable<LibraryElement> get libraries =>
      new _LibraryElementIterable(_entryLibrary);

  /**
   * Finds the first library identified by [libraryName], or null if no
   * library can be found.
   */
  LibraryElement getLibrary(String libraryName) =>
    libraries.firstWhere((l) => l.name == libraryName, orElse: () => null);

  /**
   * Resolves a fully-qualified type name (library_name.ClassName).
   */
  ClassElement getType(String typeName) {
    var dotIndex = typeName.lastIndexOf('.');
    var libraryName = dotIndex == -1 ? '' : typeName.substring(0, dotIndex);
    // Can have conflicting library names.
    var libs = libraries.where((l) => l.name == libraryName);

    var className = dotIndex == -1 ?
        typeName : typeName.substring(dotIndex + 1);

    for (var lib in libs) {
      var type = lib.getType(className);
      if (type != null) {
        return type;
      }
    }
    return null;
  }

  /**
   * Resolves a fully-qualified top-level library variable (library_name.Name).
   */
  Element getLibraryVariable(String variableName) {
    var dotIndex = variableName.lastIndexOf('.');
    var libraryName = dotIndex == -1 ? '' : variableName.substring(0, dotIndex);
    // Can have conflicting library names.
    var libs = libraries.where((l) => l.name == libraryName);

    var varName = dotIndex == -1 ?
        variableName : variableName.substring(dotIndex + 1);

    for (var lib in libs) {
      for (var unit in getUnits(lib)) {
        for (var variable in unit.topLevelVariables) {
          if (variable.name == varName) {
            return variable;
          }
        }
      }
    }
    return null;
  }

  /**
   * Gets an absolute URI appropriate for importing the specified library.
   */
  Uri getAbsoluteImportUri(LibraryElement lib) {
    var source = lib.source;
    if (source is _AssetBasedSource) {
      var id = source.assetId;
      // Cannot do absolute imports of non lib-based assets.
      if (!id.path.startsWith('lib/')) return null;

      return Uri.parse('package:${id.package}/${id.path.substring(4)}');
    } else if (source is _DartSourceProxy) {
      return source.uri;
    }
    // Should not be able to encounter any other source types.
    throw new StateError('Unable to resolve URI for ${source.runtimeType}');
  }

  AssetId getSourceAssetId(Element element) {
    if (element.source is _AssetBasedSource) return element.source.assetId;
    return null;
  }

  Span getSourceSpan(Element element) {
    var assetId = getSourceAssetId(element);
    if (assetId == null) return null;

    var sourceFile =
        new SourceFile.text(assetId.path, sources[assetId].contents);
    return sourceFile.span(element.node.offset, element.node.end);
  }

  // TODO: remove for analyzer 0.11+
  Iterable<CompilationUnitElement> getUnits(LibraryElement l) =>
      [l.definingCompilationUnit]..addAll(l.parts);
}

/** Implementation of Analyzer's Source for Barback based assets. */
class _AssetBasedSource extends Source {
  /** Asset ID where this source can be found. */
  final AssetId assetId;
  final Resolver _resolver;
  /** Cache of dependent asset IDs, to avoid re-parsing the AST. */
  Iterable<AssetId> _dependentAssets;
  /** The current revision of the file, incremented only when file changes. */
  int _revision = 0;
  String _contents;

  _AssetBasedSource(this.assetId, this._resolver);

  /** Returns true if the contents of this asset have changed. */
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

  /** String contents of the file. */
  String get contents => _contents;

  TransformLogger get logger => _resolver._currentTransform.logger;

  /**
   * Gets all imports/parts/exports which resolve to assets (non-Dart files).
   */
  Iterable<AssetId> get dependentAssets {
    // Use the cached imports if we have them.
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
      other is _AssetBasedSource && assetId == other.assetId;

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
    if (id == null) return null;

    var source = _resolver.sources[id];
    if (source == null) {
      logger.error('Could not load asset $id');
    }
    return source;
  }

  Span _getSpan(ASTNode node) => _sourceFile.span(node.offset, node.end);
  SourceFile get _sourceFile => new SourceFile.text(assetId.path, contents);
}

/** Implementation of Analyzer's UriResolver for Barback based assets. */
class _AssetUriResolver implements UriResolver {
  final Resolver _resolver;
  _AssetUriResolver(this._resolver);

  Source resolveAbsolute(ContentCache contentCache, Uri uri) {
    var assetId = _resolve(null, uri.toString(), logger, null);
    var source = _resolver.sources[assetId];
    if (source == null) {
      logger.error('Unable to find asset for "$uri"');
    }
    return source;
  }

  Source fromEncoding(ContentCache contentCache, UriKind kind, Uri uri) =>
      throw new UnsupportedError('fromEncoding is not supported');

  Uri restoreAbsolute(Source source) =>
      throw new UnsupportedError('restoreAbsolute is not supported');

  TransformLogger get logger => _resolver._currentTransform.logger;
}

/**
 * Dart SDK which wraps all Dart sources to ensure they are tracked with URIs.
 */
class _DirectoryBasedDartSdkProxy extends DirectoryBasedDartSdk {
  _DirectoryBasedDartSdkProxy(JavaFile sdkDirectory) : super(sdkDirectory);

  Source mapDartUri(String dartUri) =>
      _DartSourceProxy.wrap(super.mapDartUri(dartUri), Uri.parse(dartUri));
}

/**
 * Dart SDK resolver which wraps all Dart sources to ensure they are tracked
 * with URIs.
 */
class DartUriResolverProxy implements DartUriResolver {
  final DartUriResolver _proxy;
  DartUriResolverProxy(DirectoryBasedDartSdk sdk) :
      _proxy = new DartUriResolver(sdk);

  Source resolveAbsolute(ContentCache contentCache, Uri uri) =>
    _DartSourceProxy.wrap(_proxy.resolveAbsolute(contentCache, uri), uri);

  DartSdk get dartSdk => _proxy.dartSdk;

  Source fromEncoding(ContentCache contentCache, UriKind kind, Uri uri) =>
      throw new UnsupportedError('fromEncoding is not supported');

  Uri restoreAbsolute(Source source) =>
      throw new UnsupportedError('restoreAbsolute is not supported');
}

/** Source file for dart: sources which track the sources with dart: URIs. */
class _DartSourceProxy implements Source {
  final Uri uri;
  final Source _proxy;

  _DartSourceProxy(this._proxy, this.uri);

  static _DartSourceProxy wrap(Source proxy, Uri uri) {
    if (proxy == null || proxy is _DartSourceProxy) return proxy;
    return new _DartSourceProxy(proxy, uri);
  }

  Source resolveRelative(Uri relativeUri) {
    // Assume that the type can be accessed via this URI, since these
    // should only be parts for dart core files.
    return wrap(_proxy.resolveRelative(relativeUri), uri);
  }

  bool exists() => _proxy.exists();

  bool operator ==(Object other) =>
    (other is _DartSourceProxy && _proxy == other._proxy);

  int get hashCode => _proxy.hashCode;

  void getContents(Source_ContentReceiver receiver) {
    _proxy.getContents(receiver);
  }

  String get encoding => _proxy.encoding;

  String get fullName => _proxy.fullName;

  int get modificationStamp => _proxy.modificationStamp;

  String get shortName => _proxy.shortName;

  UriKind get uriKind => _proxy.uriKind;

  bool get isInSystemLibrary => _proxy.isInSystemLibrary;
}


class _ErrorCollector extends AnalysisErrorListener {
  final errors = <AnalysisError>[];
  onError(error) => errors.add(error);
}

/** Get an asset ID for a URL relative to another source asset. */
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

// TODO: switch to Library.visibleLibraries with analyzer 11+
class _LibraryElementIterable extends IterableBase<LibraryElement> {
  final LibraryElement _entryPoint;
  _LibraryElementIterable(this._entryPoint);

  Iterator<LibraryElement> get iterator =>
      new _LibraryElementIterator(_entryPoint);
}

// TODO: switch to Library.visibleLibraries with analyzer 11+
class _LibraryElementIterator implements Iterator<LibraryElement> {
  Set<LibraryElement> _visited = new Set<LibraryElement>();
  List<LibraryElement> _toVisit = <LibraryElement>[];
  LibraryElement _current;

  _LibraryElementIterator(LibraryElement entryPoint) {
    _toVisit.add(entryPoint);
  }

  LibraryElement get current => _current;

  bool moveNext() {
    if (_toVisit.isEmpty) {
      _current = null;
      return false;
    }
    _current = _toVisit.removeAt(0);
    _visited.add(_current);

    for (var imported in _current.importedLibraries) {
      if (!_visited.contains(imported) && !_toVisit.contains(imported)) {
        _toVisit.add(imported);
      }
    }

    for (var exported in _current.exportedLibraries) {
      if (!_visited.contains(exported) && !_toVisit.contains(exported)) {
        _toVisit.add(exported);
      }
    }

    return true;
  }
}
