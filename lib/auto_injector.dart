/**
 * Library to automatically switch between the dynamic injector and a static
 * injector created by a pub build task.
 *
 * ## Step 1: Hook up the build step
 * Edit ```pubspec.yaml``` to add the di transformer to the list of
 * transformers.
 *
 *     name: transformer_demo
 *     version: 0.0.1
 *     dependencies:
 *       browser: any
 *       inject: any
 *     transformers:
 *     - angular_transformers:
 *         dart_entry: web/main.dart
 *         injectableAnnotations: NgInjectableService
 *
 * It's important to have the ```dart_entry``` entry to indicate the entry
 * point of the application.
 *
 * By default, any classes or constructors annotated with @inject will be
 * injected, but additional annotations can be specified with the annotations
 * argument.
 *
 * ## Step 2: Annotate your types
 *
 *     class Engine {
 *       @inject
 *       Engine();
 *     }
 *
 * or
 *
 *     @NgInjectableServide // custom annotation provided in pubspec.yaml
 *     class Car {}
 *
 * Note that all injectable classes must be in source files in lib/ directories.
 *
 * ## Step 3: Use the auto injector
 * Modify your entry script to use the [defaultAutoInjector] as the injector,
 * or alternatively the [defaultInjectorModule].
 *
 * This must be done from the file registered as the dart_entry in pubspec.yaml
 * as this is the only file which will be modified to include the generated
 * injector.
 */
library di.auto_injector;

import 'package:di/di.dart';
import 'package:di/dynamic_injector.dart';


@MirrorsUsed(override: '*')
import 'dart:mirrors' show MirrorsUsed;

Module get defaultInjectorModule => new Module()
    ..type(Injector, implementedBy: DynamicInjector);

Injector defaultAutoInjector({List<Module> modules, String name,
    bool allowImplicitInjection: false}) =>
    new DynamicInjector(
      modules: modules,
      name: name,
      allowImplicitInjection: allowImplicitInjection);

Injector _defaultInjectorFactory(List<Module> modules) =>
    new DynamicInjector(modules: modules);

// Empty since the default is the dynamic expression module.
Module get defaultExpressionModule => new Module();

// Empty since the default is the dynamic metadata module.
Module defaultMetadataModule() => new Module();
