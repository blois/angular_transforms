library angular_transformers.template_cache_generator;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:path/path.dart' as path;
import 'package:analyzer/src/generated/ast.dart';
import 'package:analyzer/src/generated/element.dart';


import 'refactor.dart';

/// Transformer which gathers all templates from the Angular application and
/// generates a single cache file for them.
class TemplateCacheGenerator extends ResolverTransformer {
  final TransformOptions options;

  TemplateCacheGenerator(this.options, Resolvers resolvers) {
    this.resolvers = resolvers;
  }

  Future<bool> isPrimary(Asset input) =>
      new Future.value(options.isDartEntry(input.id));

  Future applyResolver(Transform transform, Resolver resolver) {
    return new _Processor(transform, resolver, options).process();
  }
}

/// Container for resources while processing a single Transformer.apply.
class _Processor {
  final Transform transform;
  final Resolver resolver;
  final TransformOptions options;
  final Map<RegExp, String> templateUriRewrites = <RegExp, String>{};
  ConstructorElement cacheAnnotation;
  ConstructorElement componentAnnotation;

  static const String generatedFilename = 'generated_template_cache.dart';
  static const String cacheAnnotationName =
      'angular.template_cache_annotation.NgTemplateCache';
  static const String componentAnnotationName = 'angular.core.NgComponent';

  _Processor(this.transform, this.resolver, this.options) {
    for (var key in options.templateUriRewrites.keys) {
      templateUriRewrites[new RegExp(key)] = options.templateUriRewrites[key];
    }
  }

  Future process() {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    return gatherTemplates(transform, resolver).then((templates) {
      writeHeader(transform.primaryInput.id, outputBuffer);

      for (var key in templates.keys) {
        var contents = templates[key];
        contents = contents.replaceAll("'''", r"\'\'\'");
        outputBuffer.write('  \'$key\' = \'\'\'$contents\'\'\',\n');
      }
      writeFooter(outputBuffer);

      var outputId =
          new AssetId(asset.id.package, 'lib/$generatedFilename');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));

      transformIdentifiers(transform, resolver,
          identifier:
            'angular_transformers.auto_modules.defaultTemplateCacheModule',
          replacement: 'templateCacheModule',
          importPrefix: 'generated_template_cache',
          generatedFilename: generatedFilename);
    });
  }

  /// Gathers the contents of all URIs which are to be cached.
  /// Returns a map from URI to contents.
  Future<Map<String, String>> gatherTemplates(Transform transform,
      Resolver resolver) {
    var cacheAnnotationType = resolver.getType(cacheAnnotationName);
    if (cacheAnnotationType != null &&
        cacheAnnotationType.unnamedConstructor != null) {
      cacheAnnotation = cacheAnnotationType.unnamedConstructor;
    } else {
      logger.warning('Unable to resolve $cacheAnnotationName.');
    }

    var componentAnnotationType = resolver.getType(componentAnnotationName);
    if (componentAnnotationType != null &&
        componentAnnotationType.unnamedConstructor != null) {
      componentAnnotation = componentAnnotationType.unnamedConstructor;
    } else {
      logger.warning('Unable to resolve $componentAnnotationName.');
    }

    var annotations = resolver.libraries
        .expand((lib) => lib.units)
        .expand((unit) => unit.types)
        .where((type) => type.node != null)
        .expand(_AnnotatedElement.fromElement)
        .where((e) =>
            (e.annotation.element == cacheAnnotation ||
            e.annotation.element == componentAnnotation))
        .toList();

    var uriToEntry = <String, _CacheEntry>{};
    annotations.where((anno) => anno.annotation.element == componentAnnotation)
        .expand(processComponentAnnotation)
        .forEach((entry) {
          uriToEntry[entry.uri] = entry;
        });
    annotations.where((anno) => anno.annotation.element == cacheAnnotation)
        .expand(processCacheAnnotation)
        .forEach((entry) {
          uriToEntry[entry.uri] = entry;
        });

    var futures = uriToEntry.values.map(cacheEntry);

    return Future.wait(futures).then((_) {
      var uriToContents = <String, String>{};
      for (var entry in uriToEntry.values) {
        if (entry.contents == null) continue;

        uriToContents[entry.uri] = entry.contents;
      }
      return uriToContents;
    });
  }

  /// Extracts the cacheable URIs from the NgComponent annotation.
  List<_CacheEntry> processComponentAnnotation(_AnnotatedElement annotation) {
    var entries = <_CacheEntry>[];
    if (isCachingSuppressed(annotation.element)) {
      return entries;
    }
    for (var arg in annotation.annotation.arguments.arguments) {
      if (arg is NamedExpression) {
        var paramName = arg.name.label.name;
        if (paramName == 'templateUrl') {
          var entry = extractString('templateUrl', arg.expression,
              annotation.element);
          if (entry != null) {
            entries.add(entry);
          }
        } else if (paramName == 'cssUrl') {
          entries.addAll(extractListOrString(paramName, arg.expression,
              annotation.element));
        }
      }
    }

    return entries;
  }

  bool isCachingSuppressed(Element e) {
    if (cacheAnnotation == null) return false;

    for (var annotation in e.node.metadata) {
      if (annotation.element == cacheAnnotation) {
        for (var arg in annotation.arguments.arguments) {
          if (arg is NamedExpression && arg.name.label.name == 'cache') {
            var value = arg.expression;
            if (value is! BooleanLiteral) {
              warn('Expected boolean literal for NgTemplateCache.cache', e);
              return false;
            }
            return !value.value;
          }
        }
      }
    }
    return false;
  }

  List<_CacheEntry> processCacheAnnotation(_AnnotatedElement annotation) {
    var entries = <_CacheEntry>[];
    for (var arg in annotation.annotation.arguments.arguments) {
      if (arg is NamedExpression) {
        var paramName = arg.name.label.name;
        if (paramName == 'preCacheUrls') {
          entries.addAll(extractListOrString(paramName, arg.expression,
              annotation.element));
        }
      }
    }
    return entries;
  }

  List<_CacheEntry> extractListOrString(String paramName,
      Expression expression, Element element) {
    var entries = [];
    if (expression is StringLiteral) {
      var entry = uriToEntry(expression.stringValue, element);
      if (entry != null) {
        entries.add(entry);
      }
    } else if (expression is ListLiteral) {
      for (var value in expression.elements) {
        if (value is! StringLiteral) {
          warn('Expected a string literal in $paramName', element);
          continue;
        }
        var entry = uriToEntry(value.stringValue, element);
        if (entry != null) {
          entries.add(entry);
        }
      }
    } else {
      warn('$paramName must be a string or list literal.', element);
    }
    return entries;
  }

  _CacheEntry extractString(String paramName, Expression expression,
      Element element) {
    if (expression is! StringLiteral) {
      warn('$paramName must be a string literal.', element);
      return null;
    }
    return uriToEntry(expression.stringValue, element);
  }

  Future<_CacheEntry> cacheEntry(_CacheEntry entry) {
    return transform.readInputAsString(entry.assetId).then((contents) {
      if (contents == null) {
        warn('Unable to find $url at $assetId', entry.element);
      }
      entry.contents = contents;
      return entry;
    });
  }

  _CacheEntry uriToEntry(String uri, Element reference) {
    uri = rewriteUri(uri);
    if (Uri.parse(uri).scheme != '') {
      warn('Cannot cache non-local URIs. $uri', reference);
      return null;
    }
    if (path.url.isAbsolute(uri)) {
      var parts = path.posix.split(uri);
      if (parts[1] == 'packages') {
        var pkgPath = path.url.join('lib', path.url.joinAll(parts.skip(3)));
        return new _CacheEntry(uri, reference, new AssetId(parts[2], pkgPath));
      }
      warn('Cannot cache non-package absolute URIs. $uri', reference);
      return null;
    }
    var assetId = new AssetId(transform.primaryInput.id.package, uri);
    return new _CacheEntry(uri, reference, assetId);
  }

  String rewriteUri(String uri) {
    templateUriRewrites.forEach((regexp, replacement) {
      uri = uri.replaceFirst(regexp, replacement);
    });
    return uri;
  }

  void warn(String msg, Element element) {
    logger.warning(msg, asset: resolver.getSourceAssetId(element),
        span: resolver.getSourceSpan(element));
  }

  TransformLogger get logger => transform.logger;

  void writeHeader(AssetId id, StringSink sink) {
    var libPath = path.url.withoutExtension(id.path).replaceAll('/', '.');
    sink.write('''
library ${id.package}.$libPath.generated_template_cache;

import 'package:angular/angular.dart';
import 'package:di/di.dart' show Module;

Module get templateCacheModule =>
    new Module()..type(_LoadTemplateCacheDirective);

@NgDirective(selector: '[main-controller]')
class _LoadTemplateCacheDirective {
  _LoadTemplateCacheDirective(TemplateCache templateCache, Scope scope) {
    _cache.forEach((key, value) {
      templateCache.put(key, new HttpResponse(200, value));
    });
  }
}

const Map<String, String> _cache = const <String, String>{
''');
  }

  void writeFooter(StringSink sink) {
    sink.write('''};
''');
  }

}

/// Wrapper for data related to a single cache entry.
class _CacheEntry {
  final String uri;
  final Element element;
  final AssetId assetId;
  String contents;

  _CacheEntry(this.uri, this.element, this.assetId);
}

/// Wrapper for annotation AST nodes to track the element they were declared on.
class _AnnotatedElement {
  /// The annotation node.
  final Annotation annotation;
  /// The element which the annotation was declared on.
  final Element element;

  _AnnotatedElement(this.annotation, this.element);

  static Iterable<_AnnotatedElement> fromElement(Element element) =>
      element.node.metadata.map(
        (annotation) => new _AnnotatedElement(annotation, element));
}
