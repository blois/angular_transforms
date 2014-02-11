library angular_transformers.metadata_generator;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart';
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;

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
    var asset = transform.primaryInput;
    var resolver = this.resolvers.getResolver(asset.id);

    var extractor = new AnnotationExtractor(transform.logger, resolver);

    var outputBuffer = new StringBuffer();
    _writeHeader(asset.id, outputBuffer);

    var annotatedTypes = resolver.libraries
        .where((lib) => !lib.isInSdk)
        .expand((lib) => lib.units)
        .expand((unit) => unit.types)
        .map(extractor.extractAnnotations)
        .where((annotations) => annotations != null).toList();

    var libs = annotatedTypes.expand((type) => type.referencedLibraries)
        .toSet();

    var importPrefixes = <LibraryElement, String>{};
    var index = 0;
    for (var lib in libs) {
      if (lib.isDartCore) {
        importPrefixes[lib] = '';
        continue;
      }

      var prefix = 'import_${index++}';
      var url = resolver.getAbsoluteImportUri(lib);
      outputBuffer.write('import \'$url\' as $prefix;\n');
      importPrefixes[lib] = '$prefix.';
    }

    _writePreamble(outputBuffer);

    _writeClassPreamble(outputBuffer);
    for (var type in annotatedTypes) {
      type.writeClassAnnotations(outputBuffer, importPrefixes);
    }
    _writeClassEpilogue(outputBuffer);

    _writeMemberPreamble(outputBuffer);
    for (var type in annotatedTypes) {
      type.writeMemberAnnotations(outputBuffer, importPrefixes);
    }
    _writeMemberEpilogue(outputBuffer);

    var outputId =
          new AssetId(asset.id.package, 'lib/$generatedMetadataFilename');
      transform.addOutput(
            new Asset.fromString(outputId, outputBuffer.toString()));

    return new Future.value(null);
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
