library angular_transformers.injector_generator;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart';

import 'asset_sources.dart';
import 'common.dart';
import 'injectable_extractor.dart';

const String GENERATED_INJECTOR = 'generated_static_injector.dart';

class InjectorGenerator extends Transformer {
  final TransformOptions options;

  InjectorGenerator(this.options);

  Future<bool> isPrimary(Asset input) => new Future.value(
      options.isDartEntry(input.id));

  Future apply(Transform transform) {
    return _generateStaticInjector(transform).then((_) {
      // Workaround for dartbug.com/16120- do not send data across the isolate
      // boundaries.
      return null;
    });
  }

  Future<String> _generateStaticInjector(Transform transform) {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    _writeStaticInjectorHeader(asset.id, outputBuffer);

    var sources = crawlSources(transform, asset);
    // The first source file is always the entry file, update that to include
    // the generated expressions.
    sources.first.then((source) {
      _transformPrimarySource(transform, source);
    });

    return sources.map((s) => gatherLibraries(s, options))
        .where((l) => l != null).toList().then((libs) {
      var index = 0;
      for (var lib in libs) {
        var prefix = 'import_${index++}';
        lib.writeImports(outputBuffer, prefix);
      }
      _writePreamble(outputBuffer);

      index = 0;
      for (var lib in libs) {
        var prefix = 'import_${index++}';
        lib.writeGenerators(outputBuffer, prefix);
      }

      _writeFooter(outputBuffer);

      var outputId =
          new AssetId(asset.id.package, 'lib/$GENERATED_INJECTOR');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));
    });
  }

  /**
   * Modify the primary asset of the transform to import the generated source
   * and modify all references to defaultAutoInjector to refer to the generated
   * static injector.
   */
  void _transformPrimarySource(Transform transform, DartSource source) {
    var transaction = new TextEditTransaction(source.text, source.sourceFile);

    transformIdentifiers(transaction, source.compilationUnit,
        'defaultAutoInjector',
        'generated_static_injector.createStaticInjector');

    transformIdentifiers(transaction, source.compilationUnit,
        'defaultInjectorModule',
        'generated_static_injector.staticInjectorModule');

    if (transaction.hasEdits) {
      addImport(transaction, source.compilationUnit,
          'package:${source.assetId.package}/$GENERATED_INJECTOR',
          'generated_static_injector');

      var id = source.assetId;
      var printer = transaction.commit();
      var url = id.path.startsWith('lib/')
          ? 'package:${id.package}/${id.path.substring(4)}' : id.path;
      printer.build(url);
      transform.addOutput(new Asset.fromString(id, printer.text));
    } else {
      // No modifications, so just pass the source through.
      transform.addOutput(transform.primaryInput);
    }
  }
}

void _writeStaticInjectorHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  sink.write('''
library ${id.package}.$libPath.generated_static_injector;

import 'dart:core';
import 'package:di/di.dart';
import 'package:di/static_injector.dart';

@MirrorsUsed(override: const [
    'di.dynamic_injector',
    'mirrors',
    'di.src.reflected_type'])
import 'dart:mirrors';
''');
}

void _writePreamble(StringSink sink) {
  sink.write('''
Injector createStaticInjector({List<Module> modules, String name,
    bool allowImplicitInjection: false}) =>
  new StaticInjector(modules: modules, name: name,
      allowImplicitInjection: allowImplicitInjection,
      typeFactories: factories);

Module get staticInjectorModule => new Module()
    ..value(Injector, createStaticInjector(name: 'Static Injector'));

final Map<Type, TypeFactory> factories = <Type, TypeFactory>{
''');
}

void _writeFooter(StringSink sink) {
  sink.write('''
};
''');
}
