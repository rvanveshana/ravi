# Decorators

Decorators are a planned declaration transformation feature. They will allow a function or class to be wrapped or modified at declaration time.

## Intended shape

```ravi
@trace
kriya calculate(value):
    kodu value * 2
```

A decorator design must define whether `trace` is evaluated at module initialization, what object it receives, how arguments are passed, and which name is bound after wrapping.

## Required semantics

The final implementation should specify:

- decorator expression evaluation order;
- decorator arguments;
- multiple decorator order;
- class versus function decoration;
- signature and annotation preservation;
- visibility and export behavior;
- exceptions during decorator evaluation;
- interaction with closures and module initialization.

## Current status

Decorator syntax is represented in the broader language direction, but parsing arguments, applying wrappers, preserving declaration order, and validating decorated signatures remain incomplete. This page is a design reference, not a claim of executable support.
