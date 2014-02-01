Prototype of transformers for Angular
========================

Warning
--
This is highly experimental at this point and has a number of known
issues. Proceed with caution.

What
--
A set of transformers to generate static expressions and a static injector
for Angular applications. It allows the application to use dynamic expressions and injector during development, but when built via `pub build` it will switch over to using the static versions.

Usage
--

Add angular_transformers to your pubspec.yaml

```
dependencies:
  angular_transformers: any
transformers:
- angular_transformers:
    dart_entry: web/main.dart
    html_files: web/index.html
```

Additional annotations indicating types injectable via the static injector can be specified with the `injectable_annotations` parameter.
```
- angular_transformers:
    injectable_annotations:
    - NgInjectableService
    - NgDirective
```

Or additional non-annotated types can be specified with the `injectable_types` parameter.
```
- angular_transformers:
    injectable_types:
    - perf_api.Profiler
    - angular.core.parser.static_parser.StaticParser
```

Modify your app's `main()` to reference the auto members.

```
import 'package:angular_transformers/auto_injector.dart';

main() {
  var module = new Module()
    ..type(...)
    ..install(defaultExpressionModule());

  ngBootstrap(
      module:module,
      injectorFactory: (modules) => defaultAutoInjector(modules: modules));
}
```

Then build your app.
```
> pub build
```
