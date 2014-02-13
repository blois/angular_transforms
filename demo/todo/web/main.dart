import 'package:angular/angular.dart';
import 'package:angular/playback/playback_http.dart';
import 'package:angular_transformers/auto_modules.dart';
import 'package:di/di.dart';
import 'package:todo/todo.dart';

import 'dart:html';

// Everything in the 'todo' library should be preserved by MirrorsUsed
@MirrorsUsed(
    targets: const['todo'],
    override: '*')
import 'dart:mirrors';

main() {

  print(window.location.search);
  var module = new Module()
    ..type(TodoController)
    ..type(PlaybackHttpBackendConfig)
    ..install(defaultExpressionModule)
    ..install(defaultMetadataModule);

  // If these is a query in the URL, use the server-backed
  // TodoController.  Otherwise, use the stored-data controller.
  var query = window.location.search;
  if (query.contains('?')) {
    module.type(ServerController);
  } else {
    module.type(ServerController, implementedBy: NoServerController);
  }

  if (query == '?record') {
    print('Using recording HttpBackend');
    var wrapper = new HttpBackendWrapper(new HttpBackend());
    module.value(HttpBackendWrapper, new HttpBackendWrapper(new HttpBackend()));
    module.type(HttpBackend, implementedBy: RecordingHttpBackend);
  }

  if (query == '?playback') {
    print('Using playback HttpBackend');
    module.type(HttpBackend, implementedBy: PlaybackHttpBackend);
  }

  ngBootstrap(
      module:module,
      injectorFactory: (modules) => defaultInjector(modules: modules));
}
