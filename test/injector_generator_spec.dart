library angular_transformers.test.injector_generator_spec;

import 'package:angular_transformers/options.dart';
import 'package:angular_transformers/transformer.dart';
import 'package:angular_transformers/src/injector_generator.dart';
import 'jasmine_syntax.dart';
import 'common.dart';

main() {
  describe('generator', () {
    var phases = [[new InjectorGenerator(new TransformOptions(
        dartEntry: 'web/main.dart',
        injectableAnnotations: ['NgInjectableService'],
        injectableTypes: ['test_lib.Engine']))]];

    it('transforms imports', () {
      return transform(phases,
          inputs: {
            'a|web/main.dart': 'import "package:a/car.dart";',
            'a|lib/car.dart': '''
                import 'package:a/engine.dart';
                import 'package:a/seat.dart' as seat;

                class Car {
                  @inject
                  Car(Engine e, seat.Seat s) {}
                }
                ''',
            'a|lib/engine.dart': CLASS_ENGINE,
            'a|lib/seat.dart': '''
                class Seat {
                  @inject
                  Seat();
                }
                ''',
          },
          results: {
            'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/car.dart' as import_0;
import 'package:a/engine.dart' as import_0;
import 'package:a/seat.dart' as import_0_seat;
import 'dart:core' as import_1;
import 'package:a/engine.dart' as import_1;
import 'dart:core' as import_2;
import 'package:a/seat.dart' as import_2;
$BOILER_PLATE
  import_0.Car: (f) => new import_0.Car(f(import_0.Engine), f(import_0_seat.Seat)),
  import_1.Engine: (f) => new import_1.Engine(),
  import_2.Seat: (f) => new import_2.Seat(),
$FOOTER
'''
          },
          messages: []);
    });

    it('skips and warns about types in the web folder', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': '''
                class Foo {
                  @inject
                  Foo();
                }
                ''',
            },
            results: EMPTY_GENERATOR,
            messages: [
              'warning: Foo cannot be injected because the containing file '
              'cannot be imported. (web/main.dart 0 16)']);
    });

    it('skips and warns about parameterized classes', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Parameterized<T> {
                    @inject
                    Parameterized();
                  }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: [
              'warning: Parameterized cannot be injected because it is a '
              'parameterized type. (lib/a.dart 0 18)'
            ]);
      });

    it('skips and warns about parameterized constructor parameters', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Foo<T> {}
                  class Bar {
                    @inject
                    Bar(Foo<bool> f);
                  }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: [
              'warning: Bar cannot be injected because Foo<bool> f is a '
              'parameterized type. (lib/a.dart 3 24)'
            ]);
      });

      it('follows exports', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': 'export "package:a/b.dart";',
              'a|lib/b.dart': CLASS_ENGINE
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/b.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      it('handles parts', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': 'part "b.dart";',
              'a|lib/b.dart': '''
                  part of a.a;
                  $CLASS_ENGINE
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      it('follows relative imports', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': 'import "b.dart";',
              'a|lib/b.dart': CLASS_ENGINE
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/b.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      it('handles relative imports', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  import 'b.dart';
                  class Car {
                    @inject
                    Car(Engine engine);
                  }
                  ''',
              'a|lib/b.dart': CLASS_ENGINE
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
import 'package:a/b.dart' as import_0;
import 'dart:core' as import_1;
import 'package:a/b.dart' as import_1;
$BOILER_PLATE
  import_0.Car: (f) => new import_0.Car(f(import_0.Engine)),
  import_1.Engine: (f) => new import_1.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      it('skips and warns on named constructors', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Engine {
                    @inject
                    Engine.foo();
                  }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: ['warning: Named constructors cannot be injected. '
                '(lib/a.dart 1 20)']);
      });

      it('handles inject on classes', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  @inject
                  class Engine {}
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
        // warn on no implicit constructor.
      });

      it('skips and warns on abstract types with no factory constructor', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  @inject
                  abstract class Engine { }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: ['warning: Engine cannot be injected because it is an '
                'abstract type with no factory constructor. '
                '(lib/a.dart 0 18)']);
      });

      it('skips and warns on abstract types with implicit constructor', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  @inject
                  abstract class Engine {
                    Engine();
                  }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: ['warning: Engine cannot be injected because it is an '
                'abstract type with no factory constructor. '
                '(lib/a.dart 0 18)']);
      });

      it('injects abstract types with factory constructors', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  @inject
                  abstract class Engine {
                    factory Engine() => new ConcreteEngine();
                  }

                  class ConcreteEngine implements Engine {}
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      it('injects this parameters', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Engine {
                    final Fuel fuel;
                    @inject
                    Engine(this.fuel);
                  }

                  class Fuel {}
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(f(import_0.Fuel)),
$FOOTER
'''
            },
            messages: []);
      });

      it('narrows this parameters', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Engine {
                    final Fuel fuel;
                    @inject
                    Engine(JetFuel this.fuel);
                  }

                  class Fuel {}
                  class JetFuel implements Fuel {}
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(f(import_0.JetFuel)),
$FOOTER
'''
            },
            messages: []);
      });

      it('skips and warns on unresolved types', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  @inject
                  class Engine {
                    Engine(foo);
                  }

                  @inject
                  class Car {
                    var foo;
                    Car(this.foo);
                  }
                  '''
            },
            results: EMPTY_GENERATOR,
            messages: ['warning: Engine cannot be injected because parameter '
                'type foo cannot be resolved. (lib/a.dart 2 27)',
                'warning: Car cannot be injected because parameter type '
                'this.foo cannot be resolved. (lib/a.dart 8 24)']);
      });

      it('supports custom annotations', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Engine {
                    @NgInjectableService
                    Engine();
                  }

                  class Car {
                    @NgInjectableService()
                    Car();
                  }
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
  import_0.Car: (f) => new import_0.Car(),
$FOOTER
'''
            },
            messages: []);
      });

      it('supports default formal parameters', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  class Engine {
                    final Car car;

                    @inject
                    Engine([Car this.car]);
                  }

                  class Car {
                    @inject
                    Car();
                  }
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(f(import_0.Car)),
  import_0.Car: (f) => new import_0.Car(),
$FOOTER
'''
            },
            messages: []);
      });

      it('supports injectableTypes argument', () {
        return transform(phases,
            inputs: {
              'a|web/main.dart': 'import "package:a/a.dart";',
              'a|lib/a.dart': '''
                  library test_lib;
                  class Engine {
                    Engine();
                  }
                  '''
            },
            results: {
              'a|lib/generated_static_injector.dart':
'''
$IMPORTS
import 'dart:core' as import_0;
import 'package:a/a.dart' as import_0;
$BOILER_PLATE
  import_0.Engine: (f) => new import_0.Engine(),
$FOOTER
'''
            },
            messages: []);
      });

      // Test for warn on private types.
  });
}

const String IMPORTS = '''
library a.web.main.generated_static_injector;

import 'dart:core';
import 'package:di/di.dart';
import 'package:di/static_injector.dart';

@MirrorsUsed(override: const [
    'di.dynamic_injector',
    'mirrors',
    'di.src.reflected_type'])
import 'dart:mirrors';''';

const String BOILER_PLATE = '''
Injector createStaticInjector({List<Module> modules, String name,
    bool allowImplicitInjection: false}) =>
  new StaticInjector(modules: modules, name: name,
      allowImplicitInjection: allowImplicitInjection,
      typeFactories: factories);

Module get staticInjectorModule => new Module()
    ..value(Injector, createStaticInjector(name: 'Static Injector'));

final Map<Type, TypeFactory> factories = <Type, TypeFactory>{''';

const String FOOTER = '''
};''';

const Map EMPTY_GENERATOR = const {
  'a|lib/generated_static_injector.dart': '''
$IMPORTS
$BOILER_PLATE
$FOOTER
'''
};

const CLASS_ENGINE = '''
    class Engine {
      @inject
      Engine();
    }''';
