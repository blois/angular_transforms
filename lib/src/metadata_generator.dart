library angular_transformers.metadata_generator;

import 'dart:async';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:source_maps/refactor.dart';

import 'asset_libraries.dart';
import 'common.dart';
import 'metadata_extractor.dart';
import 'resolver.dart';
import 'resolver_transformer.dart';

const String generatedMetadataFilename = 'generated_metadata.dart';

class MetadataGenerator extends Transformer {
  final TransformOptions options;
  final ResolverTransformer resolvers;

  MetadataGenerator(this.options, this.resolvers);

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
    var resolver = this.resolvers.getResolver(asset.id);
    var outputBuffer = new StringBuffer();

    _writeHeader(asset.id, outputBuffer);

    var libs = crawlLibraries(transform, asset);

    _transformAsset(transform, resolver);

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
      }
      _writeMemberEpilogue(outputBuffer);

      var outputId =
          new AssetId(asset.id.package, 'lib/$generatedMetadataFilename');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));
    });
  }

  /**
   * Modify the asset of to import the generated source and modify all
   * references to angular_transformers.auto_modules.defaultMetadataModule to
   * refer to the generated expressions.
   */
  void _transformAsset(Transform transform, Resolver resolver) {
    transformIdentifiers(transform, resolver,
        identifier: 'angular_transformers.auto_modules.defaultMetadataModule',
        replacement: 'metadataModule',
        importPrefix: 'generated_metadata',
        generatedFilename: generatedMetadataFilename);
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
