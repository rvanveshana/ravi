# Classes and Instances

Classes define a reusable shape and behavior. Calling a class creates an
instance, which stores fields and can call methods declared by the class.

```ravi
class Counter:
    kriya init(start: int):
        self.value = start

    kriya increment(self):
        self.value = self.value + 1

counter = Counter(0)
counter.increment()
mudrisu(counter.value)
```

## Class parts

- `roopa` is the default-profile keyword for `class`; English source uses
    `class`.
- `init` is the conventional constructor name. The constructor initializes
    fields on the new instance.
- `self.value` is an instance field. Fields can be read and assigned through
    member access.
- A method is a function declared inside a class. Call it with
    `instance.method(arguments)`.

## Method example

```ravi
roopa Greeter:
        kriya init(prefix):
                self.prefix = prefix

        kriya greet(name):
                kodu self.prefix + name

greeter = Greeter("Namaskara ")
mudrisu(greeter.greet("Ravi"))
```

Methods may use the same parameters, defaults, keyword arguments, closures,
and return statements as ordinary functions. See [Function](type-function.md)
for the callable model.

Ravi supports instances, properties, methods, constructors, visibility metadata, and method dispatch. Inheritance, override contracts, and complete visibility analysis continue to mature.

Use the canonical examples in `examples/class_oop.rk` for the currently verified object model.
