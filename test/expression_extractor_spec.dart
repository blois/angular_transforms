library angular_transformers.test.expression_extractor_spec;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/expression_generator.dart';
import 'package:angular_transformers/transformer.dart';
import 'jasmine_syntax.dart';
import 'common.dart';

main() {
  describe('expression_extractor', () {
    var options = new TransformOptions(dartEntry: 'web/main.dart');
    var phases = [[new ExpressionGenerator(options)]];

    it('should not modify files with no defaultExpressionModule', () {
      return transform(phases,
          inputs: {
            'angular|lib/angular.dart': '',
            'angular|lib/core/parser/parser.dart': '',
            'angular|lib/core/parser/utils.dart': '',
            'a|web/main.dart': '''
library foo;
import 'package:angular/angular.dart';
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:angular/angular.dart';
'''
          });
    });

    it('should update references to defaultExpressionModule', () {
      return transform(phases,
          inputs: {
            'angular|lib/angular.dart': '',
            'angular|lib/core/parser/parser.dart': '',
            'angular|lib/core/parser/utils.dart': '',
            'a|web/main.dart': '''
library foo;
import 'package:angular/angular.dart';

main() {
  ngBootstrap(defaultExpressionModule());
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/generated_static_expressions.dart' as generated_static_expressions;
import 'package:angular/angular.dart';

main() {
  ngBootstrap(generated_static_expressions.expressionModule());
}
''',
            'a|lib/generated_static_expressions.dart': '''
$IMPORTS
Map<String, Function> buildEval(FilterLookup filters) {
  return {
    "null": (scope) => null
  };
}

Map<String, Function> buildAssign(FilterLookup filters) {
  return {

  };
}

'''
        });
    });

    it('should handle no imports', () {
      return transform(phases,
          inputs: {
            'angular|lib/angular.dart': '',
            'angular|lib/core/parser/parser.dart': '',
            'angular|lib/core/parser/utils.dart': '',
            'a|web/main.dart': '''
main() {}
'''
          },
          results: {
            'a|web/main.dart': '''
main() {}
''',
        });
    });
  });
}

const String IMPORTS = '''
library a.web.main.generated_expressions;

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
StaticParserFunctions functions(FilterLookup filters)
    => new StaticParserFunctions(
           buildEval(filters), buildAssign(filters));
''';
