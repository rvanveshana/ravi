# What Is Ravi?

Ravi is an indentation-based programming language inspired by Python and extended for Kannada-speaking developers.

## Why Ravi?

- **Familiar structure:** indentation, expressions, functions, collections, and classes are easy to recognize.
- **Kannada-friendly:** keywords can be written in Kannada script or Kanglish transliteration.
- **English-friendly:** the English profile supports teams and documentation written in English.
- **Flexible typing:** values can be used dynamically, while annotations and runtime guards support more explicit programs.
- **`.rk` libraries:** Ravi source files can be imported as modules, so a library does not need a separate language.
- **VM execution:** source is compiled to verified bytecode and executed by the Ravi virtual machine.

## Language profiles

The default profile uses Kannada/Kanglish vocabulary. An English profile can be selected with the source directive or the CLI option supported by the compiler. The language semantics stay the same across profiles; only keywords and selected builtins change.

Ravi is similar to Python in surface style, but it is more tightly integrated with a bytecode VM, typed runtime values, closures, managed collections, modules, diagnostics, and debugger tooling.
