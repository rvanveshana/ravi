# Ravi runtime features

Ravi source files use Kannada/Kanglish (`kn`) by default and may opt into
English with `# ravi: language=en`. A file has one profile; libraries can use
either profile because the bytecode and runtime APIs are language-neutral.

## Closures

`kriya(...) => expression` creates a function value. Names not belonging to
the lambda parameters are captured in a heap-backed closure environment and
loaded with `load_capture` when called. Captures use shared heap cells, so
multiple nested closures observe updates to the same variable after the
creating function has finished.

## Exceptions

`nodu`, `tappu`, and `kone` lower to try-handler bytecode. `yese value` raises
an explicit runtime exception value. Selected VM faults such as division by
zero also enter an active handler. The VM records the exception value and
function entry frames for CLI stack-trace rendering.

## Runtime values and collections

Function arguments with `int`, `bool`, or `string` annotations receive runtime
guards. List and string slices use `[start:end]`; string bounds are measured in
UTF-8 code points. Dictionary views are materialized as collection values,
with `items/jodi` represented as alternating key/value entries for efficient
indexing by the current compact VM.
