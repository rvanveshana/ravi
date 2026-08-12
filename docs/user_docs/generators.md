# Generators and `yield`

A generator is a resumable function that produces one value at a time. The default-profile keyword is `taru`; English source uses `yield`.

## Intended syntax

```ravi
kriya count(limit: int):
    i = 0
    vargu i < limit:
        taru i
        i = i + 1

for value alli count(3):
    mudrisu(value)
```

A generator call is intended to create a resumable iterator rather than execute the entire body immediately. Each resume continues after the last `taru` statement and preserves local variables.

## Generator lifecycle

The completed design will specify:

- creation of a generator object;
- first resume and yielded value delivery;
- preservation of locals and instruction position;
- completion and final return value;
- explicit close behavior;
- exception propagation into or out of the generator;
- cancellation behavior when used with async scheduling;
- nested generator calls and generator-backed `for` loops.

## Current implementation status

The compiler and MIR preserve suspension metadata and the VM can represent resumable state snapshots. Executable generator state-machine lowering, public generator objects, resume/close behavior, and generator iteration are still pending. Treat `taru`/`yield` examples as design reference until the feature is marked complete in `progress.md`.

Arrays, strings, dictionaries, ranges, and dictionary views already support the currently implemented `for` paths; they are not general generator objects yet.
