library angular_transformers.bin.extract;

import 'package:angular_transformers/extract.dart';

main(args) {
  var options = CommandLineOptions.parse(args);
  generateInjectors(options);
}
