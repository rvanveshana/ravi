# Classes and visibility

The object model is experimental. It provides class declarations, constructors,
instance fields, methods, inheritance, and visibility metadata. Enforcement and
behavior across compiler paths are not yet complete.

```ravi
roopa Counter:
    saarva kriya huttu(start: int):
        tanna.value = start

    saarva kriya increment():
        tanna.value = tanna.value + 1

    saarva kriya current():
        kodu tanna.value

counter = Counter(0)
counter.increment()
mudrisu(counter.current())
```

This prints `1`. The executable regression is [counter.rk](../../examples/regressions/counter.rk).
Methods have an implicit receiver: use `tanna`
(`self` in English) inside the body, without declaring a receiver parameter.
The constructor is `huttu` (`init` in English).

## Inheritance

A class can name a base in its declaration, for example `roopa Child guru Parent:`.
The compiler contains method override and base lookup support, including `guru`
references. Constructor chaining and dynamic method lookup are still undergoing
conformance work. Do not assume automatic base-constructor invocation or Python's
multiple-inheritance rules.

## Visibility

| Default | English | Intended access |
| --- | --- | --- |
| `saarva` | `public` | External callers |
| `swanta` | `private` | Declaring class |
| `vansha` | `protected` | Class and derived classes |
| `olage` | `internal` | Defining module |

Visibility checks are incomplete, especially through dynamic access and module
boundaries. They are not a sandbox or a protection mechanism for secrets. Complete
object protocols, visibility enforcement, and equality/hashing are tracked in the
[development plan](../development-plan.md).
