library all_tests;

import 'expression_extractor_spec.dart' as expression_extractor_spec;
import 'injector_generator_spec.dart' as injector_generator_spec;

main() {
  expression_extractor_spec.main();
  injector_generator_spec.main();
}
