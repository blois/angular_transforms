library angular_transformers.test.resolver_spec;

import 'package:angular_transformers/src/resolver_transformer.dart';
import 'package:barback/barback.dart';
import 'common.dart';
import 'jasmine_syntax.dart';

main() {
  describe('resolver', () {
    var entryPoint = new AssetId('a', 'web/main.dart');
    var transformer = new ResolverTransformer(dartSdkDirectory,
        (asset) => asset.id == entryPoint);

    var phases = [[transformer]];

    it('should handle empty files', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var source = resolver.sources[entryPoint];
            expect(source.modificationStamp, 1);

            var lib = resolver.entryLibrary;
            expect(lib, isNotNull);
            expect(lib.entryPoint, isNull);
          });
    });

    it('should update when sources change', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': ''' main() {} ''',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var source = resolver.sources[entryPoint];
            expect(source.modificationStamp, 2);

            var lib = resolver.entryLibrary;
            expect(lib, isNotNull);
            expect(lib.entryPoint, isNotNull);
          });
    });

    it('should follow imports', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import 'a.dart';

main() {
} ''',
            'a|web/a.dart': '''
library a;
''',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var lib = resolver.entryLibrary;
            expect(lib.importedLibraries.length, 2);
            var libA = lib.importedLibraries.where((l) => l.name == 'a').single;
            expect(libA.getType('Foo'), isNull);
          });
    });

    it('should update changed imports', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import 'a.dart';

main() {
} ''',
            'a|web/a.dart': '''
library a;
class Foo {}
''',
          }).then((_) {
            var lib = transformer.getResolver(entryPoint).entryLibrary;
            expect(lib.importedLibraries.length, 2);
            var libA = lib.importedLibraries.where((l) => l.name == 'a').single;
            expect(libA.getType('Foo'), isNotNull);
          });
    });

    it('should follow package imports', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import 'package:b/b.dart';

main() {
} ''',
            'b|lib/b.dart': '''
library b;
''',
          }).then((_) {
            var lib = transformer.getResolver(entryPoint).entryLibrary;
            expect(lib.importedLibraries.length, 2);
            var libB = lib.importedLibraries.where((l) => l.name == 'b').single;
            expect(libB.getType('Foo'), isNull);
          });
    });

    it('should update on changed package imports', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import 'package:b/b.dart';

main() {
} ''',
            'b|lib/b.dart': '''
library b;
class Bar {}
''',
          }).then((_) {
            var lib = transformer.getResolver(entryPoint).entryLibrary;
            expect(lib.importedLibraries.length, 2);
            var libB = lib.importedLibraries.where((l) => l.name == 'b').single;
            expect(libB.getType('Bar'), isNotNull);
          });
    });

    it('should handle deleted files', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import 'package:b/b.dart';

main() {
} ''',
          },
          messages: [
            'error: Unable to find asset for "package:b/b.dart"',
            'error: Unable to find asset for "package:b/b.dart"',
          ]).then((_) {
            var lib = transformer.getResolver(entryPoint).entryLibrary;
            expect(lib.importedLibraries.length, 1);
          });
    });

    it('should fail on absolute URIs', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
import '/b.dart';

main() {
} ''',
          },
          messages: [
            // First from the AST walker
            'error: absolute paths not allowed: "/b.dart" (web/main.dart 0 0)',
            // Then two from the resolver.
            'error: absolute paths not allowed: "/b.dart"',
            'error: absolute paths not allowed: "/b.dart"',
          ]).then((_) {
            var lib = transformer.getResolver(entryPoint).entryLibrary;
            expect(lib.importedLibraries.length, 1);
          });
    });

    it('should list all libraries', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
library a.main;
import 'package:a/a.dart';
import 'package:a/b.dart';
''',
            'a|lib/a.dart': 'library a.a;\n import "package:a/c.dart";',
            'a|lib/b.dart': 'library a.b;\n import "c.dart";',
            'a|lib/c.dart': 'library a.c;'
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var libs = resolver.libraries.where((l) => !l.isInSdk);
            expect(libs.map((l) => l.name), unorderedEquals([
              'a.main',
              'a.a',
              'a.b',
              'a.c',
            ]));
          });
    });

    it('should resolve types and library uris', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''
              import 'dart:core';
              import 'package:a/a.dart';
              import 'package:a/b.dart';
              import 'sub_dir/d.dart';
              class Foo {}
              ''',
            'a|lib/a.dart': 'library a.a;\n import "package:a/c.dart";',
            'a|lib/b.dart': 'library a.b;\n import "c.dart";',
            'a|lib/c.dart': '''
                library a.c;
                class Bar {}
                ''',
            'a|web/sub_dir/d.dart': '''
                library a.web.sub_dir.d;
                class Baz{}
                ''',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);

            var a = resolver.getLibrary('a.a');
            expect(a, isNotNull);
            expect(resolver.getImportUri(a).toString(),
                'package:a/a.dart');

            var main = resolver.getLibrary('');
            expect(main, isNotNull);
            expect(resolver.getImportUri(main), isNull);

            var fooType = resolver.getType('Foo');
            expect(fooType, isNotNull);
            expect(fooType.library, main);

            var barType = resolver.getType('a.c.Bar');
            expect(barType, isNotNull);
            expect(resolver.getImportUri(barType.library).toString(),
                'package:a/c.dart');
            expect(resolver.getSourceAssetId(barType),
                new AssetId('a', 'lib/c.dart'));

            var bazType = resolver.getType('a.web.sub_dir.d.Baz');
            expect(bazType, isNotNull);
            expect(resolver.getImportUri(bazType.library), isNull);
            expect(resolver
                .getImportUri(bazType.library, from: entryPoint).toString(),
                'sub_dir/d.dart');

            var hashMap = resolver.getType('dart.collection.HashMap');
            expect(resolver.getImportUri(hashMap.library).toString(),
                'dart:collection');

          });
    });
    it('deleted files should be removed', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '''import 'package:a/a.dart';''',
            'a|lib/a.dart': '''import 'package:a/b.dart';''',
            'a|lib/b.dart': '''class Engine{}''',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var engine = resolver.getType('Engine');
            var uri = resolver.getImportUri(engine.library);
            expect(uri.toString(), 'package:a/b.dart');
          }).then((_) {
            return transform(phases,
              inputs: {
                'a|web/main.dart': '''import 'package:a/a.dart';''',
                'a|lib/a.dart': '''lib a;\n class Engine{}'''
              });
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var engine = resolver.getType('Engine');
            var uri = resolver.getImportUri(engine.library);
            expect(uri.toString(), 'package:a/a.dart');
          });
    });
  });
}
