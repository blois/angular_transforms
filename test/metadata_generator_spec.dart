library angular_transformers.test.metadata_generator;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/transformer.dart';
import 'package:angular_transformers/src/metadata_generator.dart';
import 'package:angular_transformers/src/resolver_transformer.dart';
import 'jasmine_syntax.dart';
import 'common.dart';

// Test for private types
// Test for prefixed imports on class annotations.

main() {
  describe('metadata_generator', () {
    var options = new TransformOptions(
        dartEntry: 'web/main.dart',
        sdkDirectory: dartSdkDirectory);

    var resolver = new ResolverTransformer(dartSdkDirectory,
        (asset) => options.isDartEntry(asset.id));

    var phases = [
      [resolver],
      [new MetadataGenerator(options, resolver)]
    ];

    it('should extract member metadata', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': '',
            'a|lib/a.dart':
'''
import 'package:angular/angular.dart';

@NgDirective(selector: r'[*=/{{.*}}/]')
@proxy
class Engine {
  @NgOneWay('another-expression')
  String anotherExpression;

  @NgCallback('callback')
  set callback(Function) {}

  set twoWayStuff(String abc) {}
  @NgTwoWay('two-way-stuff')
  String get twoWayStuff => null;
}
'''
          },
          results: {
            'a|lib/generated_metadata.dart':
'''
$HEADER
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
import 'package:angular/angular.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: [
    const import_0.NgDirective(selector: r'[*=/{{.*}}/]'),
    import_0.proxy,
  ],
$MEMBER_PREAMBLE
  import_0.Engine: {
    \'anotherExpression\': const NgOneWay(\'another-expression\'),
    \'callback\': const NgCallback(\'callback\'),
    \'twoWayStuff\': const NgTwoWay('two-way-stuff'),
  },
$FOOTER
'''
          });
    });

    it('should warn on un-importable files', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'a.dart'; ''',
            'a|web/a.dart':
'''
@NgDirective(selector: r'[*=/{{.*}}/]')
class Engine {}
'''
          },
          results: EMPTY_METADATA,
          messages: ['warning: a|web/a.dart cannot contain annotated because '
              'it cannot be imported (must be in a lib folder). '
              '(web/a.dart 0 0)']);
    });

    it('should warn on multiple annotations', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'a|lib/a.dart':
'''
class Engine {
  @NgCallback('callback')
  @NgOneWay('another-expression')
  set callback(Function) {}
}
'''
          },
          results: {},
          messages: ['warning: callback can only have one annotation. '
              '(lib/a.dart 1 2)']);
    });

    it('should warn on multiple annotations (across getter/setter)', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'a|lib/a.dart':
'''
class Engine {
  @NgCallback('callback')
  set callback(Function) {}

  @NgOneWay('another-expression')
  get callback() {}
}
'''
          },
          results: {},
          messages: ['warning: callback can only have one annotation. '
              '(lib/a.dart 4 2)']);
    });
  });
}

const String HEADER = '''
library a.web.main.generated_metadata;

import 'dart:core';
import 'package:angular/angular.dart';
''';

const String BOILER_PLATE = '''
Module get metadataModule => new Module()
    ..value(MetadataExtractor, new _StaticMetadataExtractor())
    ..value(FieldMetadataExtractor, new _StaticFieldMetadataExtractor());

class _StaticMetadataExtractor implements MetadataExtractor {
  Iterable call(Type type) {
    var annotations = _classAnnotations[type];
    if (annotations != null) {
      return annotations;
    }
    return [];
  }
}

class _StaticFieldMetadataExtractor implements FieldMetadataExtractor {
  Map<String, AttrFieldAnnotation> call(Type type) {
    var annotations = _memberAnnotations[type];
    if (annotations != null) {
      return annotations;
    }
    return {};
  }
}

final Map<Type, Object> _classAnnotations = {''';

const String MEMBER_PREAMBLE = '''
};

final Map<Type, Map<String, AttrFieldAnnotation>> _memberAnnotations = {''';

const String FOOTER = '''
};''';

const Map EMPTY_METADATA = const {
  'a|lib/generated_metadata.dart': '''
$HEADER
$BOILER_PLATE
$MEMBER_PREAMBLE
$FOOTER
'''
};
