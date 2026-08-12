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

## Planned inheritance model

The intended syntax is:

```ravi
roopa Animal:
    saarva kriya speak():
        mudrisu("animal")

roopa Dog guru Animal:
    saarva kriya speak():
        guru.speak()
        mudrisu("dog")
```

`guru` is the planned default-profile super reference. English source will use `super` when the inheritance feature is complete.

The final inheritance contract is expected to define:

1. A class may name one base class.
2. The base class is initialized according to an explicit constructor rule.
3. An override must preserve compatible parameters, return behavior, and visibility.
4. `guru`/`super` calls select the implementation from the base class.
5. Private members are visible only inside the declaring class.
6. Protected members are visible to the declaring class and subclasses.
7. Public members are exported according to module visibility.

## Visibility

The profile keywords are `saarva`/public, `swanta`/private, `vansha`/protected, and `olage`/internal. Visibility is a semantic contract, not name mangling. The final implementation will reject invalid overrides and illegal member access during analysis.

## Status

Basic classes and methods execute today. Inheritance, complete override checking, constructor chaining, and end-to-end visibility enforcement remain incomplete. The examples in this page under the planned inheritance section are specification examples, not current passing fixtures.
