library angular_transformers.test.metadata_generator;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/transformer.dart';
import 'package:angular_transformers/src/metadata_generator.dart';
import 'jasmine_syntax.dart';
import 'common.dart';

// Test for private types
// Test for private members
// Test for prefixed imports on class annotations.
// Test for multiple annotations on members
// Test for getter/setter combos

main() {
  describe('metadata_generator', () {
    var phases = [[
      new MetadataGenerator(
        new TransformOptions(dartEntry: 'web/main.dart'))]];

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
/*
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
          results: {},
          messages: ['a|web/a.dart cannot contain annotated '
          'because it cannot be imported (must be in a lib folder).']
          );
    });*/
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
