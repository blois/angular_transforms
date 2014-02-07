library angular_transformers.resolver_transformer;

import 'dart:async';
import 'package:analyzer/src/generated/element.dart' show LibraryElement;
import 'package:angular_transformers/options.dart';
import 'package:barback/barback.dart';

import 'resolver.dart';


/**
 * Transformer which maintains up-to-date resolved ASTs for the specified
 * code entry points.
 *
 * This is used by transformers dependent on resolved ASTs which can reference
 * this transformer to get the resolver needed.
 *
 * This transformer must be in a phase before any dependent transformers.
 */
class ResolverTransformer extends Transformer {
  final TransformOptions options;
  final Map<AssetId, Resolver> _resolvers = {};

  ResolverTransformer(this.options);

  Future<bool> isPrimary(Asset input) =>
      new Future.value(options.isDartEntry(input.id));

  /** Updates the resolved AST for the primary input of the transform. */
  Future apply(Transform transform) {
    var resolver = getResolver(transform.primaryInput.id);

    return resolver.updateSources(transform).then((_) {
      transform.addOutput(transform.primaryInput);
      return null;
    });
  }

  /** Get a resolver for the AST starting from [id]. */
  Resolver getResolver(AssetId id) =>
      _resolvers.putIfAbsent(id, () => new Resolver(id, options.sdkDirectory));
}
