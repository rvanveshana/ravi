# Classes and Inheritance

Classes are declared with `roopa` in the default profile or `class` in English. A class defines methods and instance fields. Calling the class creates an instance and invokes the constructor when one is declared.

## Current class model

```ravi
roopa Person:
    saarva kriya huttu(name: string):
        tanna.name = name

    saarva kriya speak():
        mudrisu(tanna.name)

person = Person("Ravi")
person.speak()
```

The current executable class model supports:

- class declarations;
- constructor dispatch through `huttu`/`init`;
- instance fields such as `tanna.name`/`self.name`;
- method calls and property reads/writes;
- visibility metadata and method lookup foundations.

## Inheritance model

The executable default-profile syntax is:

```ravi
roopa Animal:
    saarva kriya speak():
        mudrisu("animal")

roopa Dog guru Animal:
    saarva kriya speak():
        kodu "dog"
```

`guru` is the default-profile base-class reference. Inside an overriding
method, `guru.method()` explicitly calls the nearest base implementation.
The English `super` alias is reserved for a future profile extension; use the
default-profile spelling in executable inheritance examples today.

The final inheritance contract is expected to define:

1. A class may name one base class.
2. The base class is initialized according to an explicit constructor rule.
3. An override must preserve compatible parameters, return behavior, and visibility.
4. `guru` calls select the implementation from the base class.
5. Private members are visible only inside the declaring class.
6. Protected members are visible to the declaring class and subclasses.
7. Public members are exported according to module visibility.

Inheritance can be chained through multiple levels. Method lookup walks from
the concrete class toward its base classes, so a deep derived instance can use
an inherited method, an override, and a nested field containing another
instance. See `examples/class_oop.rk` for an executable account and invoice
workflow with four class levels.

## Visibility

The profile keywords are `saarva`/public, `swanta`/private, `vansha`/protected, and `olage`/internal. Visibility is a semantic contract, not name mangling. The final implementation will reject invalid overrides and illegal member access during analysis.

## Status

Classes, single inheritance, multi-level method lookup, overrides,
`guru` dispatch, constructors, protected access, and nested object
composition execute today. Constructor chaining remains explicit: each
concrete class that accepts arguments initializes its own fields. Complete
override signature checking and automatic constructor chaining remain future
work.
