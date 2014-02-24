library angular_transformers.test.expression_extractor_spec;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/expression_generator.dart';
import 'package:code_transformers/resolver.dart';
import 'package:code_transformers/tests.dart' as tests;
import 'jasmine_syntax.dart';

main() {
  describe('expression_extractor', () {
    var htmlFiles = [];
    var options = new TransformOptions(
        dartEntry: 'web/main.dart',
        htmlFiles: htmlFiles,
        sdkDirectory: dartSdkDirectory);
    var resolver = new ResolverTransformer(dartSdkDirectory,
        (asset) => options.isDartEntry(asset.id));

    var phases = [
      [resolver],
      [new ExpressionGenerator(options, resolver)]
    ];

    it('should extract expressions', () {
      htmlFiles.add('web/index.html');
      return tests.applyTransformers(phases,
          inputs: {
            'angular_transformers|lib/auto_modules.dart': PACKAGE_AUTO,
            'a|web/main.dart': '''
library foo;
import 'package:angular_transformers/auto_modules.dart';
''',
            'a|web/index.html': '''
<div>{{some.getter}}</div>
'''
          },
          results: {
            'a|lib/generated_static_expressions.dart': '''
$HEADER
  Map<String, Getter> _getters = {
   r"some": (o) => o.some,
    r"getter": (o) => o.getter
  };
  Map<String, Setter> _setters = {
   r"some": (o, v) => o.some = v,
    r"getter": (o, v) => o.getter = v
  };
  List<Map<String, Function>> _functions = [];
$FOOTER
'''
        }).then((_) {
          htmlFiles.clear();
        });
    });
  });
}

const String HEADER = '''
library a.web.main.generated_expressions;

import 'package:angular/angular.dart';
import 'package:angular/core/parser/dynamic_parser.dart' show ClosureMap;

Module get expressionModule => new Module()
    ..value(ClosureMap, new StaticClosureMap());

class StaticClosureMap extends ClosureMap {''';

const String FOOTER = '''

  Getter lookupGetter(String name)
      => _getters[name];
  Setter lookupSetter(String name)
      => _setters[name];
  lookupFunction(String name, int arity)
      => (arity < _functions.length) ? _functions[arity][name] : null;
}''';

const String PACKAGE_AUTO = '''
library angular_transformers.auto_modules;

Module get defaultExpressionModule => new Module();
''';
