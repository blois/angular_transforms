library angular_transformers.extractor;

import 'dart:async';
import 'package:args/args.dart';
import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/transformer.dart';
import 'src/runner.dart';
import 'package:path/path.dart' as path;
import 'dart:io';

Future generateInjectors(CommandLineOptions options) {
  var packageHome = options.packageHome;
  var packageDirs = readPackageDirsFromPub(packageHome);
  var currentPackage = readCurrentPackageFromPubspec(packageHome);

  print('packageDir for $currentPackage is ${packageDirs[currentPackage]}');

  var transformOptions = new TransformOptions(
      dartEntry: options.entryPoint,
      htmlFiles: options.htmlFiles,
      injectableAnnotations: options.injectableAnnotations);

  var barbackOptions = new BarbackOptions(
      phases: new AngularTransformerGroup(transformOptions).phases,
      outDir: options.outDir,
      currentPackage: currentPackage,
      packageHome: packageHome,
      packageDirs: packageDirs,
      machineFormat: options.machineFormat);
  return runBarback(barbackOptions)
      .then((_) => print('Done! All files written to "${options.outDir}"'));
}

/**
 * Options that may be used either in build.dart or by the linter and deploy
 * tools.
 */
class CommandLineOptions {
  /** Root folder for the package, where pubspec.yaml resides */
  final String packageHome;

  /** Entry point for the application. */
  final String entryPoint;

  /** HTML files containing Angular expressions. */
  final List<String> htmlFiles;

  /** Annotations for injectable types. */
  final List<String> injectableAnnotations;

  /** Whether to print results using a machine parseable format. */
  final bool machineFormat;

  /** Location where to generate output files. */
  final String outDir;

  CommandLineOptions({this.packageHome, this.entryPoint, this.htmlFiles,
      this.injectableAnnotations, this.machineFormat, this.outDir});

  /**
   * Parse command-line arguments and return a [CommandLineOptions] object.
   */
  static CommandLineOptions parse([List<String> args]) {
    var parser = new ArgParser()
      ..addOption('package-home',
          help: 'The root of the package, where pubspec.yaml resides.',
          defaultsTo: '.')
      ..addOption('entry', help: 'The application entry point')
      ..addOption('html', help: 'HTML file containing Angular expressions.',
          allowMultiple: true)
      ..addOption('inject-annotation',
          help: 'Annotation indicating injectable types', allowMultiple: true)
      ..addOption('out', abbr: 'o', help: 'Directory to generate files into.',
          defaultsTo: 'out')
      ..addFlag('machine', negatable: false,
          help: 'Produce warnings in a machine parseable format.')
      ..addFlag('help', abbr: 'h',
          negatable: false, help: 'Displays this help and exit.');

    showUsage() {
      print('Usage: dart extract.dart [options]');
      print('\nThese are valid options expected by extract.dart:');
      print(parser.getUsage());
    }

    var res;
    try {
      res = parser.parse(args);
    } on FormatException catch (e) {
      print(e.message);
      showUsage();
      exit(1);
    }
    if (res['help']) {
      print('A script that generates non-mirrors based Angular modules.');
      showUsage();
      exit(0);
    }
    return new CommandLineOptions(
        packageHome: path.absolute(res['package-home']),
        entryPoint: res['entry'],
        htmlFiles: res['html'],
        injectableAnnotations: res['inject-annotation'],
        outDir: res['out'],
        machineFormat: res['machine']);
  }
}
