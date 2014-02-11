library angular_transformers.test.metadata_generator;

import 'dart:async';
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
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
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
          imports: [
            'import \'package:a/a.dart\' as import_0;',
            'import \'package:angular/angular.dart\' as import_1;',
          ],
          classes: {
            'import_0.Engine': [
              'const import_1.NgDirective(selector: \'[*=/{{.*}}/]\')',
              'proxy',
            ]
          },
          classMembers: {
            'import_0.Engine': {
              'anotherExpression': 'const import_1.NgOneWay(\'another-expression\')',
              'callback': 'const import_1.NgCallback(\'callback\')',
              'twoWayStuff': 'const import_1.NgTwoWay(\'two-way-stuff\')',
            }
          });
    });

    it('should warn on un-importable files', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|web/a.dart': '''
                import 'package:angular/angular.dart';

                @NgDirective(selector: r'[*=/{{.*}}/]')
                class Engine {}
                '''
          },
          messages: ['warning: Dropping annotations for Engine because the '
              'containing file cannot be imported (must be in a lib folder). '
              '(web/a.dart 2 16)']);
    });

    it('should warn on multiple annotations', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                class Engine {
                  @NgCallback('callback')
                  @NgOneWay('another-expression')
                  set callback(Function) {}
                }
                '''
          },
          messages: ['warning: callback can only have one annotation. '
              '(lib/a.dart 3 18)']);
    });

    it('should warn on multiple annotations (across getter/setter)', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                class Engine {
                  @NgCallback('callback')
                  set callback(Function) {}

                  @NgOneWay('another-expression')
                  get callback() {}
                }
                '''
          },
          messages: ['warning: callback can only have one annotation. '
              '(lib/a.dart 3 18)']);
    });

    it('should extract map arguments', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                @NgDirective(map: const {'ng-value': '&ngValue'})
                class Engine {}
                '''
          },
          imports: [
            'import \'package:a/a.dart\' as import_0;',
            'import \'package:angular/angular.dart\' as import_1;',
          ],
          classes: {
            'import_0.Engine': [
              'const import_1.NgDirective(map: const {\'ng-value\': \'&ngValue\'})',
            ]
          });
    });

    it('should extract list arguments', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                @NgDirective(publishTypes: const [TextChangeListener])
                class Engine {}
                '''
          },
          imports: [
            'import \'package:a/a.dart\' as import_0;',
            'import \'package:angular/angular.dart\' as import_1;',
          ],
          classes: {
            'import_0.Engine': [
              'const import_1.NgDirective(publishTypes: const [import_1.TextChangeListener,])',
            ]
          });
    });

    it('should skip and warn on unserializable annotations', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                @Foo
                class Engine {}

                @NgDirective(publishTypes: const [Foo])
                class Car {}
                '''
          },
          imports: [
            'import \'package:a/a.dart\' as import_0;',
            'import \'package:angular/angular.dart\' as import_1;',
          ],
          classes: {
            'import_0.Engine': [
              'null',
            ],
            'import_0.Car': [
              'null',
            ]
          });
    });

    it('should extract types across libs', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';
                import 'package:a/b.dart';

                @NgDirective(publishTypes: const [Car])
                class Engine {}
                ''',
            'a|lib/b.dart': '''
                class Car {}
                ''',
          },
          imports: [
            'import \'package:a/a.dart\' as import_0;',
            'import \'package:angular/angular.dart\' as import_1;',
            'import \'package:a/b.dart\' as import_2;',
          ],
          classes: {
            'import_0.Engine': [
              'const import_1.NgDirective(publishTypes: const [import_2.Car,])',
            ]
          });
    });

    it('should not gather non-member annotations', () {
      return generates(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart'; ''',
            'angular|lib/angular.dart': PACKAGE_ANGULAR,
            'a|lib/a.dart': '''
                import 'package:angular/angular.dart';

                class Engine {
                  Engine() {
                    @NgDirective()
                    print('something');
                  }
                }
                ''',
          });
    });
  });
}

Future generates(List<List<Transformer>> phases,
    {Map<String, String> inputs, Iterable<String> imports: const [],
    Map classes: const {},
    Map classMembers: const {},
    Iterable<String> messages: const []}) {

  var buffer = new StringBuffer();
  buffer.write('$HEADER\n');
  for (var i in imports) {
    buffer.write('$i\n');
  }
  buffer.write('$BOILER_PLATE\n');
  for (var className in classes.keys) {
    buffer.write('  $className: [\n');
    for (var annotation in classes[className]) {
      buffer.write('    $annotation,\n');
    }
    buffer.write('  ],\n');
  }
  buffer.write('$MEMBER_PREAMBLE\n');
  for (var className in classMembers.keys) {
    buffer.write('  $className: {\n');
    var members = classMembers[className];
    for (var memberName in members.keys) {
      buffer.write('    \'$memberName\': ${members[memberName]},\n');
    }
    buffer.write('  },\n');
  }

  buffer.write('$FOOTER\n');

  return transform(phases,
      inputs: inputs,
      results: {
        'a|lib/generated_metadata.dart': buffer.toString()
      },
      messages: messages);
}

const String HEADER = '''
library a.web.main.generated_metadata;
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


const String PACKAGE_ANGULAR = '''
library angular.core;

class NgDirective {
  const NgDirective({selector. publishTypes, map});
}

class NgOneWay {
  const NgOneWay(arg);
}

class NgTwoWay {
  const NgTwoWay(arg);
}

class NgCallback {
  const NgCallback(arg);
}

class NgAttr {
  const NgAttr();
}
class NgOneWayOneTime {
  const NgOneWayOneTime(arg);
}

class TextChangeListener {}
''';

// @NgDirective(
//     selector: 'option',
//     publishTypes: const [TextChangeListener],
//     map: const {'ng-value': '&ngValue'})
