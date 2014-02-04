library all_tests;

import 'expression_extractor_spec.dart' as expression_extractor_spec;
import 'injector_generator_spec.dart' as injector_generator_spec;
import 'metadata_generator_spec.dart' as metadata_generator_spec;
import 'resolver_spec.dart' as resolver_spec;

main() {
  expression_extractor_spec.main();
  injector_generator_spec.main();
  metadata_generator_spec.main();
  resolver_spec.main();
}
