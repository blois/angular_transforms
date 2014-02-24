library angular_transformers.test.expression_extractor_spec;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/refactor.dart' as refactor;
import 'package:barback/barback.dart';
import 'package:code_transformers/resolver.dart';
import 'package:code_transformers/tests.dart' as tests;
import 'jasmine_syntax.dart';

class SimpleTransformer extends Transformer {
  final ResolverTransformer resolvers;
  final AssetId primaryAsset;

  SimpleTransformer(this.resolvers, this.primaryAsset);

  Future<bool> isPrimary(Asset input) =>
    new Future.value(input.id == primaryAsset);

  Future apply(Transform transform) {
    var resolver = resolvers.getResolver(transform.primaryInput.id);
    refactor.transformIdentifiers(transform, resolver,
          identifier: 'source_lib.sourceIdentifier',
          replacement: 'generatedIdentifier',
          importPrefix: 'generated_code',
          generatedFilename: 'lib/generated.dart');

    return new Future.value(null);
  }
}

main() {
  describe('refactor lib', () {
    var entryPoint = new AssetId('a', 'web/main.dart');

    var resolver = new ResolverTransformer(dartSdkDirectory,
        (asset) => asset.id == entryPoint);

    var phases = [
      [resolver],
      [new SimpleTransformer(resolver, entryPoint)]
    ];

    it('should not modify files with no sourceIdentifier', () {
      return tests.applyTransformers(phases,
          inputs: {
            'a|web/main.dart': '''
library foo;
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
'''
          });
    });

    it('should update references to getters', () {
      return tests.applyTransformers(phases,
          inputs: {
            'source_lib|lib/source.dart': getterSource,
            'a|web/main.dart': '''
library foo;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(sourceIdentifier);
  print(foo.sourceIdentifier);
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/lib/generated.dart' as generated_code;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(generated_code.generatedIdentifier);
  print(generated_code.generatedIdentifier);
}
''',
        });
    });

    it('should update references to fields', () {
      return tests.applyTransformers(phases,
          inputs: {
            'source_lib|lib/source.dart': fieldSource,
            'a|web/main.dart': '''
library foo;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(sourceIdentifier);
  print(foo.sourceIdentifier);
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/lib/generated.dart' as generated_code;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(generated_code.generatedIdentifier);
  print(generated_code.generatedIdentifier);
}
''',
        });
    });

    it('should update references to methods', () {
      return tests.applyTransformers(phases,
          inputs: {
            'source_lib|lib/source.dart': methodSource,
            'a|web/main.dart': '''
library foo;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(sourceIdentifier('a'));
  print(foo.sourceIdentifier('b'));
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;
import 'package:a/lib/generated.dart' as generated_code;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(generated_code.generatedIdentifier('a'));
  print(generated_code.generatedIdentifier('b'));
}
''',
        });
    });

    it('should handle no imports', () {
      return tests.applyTransformers(phases,
          inputs: {
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

    it('should handle no library element', () {
      return tests.applyTransformers(phases,
          inputs: {
            'source_lib|lib/source.dart': methodSource,
            'a|web/main.dart': '''
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(sourceIdentifier('a'));
  print(foo.sourceIdentifier('b'));
}
'''
          },
          results: {
            'a|web/main.dart': '''
import 'package:a/lib/generated.dart' as generated_code;
import 'package:source_lib/source.dart';
import 'package:source_lib/source.dart' as foo;

main() {
  print(generated_code.generatedIdentifier('a'));
  print(generated_code.generatedIdentifier('b'));
}
''',
        });
    });

    it('should handle unresolved references', () {
      return tests.applyTransformers(phases,
          inputs: {
            'source_lib|lib/source.dart': methodSource,
            'a|web/main.dart': '''
library foo;

main() {
  print(sourceIdentifier('a'));
  print(foo.sourceIdentifier('b'));
}
'''
          },
          results: {
            'a|web/main.dart': '''
library foo;

main() {
  print(sourceIdentifier('a'));
  print(foo.sourceIdentifier('b'));
}
''',
        });
    });
  });
}

const String getterSource = '''
library source_lib;

String get sourceIdentifier => 'one';
''';

const String fieldSource = '''
library source_lib;

final String sourceIdentifier = 'two';
''';

const String methodSource = '''
library source_lib;

void sourceIdentifier(param) {}
''';
