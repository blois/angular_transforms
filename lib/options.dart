library angular_transformers.options;

import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;

/** Options used by DI transformers */
class TransformOptions {

  /**
   * The file path of the primary Dart entry point (main) for the application.
   * This is used as the starting point to find all expressions used by the
   * application.
   */
  final String dartEntry;

  /**
   * List of html file paths which may contain Angular expressions.
   * The paths are relative to the package root and
   * are represented using posix style, which matches the representation used in
   * asset ids in barback.
   */
  final List<String> htmlFiles;

  /**
   * List of additional annotations which are used to indicate types as being
   * injectable.
   */
  final List<String> injectableAnnotations;

  /**
   * Set of additional types which should be injected.
   */
  final Set<String> injectedTypes;

  /**
   * Path to the Dart SDK directory, for resolving Dart libraries.
   */
  final String sdkDirectory;

  TransformOptions({String dartEntry,
      String sdkDirectory, List<String> htmlFiles,
      List<String> injectableAnnotations, List<String> injectedTypes})
    : this.dartEntry = _systemToAssetPath(dartEntry),
      this.sdkDirectory = sdkDirectory,
      this.htmlFiles = htmlFiles != null ? htmlFiles : [],
      this.injectableAnnotations =
          injectableAnnotations != null ? injectableAnnotations : [],
      this.injectedTypes =
          new Set.from(injectedTypes != null ? injectedTypes : []) {
    if (sdkDirectory == null)
      throw new ArgumentError('sdkDirectory must be provided.');
  }

  bool isDartEntry(AssetId id) => id.path == dartEntry || dartEntry == '*';
}

/** Convert system paths to asset paths (asset paths are posix style). */
String _systemToAssetPath(String assetPath) {
  if (path.Style.platform != path.Style.windows) return assetPath;
  return path.posix.joinAll(path.split(assetPath));
}
