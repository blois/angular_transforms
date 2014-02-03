library angular_transformers.metadata_generator;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart';

import 'asset_libraries.dart';
import 'common.dart';
import 'metadata_extractor.dart';

const String GENERATED_METADATA = 'generated_metadata.dart';

class MetadataGenerator extends Transformer {
  final TransformOptions options;

  MetadataGenerator(this.options);

  Future<bool> isPrimary(Asset input) => new Future.value(
      options.isDartEntry(input.id));

  Future apply(Transform transform) {
    return _generateMetadata(transform).then((_) {
      // Workaround for dartbug.com/16120- do not send data across the isolate
      // boundaries.
      return null;
    });
  }

  Future<String> _generateMetadata(Transform transform) {
    var asset = transform.primaryInput;
    var outputBuffer = new StringBuffer();

    _writeHeader(asset.id, outputBuffer);

    var libs = crawlLibraries(transform, asset);
    // The first lib file is always the entry file, update that to include
    // the generated expressions.
    libs.first.then((lib) {
      _transformPrimarySource(transform, lib);
    });

    return libs.map((s) => gatherAnnotatedLibraries(s, options))
        .where((l) => l != null)
        .toList().then((libs) {

      var index = 0;
      for (var lib in libs) {
        var prefix = 'import_${index++}';
        lib.writeImports(outputBuffer, prefix);
      }
      _writePreamble(outputBuffer);

      _writeClassPreamble(outputBuffer);
      index = 0;
      for (var lib in libs) {
        var prefix = 'import_${index++}';
        lib.writeClassAnnotations(outputBuffer, prefix);
      }
      _writeClassEpilogue(outputBuffer);

      _writeMemberPreamble(outputBuffer);
      index = 0;
      for (var lib in libs) {
        var prefix = 'import_${index++}';
        lib.writeMemberAnnotations(outputBuffer, prefix);
        //constructor.writeGenerators(outputBuffer, prefix);
      }
      _writeMemberEpilogue(outputBuffer);

      //_writeFooter(outputBuffer);

      var outputId =
          new AssetId(asset.id.package, 'lib/$GENERATED_METADATA');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));
    });
  }

  /**
   * Modify the primary asset of the transform to import the generated source
   * and modify all references to defaultAutoInjector to refer to the generated
   * static injector.
   */
  void _transformPrimarySource(Transform transform, DartLibrary lib) {
    var transaction = new TextEditTransaction(lib.text, lib.sourceFile);

    transformIdentifiers(transaction, lib.compilationUnit,
        'defaultMetadataModule',
        'generated_metadata.metadataModule');

    if (transaction.hasEdits) {
      addImport(transaction, lib.compilationUnit,
          'package:${lib.assetId.package}/$GENERATED_METADATA',
          'generated_metadata');

      var id = lib.assetId;
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

void _writeHeader(AssetId id, StringSink sink) {
  var libPath = path.withoutExtension(id.path).replaceAll('/', '.');
  sink.write('''
library ${id.package}.$libPath.generated_metadata;

import 'dart:core';
import 'package:angular/angular.dart';

''');
}

void _writePreamble(StringSink sink) {
  sink.write('''
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

''');
}

void _writeClassPreamble(StringSink sink) {
  sink.write('''
final Map<Type, Object> _classAnnotations = {
''');
}

void _writeClassEpilogue(StringSink sink) {
  sink.write('''
};
''');
}

void _writeMemberPreamble(StringSink sink) {
  sink.write('''

final Map<Type, Map<String, AttrFieldAnnotation>> _memberAnnotations = {
''');
}

void _writeMemberEpilogue(StringSink sink) {
  sink.write('''
};
''');
}

void _writeFooter(StringSink sink) {
  sink.write('''
};
''');
}
