library angular_transformers.transformer;

import 'dart:io';
import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/src/expression_generator.dart';
import 'package:angular_transformers/src/injector_generator.dart';
import 'package:angular_transformers/src/metadata_generator.dart';
import 'package:code_transformers/resolver.dart';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;


 /**
  * The Angular transformer, which internally runs several phases that will:
  *
  *   * Extract all expressions for evaluation at runtime without using Mirrors.
  *   * Extract all classes being dependency injected into a static injector.
  */
class AngularTransformerGroup implements TransformerGroup {
  final Iterable<Iterable> phases;

  AngularTransformerGroup(TransformOptions options)
      : phases = _createDeployPhases(options);

  AngularTransformerGroup.asPlugin(BarbackSettings settings)
      : this(_parseSettings(settings));
}

TransformOptions _parseSettings(BarbackSettings settings) {
  var args = settings.configuration;
  // Default angular annotations;
  var annotations = [
      'angular.core.service.NgInjectableService',
      'angular.core.NgDirective',
      'angular.core.NgController',
      'angular.core.NgComponent',
      'angular.core.NgFilter']
      ..addAll(_readStringListValue(args, 'injectable_annotations'));

  var injectedTypes = [
      'perf_api.Profiler',
      'angular.core.parser.static_parser.StaticParser']
      ..addAll(_readStringListValue(args, 'injected_types'));

  var sdkDir = _readStringValue(args, 'dart_sdk', required: false);
  if (sdkDir == null) {
    // Assume the Pub executable is always coming from the SDK.
    sdkDir =  path.dirname(path.dirname(Platform.executable));
  }

  return new TransformOptions(
      dartEntry: _readStringValue(args, 'dart_entry'),
      htmlFiles: _readStringListValue(args, 'html_files'),
      injectableAnnotations: annotations,
      injectedTypes: injectedTypes,
      sdkDirectory: sdkDir);
}

_readStringValue(Map args, String name, {bool required: true}) {
  var value = args[name];
  if (value == null) {
    if (required) {
      print('angular_transformer "$name" has no value.');
    }
    return null;
  }
  if (value is! String) {
    print('angular_transformer "$name" value is not a string.');
    return null;
  }
  return value;
}

_readStringListValue(Map args, String name) {
  var value = args[name];
  if (value == null) return [];
  var results = [];
  bool error;
  if (value is List) {
    results = value;
    error = value.any((e) => e is! String);
  } else if (value is String) {
    results = [value];
    error = false;
  } else {
    error = true;
  }
  if (error) {
    print('Invalid value for "$name" in angular_transformers .');
  }
  return results;
}

List<List<Transformer>> _createDeployPhases(TransformOptions options) {
  var resolver = new ResolverTransformer(options.sdkDirectory,
      (asset) => options.isDartEntry(asset.id));
  return [
    [resolver],
    [new ExpressionGenerator(options, resolver)],
    [new InjectorGenerator(options, resolver)],
    [new MetadataGenerator(options, resolver)],
  ];
}
