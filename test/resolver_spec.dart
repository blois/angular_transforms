library angular_transformers.test.resolver_spec;

import 'dart:convert' as convert;
import 'dart:io';
import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/resolver_transformer.dart';
import 'package:angular_transformers/transformer.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'common.dart';
import 'jasmine_syntax.dart';

main() {
  describe('resolver', () {
    var transformer = new ResolverTransformer(
        new TransformOptions(
            dartEntry: 'web/main.dart',
            sdkDirectory: dartSdkDirectory));
    var phases = [[transformer]];
    var entryPoint = new AssetId('a', 'web/main.dart');

    it('should handle empty files', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': '',
          }).then((_) {
            var resolver = transformer.getResolver(entryPoint);
            var source = resolver.sources[entryPoint];
            expect(source.modificationStamp, 1);

            var lib = transformer.getLibrary(entryPoint);
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

            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
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
            var lib = transformer.getLibrary(entryPoint);
            expect(lib.importedLibraries.length, 1);
          });
    });
  });
}

String get dartSdkDirectory {
  if (path.split(Platform.executable).length == 1) {
    // HACK: A single part, hope it's on the path.
    var result = Process.runSync('which', ['dart'],
        stdoutEncoding: convert.UTF8);
    return path.dirname(path.dirname(result.stdout));
  }
  var absolute = path.absolute(Platform.executable);
  return path.dirname(absolute);
}
