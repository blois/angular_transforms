library angular_transformers.test.template_cache_generator_spec;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/template_cache_generator.dart';
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:code_transformers/tests.dart' as tests;
import 'jasmine_syntax.dart';

// Test for private types
// Test for prefixed imports on class annotations.

main() {
  describe('template_cache_generator', () {
    var templateUriRewrites = {};
    var options = new TransformOptions(
        dartEntry: 'web/main.dart',
        sdkDirectory: dartSdkDirectory,
        templateUriRewrites: templateUriRewrites);

    var resolver = new ResolverTransformer(dartSdkDirectory,
        (asset) => options.isDartEntry(asset.id));

    var phases = [
      [resolver],
      [new TemplateCacheGenerator(options, resolver)]
    ];

    it('should extract templateUrls', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(templateUrl: 'lib/foo.html')
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
            'a|lib/foo.html': 'xxx'
          },
          cache: {
            'lib/foo.html': 'xxx',
          });
    });

    it('should extract cssUrls', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: 'lib/a.css')
              class Foo {}

              @NgComponent(cssUrl: ['lib/b.css', 'lib/c.css'])
              class Bar {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
            'a|lib/a.css': 'aaa',
            'a|lib/b.css': 'bbb',
            'a|lib/c.css': 'ccc',
          },
          cache: {
            'lib/a.css': 'aaa',
            'lib/b.css': 'bbb',
            'lib/c.css': 'ccc',
          });
    });

    it('should apply URI rewrites', () {
      templateUriRewrites['/app/something'] = 'lib';
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: '/app/something/a.css')
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
            'a|lib/a.css': 'aaa',
          },
          cache: {
            'lib/a.css': 'aaa',
          }).whenComplete(() {
            templateUriRewrites.clear();
          });
    });

    it('should warn on URI errors', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: '/does_not_exist')
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
          },
          messages: [
            'warning: Cannot cache non-package absolute URIs. /does_not_exist '
              '(main.dart 3 14)'
          ]);
    });

    it('should warn on unsupported parameters', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              const String URI = '/does_not_exist';

              @NgComponent(cssUrl: URI)
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
          },
          messages: [
            'warning: cssUrl must be a string or list literal. (main.dart 5 14)'
          ]);
    });

    it('should warn on URIs with schemes', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: 'http://example.com')
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
          },
          messages: [
            'warning: Cannot cache non-local URIs. http://example.com '
              '(main.dart 3 14)'
          ]);
    });

    it('should support package URIs', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: '/packages/foo/foo.css')
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
            'foo|lib/foo.css': 'aaa',
          },
          cache: {
            '/packages/foo/foo.css': 'aaa',
          });
    });

    it('should support NgTemplateCache URIs', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgTemplateCache(preCacheUrls: const ['/packages/foo/foo.css'])
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
            'foo|lib/foo.css': 'aaa',
          },
          cache: {
            '/packages/foo/foo.css': 'aaa',
          });
    });

    it('should respect NgTemplateCache no-cache', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'package:angular/angular.dart';
              import 'package:angular/tools/template_cache_annotation.dart';

              @NgComponent(cssUrl: '/packages/foo/foo.css')
              @NgTemplateCache(cache: false)
              class Foo {}
              ''',
            'angular|lib/angular.dart': _libAngular,
            'angular|lib/tools/template_cache_annotation.dart':
                _libTemplateCacheAnnotation,
          });
    });
  });
}

Future generates(List<List<Transformer>> phases,
    {Map<String, String> inputs, Map<String, String> cache: const {},
    Iterable<String> messages: const []}) {

  var buffer = new StringBuffer();
  buffer.write(_header);
  cache.forEach((key, value) {
    buffer.write('  \'$key\' = \'\'\'$value\'\'\',\n');
  });
  buffer.write(_footer);

  return tests.applyTransformers(phases,
      inputs: inputs,
      results: {
        'a|lib/generated_template_cache.dart': buffer.toString()
      },
      messages: messages);
}

const String _header = '''
library a.web.main.generated_template_cache;

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
''';

const String _footer = '''
};
''';


const String _libAngular = '''
library angular.core;

class NgComponent {
  const NgComponent({String templateUrl});
}
''';

const String _libTemplateCacheAnnotation = '''
library angular.template_cache_annotation;

class NgTemplateCache {
  const NgTemplateCache();
}
''';
