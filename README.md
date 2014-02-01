Prototype of transformers for Angular
========================

Warning
-------
This is highly experimental at this point and has a number of known
issues. Proceed with caution.*

A set of transformers to generate static expressions and a static injector
for Angular applications.

Usage
--------------

Add angular_transformers to your pubspec.yaml

```
dependencies:
  angular_transformers: any
transformers:
- angular_transformers:
    dart_entry: web/main.dart
    html_files: web/index.html
```

Modify your app's `main()` to reference the auto members:

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
