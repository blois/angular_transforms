library angular_transformers.resolver_transformer;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart' show LibraryElement;
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';

import 'resolver.dart';


class ResolverTransformer extends Transformer {
  final TransformOptions options;
  final Map<AssetId, Resolver> _resolvers = {};

  ResolverTransformer(this.options);

  Future<bool> isPrimary(Asset input) =>
      new Future.value(options.isDartEntry(input.id));

  Future apply(Transform transform) {
    var resolver = _resolvers.putIfAbsent(transform.primaryInput.id,
        () => new Resolver(transform.primaryInput.id, options.sdkDirectory));

    return resolver.updateSources(transform).then((_) {
      transform.addOutput(transform.primaryInput);
      return null;
    });
  }

  /// Get the LibraryElement for the specified entryPoint.
  /// This transformer must have been applied with the entryPoint as a
  /// primary asset in order for the library to be available.
  LibraryElement getLibrary(AssetId entryPoint) {
    return _resolvers[entryPoint].entryLibrary;
  }

  /// Primarily for testing.
  Resolver getResolver(AssetId asset) {
    return _resolvers[asset];
  }
}
