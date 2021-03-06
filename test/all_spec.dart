library all_tests;

import 'expression_extractor_spec.dart' as expression_extractor_spec;
import 'injector_generator_spec.dart' as injector_generator_spec;
import 'metadata_generator_spec.dart' as metadata_generator_spec;
import 'refactor_spec.dart' as refactor_spec;

main() {
  expression_extractor_spec.main();
  injector_generator_spec.main();
  metadata_generator_spec.main();
  refactor_spec.main();
}
