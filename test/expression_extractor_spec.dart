library angular_transformers.test.expression_extractor_spec;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/expression_generator.dart';
import 'package:angular_transformers/src/resolver_transformer.dart';
import 'package:angular_transformers/transformer.dart';
import 'jasmine_syntax.dart';
import 'common.dart';

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

    it('should not modify files with no defaultExpressionModule', () {
      return transform(phases,
          inputs: {
            'angular|lib/angular.dart': '',
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
            'angular_transformers|lib/auto_modules.dart': PACKAGE_AUTO,
            'a|web/main.dart': '''
library foo;
import 'package:angular_transformers/auto_modules.dart';

main() {
  ngBootstrap(defaultExpressionModule);
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/generated_static_expressions.dart' as generated_static_expressions;
import 'package:angular_transformers/auto_modules.dart';

main() {
  ngBootstrap(generated_static_expressions.expressionModule);
}
''',
        });
    });

    it('should update references to prefixed defaultExpressionModule', () {
      return transform(phases,
          inputs: {
            'angular_transformers|lib/auto_modules.dart': PACKAGE_AUTO,
            'a|web/main.dart': '''
library foo;
import 'package:angular_transformers/auto_modules.dart' as auto;

main() {
  ngBootstrap(auto.defaultExpressionModule);
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/generated_static_expressions.dart' as generated_static_expressions;
import 'package:angular_transformers/auto_modules.dart' as auto;

main() {
  ngBootstrap(generated_static_expressions.expressionModule);
}
''',
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

    it('should extract expressions', () {
      htmlFiles.add('web/index.html');
      return transform(phases,
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
$IMPORTS
Map<String, Function> buildEval() {
  return {
    "some.getter": (scope, filters) => _getter(_some(scope))
  };
}

Map<String, Function> buildAssign() {
  return {
    "some.getter": (scope, value) => _set\$getter(_ensure\$some(scope), value)
  };
}

_some(o) {
  if (o == null) return null;
  return (o is Map) ? o["some"] : o.some;
}

_getter(o) {
  if (o == null) return null;
  return (o is Map) ? o["getter"] : o.getter;
}

_ensure\$some(o) {
  if (o == null) return null;
  if (o is Map) {
    var key = "some";
    var result = o[key];
    return (result == null) ? result = o[key] = {} : result;
  } else {
    var result = o.some;
    return (result == null) ? result = o.some = {} : result;
  }
}

_set\$getter(o, v) {
  if (o is Map) o["getter"] = v; else o.getter = v;
  return v;
}

'''
        }).then((_) {
          htmlFiles.clear();
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
  GeneratedStaticParserFunctions() :
      super(buildEval(), buildAssign());
}
StaticParserFunctions functions()
    => new StaticParserFunctions(
           buildEval(), buildAssign());
''';

const String PACKAGE_AUTO = '''
library angular_transformers.auto_modules;

Module get defaultExpressionModule => new Module();
''';
